"""
Voice snippets: say a short trigger ("my LinkedIn"), get prepared text pasted.

Fully deterministic, no LLM, ~0 ms. Matching rules (strictest first):
  1. The whole utterance is a trigger ("My LinkedIn.") -> the result IS the snippet.
     Also with a cue word: "insert my LinkedIn" as the whole utterance.
  2. Inline with an explicit cue word ("...my profile is insert my LinkedIn") -> cue + trigger replaced.
  3. Inline bare trigger, only for snippets flagged `expand_anywhere` (e.g. a unique "my email address").
Bare triggers inside normal sentences are NOT expanded by default, so dictating
"my email address is broken" stays literal.

Matching tolerates what speech-to-text varies: case, punctuation and spacing
("LinkedIn" == "linked in" == "Linked-In").

Inline matches become placeholders (⟦S1⟧) so later LLM stages (self-correction, formatting)
can't rewrite the snippet, and its content never reaches a cloud LLM. `expand()` swaps them back
at the very end.
"""
import json
import os
import re
import threading
import uuid
from typing import Dict, List, Optional, Tuple

CUE_WORDS = ("insert", "paste", "вставь", "вставить")

_PLACEHOLDER_RE = re.compile(r"⟦\s*S(\d+)\s*⟧", re.IGNORECASE)
_NON_WORD_RE = re.compile(r"[\W_]+", re.UNICODE)


def normalize(text: str) -> str:
    """Lowercase, punctuation -> space, collapse whitespace."""
    return _NON_WORD_RE.sub(" ", (text or "").lower()).strip()


def _compact(text: str) -> str:
    return normalize(text).replace(" ", "")


def _phrases(snippet: dict) -> List[str]:
    out = []
    for p in [snippet.get("trigger", "")] + list(snippet.get("aliases") or []):
        if p and _compact(p) and p not in out:
            out.append(p)
    return out


def _phrase_pattern(phrase: str) -> str:
    """Regex for a phrase that ignores case/spacing/punctuation between its characters.

    Built from the compact form char by char with optional separators, so "linkedin" matches
    "Linked In", "linked-in" and "LinkedIn"."""
    chars = [re.escape(c) for c in _compact(phrase)]
    return r"[\s,.\-]{0,2}".join(chars)


def _is_cue(text: str) -> bool:
    return normalize(text) in CUE_WORDS


class _Matcher:
    def __init__(self):
        self.expansions: Dict[str, str] = {}

    def token_for(self, content: str) -> str:
        key = f"⟦S{len(self.expansions) + 1}⟧"
        self.expansions[key] = content
        return key


def detect(text: str, snippets: List[dict]) -> Tuple[str, Dict[str, str], bool]:
    """Finds snippet triggers in a transcript.

    Returns (text_with_placeholders, {placeholder: content}, snippet_only).
    `snippet_only` means the whole utterance was a trigger: callers can skip LLM stages entirely."""
    if not text or not snippets:
        return text, {}, False

    usable = [s for s in snippets if (s.get("content") or "") and _phrases(s)]
    if not usable:
        return text, {}, False

    # Rule 1: whole utterance == trigger (optionally prefixed by a cue word)
    full = _compact(text)
    for s in usable:
        for p in _phrases(s):
            cp = _compact(p)
            if full == cp or any(full == _compact(cue) + cp for cue in CUE_WORDS):
                m = _Matcher()
                return m.token_for(s["content"]), m.expansions, True

    # Rules 2 + 3: inline. Longest phrases first so "my work email" wins over "my email".
    pairs = sorted(((p, s) for s in usable for p in _phrases(s)), key=lambda ps: -len(_compact(ps[0])))
    m = _Matcher()
    cue_alt = "|".join(re.escape(c) for c in CUE_WORDS)
    out = text
    for phrase, s in pairs:
        body = _phrase_pattern(phrase)
        # Rule 2: explicit cue word right before the trigger
        cue_re = re.compile(rf"(?<!\w)(?:{cue_alt})[\s,:]+{body}(?!\w)", re.IGNORECASE)
        out = cue_re.sub(lambda _m, c=s["content"]: m.token_for(c), out)
        # Rule 3: bare trigger, only when the user allowed it for this snippet
        if s.get("expand_anywhere"):
            bare_re = re.compile(rf"(?<!\w){body}(?!\w)", re.IGNORECASE)
            out = bare_re.sub(lambda _m, c=s["content"]: m.token_for(c), out)
    return out, m.expansions, False


def expand(text: str, expansions: Dict[str, str]) -> Tuple[str, bool]:
    """Replaces placeholders with snippet content.

    Returns (text, ok). ok=False if an LLM stage dropped or duplicated a placeholder: the caller
    should then fall back to the pre-LLM text, since the snippet would otherwise be lost."""
    if not expansions:
        return text, True
    found = [f"⟦S{n}⟧" for n in _PLACEHOLDER_RE.findall(text or "")]
    ok = sorted(found) == sorted(expansions.keys())
    result = _PLACEHOLDER_RE.sub(lambda m: expansions.get(f"⟦S{m.group(1)}⟧", ""), text or "")
    return result, ok


def whisper_bias_terms(snippets: List[dict]) -> List[str]:
    """Trigger phrases to bias speech recognition toward (never the content)."""
    terms = []
    for s in snippets or []:
        t = (s.get("trigger") or "").strip()
        if t and t not in terms:
            terms.append(t)
    return terms


class SnippetsManager:
    """JSON-backed store, same pattern as the vocabulary manager."""

    def __init__(self, path: str):
        self.path = path
        self.lock = threading.Lock()
        self._cache: Optional[List[dict]] = None
        self._mtime: float = -1.0

    def _read(self) -> List[dict]:
        try:
            mtime = os.path.getmtime(self.path)
        except OSError:
            return []
        if self._cache is not None and mtime == self._mtime:
            return self._cache
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self._cache, self._mtime = (data if isinstance(data, list) else []), mtime
        except Exception:
            self._cache = []
        return self._cache

    def _write(self, data: List[dict]) -> None:
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp, self.path)
        self._cache, self._mtime = data, os.path.getmtime(self.path)

    def get_all(self) -> List[dict]:
        with self.lock:
            return list(self._read())

    @staticmethod
    def _clean(trigger: str, content: str, aliases, expand_anywhere) -> dict:
        trigger = (trigger or "").strip()
        if not _compact(trigger):
            raise ValueError("Trigger must contain letters or digits")
        if not (content or "").strip():
            raise ValueError("Content must not be empty")
        return {
            "trigger": trigger,
            "content": content,
            "aliases": [a.strip() for a in (aliases or []) if a and _compact(a)],
            "expand_anywhere": bool(expand_anywhere),
        }

    def add(self, trigger: str, content: str, aliases=None, expand_anywhere: bool = False) -> dict:
        item = {"id": str(uuid.uuid4()), **self._clean(trigger, content, aliases, expand_anywhere)}
        with self.lock:
            data = list(self._read())
            if any(_compact(s.get("trigger", "")) == _compact(item["trigger"]) for s in data):
                raise ValueError(f"A snippet with trigger '{item['trigger']}' already exists")
            data.insert(0, item)
            self._write(data)
        return item

    def update(self, item_id: str, trigger: str, content: str, aliases=None, expand_anywhere: bool = False) -> Optional[dict]:
        fields = self._clean(trigger, content, aliases, expand_anywhere)
        with self.lock:
            data = list(self._read())
            if any(s.get("id") != item_id and _compact(s.get("trigger", "")) == _compact(fields["trigger"]) for s in data):
                raise ValueError(f"A snippet with trigger '{fields['trigger']}' already exists")
            for s in data:
                if s.get("id") == item_id:
                    s.update(fields)
                    self._write(data)
                    return s
        return None

    def delete(self, item_id: str) -> bool:
        with self.lock:
            data = list(self._read())
            kept = [s for s in data if s.get("id") != item_id]
            if len(kept) == len(data):
                return False
            self._write(kept)
            return True
