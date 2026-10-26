"""
Per-transcription performance metrics for the "advanced metrics" view.

Stored separately from history (append-only JSONL) so that:
  - incognito transcriptions can be measured without persisting any content,
  - deleting history does not erase performance data.

Privacy: entries NEVER contain transcript text or audio, only numbers and model identifiers.
"""
import json
import os
import platform
import subprocess
import threading
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from model_manager import DATA_DIR

METRICS_FILE = os.path.join(DATA_DIR, "metrics.jsonl")
MAX_ENTRIES = 500

_lock = threading.Lock()
_hardware_cache: Optional[Dict[str, Any]] = None

# Whitelist: anything not listed here is dropped before writing (defense against leaking text).
_ALLOWED_FIELDS = {
    "id", "timestamp", "mode", "model_id", "model_name", "provider", "is_cloud",
    "audio_duration_s", "word_count", "engine_ms", "end_to_end_ms", "pasted", "incognito",
    "correction_latency_ms", "whisper_latency_ms", "whisper_ms", "correction_model",
    "llm_latency_ms", "reformat_model", "format_style",
}


def _read_all(path: str = None) -> List[Dict[str, Any]]:
    path = path or METRICS_FILE
    if not os.path.exists(path):
        return []
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out


def _write_all(entries: List[Dict[str, Any]], path: str = None) -> None:
    path = path or METRICS_FILE
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def record(*, mode: str, model_id: str, model_name: str, provider: str, is_cloud: bool,
           audio_duration_s: float, word_count: int, engine_ms: float, incognito: bool,
           correction_latency_ms: float = 0.0, whisper_latency_ms: float = 0.0,
           correction_model: str = "", llm_latency_ms: float = 0.0,
           reformat_model: str = "", format_style: str = "",
           path: str = None) -> str:
    """Appends a metrics entry and returns its id. Never raises."""
    entry_id = uuid.uuid4().hex
    w_ms = round(float(whisper_latency_ms or 0))
    entry = {
        "id": entry_id,
        "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
        "mode": mode,
        "model_id": model_id,
        "model_name": model_name or model_id,
        "provider": provider,
        "is_cloud": bool(is_cloud),
        "audio_duration_s": round(float(audio_duration_s or 0), 2),
        "word_count": int(word_count or 0),
        "engine_ms": round(float(engine_ms or 0)),
        "end_to_end_ms": None,
        "pasted": None,
        "incognito": bool(incognito),
        "correction_latency_ms": round(float(correction_latency_ms or 0)),
        "whisper_latency_ms": w_ms,
        "whisper_ms": w_ms,
        "correction_model": (correction_model or "").strip(),
        "llm_latency_ms": round(float(llm_latency_ms or 0)),
        "reformat_model": (reformat_model or "").strip(),
        "format_style": (format_style or "").strip(),
    }
    entry = {k: v for k, v in entry.items() if k in _ALLOWED_FIELDS}
    try:
        path = path or METRICS_FILE
        with _lock:
            with open(path, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
            # Trim occasionally (cheap check on file size: ~300 bytes/entry)
            if os.path.getsize(path) > MAX_ENTRIES * 450:
                entries = _read_all(path)
                if len(entries) > MAX_ENTRIES:
                    _write_all(entries[-MAX_ENTRIES:], path)
    except Exception as e:
        print(f"[!] Metrics write failed: {e}")
    return entry_id


def set_latency(entry_id: str, end_to_end_ms: float, pasted: bool, path: str = None) -> bool:
    """Attaches the client-measured stop->paste latency to an entry."""
    try:
        with _lock:
            entries = _read_all(path)
            # Search from newest: the entry is almost always one of the last few
            for e in reversed(entries):
                if e.get("id") == entry_id:
                    e["end_to_end_ms"] = round(float(end_to_end_ms))
                    e["pasted"] = bool(pasted)
                    _write_all(entries, path)
                    return True
    except Exception as e:
        print(f"[!] Metrics latency update failed: {e}")
    return False


def recent(limit: int = 10, path: str = None) -> List[Dict[str, Any]]:
    entries = [e for e in _read_all(path) if e.get("end_to_end_ms") is not None]
    return list(reversed(entries[-limit:]))


def _percentile(values: List[float], p: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    k = (len(s) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def per_model(period: str = "all", path: str = None) -> List[Dict[str, Any]]:
    """Aggregates per (model, provider): count, median/p90 stop->paste, median x-real-time."""
    entries = [e for e in _read_all(path) if e.get("end_to_end_ms") is not None]
    cutoff = _period_cutoff(period)
    if cutoff is not None:
        entries = [e for e in entries if _parse_ts(e.get("timestamp")) and _parse_ts(e["timestamp"]) >= cutoff]

    groups: Dict[tuple, List[Dict[str, Any]]] = {}
    for e in entries:
        groups.setdefault((e.get("model_id"), e.get("provider")), []).append(e)

    out = []
    for (model_id, provider), items in groups.items():
        # Pure transcription latency: remove LLM formatting & self-correction so the STT model is measured accurately
        lat = [max(10.0, float(i["end_to_end_ms"]) - (float(i.get("llm_latency_ms") or 0) + float(i.get("correction_latency_ms") or 0))) for i in items]
        xrt = [i["audio_duration_s"] * 1000.0 / l
               for i, l in zip(items, lat) if i.get("audio_duration_s") and l > 0]
        fit = _latency_fit(items)
        out.append({
            "model_id": model_id,
            "model_name": items[-1].get("model_name") or model_id,
            "provider": provider,
            "is_cloud": bool(items[-1].get("is_cloud")),
            "count": len(items),
            "median_ms": round(_percentile(lat, 0.5)),
            "p90_ms": round(_percentile(lat, 0.9)),
            "median_x_realtime": round(_percentile(xrt, 0.5), 1) if xrt else None,
            # latency ≈ fixed_overhead_ms + ms_per_audio_s × audio seconds (None if not enough spread)
            "fixed_overhead_ms": fit[0] if fit else None,
            "ms_per_audio_s": fit[1] if fit else None,
        })
    out.sort(key=lambda r: (-r["count"], r["median_ms"]))
    return out


def per_formatting(period: str = "all", path: str = None) -> List[Dict[str, Any]]:
    """Aggregates per styling/formatting LLM: runs, median/p90 latency."""
    entries = [e for e in _read_all(path)
               if (e.get("llm_latency_ms") or 0) > 0 and e.get("reformat_model")]
    cutoff = _period_cutoff(period)
    if cutoff is not None:
        entries = [e for e in entries if _parse_ts(e.get("timestamp")) and _parse_ts(e["timestamp"]) >= cutoff]

    groups: Dict[str, List[Dict[str, Any]]] = {}
    for e in entries:
        groups.setdefault(e["reformat_model"], []).append(e)

    out = []
    for model, items in groups.items():
        lat = [float(i["llm_latency_ms"]) for i in items]
        out.append({
            "reformat_model": model,
            "count": len(items),
            "median_ms": round(_percentile(lat, 0.5)),
            "p90_ms": round(_percentile(lat, 0.9)),
        })
    out.sort(key=lambda r: (r["median_ms"], -r["count"]))
    return out


def per_correction(period: str = "all", path: str = None) -> List[Dict[str, Any]]:
    """Aggregates per self-correction LLM: runs, median/p90 correction latency.

    Lets the user compare correction models (speed only; output quality is not measured)."""
    entries = [e for e in _read_all(path)
               if (e.get("correction_latency_ms") or 0) > 0 and e.get("correction_model")]
    cutoff = _period_cutoff(period)
    if cutoff is not None:
        entries = [e for e in entries if _parse_ts(e.get("timestamp")) and _parse_ts(e["timestamp"]) >= cutoff]

    groups: Dict[str, List[Dict[str, Any]]] = {}
    for e in entries:
        groups.setdefault(e["correction_model"], []).append(e)

    out = []
    for corr_model, items in groups.items():
        lat = [float(i["correction_latency_ms"]) for i in items]
        out.append({
            "correction_model": corr_model,
            "count": len(items),
            "median_ms": round(_percentile(lat, 0.5)),
            "p90_ms": round(_percentile(lat, 0.9)),
        })
    out.sort(key=lambda r: (r["median_ms"], -r["count"]))
    return out


MIN_FIT_RUNS = 3
MIN_FIT_SPREAD_S = 5.0


def _latency_fit(items: List[Dict[str, Any]]):
    """Least-squares fit latency = a + b * audio_seconds.

    Separates the fixed per-dictation overhead (mic stop, HTTP, focus wait, paste) from the
    model's real speed. "x real-time" is misleading on short clips because the fixed overhead
    dominates. Returns (a_ms, b_ms_per_s) or None if there are too few runs / too little spread.
    """
    pts = [(float(i["audio_duration_s"]), float(i["end_to_end_ms"]))
           for i in items if i.get("audio_duration_s") and i.get("end_to_end_ms") is not None]
    if len(pts) < MIN_FIT_RUNS:
        return None
    xs = [p[0] for p in pts]
    if max(xs) - min(xs) < MIN_FIT_SPREAD_S:
        return None
    n = len(pts)
    mx = sum(xs) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    b = sum((x - mx) * (y - my) for x, y in pts) / sxx
    b = max(0.0, b)  # noise can produce a negative slope; latency never shrinks with longer audio
    a = max(0.0, my - b * mx)
    return round(a), round(b, 1)


def _parse_ts(ts: Optional[str]):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts)
    except Exception:
        return None


def _period_cutoff(period: str):
    from datetime import timedelta
    now = datetime.now().astimezone()
    if period == "day":
        return now.replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "week":
        return (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "month":
        return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    return None


def hardware() -> Dict[str, Any]:
    """One-time hardware summary, e.g. {'chip': 'Apple M3 Pro', 'memory_gb': 36, ...}."""
    global _hardware_cache
    if _hardware_cache is not None:
        return _hardware_cache
    os_name = f"macOS {platform.mac_ver()[0]}" if platform.system() == "Darwin" and platform.mac_ver()[0] else f"{platform.system()} {platform.release()}"
    info: Dict[str, Any] = {"os": os_name,
                            "arch": platform.machine(), "cpu_cores": os.cpu_count()}
    try:
        if platform.system() == "Darwin":
            def sysctl(key):
                return subprocess.run(["sysctl", "-n", key], capture_output=True, text=True, timeout=2).stdout.strip()
            info["chip"] = sysctl("machdep.cpu.brand_string") or platform.processor()
            mem = sysctl("hw.memsize")
            if mem.isdigit():
                info["memory_gb"] = round(int(mem) / (1024 ** 3))
            info["gpu_accel"] = "Metal" if platform.machine() in ("arm64", "aarch64") else "CPU"
        else:
            info["chip"] = platform.processor() or platform.machine()
    except Exception:
        pass
    _hardware_cache = info
    return info
