import _bootstrap  # noqa: F401
import os
import sys
import tempfile
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import snippet_service as ss

LINKEDIN = {"id": "1", "trigger": "my LinkedIn", "content": "https://www.linkedin.com/in/john-doe/"}
EMAIL = {"id": "2", "trigger": "my email address", "content": "john@example.com"}
WORK_EMAIL = {"id": "3", "trigger": "my work email", "content": "john@corp.com"}
INTRO = {"id": "4", "trigger": "intro email", "content": "Hey, would love to find some time to chat later..."}


def run(text, snippets):
    out, exp, only = ss.detect(text, snippets)
    final, ok = ss.expand(out, exp)
    return final, only, ok


class WholeUtteranceTests(unittest.TestCase):
    def test_exact_trigger_is_snippet_only(self):
        self.assertEqual(run("My LinkedIn.", [LINKEDIN]), (LINKEDIN["content"], True, True))

    def test_stt_spacing_and_punctuation_variants(self):
        for spoken in ["my linked in", "My Linked-In!", "my, LinkedIn", "MY LINKEDIN?"]:
            self.assertEqual(run(spoken, [LINKEDIN])[0], LINKEDIN["content"], spoken)

    def test_cue_word_plus_trigger_as_whole_utterance(self):
        self.assertEqual(run("Insert my LinkedIn.", [LINKEDIN]), (LINKEDIN["content"], True, True))

    def test_alias(self):
        s = dict(LINKEDIN, aliases=["my profile link"])
        self.assertEqual(run("my profile link", [s])[0], LINKEDIN["content"])

    def test_multiline_content_preserved_verbatim(self):
        s = {"id": "x", "trigger": "signature", "content": "Best,\nJohn\n+1 555 0100"}
        self.assertEqual(run("Signature.", [s])[0], "Best,\nJohn\n+1 555 0100")


class InlineTests(unittest.TestCase):
    def test_bare_trigger_in_sentence_is_not_expanded_by_default(self):
        text = "My email address is broken, please fix it."
        self.assertEqual(run(text, [EMAIL]), (text, False, True))

    def test_cue_word_inline(self):
        final, only, ok = run("Here is my profile: insert my LinkedIn. Thanks!", [LINKEDIN])
        self.assertEqual(final, f"Here is my profile: {LINKEDIN['content']}. Thanks!")
        self.assertFalse(only)
        self.assertTrue(ok)

    def test_paste_cue(self):
        final, _, _ = run("Sure, paste intro email", [INTRO])
        self.assertEqual(final, f"Sure, {INTRO['content']}")

    def test_expand_anywhere_flag(self):
        s = dict(EMAIL, expand_anywhere=True)
        final, _, _ = run("You can reach me at my email address anytime.", [s])
        self.assertEqual(final, "You can reach me at john@example.com anytime.")

    def test_longest_trigger_wins(self):
        a = {"id": "a", "trigger": "my email", "content": "A", "expand_anywhere": True}
        b = dict(WORK_EMAIL, expand_anywhere=True)
        final, _, _ = run("Send it to my work email please", [a, b])
        self.assertEqual(final, "Send it to john@corp.com please")

    def test_no_partial_word_match(self):
        s = {"id": "x", "trigger": "cv", "content": "CV TEXT", "expand_anywhere": True}
        self.assertEqual(run("cvs pharmacy", [s])[0], "cvs pharmacy")

    def test_two_snippets_in_one_sentence(self):
        final, _, ok = run("insert my LinkedIn and paste my email address", [LINKEDIN, EMAIL])
        self.assertEqual(final, f"{LINKEDIN['content']} and {EMAIL['content']}")
        self.assertTrue(ok)


class PlaceholderTests(unittest.TestCase):
    def test_placeholder_survives_llm_spacing(self):
        out, exp, _ = ss.detect("insert my LinkedIn, thanks", [LINKEDIN])
        llm_output = out.replace("⟦S1⟧", "⟦ S1 ⟧").capitalize()
        final, ok = ss.expand(llm_output, exp)
        self.assertIn(LINKEDIN["content"], final)
        self.assertTrue(ok)

    def test_dropped_placeholder_is_reported(self):
        _, exp, _ = ss.detect("insert my LinkedIn, thanks", [LINKEDIN])
        _, ok = ss.expand("Thanks!", exp)
        self.assertFalse(ok)

    def test_no_snippets_is_noop(self):
        self.assertEqual(ss.detect("hello world", []), ("hello world", {}, False))
        self.assertEqual(ss.expand("hello world", {}), ("hello world", True))


class ManagerTests(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        os.remove(self.path)
        self.m = ss.SnippetsManager(self.path)

    def tearDown(self):
        if os.path.exists(self.path):
            os.remove(self.path)

    def test_crud(self):
        self.assertEqual(self.m.get_all(), [])
        item = self.m.add("my LinkedIn", LINKEDIN["content"])
        self.assertEqual(self.m.get_all()[0]["trigger"], "my LinkedIn")
        updated = self.m.update(item["id"], "my linkedin profile", "x", expand_anywhere=True)
        self.assertTrue(updated["expand_anywhere"])
        self.assertTrue(self.m.delete(item["id"]))
        self.assertEqual(self.m.get_all(), [])

    def test_duplicate_trigger_rejected_across_spelling(self):
        self.m.add("my LinkedIn", "a")
        with self.assertRaises(ValueError):
            self.m.add("My Linked In", "b")

    def test_validation(self):
        with self.assertRaises(ValueError):
            self.m.add("!!!", "content")
        with self.assertRaises(ValueError):
            self.m.add("trigger", "   ")


if __name__ == "__main__":
    unittest.main()
