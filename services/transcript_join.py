"""Join speech-to-text pieces without splitting words or duplicating boundaries.

Two kinds of input need different treatment:

* Whisper segments (``seg.text``) already carry the leading space that starts a new
  word. Stripping each segment and joining with ``" "`` loses that signal and inserts
  a space in the middle of a word when a segment starts mid-word (common in Cyrillic
  and other multi-byte scripts).
* Cloud/API responses come back as independent, stripped strings. They need a single
  space between them, and phrase-chunking can repeat the boundary word(s), so the
  overlap is removed deterministically here.
* whisper.cpp hard-wraps long output lines and can put the newline inside a word
  (``"язы\\nк"``). ``normalize_whisper_text`` removes only those mid-word breaks and
  turns real line boundaries into spaces.

The helpers are pure Python and run in well under a millisecond on normal dictations.
"""

import re
from typing import Iterable, Optional

_WHITESPACE_RE = re.compile(r"\s+")
_TOKEN_RE = re.compile(r"\S+")
_WORD_KEY_RE = re.compile(r"[\w']+", re.UNICODE)
_LINE_WRAP_RE = re.compile(r"(?<=\w)\n(?=\w)")
_HYPHEN_WRAP_RE = re.compile(r"(?<=[-\u2010\u2011])\n(?=\w)")

# A space is never inserted before these characters.
_NO_SPACE_BEFORE = ",.!?:;…)]}"

_MAX_OVERLAP_WORDS = 4


def fix_line_wraps(text: str) -> str:
    """Remove line breaks that whisper.cpp inserts in the middle of a word.

    whisper.cpp hard-wraps long output lines. The wrap can land inside a word
    (``"русский язы\\nк"``), so replacing every newline with a space splits the
    word. A newline between two word characters, or after a hyphen, is a wrap
    and must be removed. Other newlines separate segments and become spaces.
    """
    if not text:
        return text
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _LINE_WRAP_RE.sub("", text)
    text = _HYPHEN_WRAP_RE.sub("", text)
    return text.replace("\n", " ")


def normalize_whisper_text(text: str) -> str:
    """Make a raw Whisper response safe for display and transcript joining."""
    return _fix_punctuation_spacing(fix_line_wraps(text))


def _collapse(text: str) -> str:
    return _WHITESPACE_RE.sub(" ", text).strip()


def _word_key(token: str) -> str:
    """Normalize one token for boundary comparison (case/punctuation insensitive)."""
    match = _WORD_KEY_RE.search(token)
    return match.group(0).lower() if match else ""


def _boundary_overlap(previous: str, following: str) -> int:
    """Return how many leading words of ``following`` repeat the end of ``previous``."""
    prev_tokens = _TOKEN_RE.findall(previous)
    next_tokens = _TOKEN_RE.findall(following)
    max_words = min(_MAX_OVERLAP_WORDS, len(prev_tokens), len(next_tokens))

    for count in range(max_words, 0, -1):
        tail = [_word_key(t) for t in prev_tokens[-count:]]
        head = [_word_key(t) for t in next_tokens[:count]]
        # Ignore punctuation-only tokens, and require a real word match.
        if any(not key for key in tail) or any(not key for key in head):
            continue
        if tail == head:
            return count
    return 0


def _drop_leading_tokens(text: str, count: int) -> str:
    tokens = _TOKEN_RE.findall(text)
    return " ".join(tokens[count:])


def _fix_punctuation_spacing(text: str) -> str:
    """Remove a space that would end up before punctuation, then collapse runs."""
    text = re.sub(r"\s+([,.!?:;…])", r"\1", text)
    return _collapse(text)


def join_transcript_parts(
    parts: Iterable[Optional[str]],
    *,
    separate_responses: bool = False,
    dedupe_overlap: bool = True,
) -> str:
    """Join transcript pieces into one clean string.

    ``separate_responses=False`` (default) is for Whisper segments: their raw text is
    concatenated as-is so a segment that starts mid-word is not separated by a space.

    ``separate_responses=True`` is for independent API results (Deepgram finals,
    segmented cloud chunks). Parts are joined with one space, the repeated boundary
    word(s) are dropped, and no space is added before punctuation.
    """
    items = [part for part in parts if part and part.strip()]
    if not items:
        return ""

    if not separate_responses:
        return _fix_punctuation_spacing(fix_line_wraps("".join(items)))

    result = _collapse(fix_line_wraps(items[0]))
    for part in items[1:]:
        following = _collapse(fix_line_wraps(part))
        if not following:
            continue

        if dedupe_overlap:
            overlap = _boundary_overlap(result, following)
            if overlap:
                following = _drop_leading_tokens(following, overlap).strip()
                if not following:
                    continue

        if not result:
            result = following
        elif following[0] in _NO_SPACE_BEFORE:
            result += following
        else:
            result += " " + following

    return _fix_punctuation_spacing(result)
