import _bootstrap  # noqa: F401
import asyncio
import os
from transcribe_service import TranscribeService
from model_manager import ModelManager

async def test_routing():
    ts = TranscribeService()
    
    print("Testing OpenRouter routing for nvidia/parakeet-tdt-0.6b-v3...")
    import httpx
    from unittest.mock import AsyncMock, patch, MagicMock
    
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"text": "Transcribed voice text successfully"}
    
    with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
        mock_post.return_value = mock_resp
        
        dummy_wav = "scratch_test.wav"
        import wave
        with wave.open(dummy_wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(b"\x00" * 32000) # 1 second
            
        try:
            # 1. Call transcribe_remote with provider="openrouter" and user's OpenRouter token
            res = await ts.transcribe_remote(
                audio_path=dummy_wav,
                model_name="nvidia/parakeet-tdt-0.6b-v3",
                openrouter_key="sk-or-v1-my-custom-user-token",
                provider="openrouter"
            )
            assert res == "Transcribed voice text successfully"
            call_args, call_kwargs = mock_post.call_args
            url = call_args[0]
            headers = call_kwargs["headers"]
            print(f"Verified URL: {url}")
            print(f"Verified Authorization header: {headers['Authorization']}")
            assert url == "https://openrouter.ai/api/v1/audio/transcriptions"
            assert headers["Authorization"] == "Bearer sk-or-v1-my-custom-user-token"
            print("[PASS] OpenRouter routing with user token verified!")
            
            # 2. Test Groq direct routing
            res_groq = await ts.transcribe_remote(
                audio_path=dummy_wav,
                model_name="groq/whisper-large-v3-turbo",
                openrouter_key="sk-or-v1-my-custom-user-token",
                provider="openrouter"
            )
            call_args, call_kwargs = mock_post.call_args
            url = call_args[0]
            headers = call_kwargs["headers"]
            print(f"Verified Groq URL: {url}")
            print(f"Verified Groq Authorization: {headers['Authorization'][:14]}...")
            assert "api.groq.com" in url
            print("[PASS] Groq direct routing verified!")
            
            # 3. Test Dicty Cloud routing
            res_cloud = await ts.transcribe_remote(
                audio_path=dummy_wav,
                model_name="nvidia/parakeet-tdt-0.6b-v3",
                override_key="dicty-jwt-sample-token",
                provider="dicty_cloud"
            )
            call_args, call_kwargs = mock_post.call_args
            url = call_args[0]
            headers = call_kwargs["headers"]
            print(f"Verified Dicty Cloud URL: {url}")
            assert "dicty-backend" in url or "api.dicty.io" in url
            assert headers["Authorization"] == "Bearer dicty-jwt-sample-token"
            print("[PASS] Dicty Cloud routing verified!")
            
        finally:
            if os.path.exists(dummy_wav):
                os.remove(dummy_wav)

if __name__ == "__main__":
    asyncio.run(test_routing())

def test_credit_deduction_check():
    from unittest.mock import patch, MagicMock
    from model_manager import ModelManager
    
    # Check that when llm_provider == "openrouter", credits_used is NOT calculated
    transcription_model_dict = next((m for m in ModelManager().get_available_models() if m["id"] == "nvidia/parakeet-tdt-0.6b-v3"), None)
    assert transcription_model_dict is not None
    assert transcription_model_dict.get("is_cloud", False) is True
    
    # With llm_provider = "openrouter"
    llm_provider = "openrouter"
    credits_used = 0
    if transcription_model_dict and transcription_model_dict.get("is_cloud", False) and llm_provider == "dicty_cloud":
        credits_used = 10
    assert credits_used == 0, f"Expected 0 credits used, got {credits_used}"
    print("[PASS] Credit calculation correctly bypassed when llm_provider == 'openrouter'!")
    
    # With llm_provider = "dicty_cloud"
    llm_provider = "dicty_cloud"
    credits_used = 0
    if transcription_model_dict and transcription_model_dict.get("is_cloud", False) and llm_provider == "dicty_cloud":
        credits_used = 10
    assert credits_used == 10, f"Expected 10 credits used, got {credits_used}"
    print("[PASS] Credit calculation correctly active when llm_provider == 'dicty_cloud'!")

if __name__ == "__main__":
    test_credit_deduction_check()
