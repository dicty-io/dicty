#!/usr/bin/env python3
"""Remove test artifacts that leaked into real Dicty storage.

Older versions of the test suite used CWD-relative paths, so queue and metrics
writes landed in the live user data directory. This script only removes entries
that match the exact markers used by those tests. It is a dry run by default.

Usage:
    python scripts/cleanup_test_data.py
    python scripts/cleanup_test_data.py --apply
"""

import argparse
import json
import os
import sys
import tempfile
from collections import defaultdict
from datetime import datetime

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from dicty_paths import default_data_dir  # noqa: E402

TEST_QUEUE_TEXTS = {
    "Test thought for automated test",
    "Architecture decision from mic",
}
TEST_QUEUE_SOURCES = {"ci_test"}

TEST_METRIC_MODES = {"dictation", "meeting", "focused_meeting", "librarian"}
TEST_METRIC_DURATION = 5.0


def _fmt_timestamp(value):
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value).isoformat(timespec="seconds")
    return str(value) if value is not None else "?"


def find_queue_items(path):
    if not os.path.exists(path):
        return [], []
    try:
        with open(path, encoding="utf-8") as f:
            items = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"[!] Cannot read {path}: {exc}")
        return [], []

    matched = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        source = item.get("source")
        text = item.get("text")
        if source in TEST_QUEUE_SOURCES or text in TEST_QUEUE_TEXTS:
            matched.append((index, item))
    return items, matched


def _is_test_metric(entry):
    return (
        entry.get("provider") == "VAD stream (local)"
        and entry.get("audio_duration_s") == TEST_METRIC_DURATION
        and entry.get("end_to_end_ms") is None
        and entry.get("pasted") is None
    )


def find_metric_lines(path):
    if not os.path.exists(path):
        return [], []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as exc:
        print(f"[!] Cannot read {path}: {exc}")
        return [], []

    parsed = []
    groups = defaultdict(list)
    for index, line in enumerate(lines):
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            parsed.append((index, line, None))
            continue
        parsed.append((index, line, entry))
        if isinstance(entry, dict) and _is_test_metric(entry):
            groups[entry.get("timestamp")].append((index, entry))

    matched = []
    for timestamp, entries in groups.items():
        modes = {entry.get("mode") for _, entry in entries}
        # The leaked API suite writes several modes within the same second.
        if len(entries) >= 3 and len(modes & TEST_METRIC_MODES) >= 3:
            matched.extend(entries)
    matched.sort(key=lambda pair: pair[0])
    return parsed, matched


def _write_queue(path, items):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".cleanup-queue-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(items, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp_path, path)
    except Exception:
        os.unlink(tmp_path)
        raise


def _write_metric_lines(path, keep_lines):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".cleanup-metrics-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(keep_lines))
            if keep_lines:
                f.write("\n")
        os.replace(tmp_path, path)
    except Exception:
        os.unlink(tmp_path)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--data-dir",
        default=os.environ.get("DICTY_DATA_DIR") or default_data_dir(),
        help="Dicty data directory to scan (default: %(default)s)",
    )
    parser.add_argument(
        "--legacy-repo",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Also scan the old CWD-relative queue file in the repo root",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Delete the listed entries (default is a dry run)",
    )
    args = parser.parse_args()

    data_dir = os.path.abspath(os.path.expanduser(args.data_dir))
    queue_paths = [os.path.join(data_dir, "librarian_queue.json")]
    legacy_queue = os.path.join(PROJECT_ROOT, "librarian_queue.json")
    if args.legacy_repo and os.path.abspath(legacy_queue) not in queue_paths:
        queue_paths.append(legacy_queue)
    metrics_path = os.path.join(data_dir, "metrics.jsonl")

    total_queue = 0
    total_metrics = 0
    actions = []

    for path in queue_paths:
        items, matched = find_queue_items(path)
        if not matched:
            continue
        print(f"\n=== Queue test artifacts: {path} ===")
        for index, item in matched:
            print(
                f"  [{index}] id={item.get('id')} source={item.get('source')!r} "
                f"timestamp={_fmt_timestamp(item.get('timestamp'))} "
                f"text={item.get('text')!r}"
            )
        total_queue += len(matched)
        if args.apply:
            matched_ids = {id(item) for _, item in matched}
            actions.append((path, "queue", items, matched_ids))

    parsed, matched = find_metric_lines(metrics_path)
    if matched:
        print(f"\n=== Metrics test artifacts: {metrics_path} ===")
        for index, entry in matched:
            print(
                f"  [{index}] id={entry.get('id')} mode={entry.get('mode')!r} "
                f"timestamp={entry.get('timestamp')} "
                f"duration={entry.get('audio_duration_s')}s"
            )
        total_metrics += len(matched)
        if args.apply:
            drop = {index for index, _ in matched}
            actions.append((metrics_path, "metrics", parsed, drop))

    print(
        f"\nFound {total_queue} queue item(s) and {total_metrics} metric line(s) "
        f"from tests."
    )
    if not args.apply:
        if total_queue or total_metrics:
            print("Dry run only. Re-run with --apply to delete these exact entries.")
        return 0

    for path, kind, data, selection in actions:
        if kind == "queue":
            keep = [item for item in data if id(item) not in selection]
            _write_queue(path, keep)
            print(f"[+] Removed {len(data) - len(keep)} queue item(s) from {path}")
        else:
            keep_lines = [line for index, line, _ in data if index not in selection]
            _write_metric_lines(path, keep_lines)
            print(f"[+] Removed {len(data) - len(keep_lines)} metric line(s) from {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
