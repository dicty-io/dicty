"""On-device (local) self-correction.

This is the "local" half of self-correction: it runs on the machine, never
touches the network and stays in the low-millisecond range. It cleans up the
easy spoken mistakes:

* filler words ("um", "uh", "э-э", "äh"),
* accidental repeats of short function words ("the the", "to to", "is is"),
* spacing left behind by the removals.

It is deliberately conservative. It never reorders meaning and never deletes a
word the speaker did not obviously repeat. Harder cases (real retractions like
"send it Tuesday, actually no, Wednesday") are left to the model when the mode
allows cloud, and left untouched when the mode is local-only. That is the whole
reason ``ai_location`` exists: local is instant and safe, cloud is smarter.
"""

from __future__ import annotations

import re

import style_rules

# Short function words that are almost never said twice on purpose. Words that
# can legitimately close one clause and open the next ("is is", "in in", "to to",
# "on on", "do do", "will will", "that that", "had had") are left out.
_SAFE_REPEATS = (
    "the", "a", "an", "and", "or", "but", "of", "at", "for", "with", "it",
    "its", "this", "these", "those", "they", "we", "you", "he", "she", "i",
    "my", "your", "our", "me", "us", "as", "by", "from", "have", "has", "be",
    "then", "than", "if", "not",
)

# Only spaces and tabs: never join a word at the end of one line with the first
# word of the next.
_REPEAT_RE = re.compile(
    r"\b(" + "|".join(sorted(_SAFE_REPEATS, key=len, reverse=True)) + r")\b(?:[ \t]+\1\b)+",
    re.IGNORECASE,
)


def _collapse_repeats(text: str) -> str:
    return _REPEAT_RE.sub(lambda match: match.group(1), text)


def fix(text: str) -> str:
    """Apply the local correction pass. Idempotent and safe to run twice."""
    if not text or not text.strip():
        return text
    out = style_rules._strip_fillers(text)
    out = _collapse_repeats(out)
    out = style_rules._normalize_whitespace(out)
    out = style_rules._normalize_punctuation(out)
    return out
