import _bootstrap  # noqa: F401
import unittest

from transcript_join import join_transcript_parts, normalize_whisper_text


class TestJoinWhisperSegments(unittest.TestCase):
    """Whisper segments keep their own leading space; join their raw text."""

    def test_cyrillic_word_split_across_segments(self):
        # A segment that starts mid-word has no leading space. Stripping each part
        # and joining with " " produced "гл упо" instead of "глупо".
        self.assertEqual(
            join_transcript_parts(["Это очень гл", "упо, я"]),
            "Это очень глупо, я",
        )
        self.assertEqual(
            join_transcript_parts([" Это очень гл", "упо, я"]),
            "Это очень глупо, я",
        )

    def test_normal_segment_boundary_keeps_one_space(self):
        self.assertEqual(join_transcript_parts(["Hello", " world"]), "Hello world")
        self.assertEqual(join_transcript_parts(["Hello ", "world"]), "Hello world")
        self.assertEqual(join_transcript_parts(["Hello", " world again"]), "Hello world again")

    def test_no_space_before_punctuation(self):
        self.assertEqual(join_transcript_parts(["Hello", " , world"]), "Hello, world")
        self.assertEqual(join_transcript_parts(["Really", "?"]), "Really?")

    def test_empty_and_whitespace_parts_are_ignored(self):
        self.assertEqual(
            join_transcript_parts(["", "   ", None, "Hello", " world"]),
            "Hello world",
        )
        self.assertEqual(join_transcript_parts([]), "")
        self.assertEqual(join_transcript_parts([None, "", "  "]), "")


class TestJoinSeparateResponses(unittest.TestCase):
    """Cloud chunks are independent responses: join with a space, drop overlap."""

    def test_phrase_boundary_duplicate_is_removed(self):
        self.assertEqual(
            join_transcript_parts(
                ["not for free and it's", "It's not that easy"],
                separate_responses=True,
            ),
            "not for free and it's not that easy",
        )

    def test_multi_word_overlap_is_removed(self):
        self.assertEqual(
            join_transcript_parts(
                ["we need to deploy the API", "the API now"],
                separate_responses=True,
            ),
            "we need to deploy the API now",
        )

    def test_real_repeats_inside_a_chunk_are_kept(self):
        self.assertEqual(
            join_transcript_parts(
                ["it was very very", "good"],
                separate_responses=True,
            ),
            "it was very very good",
        )

    def test_overlap_can_be_disabled(self):
        self.assertEqual(
            join_transcript_parts(
                ["not for free and it's", "It's not that easy"],
                separate_responses=True,
                dedupe_overlap=False,
            ),
            "not for free and it's It's not that easy",
        )

    def test_no_space_before_punctuation(self):
        self.assertEqual(
            join_transcript_parts(["Hello", ", world"], separate_responses=True),
            "Hello, world",
        )

    def test_empty_parts_are_skipped(self):
        self.assertEqual(
            join_transcript_parts(["Hello", "", "  ", "world"], separate_responses=True),
            "Hello world",
        )


class TestWhisperLineWraps(unittest.TestCase):
    """whisper.cpp hard-wraps long lines, sometimes in the middle of a word."""

    def test_mid_word_wrap_is_removed(self):
        self.assertEqual(
            normalize_whisper_text(
                "Сейчас я хочу проверить, стал ли работать лучше русский язы\n"
                "к в переводе"
            ),
            "Сейчас я хочу проверить, стал ли работать лучше русский язык в переводе",
        )

    def test_newline_at_word_boundary_becomes_a_space(self):
        self.assertEqual(
            normalize_whisper_text("до этого там были разные пробелы и\n выглядело нелепо"),
            "до этого там были разные пробелы и выглядело нелепо",
        )

    def test_hyphenated_wrap_is_joined(self):
        self.assertEqual(normalize_whisper_text("что-\nто"), "что-то")

    def test_crlf_wrap_is_joined(self):
        self.assertEqual(normalize_whisper_text("язы\r\nк"), "язык")

    def test_join_normalizes_wraps_in_raw_segments(self):
        self.assertEqual(
            join_transcript_parts(["язы\nк", " в переводе"]),
            "язык в переводе",
        )

    def test_join_normalizes_wraps_in_separate_responses(self):
        self.assertEqual(
            join_transcript_parts(["язы\nк", "в переводе"], separate_responses=True),
            "язык в переводе",
        )


class TestJoinPerformance(unittest.TestCase):
    def test_join_is_fast(self):
        import time
        parts = ["word "] * 2000
        start = time.perf_counter()
        for _ in range(100):
            join_transcript_parts(parts)
        elapsed = time.perf_counter() - start
        # 100 joins over ~2000 parts must stay well under a second.
        self.assertLess(elapsed, 0.5)


if __name__ == "__main__":
    unittest.main()
