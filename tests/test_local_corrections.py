import _bootstrap  # noqa: F401
import os
import sys
import time
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import local_corrections as lc


class LocalCorrectionTests(unittest.TestCase):
    def test_removes_english_fillers(self):
        self.assertEqual(lc.fix("um so I think we should uh ship it"), "so I think we should ship it")

    def test_removes_russian_and_german_fillers(self):
        self.assertEqual(lc.fix("ну вот я думаю э-э это верно"), "ну вот я думаю это верно")
        self.assertEqual(lc.fix("äh ich meine das passt"), "ich meine das passt")

    def test_collapses_repeated_function_words(self):
        self.assertEqual(lc.fix("the the report and and it is late"), "the report and it is late")
        self.assertEqual(lc.fix("I I want you you to go"), "I want you to go")

    def test_keeps_meaningful_repeats(self):
        # "had had", "that that", "is is", "in in" and "very very" can be correct.
        self.assertEqual(lc.fix("she had had enough"), "she had had enough")
        self.assertEqual(lc.fix("the problem is is that we lost"), "the problem is is that we lost")
        self.assertEqual(lc.fix("I logged in in the morning"), "I logged in in the morning")
        self.assertEqual(lc.fix("it is very very good"), "it is very very good")

    def test_does_not_join_across_lines(self):
        self.assertEqual(lc.fix("turn it on\non Monday"), "turn it on\non Monday")

    def test_keeps_snippet_placeholders(self):
        self.assertEqual(lc.fix("um here is ⟦S1⟧ for you"), "here is ⟦S1⟧ for you")

    def test_empty_and_whitespace(self):
        self.assertEqual(lc.fix(""), "")
        self.assertEqual(lc.fix("   "), "   ")

    def test_idempotent(self):
        once = lc.fix("um the the report is is late")
        self.assertEqual(lc.fix(once), once)

    def test_1000_dictations_under_half_a_second(self):
        text = "um so the the report is is late and uh we should to to send it"
        started = time.perf_counter()
        for _ in range(1000):
            lc.fix(text)
        elapsed = time.perf_counter() - started
        self.assertLess(elapsed, 0.5, f"local correction took {elapsed:.3f}s for 1000 calls")


if __name__ == "__main__":
    unittest.main(verbosity=2)
