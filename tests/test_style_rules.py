import _bootstrap  # noqa: F401
import os
import sys
import time
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import style_rules as sr


class ExactStyleTests(unittest.TestCase):
    def test_exact_is_byte_for_byte(self):
        text = "  let's meet tuesday — actually wednesday  "
        self.assertEqual(sr.apply_style(text, "exact"), text)

    def test_unknown_style_is_a_no_op(self):
        text = "um hello"
        self.assertEqual(sr.apply_style(text, "email"), text)


class CleanStyleTests(unittest.TestCase):
    def test_plan_example(self):
        self.assertEqual(
            sr.apply_clean("um so I think we should uh ship it"),
            "I think we should ship it.",
        )

    def test_english_fillers_and_comma(self):
        self.assertEqual(sr.apply_clean("I think, um, we should go"), "I think we should go.")

    def test_russian_fillers(self):
        self.assertEqual(
            sr.apply_clean("ну вот я думаю что мы должны это сделать"),
            "Я думаю что мы должны это сделать.",
        )

    def test_german_fillers(self):
        self.assertEqual(
            sr.apply_clean("äh ich meine wir sollten das machen"),
            "Ich meine wir sollten das machen.",
        )

    def test_standalone_i_and_contractions(self):
        self.assertEqual(sr.apply_clean("i'm sure i can do it"), "I'm sure I can do it.")

    def test_decimal_is_not_a_sentence_boundary(self):
        self.assertEqual(sr.apply_clean("meet me at 3.5 pm"), "Meet me at 3.5 pm.")

    def test_spoken_punctuation(self):
        self.assertEqual(
            sr.apply_clean("send it friday comma please period"),
            "Send it friday, please.",
        )

    def test_real_repeats_are_kept(self):
        # Removing false starts is self-correction's job, not clean's.
        self.assertEqual(sr.apply_clean("it is very very good"), "It is very very good.")

    def test_no_filler_no_change_except_capital_and_period(self):
        self.assertEqual(sr.apply_clean("ship it today"), "Ship it today.")

    def test_does_not_split_identifiers(self):
        self.assertEqual(
            sr.apply_clean("call get user by id now"),
            "Call get user by id now.",
        )

    def test_idempotent(self):
        once = sr.apply_clean("um so I think, uh, we should ship it")
        self.assertEqual(sr.apply_clean(once), once)

    def test_empty_and_whitespace(self):
        self.assertEqual(sr.apply_clean(""), "")
        self.assertEqual(sr.apply_clean("   "), "   ")


class CodeStyleTests(unittest.TestCase):
    def test_no_final_period(self):
        self.assertEqual(sr.apply_code("const userId = 42."), "const userId = 42")

    def test_no_added_capitals(self):
        self.assertEqual(sr.apply_code("let's call getUserId"), "let's call getUserId")

    def test_identifiers_kept_exactly(self):
        self.assertEqual(
            sr.apply_code("rename get_user_id to getUserById"),
            "rename get_user_id to getUserById",
        )

    def test_fillers_removed(self):
        self.assertEqual(sr.apply_code("um rename get user id to user id."), "rename get user id to user id")

    def test_preserves_newlines_and_indentation(self):
        self.assertEqual(sr.apply_code("line one\n  line two"), "line one\n  line two")

    def test_idempotent(self):
        once = sr.apply_code("um call doThing(x).")
        self.assertEqual(sr.apply_code(once), once)


class StyleMapTests(unittest.TestCase):
    def test_legacy_mapping_table(self):
        expected = {
            "raw": "exact",
            "punctuation_fast": "clean",
            "message": "message",
            "email": "email",
            "note": "note",
            "custom": "message",
            "book": "note",
            "dialogue_structured": "note",
            "meeting_summary": "note",
            "raw_dialogue": "exact",
            "librarian": "clean",
            "code": "code",
        }
        for old, new in expected.items():
            self.assertEqual(sr.legacy_to_style(old), new, old)

    def test_code_never_advertised_to_old_clients(self):
        self.assertEqual(sr.style_to_legacy("code"), "custom")

    def test_all_styles_have_examples(self):
        for style in sr.STYLES:
            self.assertIn(style, sr.STYLE_EXAMPLES)


class PerformanceTests(unittest.TestCase):
    def test_clean_1000_short_dictations_under_half_a_second(self):
        text = "um so I think we should uh ship it on friday and then, you know, tell the team"
        started = time.perf_counter()
        for _ in range(1000):
            sr.apply_clean(text)
        elapsed = time.perf_counter() - started
        self.assertLess(elapsed, 0.5, f"clean took {elapsed:.3f}s for 1000 calls")

    def test_code_1000_short_dictations_under_half_a_second(self):
        text = "um rename get user id to getUserId and update the schema"
        started = time.perf_counter()
        for _ in range(1000):
            sr.apply_code(text)
        elapsed = time.perf_counter() - started
        self.assertLess(elapsed, 0.5, f"code took {elapsed:.3f}s for 1000 calls")


if __name__ == "__main__":
    unittest.main(verbosity=2)
