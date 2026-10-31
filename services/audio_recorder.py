import queue
import threading
import sys
import os
import sounddevice as sd
import local_whisper
import soundfile as sf
import numpy as np
import time
import requests
import re
import io
import wave
import socket
import engine_auth
from transcript_join import join_transcript_parts, normalize_whisper_text

try:
    import scipy.signal
except ImportError:
    pass

class AudioRecorder:
    def __init__(self, sample_rate: int = 16000):
        self.sample_rate = sample_rate
        self.channels = 1  # whisper.cpp expects 16kHz mono audio
        
        # Audio capturing queues
        self.q = queue.Queue()
        self.transcription_queue = queue.Queue()
        
        self.stream = None
        self.is_recording = False
        self.is_paused = False
        self.is_muted = False
        
        self.committed_text = ""
        self.latest_partial = ""
        self.final_unprocessed_wav = None
        
        self.udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_addr = ("127.0.0.1", 55555)
        self.current_volume = 0.0
        
        self.udp_thread = None
        self.audio_worker_thread = None
        self.transcription_worker_thread = None
        
        # Buffers
        self.full_audio_history = []
        self.active_streaming_buffer = []
        
        self.lock = threading.Lock()
        self.noise_floor = 1.0

        # Loopback audio capture (WASAPI on Windows)
        self.capture_loopback = False
        self.loopback_thread = None
        self.loopback_chunks = []
        self.recording_mode = "dictation"
        # Optional cloud streaming session (cloud_streaming.StreamSession); fed every captured chunk
        self.stream_session = None

    def _loopback_worker(self):
        try:
            import soundcard as sc
        except Exception as e:
            print(f"[!] soundcard library not available for WASAPI loopback: {e}", flush=True)
            return

        try:
            speaker = sc.default_speaker()
            if not speaker:
                print("[!] No default speaker detected for WASAPI loopback capture.", flush=True)
                return

            loopback_mic = sc.get_microphone(id=str(speaker.id), include_loopback=True)
            if not loopback_mic:
                print(f"[!] Could not get loopback endpoint for speaker: {speaker.name}", flush=True)
                return

            print(f"[*] Started WASAPI loopback capture on: {speaker.name} ({self.sample_rate}Hz)", flush=True)
            chunk_frames = 1600  # 0.1s at 16000Hz for low latency loop and clean shutdown
            with loopback_mic.recorder(samplerate=self.sample_rate, channels=1) as rec:
                while self.is_recording:
                    data = rec.record(numframes=chunk_frames)
                    if self.is_paused:
                        continue
                    with self.lock:
                        self.loopback_chunks.append(data.copy())
                        try:
                            peak = float(np.max(np.abs(data))) * 2.0
                            if peak > self.current_volume:
                                self.current_volume = peak
                        except Exception:
                            pass
        except Exception as e:
            print(f"[!] WASAPI loopback worker exception: {e}", flush=True)

    def _udp_worker(self):
        while self.is_recording:
            try:
                vol = 0.0 if (self.is_paused or self.is_muted) else self.current_volume
                self.udp_sock.sendto(str(vol).encode('utf-8'), self.udp_addr)
            except Exception:
                pass
            time.sleep(0.05) # 20fps

    def _callback(self, indata, frames, time_info, status):
        if status:
            print(f"Status: {status}", flush=True)
            
        if self.is_recording and not self.is_paused:
            if self.is_muted:
                self.q.put(np.zeros_like(indata))
            else:
                # ONLY copy data to avoid blocking the high-priority CoreAudio thread!
                self.q.put(indata.copy())

    def _audio_worker(self):
        # Reads raw audio from hardware, calculates VAD, creates sliding windows, and sends to transcriber
        while self.is_recording or not self.q.empty():
            try:
                # Get audio chunks from hardware
                indata = self.q.get(timeout=0.05)
                if indata is None:
                    break
                
                try:
                    # Calculate volume for UI off the critical hardware thread
                    peak = float(np.max(np.abs(indata))) * 2.0
                    self.current_volume = peak
                except Exception:
                    pass
                
                with self.lock:
                    self.full_audio_history.append(indata)
                    self.active_streaming_buffer.append(indata)
                    
                    audio_data_float = np.concatenate(self.active_streaming_buffer, axis=0)
                    
                    # Inside the lock so attach_stream_session() can't double-feed a chunk
                    if self.stream_session is not None:
                        try:
                            self.stream_session.feed(indata)
                        except Exception as feed_err:
                            print(f"[!] Cloud stream feed error: {feed_err}")
                
                actual_sr = getattr(self, 'actual_sample_rate', 16000)
                sr_ratio = 16000.0 / actual_sr if actual_sr else 1.0
                
                # Check for silence using RMS energy in the last 0.6s (rapid commits for ultra-low latency)
                tail_len = int(0.6 * actual_sr)
                tail_frames = audio_data_float[-tail_len:] if len(audio_data_float) > tail_len else audio_data_float
                is_silence = False
                
                # Dynamic Noise Floor VAD
                if len(tail_frames) >= tail_len:
                    rms = float(np.sqrt(np.mean(tail_frames**2)))
                    # Only update noise floor if it's actually quiet (e.g. < 0.02)
                    if rms < self.noise_floor and rms < 0.02:
                        self.noise_floor = rms
                        
                    # Require a full 0.6s of silence before committing.
                    # Cap the silence threshold to avoid triggering on soft speech
                    silence_threshold = min((self.noise_floor * 2.0) + 0.005, 0.015)
                    if rms < silence_threshold:
                        is_silence = True
                        
                # Force a hard commit every 4.0 seconds to bound the maximum possible latency on stop()
                force_commit = len(audio_data_float) > int(4.0 * actual_sr)
                
                # Send a partial UI update every 0.5s of new audio
                last_len = getattr(self, "last_sent_length", 0)
                should_partial = (len(audio_data_float) - last_len) > int(0.5 * actual_sr)
                
                if self.use_vad_streaming:
                    if is_silence or force_commit:
                        if self._has_speech(audio_data_float):
                            wav_bytes = self._encode_wav(audio_data_float)
                            self.transcription_queue.put((wav_bytes, True))
                        with self.lock:
                            self.active_streaming_buffer = []
                            self.last_sent_length = 0
                    elif should_partial and self.transcription_queue.empty():
                        if self._has_speech(audio_data_float):
                            wav_bytes = self._encode_wav(audio_data_float)
                            self.transcription_queue.put((wav_bytes, False))
                        with self.lock:
                            self.last_sent_length = len(audio_data_float)
                            
            except queue.Empty:
                continue

                pass

    def _has_speech(self, audio_data_float):
        if len(audio_data_float) == 0:
            return False
        max_amp = float(np.max(np.abs(audio_data_float)))
        # Speech generally hits >5% volume (0.05). Silence is <1% (0.01).
        return max_amp > 0.03

    def _encode_wav(self, audio_data_float):
        if audio_data_float.ndim > 1:
            audio_data_float = audio_data_float.flatten()

        actual_sr = getattr(self, 'actual_sample_rate', 16000)
        if actual_sr != 16000:
            try:
                import scipy.signal
                audio_data_float = scipy.signal.resample_poly(audio_data_float, 16000, int(actual_sr))
            except ImportError:
                x_old = np.linspace(0, 1, len(audio_data_float))
                x_new = np.linspace(0, 1, int(len(audio_data_float) * 16000 / actual_sr))
                audio_data_float = np.interp(x_new, x_old, audio_data_float)

        # Add 0.5s of pure silence padding to prevent Whisper from dropping the final trailing word on abrupt stops
        padding = np.zeros(int(16000 * 0.5), dtype=np.float32)
        padded_audio = np.concatenate([audio_data_float, padding])

        # Prevent float overflow (clipping) which causes whisper static hallucinations
        audio_data_float = np.clip(padded_audio, -1.0, 1.0)
        audio_data = (audio_data_float * 32767).astype(np.int16)
        
        wav_io = io.BytesIO()
        with wave.open(wav_io, 'wb') as wav_file:
            wav_file.setnchannels(self.channels)
            wav_file.setsampwidth(2)
            wav_file.setframerate(self.sample_rate)
            wav_file.writeframes(audio_data.tobytes())
        return wav_io.getvalue()

    def _transcription_worker(self):
        # Serially consumes the transcription queue for real-time partial streaming.
        # Continues draining the queue even after recording stops so the final words are captured.
        while self.is_recording or not self.transcription_queue.empty():
            try:
                item = self.transcription_queue.get(timeout=0.05)
                if item is None or item[0] is None:
                    break
                wav_bytes, is_commit = item
                
                url = local_whisper.INFERENCE_URL
                files = {"file": ("chunk.wav", wav_bytes, "audio/wav")}
                lang = getattr(self, 'language', 'auto') or 'auto'
                data = {
                    "response_format": "json",
                    "language": lang,
                    "temperature": "0.0",
                    "suppress_non_speech": "true"
                }
                
                base_prompt = getattr(self, 'custom_prompt', "")
                
                with self.lock:
                    ctx = self.committed_text.strip()
                if ctx and base_prompt:
                    data["prompt"] = base_prompt + ". " + ctx[-200:]
                elif ctx:
                    data["prompt"] = ctx[-200:]
                elif base_prompt:
                    data["prompt"] = base_prompt

                if not self._is_whisper_server_available():
                    continue
                
                # Fast timeout for live preview streaming to avoid blocking
                resp = requests.post(url, files=files, data=data, timeout=1.5)
                if resp.status_code == 200:
                    result = resp.json()
                    if "text" in result:
                        # Force single-line flow without splitting words at whisper.cpp's
                        # hard line wraps (e.g. "язы\nк" must become "язык").
                        text = normalize_whisper_text(result["text"])
                        # Remove hallucinated tags like [BLANK_AUDIO], (silence), etc.
                        text = re.sub(r'\[.*?\]|\(.*?\)', '', text).strip()
                        
                        text = text.replace('...', ' ').replace('..', ' ').replace('…', ' ')
                        text = normalize_whisper_text(text)
                        
                        clean_check = text.lower().strip().rstrip('.!,;:')
                        known_hallucinations = {
                            "thank you", "bye", "you", "okay", "test", 
                            "thank you for watching", "thanks for watching", "thanks", "thank you for watching!",
                            "please subscribe", "subscribe to my channel", "subscribe", 
                            "if you enjoyed this video", "see you next time",
                            "great", "in this collection", "mbc news", "bbc news",
                            "like", "so", "right", "all right", "like, and, right",
                            "thanks for watching, such as", "thanks for watching! <3", "thanks for watching!"
                        }
                        if clean_check in known_hallucinations or len(clean_check) <= 1:
                            continue
                        
                        # Filter out CJK/Cyrillic hallucinated scripts when targeting English
                        if lang == "en" and re.search(r'[\u3000-\u30ff\u4e00-\u9fff\u0400-\u04ff]', text):
                            continue
                        
                        with self.lock:
                            if is_commit:
                                # Preserve punctuation on commit so the next sentence is grammatically correct.
                                # The join helper also removes a boundary word echoed from the prompt/overlap.
                                self.committed_text = join_transcript_parts(
                                    [self.committed_text, text], separate_responses=True
                                )
                                self.latest_partial = ""
                                full_text = self.committed_text
                            else:
                                # Strip trailing punctuation from intermediate chunks so we don't spam periods in the UI
                                clean_chunk = text.rstrip('.!,;:')
                                self.latest_partial = clean_chunk
                                full_text = join_transcript_parts(
                                    [self.committed_text, clean_chunk], separate_responses=True
                                )
                            
                        # Broadcast partial update (only while still recording for UI)
                        if self.is_recording and full_text and len(full_text) > 0:
                            try:
                                requests.post(
                                    "http://127.0.0.1:8075/recording/internal/partial",
                                    json={"text": full_text},
                                    headers=engine_auth.auth_headers(),
                                    timeout=1.0,
                                )
                            except: pass
                            
            except queue.Empty:
                continue
            except Exception as e:
                print(f"[!] Background worker exception: {e}")

    def get_current_buffer_wav(self):
        """
        Snapshot the currently unprocessed audio buffer as WAV bytes.
        Used to send the final uncommitted audio to whisper immediately
        when the user presses Stop, in parallel with saving the full audio.
        Returns None if the buffer is too short to be useful.
        """
        with self.lock:
            if not self.active_streaming_buffer:
                return None
            audio_data = np.concatenate(self.active_streaming_buffer, axis=0)
            
        if not self._has_speech(audio_data):
            return None
        
        actual_sr = getattr(self, 'actual_sample_rate', 16000)
        # Only transcribe if there's at least 0.5s of audio (avoid noise bursts)
        if len(audio_data) < int(0.5 * actual_sr):
            return None
        return self._encode_wav(audio_data)

    def get_input_devices(self):
        devices = []
        try:
            # Refresh PortAudio internal device list so dynamically connected AirPods/headsets appear immediately
            # IMPORTANT: Never terminate PortAudio while a stream is active, or it will corrupt the audio recording!
            if not getattr(self, 'is_recording', False):
                try:
                    sd._terminate()
                    sd._initialize()
                except Exception:
                    pass
            device_list = sd.query_devices()
            for idx, dev in enumerate(device_list):
                if dev['max_input_channels'] > 0:
                    devices.append({
                        "id": idx,
                        "name": dev['name'],
                        "is_default": idx == sd.default.device[0]
                    })
        except Exception as e:
            print(f"Error querying devices: {e}")
        return devices

    def start(self, device_id: int = None, language: str = "auto", custom_prompt: str = "", is_muted: bool = False, mode: str = "dictation", capture_loopback: bool = None, use_vad_streaming: bool = False):
        with self.lock:
            if self.is_recording:
                return

            self.is_recording = True
            self.is_paused = False
            self.has_paused = False
            self.is_muted = is_muted
            self.language = language or "auto"
            self.custom_prompt = custom_prompt
            self.recording_mode = mode or "dictation"
            self.use_vad_streaming = use_vad_streaming

            if capture_loopback is None:
                capture_loopback = (self.recording_mode in ("meeting", "focused_meeting") and sys.platform == "win32")
            self.capture_loopback = capture_loopback
            self.loopback_chunks = []

            self.q = queue.Queue()
            self.transcription_queue = queue.Queue()

            self.full_audio_history = []
            self.active_streaming_buffer = []
            self.committed_text = ""
            self.latest_partial = ""
            self.final_unprocessed_wav = None
            self.noise_floor = 1.0

            if self.stream:
                try:
                    self.stream.stop()
                    self.stream.close()
                except Exception:
                    pass
                self.stream = None

            def _open_stream():
                info = sd.query_devices(device_id, 'input') if device_id is not None else sd.query_devices(sd.default.device[0], 'input')
                sr = int(info['default_samplerate'])
                stream = sd.InputStream(
                    samplerate=sr,
                    channels=1,
                    device=device_id,
                    callback=self._callback,
                    dtype='float32'
                )
                return stream, sr

            try:
                # Refresh PortAudio's device table before opening the stream so hot-plugged/reconnected
                # Bluetooth headsets (e.g. AirPods Max) and updated macOS default input devices are picked up,
                # instead of silently recording zeros from a stale PortAudio device handle.
                sd._terminate()
                sd._initialize()
                self.stream, native_sr = _open_stream()
            except Exception as e1:
                print(f"[!] InputStream failed: {e1}")
                self.is_recording = False
                self.is_paused = False
                self.has_paused = False
                return

            self.actual_sample_rate = native_sr
            print(f"[*] Native InputStream opened at {native_sr}Hz with 1 channels")

            self.stream.start()
            
            self.udp_thread = threading.Thread(target=self._udp_worker, daemon=True)
            self.udp_thread.start()
            
            self.audio_worker_thread = threading.Thread(target=self._audio_worker, daemon=True)
            self.audio_worker_thread.start()
            
            if self.use_vad_streaming:
                self.transcription_worker_thread = threading.Thread(target=self._transcription_worker, daemon=True)
                self.transcription_worker_thread.start()

            if self.capture_loopback:
                self.loopback_thread = threading.Thread(target=self._loopback_worker, daemon=True)
                self.loopback_thread.start()
            
            print(f"[*] Voice recording started (VAD streaming: {self.use_vad_streaming})...")

    def attach_stream_session(self, session) -> None:
        """Attach a cloud streaming session after start() (the device sample rate is only known then).
        Audio captured before attaching is replayed into the session first, so nothing is lost."""
        with self.lock:
            if self.full_audio_history:
                try:
                    session.feed(np.concatenate(self.full_audio_history, axis=0))
                except Exception as e:
                    print(f"[!] Cloud stream backfill error: {e}")
            self.stream_session = session

    def detach_stream_session(self):
        with self.lock:
            session, self.stream_session = self.stream_session, None
        return session

    def _is_whisper_server_available(self) -> bool:
        try:
            r = requests.get(local_whisper.HEALTH_URL, timeout=0.1)
            return r.status_code == 200
        except Exception:
            return False

    def pause(self):
        with self.lock:
            if not self.is_recording or self.is_paused:
                return
            self.is_paused = True
            self.has_paused = True
            self.current_volume = 0.0
            print("[*] Voice recording paused.")
            
            # If local whisper-server is active on its local port, flush pending speech
            if self._is_whisper_server_available() and len(self.active_streaming_buffer) > 0:
                audio_data_float = np.concatenate(self.active_streaming_buffer, axis=0)
                if self._has_speech(audio_data_float):
                    wav_bytes = self._encode_wav(audio_data_float)
                    self.transcription_queue.put((wav_bytes, True))
                self.active_streaming_buffer = []
                self.last_sent_length = 0

    def resume(self):
        with self.lock:
            if not self.is_recording or not self.is_paused:
                return
            self.is_paused = False
            self.noise_floor = 1.0
            actual_sr = getattr(self, 'actual_sample_rate', 16000)
            # Insert a clean 0.35s acoustic silence padding between segments so Whisper has natural phrasing boundaries
            silence_frames = np.zeros((int(0.35 * actual_sr), 1), dtype=np.float32)
            self.full_audio_history.append(silence_frames)
            if getattr(self, 'capture_loopback', False):
                silence_loop = np.zeros((int(0.35 * self.sample_rate), 1), dtype=np.float32)
                self.loopback_chunks.append(silence_loop)
            print("[*] Voice recording resumed.")

    def set_muted(self, muted: bool):
        with self.lock:
            self.is_muted = muted
            if muted:
                self.current_volume = 0.0
                self.active_streaming_buffer = []
                self.last_sent_length = 0
            print(f"[*] Voice recording microphone muted: {muted}")

    @staticmethod
    def _trim_silence(audio: "np.ndarray", sr: int, frame_ms: int = 20,
                      lead_margin_s: float = 0.25, tail_margin_s: float = 0.25) -> "np.ndarray":
        """Conservatively trims leading/trailing silence using an adaptive RMS threshold.
        Keeps generous margins around speech; returns the input unchanged if no speech is detected
        or if the clip is very short."""
        try:
            frame = int(sr * frame_ms / 1000)
            n_frames = len(audio) // frame
            if n_frames < 25:  # < 0.5s, not worth trimming
                return audio
            frames = audio[: n_frames * frame].reshape(n_frames, frame)
            rms = np.sqrt(np.mean(frames.astype(np.float32) ** 2, axis=1))
            noise_floor = float(np.percentile(rms, 10))
            threshold = max(noise_floor * 3.0, 0.004)
            voiced = np.where(rms > threshold)[0]
            if len(voiced) == 0:
                return audio
            start = max(0, voiced[0] * frame - int(lead_margin_s * sr))
            end = min(len(audio), (voiced[-1] + 1) * frame + int(tail_margin_s * sr))
            trimmed_s = (len(audio) - (end - start)) / sr
            if trimmed_s > 0.1:
                print(f"[*] Trimmed {trimmed_s:.2f}s of leading/trailing silence")
            return audio[start:end]
        except Exception as e:
            print(f"[!] Silence trim skipped: {e}")
            return audio

    def stop(self, output_path: str, loopback_output_path: str = None, use_vad_streaming: bool = True) -> bool:
        import time
        t0 = time.perf_counter()
        
        with self.lock:
            if not self.is_recording:
                return False
            self.is_recording = False
            self.is_paused = False
            self.is_muted = False
            print("[*] Voice recording stopped. Packaging audio...")
        
        if self.stream:
            # Must run on a separate thread to prevent deadlocking portaudio
            def _async_close(stream):
                try: stream.stop()
                except: pass
                try: stream.close()
                except: pass
            
            if self.stream:
                threading.Thread(target=_async_close, args=(self.stream,), daemon=True).start()
                self.stream = None
            
        try:
            self.q.put(None)
        except Exception: pass

        # Fast non-blocking join for the audio worker thread
        if hasattr(self, 'audio_worker_thread') and self.audio_worker_thread and self.audio_worker_thread.is_alive():
            self.audio_worker_thread.join(timeout=0.08)

        # Fast join for the loopback worker thread if active
        if hasattr(self, 'loopback_thread') and self.loopback_thread and self.loopback_thread.is_alive():
            self.loopback_thread.join(timeout=0.25)

        # Drain any lingering audio chunks from the callback directly in the main thread (thread-safe now)
        while not self.q.empty():
            try:
                indata = self.q.get_nowait()
                if indata is not None:
                    self.full_audio_history.append(indata)
                    self.active_streaming_buffer.append(indata)
                    if self.stream_session is not None:
                        try: self.stream_session.feed(indata)
                        except Exception: pass
            except Exception:
                break

        # Purge all pending partial updates from the queue so the worker can catch up instantly
        # If we find a pending commit, put it back and stop purging.
        try:
            items_to_keep = []
            while not self.transcription_queue.empty():
                item = self.transcription_queue.get_nowait()
                if item and item[1] == True:
                    items_to_keep.append(item)
                    
            for item in items_to_keep:
                self.transcription_queue.put(item)
        except Exception: pass

        try:
            self.transcription_queue.put((None, False))
        except Exception: pass

        # Only query whisper-server on its local port if it is actively running and responding
        server_live = use_vad_streaming and self._is_whisper_server_available()
        if use_vad_streaming and server_live:
            if hasattr(self, 'transcription_worker_thread') and self.transcription_worker_thread and self.transcription_worker_thread.is_alive():
                self.transcription_worker_thread.join(timeout=0.1)
    
            # Instantly Transcribe the Final Uncommitted Audio Chunk
            final_wav = self.get_current_buffer_wav()
            if final_wav:
                url = local_whisper.INFERENCE_URL
                files = {"file": ("chunk.wav", final_wav, "audio/wav")}
                lang = getattr(self, 'language', 'auto') or 'auto'
                data = {
                    "response_format": "json", 
                    "language": lang,
                    "temperature": "0.0",
                    "suppress_non_speech": "true"
                }
                
                with self.lock:
                    ctx = self.committed_text.strip()
                base_prompt = getattr(self, 'custom_prompt', "")
                if ctx and base_prompt:
                    data["prompt"] = base_prompt + ". " + ctx[-200:]
                elif ctx:
                    data["prompt"] = ctx[-200:]
                elif base_prompt:
                    data["prompt"] = base_prompt
                    
                try:
                    resp = requests.post(url, files=files, data=data, timeout=1.0)
                    if resp.status_code == 200:
                        result = resp.json()
                        if "text" in result:
                            text = normalize_whisper_text(result["text"])
                            text = re.sub(r'\[.*?\]|\(.*?\)', '', text).strip()
                            text = text.replace('...', ' ').replace('..', ' ').replace('…', ' ')
                            text = normalize_whisper_text(text)
                            
                            if len(text) > 1:
                                with self.lock:
                                    self.committed_text = join_transcript_parts(
                                        [self.committed_text, text], separate_responses=True
                                    )
                except Exception as e:
                    print(f"[!] Background final chunk inference failed: {e}")

        # Save loopback audio if captured and destination path specified
        if loopback_output_path and hasattr(self, 'loopback_chunks') and self.loopback_chunks:
            try:
                sys_audio_float = np.concatenate(self.loopback_chunks, axis=0)
                if sys_audio_float.ndim > 1:
                    sys_audio_float = sys_audio_float.flatten()
                padding = np.zeros(int(self.sample_rate * 0.5), dtype=np.float32)
                padded_sys = np.concatenate([sys_audio_float, padding])
                sys_audio_float = np.clip(padded_sys, -1.0, 1.0)
                sys_audio = (sys_audio_float * 32767).astype(np.int16)
                sf.write(loopback_output_path, sys_audio, self.sample_rate, subtype='PCM_16')
                print(f"[+] Saved system loopback recording to {loopback_output_path} ({len(sys_audio)/self.sample_rate:.2f}s)", flush=True)
            except Exception as e_lb:
                print(f"[!] Failed to save loopback recording: {e_lb}", flush=True)

        with self.lock:
            self.committed_text = self.committed_text.strip()
            
            if len(self.full_audio_history) == 0:
                if loopback_output_path and os.path.exists(loopback_output_path) and os.path.getsize(loopback_output_path) > 100:
                    silence_pad = np.zeros(int(self.sample_rate * 0.5), dtype=np.int16)
                    sf.write(output_path, silence_pad, self.sample_rate, subtype='PCM_16')
                    return True
                print("[!] No voice audio recorded.")
                return False
                
            # Save exact full recording history to disk
            audio_data_float = np.concatenate(self.full_audio_history, axis=0)
            if audio_data_float.ndim > 1:
                audio_data_float = audio_data_float.flatten()

            actual_sr = getattr(self, 'actual_sample_rate', 16000)
            if actual_sr != 16000:
                try:
                    import scipy.signal
                    audio_data_float = scipy.signal.resample_poly(audio_data_float, 16000, int(actual_sr))
                except ImportError:
                    x_old = np.linspace(0, 1, len(audio_data_float))
                    x_new = np.linspace(0, 1, int(len(audio_data_float) * 16000 / actual_sr))
                    audio_data_float = np.interp(x_new, x_old, audio_data_float)

            # Dictation only: trim leading/trailing silence so Whisper doesn't decode dead air.
            # (Meeting mic audio is mixed with system audio and must stay time-aligned, so it is left untouched.)
            if getattr(self, "recording_mode", "dictation") == "dictation":
                audio_data_float = self._trim_silence(audio_data_float, 16000)

            # Short silence tail so Whisper doesn't drop the final trailing word on abrupt stops
            padding = np.zeros(int(16000 * 0.3), dtype=np.float32)
            padded_audio = np.concatenate([audio_data_float, padding])

            audio_data_float = np.clip(padded_audio, -1.0, 1.0)
            audio_data = (audio_data_float * 32767).astype(np.int16)
            
            if output_path and not output_path.endswith(".discard"):
                sf.write(output_path, audio_data, self.sample_rate, subtype='PCM_16')
                print(f"[+] Saved recording to {output_path}")
            # Release raw capture buffers now that the WAV is on disk. Previously they were kept
            # until the next recording started (~690 MB/hour of float32 audio at 48 kHz).
            self.full_audio_history = []
            self.active_streaming_buffer = []
            self.loopback_chunks = []
            return True
