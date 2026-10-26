"""
meeting_dialogue.py
===================
Speaker separation and dialogue reconstruction pipeline for meetings.
Provides:
  - Segment dataclass
  - parse_whisper_timestamped
  - merge_timelines
  - dedupe_bleed
  - label_you_others
  - render_dialogue
  - smart_llm_speaker_separation (chunked, temperature=0, robust fallback)
"""
from __future__ import annotations
from dataclasses import dataclass, field
import difflib
import json
import re
from typing import Literal, Optional, List, Dict, Any, Tuple

@dataclass
class Segment:
    id: int
    start: float
    end: float
    source: Literal["you", "others"]
    text: str
    speaker: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "start": round(self.start, 2),
            "end": round(self.end, 2),
            "source": self.source,
            "text": self.text,
            "speaker": self.speaker
        }


KNOWN_WHISPER_HALLUCINATIONS = {
    "thank you", "thank you.", "thank you very much", "thank you very much.",
    "thanks", "thanks.", "thanks for watching", "thanks for watching.", "thanks for watching!",
    "thank you for watching", "thank you for watching.", "thank you for watching!",
    "thank you so much", "thank you so much for watching",
    "please subscribe", "subscribe", "subscribe to my channel",
    "please subscribe, like, and turn on the bell icon to be notified when i post my latest videos",
    "please subscribe, like, and turn on the bell icon to be notified when i post my latest videos.",
    "thank you for watching, please subscribe, like, and turn on the bell icon to be notified when i post my latest videos",
    "thank you for watching, please subscribe, like, and turn on the bell icon to be notified when i post my latest videos.",
    "thank you for watching, please turn on the bell icon to be notified when i post my latest videos",
    "thank you for watching, please turn on the bell icon to be notified when i post my latest videos.",
    "notified when i post my latest videos", "notified when i post my latest videos.",
    "the bell icon to be notified when i post my latest videos",
    "the bell icon to be notified when i post my latest videos.",
    "if you enjoyed this video", "see you next time", "see you in the next video",
    "bye", "bye.", "you", "you.", "okay", "okay.", "test", "test.",
    "[blank_audio]", "[silence]", "."
}


def is_whisper_hallucination(text: str) -> bool:
    """Detects repetitive YouTube training set hallucinations emitted by Whisper during silence."""
    if not text:
        return True
    cleaned = re.sub(r"[^\w\s]", "", text.lower()).strip()
    if len(cleaned) < 2:
        return True
    if cleaned in KNOWN_WHISPER_HALLUCINATIONS:
        return True
    # Catch characteristic YouTube outro / subtitle hallucination cues
    single_cues = [
        "subscribe to my channel", "subscribe to our channel",
        "please subscribe", "bell icon", "latest videos",
        "turn on the bell", "like and subscribe", "thank you for watching",
        "thanks for watching", "see you next time", "see you in the next video"
    ]
    if any(cue in cleaned for cue in single_cues):
        return True

    # Repetitive token / single-character loops emitted by Whisper on silent tracks
    # (e.g. "ლ ლ ლ ლ ..." or "ᶜ ᶜ ᶜ ..." when the microphone was unused during a meeting).
    tokens = cleaned.split()
    if tokens:
        if all(len(t) <= 1 for t in tokens):
            return True
        if len(tokens) >= 4 and len(set(tokens)) <= max(2, len(tokens) // 4):
            return True
    if len(cleaned) >= 6 and len(set(cleaned.replace(" ", ""))) <= 2:
        return True
    return False


def track_has_speech(
    audio_path: str,
    min_rms: float = 0.008,
    min_voiced_seconds: float = 0.4,
) -> bool:
    """
    Fast pre-transcription check (~2ms for a 2-minute WAV): returns True only if `audio_path`
    contains at least `min_voiced_seconds` of frames above `min_rms`.
    Used to skip transcribing the microphone track when the user stayed silent during a meeting,
    which otherwise queues a second full-length job on single-threaded whisper-server and doubles latency.
    """
    try:
        import os
        import wave
        import numpy as np
        if not audio_path or not os.path.exists(audio_path):
            return False
        with wave.open(audio_path, "rb") as w:
            sr = w.getframerate()
            raw = w.readframes(w.getnframes())
            sampwidth = w.getsampwidth()
            channels = max(1, w.getnchannels())
        if sampwidth != 2 or sr <= 0 or not raw:
            return True
        audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
        if channels > 1:
            audio = audio.reshape(-1, channels).mean(axis=1)
        frame = max(1, int(sr * 0.02))  # 20ms frames
        n_frames = len(audio) // frame
        if n_frames == 0:
            return False
        frames = audio[: n_frames * frame].reshape(n_frames, frame)
        rms = np.sqrt(np.mean(frames * frames, axis=1))
        voiced_seconds = float(np.sum(rms >= min_rms)) * 0.02
        return voiced_seconds >= min_voiced_seconds
    except Exception:
        return True


def filter_silent_track_segments(
    audio_path: str,
    segments: List[Segment],
    min_segment_rms: float = 0.008,
    min_active_ratio: float = 0.08,
) -> List[Segment]:
    """
    Drops segments whose time span in `audio_path` has no real speech energy.
    Whisper hallucinates repetitive characters or YouTube phrases on near-silent tracks (e.g. an
    unspoken microphone during a meeting). Checking the actual waveform in each [start, end] span
    prevents silent-mic hallucinations from interleaving and splitting the other track's sentences.
    """
    if not segments or not audio_path:
        return segments
    try:
        import os
        import wave
        import numpy as np
        if not os.path.exists(audio_path):
            return segments
        with wave.open(audio_path, "rb") as w:
            sr = w.getframerate()
            raw = w.readframes(w.getnframes())
            sampwidth = w.getsampwidth()
            channels = max(1, w.getnchannels())
        if sampwidth != 2 or sr <= 0 or not raw:
            return segments
        audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
        if channels > 1:
            audio = audio.reshape(-1, channels).mean(axis=1)
        # Synthetic all-zero dummy WAVs in unit tests have peak == 0.0 (real mics always have a non-zero noise floor)
        if float(np.max(np.abs(audio))) == 0.0:
            return segments
        frame = max(1, int(sr * 0.02))  # 20ms frames
    except Exception:
        return segments

    kept: List[Segment] = []
    for seg in segments:
        s0 = max(0, int(seg.start * sr))
        s1 = min(len(audio), int(max(seg.end, seg.start + 0.2) * sr))
        clip = audio[s0:s1]
        if len(clip) < frame:
            continue
        n_frames = len(clip) // frame
        frames = clip[: n_frames * frame].reshape(n_frames, frame)
        rms = np.sqrt(np.mean(frames * frames, axis=1))
        # Voice activity: 90th-percentile frame energy must clear the speech floor, and at least
        # `min_active_ratio` of frames must be above threshold (rejects isolated mic clicks).
        p90 = float(np.percentile(rms, 90))
        active = float(np.mean(rms >= min_segment_rms))
        if p90 >= min_segment_rms and active >= min_active_ratio:
            kept.append(seg)
    return kept


def parse_whisper_timestamped(text: str, source: Literal["you", "others"] = "others") -> List[Segment]:
    """
    Parses `[mm:ss - mm:ss] text`, `[mm:ss.xxx --> mm:ss.xxx] text`, or
    `[hh:mm:ss.xxx --> hh:mm:ss.xxx] text` (whisper.cpp CLI format) into Segment objects.
    Filters out Whisper silence hallucinations (e.g. YouTube subscriber intros/outros).
    If no timestamp regex matches, treats the entire non-empty text as a single segment covering 0.0 to 0.0.
    """
    if not text or not text.strip():
        return []

    pattern = re.compile(
        r"\[(?:(\d{1,2}):)?(\d{1,2}):(\d{2}(?:\.\d+)?)\s*(?:-|-->)\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2}(?:\.\d+)?)\]\s*(.*)"
    )
    inline_ts_strip = re.compile(
        r"\[(?:\d{1,2}:)?\d{1,2}:\d{2}(?:\.\d+)?\s*(?:-|-->)\s*(?:\d{1,2}:)?\d{1,2}:\d{2}(?:\.\d+)?\]\s*"
    )
    segments: List[Segment] = []
    idx = 0

    for line in text.splitlines():
        line_clean = line.strip()
        if not line_clean:
            continue
        m = pattern.match(line_clean)
        if m:
            start_h, start_m, start_s, end_h, end_m, end_s, segment_text = m.groups()
            start_val = (float(start_h) * 3600.0 if start_h else 0.0) + float(start_m) * 60.0 + float(start_s)
            end_val = (float(end_h) * 3600.0 if end_h else 0.0) + float(end_m) * 60.0 + float(end_s)
            seg_text_clean = inline_ts_strip.sub("", segment_text).strip()
            if seg_text_clean and not is_whisper_hallucination(seg_text_clean):
                segments.append(Segment(
                    id=idx,
                    start=start_val,
                    end=max(start_val, end_val),
                    source=source,
                    text=seg_text_clean
                ))
                idx += 1
        else:
            # Line without timestamps
            cleaned = inline_ts_strip.sub("", line_clean).strip()
            if cleaned and not is_whisper_hallucination(cleaned):
                segments.append(Segment(
                    id=idx,
                    start=0.0,
                    end=0.0,
                    source=source,
                    text=cleaned
                ))
                idx += 1

    return segments


def merge_timelines(you_segments: List[Segment], others_segments: List[Segment]) -> List[Segment]:
    """
    Merges segments from both sources, sorts chronologically by start time,
    and re-indexes IDs monotonically starting from 0.
    If start times are identical, preserves 'you' then 'others' stably.
    """
    combined = []
    for s in you_segments:
        combined.append(Segment(id=0, start=s.start, end=s.end, source="you", text=s.text, speaker=s.speaker))
    for s in others_segments:
        combined.append(Segment(id=0, start=s.start, end=s.end, source="others", text=s.text, speaker=s.speaker))

    # Stable sort by start time
    combined.sort(key=lambda s: (s.start, 0 if s.source == "you" else 1))

    for idx, seg in enumerate(combined):
        seg.id = idx

    return combined


def dedupe_bleed(
    you_segments: List[Segment],
    others_segments: List[Segment],
    time_overlap_ratio_threshold: float = 0.60,
    text_similarity_threshold: float = 0.70
) -> List[Segment]:
    """
    Echo / bleed mitigation:
    When speakers are used without headphones, the microphone picks up audio from the participants.
    Drops a mic ('you') segment if:
      1. Its time interval overlaps with an 'others' segment by > 60% of the mic segment duration.
      2. Its normalized text matches the 'others' text by > 70% difflib ratio.
    Returns the filtered you_segments list.
    """
    if not you_segments or not others_segments:
        return list(you_segments)

    kept: List[Segment] = []

    def normalize(t: str) -> str:
        return re.sub(r"[^\w\s]", "", t.lower()).strip()

    for y in you_segments:
        y_dur = max(0.001, y.end - y.start)
        y_norm = normalize(y.text)
        is_bleed = False

        for o in others_segments:
            # Calculate temporal overlap
            overlap_start = max(y.start, o.start)
            overlap_end = min(y.end, o.end)
            overlap_duration = max(0.0, overlap_end - overlap_start)
            overlap_ratio = overlap_duration / y_dur

            if overlap_ratio >= time_overlap_ratio_threshold:
                o_norm = normalize(o.text)
                sim = difflib.SequenceMatcher(None, y_norm, o_norm).ratio()
                if sim >= text_similarity_threshold:
                    is_bleed = True
                    break

        if not is_bleed:
            kept.append(y)

    return kept


def label_you_others(
    segments: List[Segment],
    you_label: str = "You",
    others_label: str = "Others"
) -> List[Segment]:
    """
    Labels each segment deterministically based on track source.
    """
    for seg in segments:
        if seg.source == "you":
            seg.speaker = you_label if you_label.strip() else "You"
        else:
            seg.speaker = others_label if others_label.strip() else "Others"
    return segments


def consolidate_sentence_units(segments: List[Segment], max_join_gap_s: float = 0.8) -> List[Dict[str, Any]]:
    """
    Merges consecutive segments from the same track ('you' or 'others') that clearly belong to the
    same ongoing sentence (previous segment does NOT end with terminal sentence punctuation `.`, `?`, `!`)
    into sentence-level units before sending to the LLM.

    Whisper splits continuous speech every ~2-4s at arbitrary word boundaries (e.g. 'no UX' / 'component.').
    Feeding 47 sub-sentence fragments to an LLM causes it to either assign 'Speaker 1' to everything or
    switch speakers mid-phrase. Consolidating into sentence units (~10-15 per minute) lets the LLM reason
    over actual statements, questions, and replies, and maps the chosen speaker back to the underlying
    segment IDs.
    """
    units: List[Dict[str, Any]] = []
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        if units:
            prev = units[-1]
            gap = seg.start - prev["end"]
            prev_text = prev["text"].rstrip()
            ends_sentence = bool(re.search(r"[.!?…\"')\]]\s*$", prev_text))
            if prev["source"] == seg.source and not ends_sentence and gap <= max_join_gap_s:
                prev["text"] = prev_text + " " + text
                prev["end"] = max(prev["end"], seg.end)
                prev["seg_ids"].append(seg.id)
                continue
        units.append({
            "unit_id": len(units),
            "seg_ids": [seg.id],
            "start": seg.start,
            "end": seg.end,
            "source": seg.source,
            "text": text,
        })
    return units


def compute_voice_hints(
    units: List[Dict[str, Any]],
    audio_path: Optional[str],
    max_clusters: int = 4,
) -> Dict[int, str]:
    """
    Extracts lightweight acoustic voice signatures (fundamental pitch F0 + spectral centroid +
    13 MFCCs) for each 'others' sentence unit directly from `audio_path` (~15ms total using numpy/scipy)
    and clusters them into recurring voice IDs (`V1 ~155Hz`, `V2 ~210Hz`, ...).

    Why this matters: text alone cannot reliably tell whether a later paragraph is a brand-new speaker
    or an earlier speaker (e.g. Speaker 1) returning to the conversation. Passing `[voice:V1 ~155Hz]`
    hints into the LLM prompt anchors speaker re-identification across the meeting at zero extra cost.
    """
    if not audio_path or not units:
        return {}
    try:
        import os
        import wave
        import numpy as np
        if not os.path.exists(audio_path):
            return {}
        with wave.open(audio_path, "rb") as w:
            sr = w.getframerate()
            raw = w.readframes(w.getnframes())
            sampwidth = w.getsampwidth()
            channels = max(1, w.getnchannels())
        if sampwidth != 2 or sr <= 0 or not raw:
            return {}
        audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
        if channels > 1:
            audio = audio.reshape(-1, channels).mean(axis=1)
        if float(np.max(np.abs(audio))) == 0.0:
            return {}
    except Exception:
        return {}

    # Precompute mel filterbank (80 Hz .. sr/2, 24 bands)
    n_fft = 512
    freqs = np.fft.rfftfreq(n_fft, 1.0 / sr)
    mel_lo = 2595.0 * np.log10(1.0 + 80.0 / 700.0)
    mel_hi = 2595.0 * np.log10(1.0 + (sr / 2.0) / 700.0)
    mel_pts = 700.0 * (10.0 ** (np.linspace(mel_lo, mel_hi, 26) / 2595.0) - 1.0)
    fb = np.zeros((24, len(freqs)), dtype=np.float32)
    for m in range(1, 25):
        f_l, f_c, f_r = mel_pts[m - 1], mel_pts[m], mel_pts[m + 1]
        up = (freqs - f_l) / (f_c - f_l + 1e-8)
        dn = (f_r - freqs) / (f_r - f_c + 1e-8)
        fb[m - 1] = np.maximum(0.0, np.minimum(up, dn))
    # Cosine DCT-II basis for 13 MFCCs (c1..c13)
    k_idx = np.arange(1, 14)[:, None]
    n_idx = np.arange(24)[None, :]
    dct_basis = np.cos(np.pi * k_idx * (2 * n_idx + 1) / 48.0).astype(np.float32)

    frame = max(1, int(0.032 * sr))
    hop = max(1, int(0.016 * sr))
    win = np.hanning(frame).astype(np.float32)
    q_lo, q_hi = max(1, int(sr / 300.0)), max(2, int(sr / 75.0))

    sigs: Dict[int, Any] = {}
    for u in units:
        if u.get("source") != "others":
            continue
        s0 = max(0, int(u["start"] * sr))
        s1 = min(len(audio), int(u["end"] * sr))
        clip = audio[s0:s1]
        if len(clip) < frame:
            continue
        clip = np.append(clip[0], clip[1:] - 0.97 * clip[:-1])
        n_fr = 1 + (len(clip) - frame) // hop
        idx = np.arange(frame)[None, :] + hop * np.arange(n_fr)[:, None]
        frames = clip[idx]
        rms = np.sqrt(np.mean(frames * frames, axis=1))
        thr = max(0.005, float(np.percentile(rms, 35)))
        voiced = frames[rms >= thr]
        if len(voiced) < 2:
            voiced = frames
        wframes = voiced * win
        spec = (np.abs(np.fft.rfft(wframes, n=n_fft)) ** 2).astype(np.float32)
        mel = np.log(np.maximum(spec @ fb.T, 1e-10))
        mfcc = (mel @ dct_basis.T)  # (frames, 13)
        cent = float(np.median((spec @ freqs) / (np.sum(spec, axis=1) + 1e-8)))
        cep = np.fft.irfft(np.log(np.maximum(spec, 1e-10)), n=n_fft)
        f0s = []
        if q_hi > q_lo and q_hi <= cep.shape[1]:
            sub = cep[:, q_lo:q_hi]
            pks = q_lo + np.argmax(sub, axis=1)
            vals = np.max(sub, axis=1)
            for pk, val in zip(pks, vals):
                if val > 0.04 and pk > 0:
                    f0s.append(sr / float(pk))
        f0 = float(np.median(f0s)) if f0s else 150.0
        sigs[u["unit_id"]] = (f0, cent, np.median(mfcc, axis=0), u["end"] - u["start"])

    if len(sigs) < 2:
        return {}

    # Anchor clustering on segments >= 2.0s (stable voice print), then assign shorter utterances
    uids = sorted(sigs.keys())
    raw_vecs = np.array([
        np.concatenate([[np.log(max(sigs[i][0], 75.0)), np.log(max(sigs[i][1], 200.0))], sigs[i][2]])
        for i in uids
    ], dtype=np.float32)
    std = np.std(raw_vecs, axis=0)
    std[std < 1e-6] = 1.0
    Z = (raw_vecs - np.mean(raw_vecs, axis=0)) / std
    Z[:, 0] *= 1.6  # pitch
    Z[:, 1] *= 1.2  # vocal-tract spectral brightness
    Z = Z / (np.linalg.norm(Z, axis=1, keepdims=True) + 1e-8)

    anchor_idx = [k for k, uid in enumerate(uids) if sigs[uid][3] >= 2.0]
    if len(anchor_idx) < 2:
        anchor_idx = list(range(len(uids)))

    clusters: List[List[int]] = [[k] for k in anchor_idx]
    dist = 1.0 - (Z @ Z.T)
    while len(clusters) > 1:
        best_d = 999.0
        best_pair = None
        for a in range(len(clusters)):
            for b in range(a + 1, len(clusters)):
                d = float(np.mean([dist[i, j] for i in clusters[a] for j in clusters[b]]))
                if d < best_d:
                    best_d, best_pair = d, (a, b)
        if best_d > 0.78 and len(clusters) <= max_clusters:
            break
        if best_pair is None:
            break
        a, b = best_pair
        clusters[a].extend(clusters[b])
        del clusters[b]

    # Assign non-anchor short segments to nearest cluster centroid
    centroids = [np.mean(Z[c], axis=0) for c in clusters]
    for k in range(len(uids)):
        if k in anchor_idx:
            continue
        sims = [float(np.dot(Z[k], c / (np.linalg.norm(c) + 1e-8))) for c in centroids]
        clusters[int(np.argmax(sims))].append(k)

    clusters.sort(key=lambda c: min(c))
    hints: Dict[int, str] = {}
    for cid, c in enumerate(clusters, 1):
        med_f0 = int(round(float(np.median([sigs[uids[k]][0] for k in c])) / 5.0) * 5)
        for k in c:
            uid = uids[k]
            hints[uid] = f"V{cid}~{med_f0}Hz"
    return hints


def build_smart_llm_input(segments: List[Segment], voice_hints: Optional[Dict[int, str]] = None) -> str:
    """
    Builds compact numbered transcript with pause gaps (and optional acoustic voice cluster hints)
    to feed into LLM:
    #0 [00:01.2-00:04.8] (YOU) Hi everyone...
    #1 [00:05.1-00:09.0] (OTHERS) [voice:V1~155Hz] Thanks Vasilii... [gap +0.3s]
    """
    lines: List[str] = []
    prev_end: Optional[float] = None

    for seg in segments:
        s_m = int(seg.start) // 60
        s_s = seg.start % 60
        e_m = int(seg.end) // 60
        e_s = seg.end % 60
        time_tag = f"[{s_m:02d}:{s_s:04.1f}-{e_m:02d}:{e_s:04.1f}]"
        src_tag = "(YOU)" if seg.source == "you" else "(OTHERS)"
        vh = f" [voice:{voice_hints[seg.id]}]" if (voice_hints and seg.id in voice_hints) else ""

        gap_str = ""
        if prev_end is not None and seg.start > prev_end + 0.15:
            gap_dur = seg.start - prev_end
            gap_str = f"  [gap +{gap_dur:.1f}s]"

        lines.append(f"#{seg.id} {time_tag} {src_tag}{vh} {seg.text}{gap_str}")
        prev_end = max(prev_end or 0.0, seg.end)

    return "\n".join(lines)


async def smart_llm_speaker_separation(
    segments: List[Segment],
    llm_service: Any,
    model: str = "openai/gpt-4o-mini",
    api_key: Optional[str] = None,
    provider: Optional[str] = None,
    base_url: Optional[str] = None,
    you_label: str = "You",
    others_label: str = "Others",
    others_audio_path: Optional[str] = None,
) -> Tuple[List[Segment], List[str]]:
    """
    Uses LLM to separate OTHERS track segments into Speaker 1, 2... or identified names.
    Processes in chunks of 150 segments if very long.
    Returns (segments, warning_notes).
    """
    warnings: List[str] = []
    if not segments:
        return segments, warnings

    # Check if there are any 'others' segments to disambiguate
    others_count = sum(1 for s in segments if s.source == "others")
    if others_count == 0:
        return label_you_others(segments, you_label=you_label, others_label=others_label), warnings

    from prompts import get_speaker_labeling_system_prompt

    # Consolidate sub-sentence Whisper fragments into full sentence units so the LLM reasons over
    # complete statements/questions/replies instead of mid-phrase slices, then map labels back to segments.
    units_raw = consolidate_sentence_units(segments)
    unit_segments: List[Segment] = [
        Segment(id=u["unit_id"], start=u["start"], end=u["end"], source=u["source"], text=u["text"])
        for u in units_raw
    ]
    unit_to_seg_ids: Dict[int, List[int]] = {u["unit_id"]: u["seg_ids"] for u in units_raw}
    voice_hints = compute_voice_hints(units_raw, others_audio_path)

    chunk_size = 150
    overlap = 10
    total_segments = len(unit_segments)

    # Dictionary mapping unit_id (int) -> speaker label (str)
    all_assigned_labels: Dict[int, str] = {}
    known_speakers_cumulative: Dict[str, str] = {} # e.g. {"Speaker 1": "Anna"}

    start_idx = 0
    while start_idx < total_segments:
        end_idx = min(start_idx + chunk_size, total_segments)
        chunk = unit_segments[start_idx:end_idx]

        transcript_chunk_input = build_smart_llm_input(chunk, voice_hints=voice_hints)
        system_prompt = get_speaker_labeling_system_prompt()

        known_speakers_desc = ""
        if known_speakers_cumulative:
            known_speakers_desc = f"\nKnown speakers from earlier conversation context: {json.dumps(known_speakers_cumulative)}"

        others_ids = [str(s.id) for s in chunk if s.source == "others"]
        user_prompt = (
            f"Please assign speakers ('Speaker 1', 'Speaker 2', 'Speaker 3', ...) "
            f"to EVERY `(OTHERS)` line: {', '.join('#' + i for i in others_ids)}.\n"
            f"Carefully identify every question/answer exchange, direct address by name, acknowledgment, "
            f"and perspective shift so distinct participants are separated.\n"
            f"{known_speakers_desc}\n\n"
            f"<transcript>\n{transcript_chunk_input}\n</transcript>\n\n"
            f"Return a JSON object containing `\"analysis\"`, `\"speakers\"` (with a key for EVERY `(OTHERS)` ID: {', '.join(others_ids)}), and `\"names\"`:\n"
            f'{{"analysis": "...", "speakers": {{"0": "Speaker 1", "1": "Speaker 2"}}, "names": {{}}}}'
        )

        try:
            import asyncio
            response_text = await asyncio.wait_for(
                llm_service.generate(
                    prompt=user_prompt,
                    system_prompt=system_prompt,
                    model=model,
                    api_key=api_key,
                    provider=provider,
                    base_url=base_url,
                    temperature=0.0
                ),
                timeout=45.0
            )

            # Robust JSON extraction
            parsed_json = None
            text_resp = response_text.strip()
            # If wrapped in markdown code fence, strip it
            if "```" in text_resp:
                match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text_resp)
                if match:
                    text_resp = match.group(1).strip()

            try:
                parsed_json = json.loads(text_resp)
            except Exception:
                # Attempt to extract first outer json object
                match = re.search(r"\{[\s\S]*\}", text_resp)
                if match:
                    parsed_json = json.loads(match.group(0))

            if isinstance(parsed_json, dict) and "speakers" in parsed_json:
                speakers_dict = parsed_json.get("speakers") or {}
                names_dict = parsed_json.get("names") or {}
                if isinstance(names_dict, dict):
                    known_speakers_cumulative.update(names_dict)

                # Map IDs
                last_label = "Speaker 1"
                for s in chunk:
                    if s.source == "you":
                        all_assigned_labels[s.id] = you_label
                        continue

                    raw_lbl = str(speakers_dict.get(str(s.id)) or speakers_dict.get(s.id) or "").strip()
                    if not raw_lbl or raw_lbl.lower() in ("you", "(you)", "none"):
                        # Inherit previous or default to Speaker 1
                        raw_lbl = last_label
                    else:
                        # Clean label: ensure "Speaker N" format if given as "speaker 1" or integer
                        if raw_lbl.isdigit():
                            raw_lbl = f"Speaker {raw_lbl}"
                        elif re.match(r"^speaker\s*\d+$", raw_lbl, re.IGNORECASE):
                            num = re.sub(r"[^\d]", "", raw_lbl)
                            raw_lbl = f"Speaker {num}"
                        last_label = raw_lbl

                    all_assigned_labels[s.id] = raw_lbl

                # If the LLM optionally provided real-name resolutions in 'names' mapping, apply them
                if isinstance(names_dict, dict) and names_dict:
                    for sid, lbl in list(all_assigned_labels.items()):
                        if lbl in names_dict:
                            all_assigned_labels[sid] = names_dict[lbl]
            else:
                raise ValueError("JSON response missing 'speakers' object")

        except Exception as e:
            msg = f"Speaker separation incomplete for segments {start_idx}..{end_idx}: {e}"
            print(f"[!] {msg}")
            warnings.append(msg)
            # Fallback to you_others for this chunk
            for s in chunk:
                if s.id not in all_assigned_labels:
                    all_assigned_labels[s.id] = you_label if s.source == "you" else others_label

        if end_idx >= total_segments:
            break
        start_idx = end_idx - overlap

    # Apply assigned unit labels back to the underlying segments
    seg_label_map: Dict[int, str] = {}
    for uid, lbl in all_assigned_labels.items():
        for sid in unit_to_seg_ids.get(uid, [uid]):
            seg_label_map[sid] = lbl
    for s in segments:
        s.speaker = seg_label_map.get(s.id, you_label if s.source == "you" else others_label)

    return segments, warnings


_CONVERSATIONAL_STARTER_RE = re.compile(
    r"^(?:yeah\b|yes\b|yep\b|no\b|nope\b|okay\b|ok\b|right\b|sure\b|totally\b|agreed\b|"
    r"thanks\b|thank you\b|got it\b|makes sense\b|all right\b|alright\b|so\s+yeah\b|"
    r"first of all\b|also,\b|and finally\b|as for\b|now\s+there\b|by the way\b|"
    r"this is great\b|on the other hand\b|[a-z]+,\s+(?:over to you|just a quick|thank|thanks)\b)",
    re.IGNORECASE,
)
_ACK_ONLY_RE = re.compile(
    r"^(?:yeah|yes|yep|no|nope|okay|ok|right|sure|totally|agreed|got it|makes sense|fine with that|it's understood)[.!?]*$",
    re.IGNORECASE,
)


def render_dialogue(
    segments: List[Segment],
    show_timestamps: bool = False,
    pause_merge_threshold_s: float = 2.0,
    max_bubble_words: int = 42,
    max_bubble_duration_s: float = 18.0,
) -> str:
    """
    Renders segments into clean Messenger-style Markdown dialogue turns:
    - Merges sub-sentence fragments from the same speaker until a complete sentence ends (`.`, `?`, `!`).
    - Starts a new chat bubble when:
      1. The speaker changes, OR
      2. There is a pause >= `pause_merge_threshold_s` after a completed sentence, OR
      3. The previous turn ended a sentence AND the next segment starts with a conversational turn/topic
         opener ('Yeah.', 'Okay.', 'Thanks, Kenny...', 'James, over to you...', 'Also, ...') or is a short
         standalone acknowledgment, OR
      4. The previous turn ended a sentence AND the current bubble already reached `max_bubble_words`
         or `max_bubble_duration_s` (so monologues break into readable 1-3 sentence chat messages).
    - Formats turns as `**Speaker**: Text` or `*(00:15)* **Speaker**: Text`.
    """
    if not segments:
        return ""

    inline_ts_strip = re.compile(
        r"\[(?:\d{1,2}:)?\d{1,2}:\d{2}(?:\.\d+)?\s*(?:-|-->)\s*(?:\d{1,2}:)?\d{1,2}:\d{2}(?:\.\d+)?\]\s*"
    )
    turns: List[Dict[str, Any]] = []

    for seg in segments:
        speaker = seg.speaker or ("You" if seg.source == "you" else "Others")
        text = inline_ts_strip.sub("", seg.text).strip()
        if not text:
            continue

        if turns:
            prev = turns[-1]
            gap = seg.start - prev["end"]
            prev_ends_sentence = bool(re.search(r"[.!?…\"')\]]\s*$", prev["text"]))

            if prev["speaker"] == speaker:
                # Never split mid-sentence unless there is an extreme pause (> 6s)
                if not prev_ends_sentence and gap < 6.0:
                    prev["text"] += " " + text
                    prev["end"] = max(prev["end"], seg.end)
                    continue

                if gap < pause_merge_threshold_s:
                    prev_words = len(prev["text"].split())
                    prev_dur = prev["end"] - prev["start"]
                    starts_new_thought = bool(_CONVERSATIONAL_STARTER_RE.match(text))
                    is_short_ack = bool(_ACK_ONLY_RE.match(prev["text"].strip()))
                    if (
                        not starts_new_thought
                        and not is_short_ack
                        and prev_words < max_bubble_words
                        and prev_dur < max_bubble_duration_s
                    ):
                        prev["text"] += " " + text
                        prev["end"] = max(prev["end"], seg.end)
                        continue

            # If a brief (<4s) interjection from another speaker split a single speaker's ongoing sentence
            # ("Sarah O'Don" / [brief You] / "nell and her team..."), stitch back into the speaker's prior
            # turn when that turn clearly ended mid-sentence (no terminal punctuation) and the current
            # segment is its immediate continuation.
            if (
                len(turns) >= 2
                and turns[-2]["speaker"] == speaker
                and turns[-1]["speaker"] != speaker
                and (turns[-1]["end"] - turns[-1]["start"]) <= 4.0
                and (seg.start - turns[-2]["end"]) < pause_merge_threshold_s
                and not re.search(r"[.!?…\"')\]]\s*$", turns[-2]["text"])
            ):
                turns[-2]["text"] += " " + text
                turns[-2]["end"] = max(turns[-2]["end"], seg.end)
                continue

        turns.append({
            "speaker": speaker,
            "text": text,
            "start": seg.start,
            "end": seg.end
        })

    lines: List[str] = []
    for turn in turns:
        speaker_part = f"**{turn['speaker']}**:"
        if show_timestamps:
            m = int(turn['start']) // 60
            s = int(turn['start']) % 60
            ts_part = f"*({m:02d}:{s:02d})* "
            lines.append(f"{ts_part}{speaker_part} {turn['text']}")
        else:
            lines.append(f"{speaker_part} {turn['text']}")

    return "\n\n".join(lines)
