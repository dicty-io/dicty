"""Deterministic dictation styles.

Only three styles are rule based and never touch a language model:

* ``exact``  - the words exactly as they came out of speech-to-text.
* ``clean``  - remove spoken fillers, add basic punctuation and capitalisation.
* ``code``   - keep identifiers and casing exactly; never add a final period.

``message``, ``email`` and ``note`` are handled by the formatting LLM (see
``prompts.py``); ``message`` may use the same rule pass first so short dictations
stay instant.

Everything in this module has to stay in the low-millisecond range. No network,
no model loading, no per-call regex compilation.
"""

from __future__ import annotations

import re

STYLES = ("exact", "clean", "message", "email", "note", "code")

# Styles that are complete without an LLM.
RULE_BASED_STYLES = frozenset({"exact", "clean", "code"})

# Styles whose best output needs an LLM. ``message`` is intentionally absent:
# it works with rules and only benefits from an LLM when one is available.
STYLE_NEEDS_LLM = {
    "exact": False,
    "clean": False,
    "message": False,
    "email": True,
    "note": True,
    "code": False,
}

# Old client values (Profile.formatStyle / dictation_format_style) -> new style.
# Keep this table as the single source of truth for the migration report.
LEGACY_STYLE_MAP = {
    "raw": "exact",
    "exact": "exact",
    "punctuation_fast": "clean",
    "clean": "clean",
    "message": "message",
    "email": "email",
    "note": "note",
    "code": "code",
    "custom": "message",
    "book": "note",
    "dialogue_structured": "note",
    "meeting_summary": "note",
    "summary": "note",
    "raw_dialogue": "exact",
    "librarian": "clean",
}

# Reverse mapping for the deprecated fields clients read for one more release.
STYLE_TO_LEGACY = {
    "exact": "raw",
    "clean": "punctuation_fast",
    "message": "message",
    "email": "email",
    "note": "note",
    # Never advertise "code" to old clients: it triggers the librarian queue there.
    "code": "custom",
}

# Short before/after pairs used by the clients and by the migration report.
STYLE_EXAMPLES = {
    "exact": (
        "let's meet Tuesday actually Wednesday",
        "let's meet Tuesday actually Wednesday",
    ),
    "clean": (
        "um so I think we should uh ship it",
        "I think we should ship it.",
    ),
    "message": (
        "hey um can we push the call to tomorrow",
        "Hey, can we push the call to tomorrow?",
    ),
    "email": (
        "hi sarah thanks for the update can we move the review to friday",
        "Hi Sarah,\n\nThanks for the update. Can we move the review to Friday?\n\nBest,",
    ),
    "note": (
        "the api is slow because the cache misses on every request",
        "## Finding\n\n- The API is slow because the cache misses on every request.",
    ),
    "code": (
        "um rename get user id to user id.",
        "rename get user id to user id",
    ),
}


def legacy_to_style(value: str | None, default: str = "clean") -> str:
    """Translate an old formatting-style value to the new style vocabulary."""
    if not value:
        return default
    key = str(value).strip().lower()
    return LEGACY_STYLE_MAP.get(key, default if key not in STYLES else key)


def style_to_legacy(value: str | None) -> str:
    return STYLE_TO_LEGACY.get(str(value or "").strip().lower(), "raw")


# Spoken fillers in English, German and Russian. Deliberately conservative:
# words that can carry meaning ("like", "er", "mm") are not removed.
_FILLER_RE = re.compile(
    r"(?:,\s*)?(?<![\w-])(?:um+|uh+|uhm+|erm+|hmm+|mhm+|äh+m?|öh+m?|э-э|ээ+|мм+)(?![\w-])[,]?\s*",
    re.IGNORECASE,
)

# Discourse markers that only add noise at the start of a sentence.
_LEADING_MARKERS_RE = re.compile(
    r"(^|(?<=[.!?])\s+)(?:(?:so|well|okay|ok|right|alright|ну|вот|короче|also|na)\b[,]?\s+)+",
    re.IGNORECASE,
)

_SPOKEN_PUNCTUATION = (
    # Longest phrases first so "точка с запятой" is not eaten by "точка".
    (re.compile(r"\b(?:новое\s+предложение|new\s+sentence|neuer\s+satz)\b", re.IGNORECASE), ". "),
    (re.compile(r"\b(?:точка\s+с\s+запятой|semicolon|semikolon)\b", re.IGNORECASE), ";"),
    (re.compile(r"\b(?:новый\s+абзац|new\s+paragraph|neuer\s+absatz)\b", re.IGNORECASE), "\n\n"),
    (re.compile(r"\b(?:новая\s+строка|new\s+line|neue\s+zeile)\b", re.IGNORECASE), "\n"),
    (re.compile(r"\b(?:вопросительный\s+знак|знак\s+вопроса|question\s+mark|fragezeichen)\b", re.IGNORECASE), "?"),
    (re.compile(r"\b(?:восклицательный\s+знак|знак\s+восклицания|exclamation\s+(?:mark|point)|ausrufezeichen)\b", re.IGNORECASE), "!"),
    (re.compile(r"\b(?:двоеточие|colon|doppelpunkt)\b", re.IGNORECASE), ":"),
    (re.compile(r"\b(?:тире|em\s*dash|gedankenstrich)\b", re.IGNORECASE), " — "),
    (re.compile(r"\b(?:запятая|comma|komma)\b", re.IGNORECASE), ","),
    (re.compile(r"\b(?:точк[ау]|точка|period|full\s+stop|punkt)\b", re.IGNORECASE), "."),
    (re.compile(r"\b(?:многоточие|ellipsis)\b", re.IGNORECASE), "…"),
    (re.compile(r"\b(?:открыть\s+кавычки|открываются\s+кавычки|open\s+quotes?|anführungszeichen\s+unten)\b", re.IGNORECASE), "«"),
    (re.compile(r"\b(?:закрыть\s+кавычки|закрываются\s+кавычки|close\s+quotes?|anführungszeichen\s+oben)\b", re.IGNORECASE), "»"),
    (re.compile(r"\b(?:в\s+кавычках|quotes?)\b", re.IGNORECASE), '"'),
)

_I_CONTRACTION_RE = re.compile(r"\bi(['’])(m|ve|ll|d)\b", re.IGNORECASE)


def _apply_spoken_punctuation(text: str) -> str:
    # Hyphen joins surrounding words directly without spaces ("art hyphen design" -> "art-design")
    text = re.sub(r"\s*\b(?:дефис|hyphen|bindestrich)\b\s*", "-", text, flags=re.IGNORECASE)
    for pattern, replacement in _SPOKEN_PUNCTUATION:
        # A spoken mark attaches to the word before it.
        text = pattern.sub(replacement, text)
    return text


def _strip_fillers(text: str) -> str:
    # A space keeps "think, um, we" -> "think we" instead of "thinkwe".
    return _FILLER_RE.sub(" ", text)


def _strip_leading_markers(text: str) -> str:
    text = text.lstrip()
    # Two passes handle "um, so, well ..." after the filler pass.
    for _ in range(2):
        updated = _LEADING_MARKERS_RE.sub(r"\1", text)
        if updated == text:
            break
        text = updated
    return text


def _normalize_whitespace(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = []
    for line in text.split("\n"):
        line = re.sub(r"[ \t]+", " ", line).strip()
        lines.append(line)
    text = "\n".join(lines)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _normalize_code_whitespace(text: str) -> str:
    """Collapse noisy spaces without touching indentation or identifiers."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"(?<=\S)[ \t]{2,}", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _normalize_punctuation(text: str) -> str:
    # No space before punctuation.
    text = re.sub(r"[ \t]+([,.;:!?…»])", r"\1", text)
    # No space after opening quotes.
    text = re.sub(r"([«])\s+", r"\1", text)
    # One space after punctuation, except before digits (3.5), newlines and
    # another punctuation mark. A period only gets a space when it follows a
    # lowercase letter and is followed by an uppercase one ("end.Next").
    text = re.sub(r"([,;:!?…»])(?=[^\s\d,.;:!?…»])", r"\1 ", text)
    text = re.sub(r"(?<=[a-zа-яё])\.(?=[A-ZА-ЯЁ])", ". ", text)
    # Collapse duplicated punctuation produced by a filler removal.
    text = re.sub(r",\s*,+", ",", text)
    text = re.sub(r",\s*\.", ".", text)
    text = re.sub(r"\.\s*\.(?!\.)", ".", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    return text


def _capitalize_sentences(text: str) -> str:
    out = []
    capitalize_next = True
    for index, char in enumerate(text):
        if capitalize_next and char.isalpha():
            out.append(char.upper())
            capitalize_next = False
        else:
            out.append(char)
        if char in ".!?…":
            # A period between digits is a decimal (3.5), not a sentence end.
            if (
                char == "."
                and 0 < index < len(text) - 1
                and text[index - 1].isdigit()
                and text[index + 1].isdigit()
            ):
                continue
            capitalize_next = True
        elif char == "\n":
            capitalize_next = True
    return "".join(out)


def _fix_standalone_i(text: str) -> str:
    text = re.sub(r"\bi\b", "I", text)
    return _I_CONTRACTION_RE.sub(lambda m: "I" + m.group(1) + m.group(2).lower(), text)


def _ensure_final_period(text: str) -> str:
    stripped = text.rstrip()
    if not stripped:
        return stripped
    last = stripped[-1]
    if last.isalnum() or last in '"\')]}»':
        stripped += "."
    return stripped


def apply_clean(text: str) -> str:
    """Rules-only cleanup: fillers out, punctuation and capitals in."""
    if not text or not text.strip():
        return text
    cleaned = _apply_spoken_punctuation(text)
    cleaned = _strip_fillers(cleaned)
    cleaned = _strip_leading_markers(cleaned)
    cleaned = _normalize_whitespace(cleaned)
    cleaned = _normalize_punctuation(cleaned)
    cleaned = _capitalize_sentences(cleaned)
    cleaned = _fix_standalone_i(cleaned)
    cleaned = _ensure_final_period(cleaned)
    return cleaned.strip()


def apply_code(text: str) -> str:
    """Rules-only code style: keep identifiers, casing and line structure."""
    if not text or not text.strip():
        return text
    cleaned = _strip_fillers(text)
    cleaned = _strip_leading_markers(cleaned)
    cleaned = _normalize_code_whitespace(cleaned)
    # A dictated sentence often ends with a period; code must not.
    cleaned = re.sub(r"\.\s*$", "", cleaned).rstrip()
    return cleaned


def apply_style(text: str, style: str | None) -> str:
    """Apply a style. Non rule-based styles are returned unchanged."""
    if not text:
        return text
    key = str(style or "").strip().lower()
    if key == "exact":
        return text
    if key == "clean":
        return apply_clean(text)
    if key == "code":
        return apply_code(text)
    return text
