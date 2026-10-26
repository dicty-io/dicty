import _bootstrap  # noqa: F401
import asyncio
import os
import sys
import unittest
from unittest.mock import AsyncMock, MagicMock

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import meeting_dialogue as md
from meeting_dialogue import Segment


class TestMeetingDialogue(unittest.TestCase):

    def test_parse_whisper_timestamped(self):
        text = (
            "[00:01 - 00:04] Hello world\n"
            "[00:05.500 --> 00:09.200] This is a test segment.\n"
            "Just a line without timestamp"
        )
        segs = md.parse_whisper_timestamped(text, source="others")
        self.assertEqual(len(segs), 3)

        self.assertEqual(segs[0].id, 0)
        self.assertEqual(segs[0].start, 1.0)
        self.assertEqual(segs[0].end, 4.0)
        self.assertEqual(segs[0].text, "Hello world")
        self.assertEqual(segs[0].source, "others")

        self.assertEqual(segs[1].id, 1)
        self.assertAlmostEqual(segs[1].start, 5.5)
        self.assertAlmostEqual(segs[1].end, 9.2)
        self.assertEqual(segs[1].text, "This is a test segment.")

        self.assertEqual(segs[2].id, 2)
        self.assertEqual(segs[2].start, 0.0)
        self.assertEqual(segs[2].end, 0.0)
        self.assertEqual(segs[2].text, "Just a line without timestamp")

    def test_parse_whisper_timestamped_empty(self):
        self.assertEqual(md.parse_whisper_timestamped(""), [])
        self.assertEqual(md.parse_whisper_timestamped("   \n\t  "), [])

    def test_parse_whisper_timestamped_hallucination_filtered(self):
        hallucinated_text = (
            "[00:01 - 00:04] Thank you for watching, please subscribe, like, and turn on the bell icon to be notified when I post my latest videos.\n"
            "[00:05 - 00:08] Thank you for watching, please turn on the bell icon to be notified when I post my latest videos.\n"
            "[00:09 - 00:12] Please subscribe to my channel.\n"
            "[00:13 - 00:16] Genuine user speech about project milestones."
        )
        segs = md.parse_whisper_timestamped(hallucinated_text, source="you")
        self.assertEqual(len(segs), 1)
        self.assertEqual(segs[0].text, "Genuine user speech about project milestones.")

    def test_merge_timelines(self):
        you = [
            Segment(id=0, start=1.0, end=3.0, source="you", text="You speaking first"),
            Segment(id=1, start=6.0, end=8.0, source="you", text="You speaking again"),
        ]
        others = [
            Segment(id=0, start=2.5, end=5.0, source="others", text="Others interjecting"),
            Segment(id=1, start=9.0, end=11.0, source="others", text="Others concluding"),
        ]

        merged = md.merge_timelines(you, others)
        self.assertEqual(len(merged), 4)
        # Check renumbered monotonically
        self.assertEqual([s.id for s in merged], [0, 1, 2, 3])
        # Check sorted by start time
        self.assertEqual([s.source for s in merged], ["you", "others", "you", "others"])
        self.assertEqual(merged[0].text, "You speaking first")
        self.assertEqual(merged[1].text, "Others interjecting")

    def test_merge_timelines_empty(self):
        you = [Segment(id=0, start=1.0, end=3.0, source="you", text="Only you")]
        self.assertEqual(len(md.merge_timelines(you, [])), 1)
        self.assertEqual(len(md.merge_timelines([], you)), 1)
        self.assertEqual(md.merge_timelines([], []), [])

    def test_dedupe_bleed_drops_echoed_mic_segments(self):
        # Mic picked up audio echoing the speaker: overlaps >60% and text matches >70%
        others = [
            Segment(id=0, start=10.0, end=15.0, source="others", text="Let us review the quarterly report together.")
        ]
        you_echo = [
            Segment(id=0, start=10.2, end=14.8, source="you", text="Let us review the quarterly report together")
        ]

        kept = md.dedupe_bleed(you_echo, others)
        self.assertEqual(kept, [])

    def test_dedupe_bleed_preserves_genuine_interruption(self):
        # Genuine user speech overlapping in time with others, but different words
        others = [
            Segment(id=0, start=10.0, end=15.0, source="others", text="Let us review the quarterly report together.")
        ]
        you_genuine = [
            Segment(id=0, start=10.2, end=14.8, source="you", text="Wait, I completely disagree with those numbers!")
        ]

        kept = md.dedupe_bleed(you_genuine, others)
        self.assertEqual(len(kept), 1)
        self.assertEqual(kept[0].text, "Wait, I completely disagree with those numbers!")

    def test_label_you_others(self):
        segs = [
            Segment(id=0, start=1.0, end=3.0, source="you", text="Hi"),
            Segment(id=1, start=4.0, end=6.0, source="others", text="Hello there"),
        ]
        md.label_you_others(segs, you_label="Vasilii", others_label="Participants")
        self.assertEqual(segs[0].speaker, "Vasilii")
        self.assertEqual(segs[1].speaker, "Participants")

    def test_build_smart_llm_input(self):
        segs = [
            Segment(id=0, start=1.2, end=4.8, source="you", text="Hi everyone, let's start."),
            Segment(id=1, start=5.1, end=9.0, source="others", text="Thanks Vasilii."),
        ]
        formatted = md.build_smart_llm_input(segs)
        self.assertIn("#0 [00:01.2-00:04.8] (YOU) Hi everyone, let's start.", formatted)
        self.assertIn("#1 [00:05.1-00:09.0] (OTHERS) Thanks Vasilii.", formatted)
        self.assertIn("[gap +0.3s]", formatted)

    def test_render_dialogue_merges_close_turns(self):
        # Two turns by the same speaker separated by < 2.0s gap
        segs = [
            Segment(id=0, start=1.0, end=3.0, source="you", text="First thought.", speaker="Vasilii"),
            Segment(id=1, start=3.8, end=5.5, source="you", text="Second thought continuing.", speaker="Vasilii"),
            Segment(id=2, start=6.0, end=8.0, source="others", text="Response from others.", speaker="Speaker 1"),
        ]
        rendered = md.render_dialogue(segs, show_timestamps=False)
        lines = [line for line in rendered.split("\n\n") if line.strip()]
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0], "**Vasilii**: First thought. Second thought continuing.")
        self.assertEqual(lines[1], "**Speaker 1**: Response from others.")

    def test_render_dialogue_with_timestamps(self):
        segs = [
            Segment(id=0, start=65.0, end=70.0, source="you", text="At one minute five seconds.", speaker="You"),
        ]
        rendered = md.render_dialogue(segs, show_timestamps=True)
        self.assertEqual(rendered, "*(01:05)* **You**: At one minute five seconds.")

    def test_smart_llm_speaker_separation_valid_json(self):
        segs = [
            Segment(id=0, start=1.0, end=3.0, source="you", text="Hello team."),
            Segment(id=1, start=3.5, end=6.0, source="others", text="Hi, Anna here."),
            Segment(id=2, start=6.5, end=9.0, source="others", text="And I am Bob."),
        ]
        mock_llm = MagicMock()
        mock_llm.generate = AsyncMock(return_value='{"speakers": {"1": "Speaker 1", "2": "Speaker 2"}, "names": {"Speaker 1": "Anna", "Speaker 2": "Bob"}}')

        updated, warnings = asyncio.run(
            md.smart_llm_speaker_separation(segs, mock_llm, you_label="Vasilii")
        )
        self.assertEqual(warnings, [])
        self.assertEqual(updated[0].speaker, "Vasilii")
        self.assertEqual(updated[1].speaker, "Anna")
        self.assertEqual(updated[2].speaker, "Bob")

    def test_smart_llm_speaker_separation_markdown_fence(self):
        segs = [
            Segment(id=0, start=1.0, end=3.0, source="others", text="Testing markdown fences."),
        ]
        mock_llm = MagicMock()
        mock_llm.generate = AsyncMock(return_value='```json\n{"speakers": {"0": "Speaker 1"}, "names": {}}\n```')

        updated, warnings = asyncio.run(
            md.smart_llm_speaker_separation(segs, mock_llm)
        )
        self.assertEqual(warnings, [])
        self.assertEqual(updated[0].speaker, "Speaker 1")

    def test_smart_llm_speaker_separation_missing_and_unknown_ids(self):
        segs = [
            Segment(id=0, start=1.0, end=3.0, source="others", text="First"),
            Segment(id=1, start=3.5, end=6.0, source="others", text="Second"),
        ]
        mock_llm = MagicMock()
        # LLM omits ID 1 and includes unknown ID 99
        mock_llm.generate = AsyncMock(return_value='{"speakers": {"0": "Alice", "99": "Ghost"}, "names": {}}')

        updated, warnings = asyncio.run(
            md.smart_llm_speaker_separation(segs, mock_llm)
        )
        self.assertEqual(warnings, [])
        self.assertEqual(updated[0].speaker, "Alice")
        # Missing ID 1 inherits previous speaker's label (Alice)
        self.assertEqual(updated[1].speaker, "Alice")

    def test_smart_llm_speaker_separation_invalid_json_fallback(self):
        segs = [
            Segment(id=0, start=1.0, end=3.0, source="you", text="You speaking."),
            Segment(id=1, start=3.5, end=6.0, source="others", text="Others speaking."),
        ]
        mock_llm = MagicMock()
        mock_llm.generate = AsyncMock(return_value='Not a json response at all')

        updated, warnings = asyncio.run(
            md.smart_llm_speaker_separation(segs, mock_llm, you_label="You", others_label="Others")
        )
        self.assertEqual(len(warnings), 1)
        self.assertIn("Speaker separation incomplete", warnings[0])
        self.assertEqual(updated[0].speaker, "You")
        self.assertEqual(updated[1].speaker, "Others")

    def test_process_transcription_separated_meeting(self):
        import dicty_engine
        import tempfile
        import wave

        # Create dummy WAV files
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f_mic, \
             tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f_sys:
            for f in (f_mic, f_sys):
                with wave.open(f.name, "wb") as w:
                    w.setnchannels(1)
                    w.setsampwidth(2)
                    w.setframerate(16000)
                    w.writeframes(b"\x00" * 32000) # 1 sec

        try:
            # Mock TranscribeService.transcribe_segments
            async def mock_segs(path, **kwargs):
                if path == f_mic.name:
                    return [{"start": 1.0, "end": 3.0, "text": "Hi everyone, thank you for joining."}]
                else:
                    return [{"start": 3.5, "end": 6.0, "text": "Hello, good to be here."}]

            # Mock LLMService.generate for summary
            async def mock_generate(prompt, system_prompt, **kwargs):
                return "## Summary\nBrief summary.\n\n## Action items\n- [ ] Follow up @Vasilii"

            with unittest.mock.patch("dicty_engine.TranscribeService.transcribe_segments", side_effect=mock_segs), \
                 unittest.mock.patch("dicty_engine.LLMService.generate", side_effect=mock_generate):

                res = asyncio.run(dicty_engine.process_transcription(
                    audio_path=f_sys.name,
                    mic_audio_path=f_mic.name,
                    mode="meeting",
                    speaker_separation="you_others",
                    speaker_you_label="Vasilii",
                    is_incognito=True
                ))

                self.assertEqual(res["status"], "success")
                self.assertIn("## Dialogue", res["text"])
                self.assertIn("**Vasilii**: Hi everyone, thank you for joining.", res["text"])
                self.assertIn("**Others**: Hello, good to be here.", res["text"])
                self.assertIn("## Summary", res["text"])
                self.assertIn("## Action items", res["text"])
                self.assertIn("- [ ] Follow up @Vasilii", res["text"])
                self.assertEqual(res["speaker_separation"], "you_others")
                self.assertEqual(res["speakers"], ["Vasilii", "Others"])
        finally:
            for p in (f_mic.name, f_sys.name):
                if os.path.exists(p):
                    os.remove(p)

    def test_process_transcription_separated_meeting_smart_llm(self):
        import dicty_engine
        import tempfile
        import wave

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f_mic, \
             tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f_sys:
            for f in (f_mic, f_sys):
                with wave.open(f.name, "wb") as w:
                    w.setnchannels(1)
                    w.setsampwidth(2)
                    w.setframerate(16000)
                    w.writeframes(b"\x00" * 32000)

        try:
            async def mock_segs(path, **kwargs):
                if path == f_mic.name:
                    return [{"start": 1.0, "end": 3.0, "text": "Hi everyone."}]
                else:
                    return [{"start": 3.5, "end": 6.0, "text": "Hi, this is Anna from product."}]

            async def mock_generate(prompt, system_prompt, **kwargs):
                # If separation prompt:
                if "assign speakers" in prompt.lower() or "assign speakers" in system_prompt.lower():
                    return '{"speakers": {"1": "Speaker 1"}, "names": {"Speaker 1": "Anna"}}'
                # Summary prompt:
                return "## Summary\nExecutive summary.\n\n## Action items\n- [ ] Ship feature @Anna"

            with unittest.mock.patch("dicty_engine.TranscribeService.transcribe_segments", side_effect=mock_segs), \
                 unittest.mock.patch("dicty_engine.LLMService.generate", side_effect=mock_generate):

                res = asyncio.run(dicty_engine.process_transcription(
                    audio_path=f_sys.name,
                    mic_audio_path=f_mic.name,
                    mode="meeting",
                    speaker_separation="smart_llm",
                    speaker_you_label="Vasilii",
                    is_incognito=True
                ))

                self.assertEqual(res["status"], "success")
                self.assertIn("## Dialogue", res["text"])
                self.assertIn("**Vasilii**: Hi everyone.", res["text"])
                self.assertIn("**Others**: Hi, this is Anna from product.", res["text"])
                self.assertIn("## Summary", res["text"])
                self.assertIn("## Action items", res["text"])
                self.assertIn("- [ ] Ship feature @Anna", res["text"])
                self.assertEqual(res["speaker_separation"], "smart_llm")
                self.assertEqual(res["speakers"], ["Vasilii", "Others"])
        finally:
            for p in (f_mic.name, f_sys.name):
                if os.path.exists(p):
                    os.remove(p)

    def test_process_transcription_separation_off_regression(self):
        import dicty_engine
        import tempfile
        import wave

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            with wave.open(f.name, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(16000)
                w.writeframes(b"\x00" * 32000)

        try:
            async def mock_transcribe(path, *args, **kwargs):
                return "This is a single flat transcript of a meeting without separation."

            with unittest.mock.patch("dicty_engine.TranscribeService.transcribe", side_effect=mock_transcribe):
                res = asyncio.run(dicty_engine.process_transcription(
                    audio_path=f.name,
                    mode="meeting",
                    speaker_separation="off",
                    dictation_format_style="raw",
                    is_incognito=True
                ))
                self.assertEqual(res["status"], "success")
                self.assertNotIn("## Dialogue", res["text"])
                self.assertEqual(res["text"], "This is a single flat transcript of a meeting without separation.")
                self.assertEqual(res.get("speaker_separation"), "off")
        finally:
            if os.path.exists(f.name):
                os.remove(f.name)

    def test_process_transcription_dictation_regression(self):
        import dicty_engine
        import tempfile
        import wave

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            with wave.open(f.name, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(16000)
                w.writeframes(b"\x00" * 32000)

        try:
            async def mock_transcribe(path, *args, **kwargs):
                return "Dictated text here for a normal memo."

            with unittest.mock.patch("dicty_engine.TranscribeService.transcribe", side_effect=mock_transcribe):
                res = asyncio.run(dicty_engine.process_transcription(
                    audio_path=f.name,
                    mode="dictation",
                    dictation_format_style="raw",
                    is_incognito=True
                ))
                self.assertEqual(res["status"], "success")
                self.assertEqual(res["text"], "Dictated text here for a normal memo.")
                self.assertEqual(res["mode"], "dictation")
        finally:
            if os.path.exists(f.name):
                os.remove(f.name)


if __name__ == "__main__":
    unittest.main()

