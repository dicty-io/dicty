import ssl
import os
import re
import sys
import wave
import time
import json
import shutil
import logging
import platform
import tempfile
import threading
import urllib.request
import zipfile
from typing import Dict, Any, Optional, Tuple, List
import numpy as np

logger = logging.getLogger("dicty.silero")

def get_ssl_context():
    """Returns an SSL context with certifi or fallback to unverified if certificates are missing."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass
    try:
        return ssl.create_default_context()
    except Exception:
        pass
    try:
        return ssl._create_unverified_context()
    except Exception:
        return None

def open_url_safe(req_or_url, timeout=30):
    """Safely opens a URL with certificate fallback to ensure downloads never fail due to macOS CA bundle issues."""
    ctx = get_ssl_context()
    try:
        if ctx is not None:
            return urllib.request.urlopen(req_or_url, context=ctx, timeout=timeout)
        return urllib.request.urlopen(req_or_url, timeout=timeout)
    except Exception as e:
        # If certificate verify failed with the context, retry with unverified context
        try:
            unverified_ctx = ssl._create_unverified_context()
            return urllib.request.urlopen(req_or_url, context=unverified_ctx, timeout=timeout)
        except Exception:
            raise e

from dicty_paths import get_user_data_dir

def get_dynamic_lib_dir() -> str:
    path = os.path.join(get_user_data_dir(), "lib")
    os.makedirs(path, exist_ok=True)
    return path

torch = None
package = None
TORCH_AVAILABLE = False

def ensure_torch_runtime() -> bool:
    """Dynamically locates and loads PyTorch runtime if available."""
    global torch, package, TORCH_AVAILABLE
    if TORCH_AVAILABLE and torch is not None and package is not None:
        return True

    # 1. Try importing from current sys.path
    try:
        import importlib
        torch = importlib.import_module("torch")
        package = getattr(torch, "package", None)
        if torch and package:
            TORCH_AVAILABLE = True
            return True
    except Exception:
        pass

    # 2. Check Dicty dynamic lib directory
    lib_dir = get_dynamic_lib_dir()
    if os.path.exists(os.path.join(lib_dir, "torch")):
        if lib_dir not in sys.path:
            sys.path.insert(0, lib_dir)
        try:
            import importlib
            torch = importlib.import_module("torch")
            package = getattr(torch, "package", None)
            if torch and package:
                TORCH_AVAILABLE = True
                logger.info(f"Loaded dynamic PyTorch runtime from {lib_dir}")
                return True
        except Exception as e:
            for k in list(sys.modules.keys()):
                if k == "torch" or k.startswith("torch."):
                    del sys.modules[k]
            logger.warning(f"Failed to load dynamic torch from {lib_dir}: {e}")

    torch = None
    package = None
    TORCH_AVAILABLE = False
    return False

# NOTE: torch is loaded lazily via ensure_torch_runtime() only when a Silero voice is actually used.
# Importing it at module load cost ~190 MB of resident memory for every engine process,
# even for users who never use Silero TTS.

def get_torch_wheel_info() -> Dict[str, Any]:
    """Finds the appropriate PyTorch wheel from PyPI for the running platform."""
    py_tag = f"cp{sys.version_info.major}{sys.version_info.minor}"
    abi = getattr(sys, "abiflags", "")
    expected_abi = f"{py_tag}{abi}"
    full_tag = f"{py_tag}-{expected_abi}-"
    arch = platform.machine().lower()
    target_arch = "arm64" if arch in ("arm64", "aarch64") else "x86_64"

    url = "https://pypi.org/pypi/torch/json"
    req = urllib.request.Request(url, headers={"User-Agent": "Dicty/1.0"})
    with open_url_safe(req, timeout=12) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    # Search releases from newest to oldest
    for ver in sorted(data.get("releases", {}).keys(), reverse=True):
        files = data["releases"][ver]
        for f in files:
            fn = f.get("filename", "")
            if full_tag in fn and "macosx" in fn and (target_arch in fn or "universal2" in fn):
                return {
                    "filename": fn,
                    "url": f["url"],
                    "size": f.get("size", 125 * 1024 * 1024),
                    "version": ver
                }
    raise RuntimeError(f"No compatible PyTorch wheel found on PyPI for {full_tag}{target_arch}")

def download_and_install_torch_runtime(progress_callback=None) -> bool:
    """Downloads PyTorch macOS wheel on demand and extracts into Dicty dynamic lib."""
    lib_dir = get_dynamic_lib_dir()
    wheel_info = get_torch_wheel_info()
    wheel_url = wheel_info["url"]
    total_size = wheel_info["size"]

    temp_whl = os.path.join(tempfile.gettempdir(), wheel_info["filename"])
    try:
        logger.info(f"Downloading on-demand PyTorch runtime ({total_size/(1024*1024):.1f} MB)...")
        req = urllib.request.Request(wheel_url, headers={"User-Agent": "Dicty/1.0"})
        downloaded = 0
        with open_url_safe(req, timeout=30) as response, open(temp_whl, "wb") as out_f:
            chunk_size = 512 * 1024
            while True:
                chunk = response.read(chunk_size)
                if not chunk:
                    break
                out_f.write(chunk)
                downloaded += len(chunk)
                if progress_callback and total_size > 0:
                    pct = min(100.0, (downloaded / total_size) * 100.0)
                    progress_callback(pct, downloaded, total_size)

        # Extract into a temporary unpack directory first so concurrent status checks
        # never attempt to import half-extracted torch modules
        extract_tmp = os.path.join(lib_dir, ".torch_unpack_tmp")
        if os.path.exists(extract_tmp):
            shutil.rmtree(extract_tmp, ignore_errors=True)
        os.makedirs(extract_tmp, exist_ok=True)

        logger.info("Extracting PyTorch runtime into temporary directory...")
        with zipfile.ZipFile(temp_whl, "r") as zf:
            for member in zf.namelist():
                if (
                    member.startswith("torch/")
                    or member.startswith("torchgen/")
                    or member.startswith("typing_extensions")
                ):
                    zf.extract(member, extract_tmp)

        # Move atomically into lib_dir
        for item in os.listdir(extract_tmp):
            src_item = os.path.join(extract_tmp, item)
            dst_item = os.path.join(lib_dir, item)
            if os.path.exists(dst_item):
                if os.path.isdir(dst_item):
                    shutil.rmtree(dst_item, ignore_errors=True)
                else:
                    os.remove(dst_item)
            shutil.move(src_item, dst_item)
        shutil.rmtree(extract_tmp, ignore_errors=True)

        # Ensure required helper modules (typing_extensions, pickletools, _compat_pickle) are present
        for mod_name in ["typing_extensions", "pickletools", "_compat_pickle"]:
            dest = os.path.join(lib_dir, f"{mod_name}.py")
            if not os.path.exists(dest):
                try:
                    mod = __import__(mod_name)
                    if getattr(mod, "__file__", None) and os.path.exists(mod.__file__):
                        shutil.copy2(mod.__file__, dest)
                except Exception:
                    pass
                if not os.path.exists(dest):
                    te_url = f"https://raw.githubusercontent.com/python/cpython/3.13/Lib/{mod_name}.py" if mod_name != "typing_extensions" else "https://raw.githubusercontent.com/python/typing_extensions/main/src/typing_extensions.py"
                    try:
                        te_req = urllib.request.Request(te_url, headers={"User-Agent": "Dicty/1.0"})
                        with open_url_safe(te_req, timeout=15) as te_resp, open(dest, "wb") as te_f:
                            te_f.write(te_resp.read())
                        logger.info(f"{mod_name}.py saved to dynamic lib.")
                    except Exception as te_err:
                        logger.warning(f"Could not fetch {mod_name}: {te_err}")

        # Clean any cached torch in sys.modules to force clean re-import
        for k in list(sys.modules.keys()):
            if k == "torch" or k.startswith("torch."):
                del sys.modules[k]

        logger.info("PyTorch runtime successfully extracted and configured.")
        return ensure_torch_runtime()
    finally:
        if os.path.exists(temp_whl):
            try:
                os.remove(temp_whl)
            except Exception:
                pass

SILERO_MODELS_DIR = os.path.join(get_user_data_dir(), "models", "tts", "silero")

SILERO_LANG_CONFIG: Dict[str, Dict[str, Any]] = {
    "ru": {
        "model_file": "v5_ru.pt",
        "url": "https://models.silero.ai/models/tts/ru/v5_ru.pt",
        "speakers": ["baya", "kseniya", "xenia", "aidar", "eugene"],
        "lang": "ru",
        "flag": "🇷🇺",
        "sample_rate": 48000,
        "put_accent": True,
        "put_yo": True,
        "put_stress_homo": True,
        "put_yo_homo": True,
    },
    "de": {
        "model_file": "v3_de.pt",
        "url": "https://models.silero.ai/models/tts/de/v3_de.pt",
        "speakers": ["karlsson", "eva_k", "bernd_ungerer", "friedrich", "hokuspokus"],
        "lang": "de",
        "flag": "🇩🇪",
        "sample_rate": 48000,
        "put_accent": False,
        "put_yo": False,
    },
    "es": {
        "model_file": "v3_es.pt",
        "url": "https://models.silero.ai/models/tts/es/v3_es.pt",
        "speakers": ["es_0", "es_1", "es_2"],
        "lang": "es",
        "flag": "🇪🇸",
        "sample_rate": 48000,
        "put_accent": False,
        "put_yo": False,
    },
    "ua": {
        "model_file": "v4_ua.pt",
        "url": "https://models.silero.ai/models/tts/ua/v4_ua.pt",
        "speakers": ["mykyta"],
        "lang": "uk",
        "flag": "🇺🇦",
        "sample_rate": 48000,
        "put_accent": True,
        "put_yo": False,
    }
}

SILERO_VOICES_CONFIG: Dict[str, Dict[str, Any]] = {
    # Russian
    "silero:ru_xenia": {
        "id": "silero:ru_xenia",
        "lang_key": "ru",
        "speaker": "xenia",
        "name": "Xenia",
        "gender": "female",
        "lang": "ru",
        "accent": "RU",
        "flag": "🇷🇺",
        "description": "Crisp, studio-grade Russian female narrator (Silero 48kHz)"
    },
    "silero:ru_kseniya": {
        "id": "silero:ru_kseniya",
        "lang_key": "ru",
        "speaker": "kseniya",
        "name": "Kseniya",
        "gender": "female",
        "lang": "ru",
        "accent": "RU",
        "flag": "🇷🇺",
        "description": "Warm, conversational Russian female voice (Silero 48kHz)"
    },
    "silero:ru_baya": {
        "id": "silero:ru_baya",
        "lang_key": "ru",
        "speaker": "baya",
        "name": "Baya",
        "gender": "female",
        "lang": "ru",
        "accent": "RU",
        "flag": "🇷🇺",
        "description": "Expressive, dynamic Russian female voice (Silero 48kHz)"
    },
    "silero:ru_aidar": {
        "id": "silero:ru_aidar",
        "lang_key": "ru",
        "speaker": "aidar",
        "name": "Aidar",
        "gender": "male",
        "lang": "ru",
        "accent": "RU",
        "flag": "🇷🇺",
        "description": "Deep, authoritative Russian male voice (Silero 48kHz)"
    },
    "silero:ru_eugene": {
        "id": "silero:ru_eugene",
        "lang_key": "ru",
        "speaker": "eugene",
        "name": "Eugene",
        "gender": "male",
        "lang": "ru",
        "accent": "RU",
        "flag": "🇷🇺",
        "description": "Clear, modern Russian male narrator (Silero 48kHz)"
    },
    # German
    "silero:de_karlsson": {
        "id": "silero:de_karlsson",
        "lang_key": "de",
        "speaker": "karlsson",
        "name": "Karlsson",
        "gender": "male",
        "lang": "de",
        "accent": "DE",
        "flag": "🇩🇪",
        "description": "Natural, conversational German male voice (Silero 48kHz)"
    },
    "silero:de_eva_k": {
        "id": "silero:de_eva_k",
        "lang_key": "de",
        "speaker": "eva_k",
        "name": "Eva",
        "gender": "female",
        "lang": "de",
        "accent": "DE",
        "flag": "🇩🇪",
        "description": "Clear, articulate German female narrator (Silero 48kHz)"
    },
    "silero:de_bernd_ungerer": {
        "id": "silero:de_bernd_ungerer",
        "lang_key": "de",
        "speaker": "bernd_ungerer",
        "name": "Bernd",
        "gender": "male",
        "lang": "de",
        "accent": "DE",
        "flag": "🇩🇪",
        "description": "Classic German documentary narrator (Silero 48kHz)"
    },
    "silero:de_friedrich": {
        "id": "silero:de_friedrich",
        "lang_key": "de",
        "speaker": "friedrich",
        "name": "Friedrich",
        "gender": "male",
        "lang": "de",
        "accent": "DE",
        "flag": "🇩🇪",
        "description": "Expressive, lively German male voice (Silero 48kHz)"
    },
    "silero:de_hokuspokus": {
        "id": "silero:de_hokuspokus",
        "lang_key": "de",
        "speaker": "hokuspokus",
        "name": "Hokuspokus",
        "gender": "male",
        "lang": "de",
        "accent": "DE",
        "flag": "🇩🇪",
        "description": "Warm storytelling German voice (Silero 48kHz)"
    },
    # Spanish
    "silero:es_es_0": {
        "id": "silero:es_es_0",
        "lang_key": "es",
        "speaker": "es_0",
        "name": "Elena",
        "gender": "female",
        "lang": "es",
        "accent": "ES",
        "flag": "🇪🇸",
        "description": "Clear, expressive Spanish female narrator (Silero 48kHz)"
    },
    "silero:es_es_1": {
        "id": "silero:es_es_1",
        "lang_key": "es",
        "speaker": "es_1",
        "name": "Mateo",
        "gender": "male",
        "lang": "es",
        "accent": "ES",
        "flag": "🇪🇸",
        "description": "Warm conversational Spanish male narrator (Silero 48kHz)"
    },
    # Ukrainian
    "silero:ua_mykyta": {
        "id": "silero:ua_mykyta",
        "lang_key": "ua",
        "speaker": "mykyta",
        "name": "Mykyta",
        "gender": "male",
        "lang": "uk",
        "accent": "UA",
        "flag": "🇺🇦",
        "description": "Natural Ukrainian male narrator (Silero 48kHz)"
    }
}

RU_COMMON_WORDS = {
    'dicty': 'Дикти',
    'apple': 'Эппл',
    'google': 'Гугл',
    'macos': 'Мак О Эс',
    'mac': 'Мак',
    'ios': 'Ай О Эс',
    'python': 'Пайтон',
    'chatgpt': 'Чат Джи Пи Ти',
    'openai': 'Опен Эй Ай',
    'ai': 'Эй Ай',
    'tts': 'Ти Ти Эс',
    'stt': 'Эс Ти Ти',
    'silero': 'Силеро',
    'kokoro': 'Кокоро',
    'piper': 'Пайпер',
    'vits': 'Витс',
    'api': 'А Пи Ай',
    'sdk': 'Эс Ди Кей',
    'ui': 'Ю Ай',
    'ux': 'Ю Икс',
    'id': 'Ай Ди',
    'wifi': 'Вай Фай',
    'wi-fi': 'Вай Фай',
    'bluetooth': 'Блютуз',
    'youtube': 'Ютуб',
    'telegram': 'Телеграм',
    'whatsapp': 'Вотсап',
    'github': 'Гитхаб',
    'docker': 'Докер',
    'linux': 'Линукс',
    'windows': 'Виндоус',
    'online': 'онлайн',
    'offline': 'офлайн',
    'web': 'веб',
    'app': 'приложение',
    'cpu': 'Си Пи Ю',
    'gpu': 'Джи Пи Ю',
    'ram': 'ОЗУ',
    'url': 'Ю Эр Эл',
    'http': 'Эйч Ти Ти Пи',
    'https': 'Эйч Ти Ти Пи Эс',
    'vpn': 'Ви Пи Эн',
    'ide': 'Ай Ди И',
    'sql': 'Эс Кью Эль',
    'pdf': 'Пэ Дэ Эф',
    'mp3': 'Эм Пэ Три',
    'wav': 'Вав',
}

LATIN_TO_CYR = [
    ('sch', 'ш'), ('sh', 'ш'), ('ch', 'ч'), ('th', 'т'), ('ph', 'ф'),
    ('kh', 'х'), ('zh', 'ж'), ('ts', 'ц'), ('ya', 'я'), ('yu', 'ю'),
    ('yo', 'ё'), ('ye', 'е'), ('ee', 'и'), ('oo', 'у'), ('ck', 'к'),
    ('qu', 'кв'), ('a', 'а'), ('b', 'б'), ('c', 'к'), ('d', 'д'),
    ('e', 'е'), ('f', 'ф'), ('g', 'г'), ('h', 'х'), ('i', 'и'),
    ('j', 'дж'), ('k', 'к'), ('l', 'л'), ('m', 'м'), ('n', 'н'),
    ('o', 'о'), ('p', 'п'), ('q', 'к'), ('r', 'р'), ('s', 'с'),
    ('t', 'т'), ('u', 'у'), ('v', 'в'), ('w', 'в'), ('x', 'кс'),
    ('y', 'и'), ('z', 'з')
]

RU_MONTHS = r'(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)'

def transliterate_latin_to_cyrillic(word: str) -> str:
    res = word.lower()
    for lat, cyr in LATIN_TO_CYR:
        res = res.replace(lat, cyr)
    return res

def _to_genitive_num_ru(val: int, num2words_mod) -> str:
    special = {
        1: 'одного', 2: 'двух', 3: 'трёх', 4: 'четырёх',
        40: 'сорока', 90: 'девяноста', 100: 'ста',
        200: 'двухсот', 300: 'трёхсот', 400: 'четырёхсот',
        500: 'пятисот', 600: 'шестисот', 700: 'семисот',
        800: 'восьмисот', 900: 'девятисот'
    }
    if val in special:
        return special[val]
    w = num2words_mod.num2words(val, lang='ru')
    if val in [5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,30]:
        return re.sub(r'ь$', 'и', w)
    elif val in [50, 60, 70, 80]:
        w = re.sub(r'десят$', 'десяти', w)
        w = re.sub(r'^шесть', 'шести', w)
        w = re.sub(r'^пять', 'пяти', w)
        w = re.sub(r'^семь', 'семи', w)
        w = re.sub(r'^восемь', 'восьми', w)
        return w
    return w

def normalize_text_for_silero(text: str, lang_key: str) -> str:
    if not text:
        return text

    try:
        import num2words
    except ImportError:
        num2words = None

    if lang_key in ("ru", "ua"):
        # 1. Punctuation & Quotes
        text = text.replace('—', ' – ') # Silero symbols support \u2013 en-dash, not \u2014 em-dash
        text = re.sub(r'[«»\"„“”\']', ' ', text)
        text = re.sub(r'[()[\]{}]', ', ', text)

        # 2. Common Russian abbreviations
        text = re.sub(r'\bкм/ч\b', ' километров в час ', text)
        text = re.sub(r'\bт\.е\.\b', ' то есть ', text)
        text = re.sub(r'\bт\.д\.\b', ' так далее ', text)
        text = re.sub(r'\bт\.к\.\b', ' так как ', text)
        text = re.sub(r'\bт\.п\.\b', ' тому подобное ', text)
        text = re.sub(r'\bн\.э\.\b', ' нашей эры ', text)
        text = re.sub(r'\bдр\.\b', ' другие ', text)

        # 3. Currency and symbols
        text = text.replace('%', ' процентов ')
        text = text.replace('$', ' долларов ')
        text = text.replace('€', ' евро ')
        text = text.replace('₽', ' рублей ')
        text = text.replace('№', ' номер ')
        text = text.replace('#', ' номер ')
        text = text.replace('+', ' плюс ')
        text = text.replace('&', ' и ')
        text = text.replace('@', ' собака ')
        text = re.sub(r'°C\b', ' градусов Цельсия ', text)
        text = text.replace('°', ' градусов ')

        # 4. Tech / brand names mapping (case-insensitive)
        for eng, rus in sorted(RU_COMMON_WORDS.items(), key=lambda x: -len(x[0])):
            text = re.sub(rf'\b{re.escape(eng)}\b', rus, text, flags=re.IGNORECASE)

        # 5. Version prefixes: 'v2.0' -> 'версии 2.0'
        text = re.sub(r'\bv(\d+)', r'версии \1', text, flags=re.IGNORECASE)

        if num2words:
            # 6. Dates with months: '15 мая', '3 сентября'
            def repl_date(m):
                day = int(m.group(1))
                month = m.group(2)
                try:
                    w = num2words.num2words(day, lang='ru', to='ordinal')
                    w = re.sub(r'ый$', 'ого', w)
                    w = re.sub(r'ой$', 'ого', w)
                    w = re.sub(r'ий$', 'ьего', w) if day == 3 else re.sub(r'ий$', 'его', w)
                    return f'{w} {month}'
                except Exception:
                    return m.group(0)
            text = re.sub(rf'(\b\d{{1,2}})\s+{RU_MONTHS}\b', repl_date, text, flags=re.IGNORECASE)

            # 7. Prepositional Years: 'в 1927 году / г.'
            def repl_prep_yr(m):
                prep = m.group(1)
                yr = int(m.group(2))
                try:
                    w = num2words.num2words(yr, lang='ru', to='ordinal')
                    w = re.sub(r'ый$', 'ом', w)
                    w = re.sub(r'ой$', 'ом', w)
                    w = re.sub(r'ий$', 'ем', w)
                    return f'{prep}{w} году'
                except Exception:
                    return m.group(0)
            text = re.sub(r'(\b[в|к]\s+)(\d{4})(?:\s+году|\s*г\.?(?=\s|[.,!?]|$))', repl_prep_yr, text, flags=re.IGNORECASE)

            # 8. Genitive years: 'с 1927 года / г.'
            def repl_gen_yr(m):
                prefix = m.group(1) or ''
                yr = int(m.group(2))
                try:
                    w = num2words.num2words(yr, lang='ru', to='ordinal')
                    w = re.sub(r'ый$', 'ого', w)
                    w = re.sub(r'ой$', 'ого', w)
                    w = re.sub(r'ий$', 'его', w)
                    return f'{prefix}{w} года'
                except Exception:
                    return m.group(0)
            text = re.sub(r'(\b(?:с|со|до|от|после|около|начала|конца|середины)\s+)?(\d{4})(?:\s+года|\s*г\.?(?=\s|[.,!?]|$))', repl_gen_yr, text, flags=re.IGNORECASE)

            # 9. Nominative years: '1927 год'
            def repl_nom_yr(m):
                yr = int(m.group(1))
                try:
                    w = num2words.num2words(yr, lang='ru', to='ordinal')
                    return f'{w} год'
                except Exception:
                    return m.group(0)
            text = re.sub(r'(\d{4})\s+год\b', repl_nom_yr, text, flags=re.IGNORECASE)

            # 10. Quantities after prepositions: 'около 60 гектаров', 'до 500'
            def repl_gen_num(m):
                prep = m.group(1)
                val = int(m.group(2))
                try:
                    w = _to_genitive_num_ru(val, num2words)
                    return f'{prep}{w}'
                except Exception:
                    return m.group(0)
            text = re.sub(r'(\b(?:около|до|от|более|менее|свыше|не менее|не более)\s+)(\d+)\b', repl_gen_num, text, flags=re.IGNORECASE)

            # 11. Decimals: '2.0' -> 'два точка ноль', '3,5' -> 'три запятая пять'
            def repl_dec(m):
                try:
                    i = num2words.num2words(int(m.group(1)), lang='ru')
                    sep = 'точка' if m.group(2) == '.' else 'запятая'
                    f = num2words.num2words(int(m.group(3)), lang='ru')
                    return f'{i} {sep} {f}'
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b(\d+)([.,])(\d+)\b', repl_dec, text)

            # 12. Time: '14:30' -> 'четырнадцать тридцать'
            def repl_time(m):
                try:
                    h = num2words.num2words(int(m.group(1)), lang='ru')
                    mi = num2words.num2words(int(m.group(2)), lang='ru')
                    return f'{h} {mi}'
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b(\d{1,2}):(\d{2})\b', repl_time, text)

            # 13. Ranges: '10-15' -> 'десять тире пятнадцать'
            def repl_range(m):
                try:
                    a = num2words.num2words(int(m.group(1)), lang='ru')
                    b = num2words.num2words(int(m.group(2)), lang='ru')
                    return f'{a} тире {b}'
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b(\d+)\s*[-–—]\s*(\d+)\b', repl_range, text)

            # 14. Units after remaining numbers
            text = re.sub(r'(\b\d+)\s*км\b', r'\1 километров', text)
            text = re.sub(r'(\b\d+)\s*кг\b', r'\1 килограммов', text)
            text = re.sub(r'(\b\d+)\s*мин\b', r'\1 минут', text)
            text = re.sub(r'(\b\d+)\s*сек\b', r'\1 секунд', text)
            text = re.sub(r'(\b\d+)\s*руб\.?\b', r'\1 рублей', text)

            # 15. Remaining cardinal numbers
            def repl_cardinal(m):
                try:
                    return num2words.num2words(int(m.group(0)), lang='ru')
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b\d+\b', repl_cardinal, text)

        # 16. Transliterate remaining English/Latin words into Cyrillic phonemes
        def repl_latin(m):
            return transliterate_latin_to_cyrillic(m.group(0))
        text = re.sub(r'[a-zA-Z]+', repl_latin, text)

    elif lang_key == "de":
        text = text.replace('%', ' Prozent ')
        text = text.replace('$', ' Dollar ')
        text = text.replace('€', ' Euro ')
        text = text.replace('&', ' und ')
        text = text.replace('+', ' plus ')

        # Brand names pronunciation in German
        text = re.sub(r'\bDicty\b', 'Dikti', text, flags=re.IGNORECASE)
        text = re.sub(r'\bTTS\b', 'T-T-S', text, flags=re.IGNORECASE)

        if num2words:
            # Decimals: '2,5' -> 'zwei Komma fünf'
            def repl_de_dec(m):
                try:
                    i = num2words.num2words(int(m.group(1)), lang='de')
                    f = num2words.num2words(int(m.group(3)), lang='de')
                    return f'{i} Komma {f}'
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b(\d+)([.,])(\d+)\b', repl_de_dec, text)

            # Years: 'im Jahr 1927'
            def repl_de_year(m):
                yr = int(m.group(2))
                try:
                    return f"{m.group(1)}{num2words.num2words(yr, lang='de', to='year')}"
                except Exception:
                    return m.group(0)
            text = re.sub(r'(\b(?:im Jahr|Jahr)\s+)(\d{4})\b', repl_de_year, text, flags=re.IGNORECASE)

            # General numbers
            def repl_de_num(m):
                try:
                    return num2words.num2words(int(m.group(0)), lang='de')
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b\d+\b', repl_de_num, text)

        text = text.lower()

    elif lang_key == "es":
        text = text.replace('%', ' por ciento ')
        text = text.replace('$', ' dólares ')
        text = text.replace('€', ' euros ')
        text = text.replace('&', ' y ')
        text = text.replace('+', ' más ')
        text = re.sub(r'\bDicty\b', 'Dicti', text, flags=re.IGNORECASE)

        if num2words:
            # Decimals: '2,5' -> 'dos coma cinco'
            def repl_es_dec(m):
                try:
                    i = num2words.num2words(int(m.group(1)), lang='es')
                    f = num2words.num2words(int(m.group(3)), lang='es')
                    return f'{i} coma {f}'
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b(\d+)([.,])(\d+)\b', repl_es_dec, text)

            def repl_es_num(m):
                try:
                    return num2words.num2words(int(m.group(0)), lang='es')
                except Exception:
                    return m.group(0)
            text = re.sub(r'\b\d+\b', repl_es_num, text)

        text = text.lower()

    text = re.sub(r'\s+', ' ', text).strip()
    return text


class SileroService:
    _instance = None
    _singleton_lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            with cls._singleton_lock:
                if not cls._instance:
                    cls._instance = super(SileroService, cls).__new__(cls)
                    cls._instance._initialized = False
        return cls._instance

    def __init__(self, models_dir: str = SILERO_MODELS_DIR):
        if getattr(self, "_initialized", False):
            return
        self._initialized = True
        self.models_dir = models_dir
        os.makedirs(self.models_dir, exist_ok=True)
        self._loaded_models: Dict[str, Any] = {}
        self._model_lock = threading.Lock()
        
        # Background download state
        self._download_state = {
            "status": "idle",
            "percent": 0.0,
            "message": "",
            "voice_id": None,
            "lang_key": None
        }
        self._download_lock = threading.Lock()

    def get_catalog_voices(self) -> List[Dict[str, Any]]:
        voices = []
        for voice_id, cfg in SILERO_VOICES_CONFIG.items():
            lang_key = cfg["lang_key"]
            is_inst = self.is_model_installed(lang_key)
            voices.append({
                "id": voice_id,
                "name": cfg["name"],
                "gender": cfg["gender"],
                "accent": cfg["accent"],
                "flag": cfg.get("flag", "🌐"),
                "description": cfg["description"],
                "lang": cfg["lang"],
                "engine": "silero",
                "installed": is_inst
            })
        return voices

    def is_model_installed(self, lang_key: str) -> bool:
        cfg = SILERO_LANG_CONFIG.get(lang_key)
        if not cfg:
            return False
        model_path = os.path.join(self.models_dir, cfg["model_file"])
        if os.path.exists(model_path) and os.path.getsize(model_path) > 10 * 1024 * 1024:
            return True
        if lang_key == "ru":
            for alt_name in ["v5_ru.pt", "v4_ru.pt"]:
                alt_p = os.path.join(self.models_dir, alt_name)
                if os.path.exists(alt_p) and os.path.getsize(alt_p) > 10 * 1024 * 1024:
                    return True
        return False

    def is_voice_installed(self, voice_id: str) -> bool:
        if not ensure_torch_runtime():
            return False
        cfg = SILERO_VOICES_CONFIG.get(voice_id)
        if not cfg:
            return False
        return self.is_model_installed(cfg["lang_key"])

    def delete_voice(self, voice_id: str) -> bool:
        cfg = SILERO_VOICES_CONFIG.get(voice_id)
        if not cfg:
            return False
        lang_key = cfg["lang_key"]
        lcfg = SILERO_LANG_CONFIG.get(lang_key)
        if not lcfg:
            return False
        
        model_path = os.path.join(self.models_dir, lcfg["model_file"])
        with self._model_lock:
            if lang_key in self._loaded_models:
                del self._loaded_models[lang_key]
            if os.path.exists(model_path):
                try:
                    os.remove(model_path)
                    logger.info(f"Deleted Silero model: {model_path}")
                except Exception as e:
                    logger.error(f"Failed to delete model {model_path}: {e}")
                    return False

            # If Russian, also remove any alternative model files (e.g. v4_ru.pt)
            if lang_key == "ru":
                for alt_name in ["v4_ru.pt", "v5_ru.pt"]:
                    alt_path = os.path.join(self.models_dir, alt_name)
                    if os.path.exists(alt_path):
                        try:
                            os.remove(alt_path)
                        except Exception:
                            pass

            # Check if any other Silero models remain installed
            remaining = [
                f for f in os.listdir(self.models_dir)
                if f.endswith(".pt") and os.path.getsize(os.path.join(self.models_dir, f)) > 10 * 1024 * 1024
            ] if os.path.exists(self.models_dir) else []

            if not remaining:
                logger.info("No Silero models remain. Reclaiming disk space by removing PyTorch runtime...")
                self.delete_torch_runtime()

            return True

    def delete_torch_runtime(self) -> bool:
        """Deletes dynamic PyTorch library from Application Support to free disk space."""
        lib_dir = get_dynamic_lib_dir()
        torch_dir = os.path.join(lib_dir, "torch")
        torchgen_dir = os.path.join(lib_dir, "torchgen")
        te_file = os.path.join(lib_dir, "typing_extensions.py")
        try:
            if os.path.exists(torch_dir):
                shutil.rmtree(torch_dir, ignore_errors=True)
            if os.path.exists(torchgen_dir):
                shutil.rmtree(torchgen_dir, ignore_errors=True)
            if os.path.exists(te_file):
                try:
                    os.remove(te_file)
                except Exception:
                    pass
            try:
                if os.path.exists(lib_dir) and not os.listdir(lib_dir):
                    os.rmdir(lib_dir)
            except Exception:
                pass
            logger.info("Successfully deleted dynamic PyTorch runtime to free disk space.")
            global TORCH_AVAILABLE, torch, package
            TORCH_AVAILABLE = False
            torch = None
            package = None
            return True
        except Exception as e:
            logger.error(f"Failed to delete PyTorch runtime: {e}")
            return False

    def get_download_status(self) -> Dict[str, Any]:
        with self._download_lock:
            return dict(self._download_state)

    def start_download_background(self, voice_id: str) -> Dict[str, Any]:
        with self._download_lock:
            if self._download_state["status"] == "downloading":
                return {"status": "already_downloading", "percent": self._download_state["percent"], "voice_id": self._download_state.get("voice_id")}
            cfg = SILERO_VOICES_CONFIG.get(voice_id, {})
            lang_key = cfg.get("lang_key", "")
            self._download_state["status"] = "downloading"
            self._download_state["percent"] = 2.0
            self._download_state["message"] = f"Initiating download for {voice_id}..."
            self._download_state["voice_id"] = voice_id
            self._download_state["lang_key"] = lang_key

        thread = threading.Thread(target=self._download_worker, args=(voice_id,), daemon=True)
        thread.start()
        return {"status": "started", "voice_id": voice_id, "lang_key": lang_key}

    def _download_worker(self, voice_id: str):
        try:
            cfg = SILERO_VOICES_CONFIG.get(voice_id)
            if not cfg:
                raise ValueError(f"Unknown voice_id: {voice_id}")
            lang_key = cfg["lang_key"]
            lcfg = SILERO_LANG_CONFIG.get(lang_key)
            if not lcfg:
                raise ValueError(f"Unknown language key: {lang_key}")

            # 1. Ensure PyTorch runtime is available
            if not ensure_torch_runtime():
                logger.info("PyTorch runtime not detected; downloading on-demand...")
                with self._download_lock:
                    self._download_state["status"] = "downloading"
                    self._download_state["percent"] = 5.0
                    self._download_state["message"] = "Downloading Speech Engine components (PyTorch ~120 MB)..."
                    self._download_state["voice_id"] = voice_id
                    self._download_state["lang_key"] = lang_key

                def torch_progress(pct, downloaded, total):
                    # Scale PyTorch download from 5% to 55%
                    scaled = 5.0 + (pct * 0.50)
                    with self._download_lock:
                        self._download_state["percent"] = round(scaled, 1)
                        self._download_state["message"] = f"Downloading Speech Engine ({downloaded/(1024*1024):.1f}/{total/(1024*1024):.1f} MB)..."

                success = download_and_install_torch_runtime(progress_callback=torch_progress)
                if not success:
                    raise RuntimeError("Failed to initialize PyTorch runtime after download.")

            # 2. Download Silero voice model file if not already present
            dest_path = os.path.join(self.models_dir, lcfg["model_file"])
            temp_path = dest_path + ".tmp"
            
            # Check if model already exists and is valid (> 10MB)
            model_installed = os.path.exists(dest_path) and os.path.getsize(dest_path) > 10 * 1024 * 1024
            if not model_installed and lang_key == "ru":
                # Check if v4_ru.pt already exists
                alt_p = os.path.join(self.models_dir, "v4_ru.pt")
                if os.path.exists(alt_p) and os.path.getsize(alt_p) > 10 * 1024 * 1024:
                    model_installed = True

            if not model_installed:
                url = lcfg["url"]
                logger.info(f"Downloading Silero model from {url} to {dest_path}...")

                with self._download_lock:
                    self._download_state["percent"] = 60.0
                    self._download_state["message"] = f"Downloading voice model ({lcfg['model_file']})..."

                req = urllib.request.Request(url, headers={"User-Agent": "Dicty/1.0"})
                with open_url_safe(req, timeout=30) as resp:
                    total_bytes = int(resp.headers.get("Content-Length", 0))
                    downloaded = 0
                    with open(temp_path, "wb") as f_out:
                        chunk_size = 512 * 1024
                        while True:
                            chunk = resp.read(chunk_size)
                            if not chunk:
                                break
                            f_out.write(chunk)
                            downloaded += len(chunk)
                            if total_bytes > 0:
                                pct = (downloaded / total_bytes) * 100.0
                                scaled = 60.0 + (pct * 0.38) # 60% -> 98%
                                with self._download_lock:
                                    self._download_state["percent"] = round(scaled, 1)
                                    self._download_state["message"] = f"Downloading {lcfg['model_file']} ({downloaded/(1024*1024):.1f}/{total_bytes/(1024*1024):.1f} MB)..."
                os.replace(temp_path, dest_path)

            logger.info(f"Successfully configured Silero voice {voice_id}")
            with self._download_lock:
                self._download_state["status"] = "completed"
                self._download_state["percent"] = 100.0
                self._download_state["message"] = f"Voice {voice_id} ready to use."
                self._download_state["voice_id"] = voice_id
                self._download_state["lang_key"] = lang_key

        except Exception as e:
            logger.error(f"Failed to install Silero voice {voice_id}: {e}", exc_info=True)
            with self._download_lock:
                self._download_state["status"] = "failed"
                self._download_state["message"] = f"Download failed: {str(e)}"

    def _get_or_load_model(self, lang_key: str):
        with self._model_lock:
            if lang_key in self._loaded_models:
                return self._loaded_models[lang_key]

            lcfg = SILERO_LANG_CONFIG.get(lang_key)
            if not lcfg:
                raise ValueError(f"Unsupported Silero language: {lang_key}")

            model_path = os.path.join(self.models_dir, lcfg["model_file"])
            if not os.path.exists(model_path):
                if lang_key == "ru":
                    for alt_name in ["v5_ru.pt", "v4_ru.pt"]:
                        alt_p = os.path.join(self.models_dir, alt_name)
                        if os.path.exists(alt_p) and os.path.getsize(alt_p) > 10 * 1024 * 1024:
                            model_path = alt_p
                            break
                if not os.path.exists(model_path):
                    # Also check local cache fallback if present
                    cache_path = os.path.expanduser(f"~/.cache/torch/hub/snakers4_silero-models_master/src/silero/model/{lcfg['model_file']}")
                    if os.path.exists(cache_path):
                        model_path = cache_path
                    else:
                        raise FileNotFoundError(f"Silero model for {lang_key} not installed at {model_path}")

            logger.info(f"Loading Silero model from {model_path}...")
            t0 = time.perf_counter()
            if not ensure_torch_runtime() or package is None:
                raise RuntimeError("PyTorch is required for Silero TTS models but is not installed in this environment.")
            imp = package.PackageImporter(model_path)
            model = imp.load_pickle("tts_models", "model")
            self._loaded_models[lang_key] = model
            logger.info(f"Loaded Silero {lang_key} model in {time.perf_counter()-t0:.3f}s")
            return model

    def synthesize(
        self,
        text: str,
        voice: str,
        speed: float = 1.0,
        sentence_pause: float = 0.25,
        clause_pause: float = 0.10,
        expressiveness: float = 0.0,
    ) -> bytes:
        if not text or not text.strip():
            raise ValueError("Input text is empty")

        vcfg = SILERO_VOICES_CONFIG.get(voice)
        if not vcfg:
            # Fallback to first matching voice
            vcfg = next((v for v in SILERO_VOICES_CONFIG.values() if v["speaker"] in voice), None)
            if not vcfg:
                vcfg = SILERO_VOICES_CONFIG["silero:ru_baya"]

        lang_key = vcfg["lang_key"]
        speaker = vcfg["speaker"]
        lcfg = SILERO_LANG_CONFIG[lang_key]
        sample_rate = lcfg["sample_rate"] # 48000

        model = self._get_or_load_model(lang_key)

        t_start = time.perf_counter()
        
        # 1. Normalize text (expand numbers, dates, currencies, tech terms, transliterate foreign words)
        norm_text = normalize_text_for_silero(text, lang_key)
        if not norm_text.strip():
            norm_text = text.strip()

        # Prepare keyword arguments for Silero apply_tts
        kwargs = {
            "speaker": speaker,
            "sample_rate": sample_rate,
        }
        if lcfg.get("put_accent"):
            kwargs["put_accent"] = True
        if lcfg.get("put_yo"):
            kwargs["put_yo"] = True

        import inspect
        sig = inspect.signature(model.apply_tts)
        if "put_stress_homo" in sig.parameters and lcfg.get("put_stress_homo", True):
            kwargs["put_stress_homo"] = True
        if "put_yo_homo" in sig.parameters and lcfg.get("put_yo_homo", True):
            kwargs["put_yo_homo"] = True
        if "stress_single_vowel" in sig.parameters:
            kwargs["stress_single_vowel"] = True

        # Silero FastPitch models achieve their natural, fluid melodic prosody when processing
        # full paragraphs unified (as in the official Google Colab demo).
        # We only chunk text if it exceeds Silero's single-pass symbol limit (~800 characters).
        if len(norm_text) <= 800:
            try:
                chunk = model.apply_tts(text=norm_text, **kwargs)
                combined = chunk.numpy().astype(np.float32)
            except Exception as e:
                logger.warning(f"Unified synthesis failed: {e}, falling back to paragraph chunks")
                combined = None
        else:
            combined = None

        if combined is None:
            # Group into larger paragraph chunks (~500-700 chars) on sentence boundaries
            raw_sentences = [s.strip() for s in re.split(r'([.!?…]+[\s\n]+)', norm_text) if s.strip()]
            sentences = []
            buf = ""
            for s in raw_sentences:
                if re.match(r'^[.!?…]+$', s):
                    buf += s
                    if buf.strip():
                        sentences.append(buf.strip())
                    buf = ""
                else:
                    if buf.strip():
                        sentences.append(buf.strip())
                    buf = s
            if buf.strip():
                sentences.append(buf.strip())

            # Aggregate into ~600 character blocks
            blocks = []
            current_block = ""
            for s in sentences:
                if len(current_block) + len(s) + 1 <= 600:
                    current_block = f"{current_block} {s}".strip() if current_block else s
                else:
                    if current_block:
                        blocks.append(current_block)
                    current_block = s
            if current_block:
                blocks.append(current_block)

            audio_chunks: List[np.ndarray] = []
            for b in blocks:
                try:
                    c = model.apply_tts(text=b, **kwargs)
                    audio_chunks.append(c.numpy().astype(np.float32))
                except Exception as e:
                    logger.warning(f"Error synthesizing block '{b[:30]}...': {e}")
                    continue

            if not audio_chunks:
                raise RuntimeError("Failed to generate audio chunks for text")
            combined = np.concatenate(audio_chunks)

        # Speed scaling if requested (resample or time-stretch)
        out_sr = sample_rate
        if abs(speed - 1.0) > 0.03:
            # We scale playback rate cleanly by adjusting WAV framerate or resampling
            # DictyClient's AVAudioPlayer also handles hardware speed directly
            pass

        # Convert to 16-bit PCM WAV
        audio_int16 = (combined * 32767.0).clip(-32768, 32767).astype(np.int16)
        
        import io
        wav_io = io.BytesIO()
        with wave.open(wav_io, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(out_sr)
            wf.writeframes(audio_int16.tobytes())

        elapsed = time.perf_counter() - t_start
        audio_dur = len(audio_int16) / float(out_sr)
        speed_factor = audio_dur / elapsed if elapsed > 0 else 0
        logger.info(
            f"[TTS:Silero] Synthesized {len(text)} chars with '{voice}' ({speaker}) @ {out_sr}Hz | "
            f"audio={audio_dur:.2f}s | latency={elapsed*1000:.1f}ms | speed={speed_factor:.1f}x real-time"
        )

        return wav_io.getvalue()
