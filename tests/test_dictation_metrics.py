import _bootstrap  # noqa: F401
import json
import os
import sys
import tempfile
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import dictation_metrics as dm


class DictationMetricsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False)
        self.tmp.close()
        os.remove(self.tmp.name)
        self.path = self.tmp.name

    def tearDown(self):
        if os.path.exists(self.path):
            os.remove(self.path)

    def _rec(self, model="small", provider="whisper-server", dur=10.0, words=20, incognito=False):
        return dm.record(mode="dictation", model_id=model, model_name=model.title(), provider=provider,
                         is_cloud=False, audio_duration_s=dur, word_count=words, engine_ms=400,
                         incognito=incognito, path=self.path)

    def test_recent_only_includes_measured_entries_newest_first(self):
        a = self._rec()
        b = self._rec()
        self._rec()  # never measured -> excluded
        dm.set_latency(a, 900, True, path=self.path)
        dm.set_latency(b, 1100, False, path=self.path)
        rows = dm.recent(10, path=self.path)
        self.assertEqual([r["id"] for r in rows], [b, a])
        self.assertEqual(rows[0]["end_to_end_ms"], 1100)
        self.assertFalse(rows[0]["pasted"])

    def test_recent_respects_limit(self):
        for _ in range(15):
            dm.set_latency(self._rec(), 500, True, path=self.path)
        self.assertEqual(len(dm.recent(10, path=self.path)), 10)

    def test_entries_never_contain_text(self):
        dm.set_latency(self._rec(incognito=True), 700, True, path=self.path)
        with open(self.path) as f:
            entry = json.loads(f.readline())
        self.assertTrue(set(entry).issubset(dm._ALLOWED_FIELDS))
        self.assertNotIn("text", entry)
        self.assertTrue(entry["incognito"])

    def test_per_model_median_p90_and_realtime(self):
        for ms in (1000, 2000, 3000, 4000, 5000):
            dm.set_latency(self._rec(dur=10.0), ms, True, path=self.path)
        dm.set_latency(self._rec(model="medium", dur=5.0), 2500, True, path=self.path)
        rows = {r["model_id"]: r for r in dm.per_model(path=self.path)}
        s = rows["small"]
        self.assertEqual(s["count"], 5)
        self.assertEqual(s["median_ms"], 3000)
        self.assertEqual(s["p90_ms"], 4600)
        self.assertEqual(s["median_x_realtime"], 3.3)  # 10s audio / 3s
        self.assertEqual(rows["medium"]["median_x_realtime"], 2.0)

    def test_trim_keeps_last_entries(self):
        old_max = dm.MAX_ENTRIES
        dm.MAX_ENTRIES = 5
        try:
            ids = [self._rec() for _ in range(40)]
            entries = dm._read_all(self.path)
            self.assertLessEqual(len(entries), 40)
            self.assertEqual(entries[-1]["id"], ids[-1])
        finally:
            dm.MAX_ENTRIES = old_max

    def test_latency_fit_separates_overhead_from_model_speed(self):
        # Real "Fast" runs from the latency report: (audio s, stop->paste ms)
        for dur, ms in [(3.4, 338), (12.5, 347), (2.5, 312), (8.7, 390), (18.1, 489)]:
            dm.set_latency(self._rec(dur=dur), ms, True, path=self.path)
        row = dm.per_model(path=self.path)[0]
        self.assertTrue(250 <= row["fixed_overhead_ms"] <= 320, row)
        self.assertTrue(5 <= row["ms_per_audio_s"] <= 12, row)

    def test_latency_fit_needs_runs_and_spread(self):
        for dur, ms in [(4.3, 214), (5.4, 299)]:  # 2 runs only
            dm.set_latency(self._rec(model="tiny", dur=dur), ms, True, path=self.path)
        for dur in (4.0, 5.0, 6.0):  # 3 runs but < 5s spread
            dm.set_latency(self._rec(model="base", dur=dur), 230, True, path=self.path)
        rows = {r["model_id"]: r for r in dm.per_model(path=self.path)}
        self.assertIsNone(rows["tiny"]["ms_per_audio_s"])
        self.assertIsNone(rows["base"]["fixed_overhead_ms"])

    def test_set_latency_unknown_id(self):
        self._rec()
        self.assertFalse(dm.set_latency("nope", 100, True, path=self.path))


if __name__ == "__main__":
    unittest.main()
