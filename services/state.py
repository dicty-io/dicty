import asyncio
from typing import Optional
from audio_recorder import AudioRecorder
from git_service import GitService
from model_manager import ModelManager
from transcribe_service import TranscribeService
from update_manager import UpdateManager

recorder = AudioRecorder()
transcriber = TranscribeService()
git = GitService()
updater = UpdateManager()
model_manager = ModelManager()

_active_processing_task: Optional[asyncio.Task] = None

def register_processing_task(task: asyncio.Task) -> None:
    """Registers an in-flight transcription or audio processing asyncio task."""
    global _active_processing_task
    _active_processing_task = task

def unregister_processing_task(task: asyncio.Task) -> None:
    """Unregisters an in-flight task upon completion or cancellation."""
    global _active_processing_task
    if _active_processing_task is task:
        _active_processing_task = None

def cancel_active_processing() -> None:
    """Cancels any in-flight transcription or audio processing asyncio task."""
    global _active_processing_task
    if _active_processing_task and not _active_processing_task.done():
        print("[*] Cancelling active transcription/processing task on user request...")
        _active_processing_task.cancel()
        _active_processing_task = None

