import _bootstrap  # noqa: F401
import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import asyncio
from prompts import get_meeting_diarization_system_prompt, get_meeting_diarization_user_prompt
from transcribe_service import TranscribeService

def test_meeting_diarization_prompts():
    sys_prompt = get_meeting_diarization_system_prompt()
    assert "dialogue reconstruction" in sys_prompt.lower()
    assert "Speaker 1" in sys_prompt
    
    transcript = "[00:00 - 00:04] Hello team\n[00:05 - 00:09] Hey Dmitry, did you finish the packaging?"
    user_prompt = get_meeting_diarization_user_prompt(transcript)
    assert transcript in user_prompt
    assert "<transcript>" in user_prompt
    print("✓ test_meeting_diarization_prompts passed")

async def test_diarize_dialogue_fallback():
    ts = TranscribeService()
    transcript = "[00:00 - 00:04] Speaker test"
    res = await ts.diarize_dialogue(transcript, raw_text="Speaker test", provider="invalid_provider")
    assert res == transcript
    print("✓ test_diarize_dialogue_fallback passed")

if __name__ == "__main__":
    test_meeting_diarization_prompts()
    asyncio.run(test_diarize_dialogue_fallback())
    print("All diarization tests passed successfully!")
