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
