import asyncio
from typing import Set
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

_active_processing_tasks: Set[asyncio.Task] = set()

def register_processing_task(task: asyncio.Task) -> None:
    """Registers an in-flight transcription or audio processing asyncio task."""
    _active_processing_tasks.add(task)

def unregister_processing_task(task: asyncio.Task) -> None:
    """Unregisters an in-flight task upon completion or cancellation."""
    _active_processing_tasks.discard(task)

def cancel_active_processing() -> None:
    """Cancels any in-flight transcription or audio processing asyncio tasks."""
    tasks = [t for t in _active_processing_tasks if not t.done()]
    _active_processing_tasks.clear()
    for task in tasks:
        print("[*] Cancelling active transcription/processing task on user request...")
        task.cancel()

