import os

def play_start_chime():
    # Audio feedback is handled natively by the client application (Tauri / Mac)
    pass

def play_stop_chime():
    # Audio feedback is handled natively by the client application (Tauri / Mac)
    pass

def play_pause_chime():
    # Audio feedback is handled natively by the client application (Tauri / Mac)
    pass

def play_resume_chime():
    # Audio feedback is handled natively by the client application (Tauri / Mac)
    pass

def mix_audio(sys_wav, mic_wav, out_wav):
    has_sys = os.path.exists(sys_wav) and os.path.getsize(sys_wav) > 100
    has_mic = os.path.exists(mic_wav) and os.path.getsize(mic_wav) > 100

    if not has_sys and has_mic:
        import shutil
        shutil.copy2(mic_wav, out_wav)
        return
    elif not has_mic and has_sys:
        import shutil
        shutil.copy2(sys_wav, out_wav)
        return
    elif not has_sys and not has_mic:
        return

    # 1. Try ffmpeg first for extremely fast mixing if available
    try:
        import subprocess
        cmd = [
            "ffmpeg", "-y",
            "-i", sys_wav,
            "-i", mic_wav,
            "-filter_complex", "amix=inputs=2:duration=longest:dropout_transition=0",
            "-ar", "16000",
            "-ac", "1",
            out_wav
        ]
        result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0 and os.path.exists(out_wav) and os.path.getsize(out_wav) > 100:
            return
    except Exception:
        pass

    # 2. Try soundfile + numpy (handles arbitrary sample rates, channels, soft-normalized mixing)
    try:
        import soundfile as sf
        import numpy as np

        data_sys, sr_sys = sf.read(sys_wav, dtype='float32')
        data_mic, sr_mic = sf.read(mic_wav, dtype='float32')

        if data_sys.ndim > 1:
            data_sys = np.mean(data_sys, axis=1)
        if data_mic.ndim > 1:
            data_mic = np.mean(data_mic, axis=1)

        target_sr = 16000
        if sr_sys != target_sr:
            import scipy.signal
            data_sys = scipy.signal.resample(data_sys, int(len(data_sys) * target_sr / sr_sys))
        if sr_mic != target_sr:
            import scipy.signal
            data_mic = scipy.signal.resample(data_mic, int(len(data_mic) * target_sr / sr_mic))

        max_len = max(len(data_sys), len(data_mic))
        if len(data_sys) < max_len:
            data_sys = np.pad(data_sys, (0, max_len - len(data_sys)))
        if len(data_mic) < max_len:
            data_mic = np.pad(data_mic, (0, max_len - len(data_mic)))

        mixed = data_sys + data_mic
        peak = np.max(np.abs(mixed))
        if peak > 1.0:
            mixed = mixed / peak

        sf.write(out_wav, mixed, target_sr, subtype='PCM_16')
        print(f"[+] Successfully mixed system and microphone audio using soundfile: {out_wav}")
        return
    except Exception as e_sf:
        pass

    # 3. Native wave + numpy fallback (Python 3.13+ safe, zero external binaries, no audioop)
    try:
        import wave
        import numpy as np
        with wave.open(sys_wav, 'rb') as w_sys, wave.open(mic_wav, 'rb') as w_mic:
            params = w_sys.getparams()
            frames_sys = w_sys.readframes(w_sys.getnframes())
            frames_mic = w_mic.readframes(w_mic.getnframes())
            
            arr_sys = np.frombuffer(frames_sys, dtype=np.int16)
            arr_mic = np.frombuffer(frames_mic, dtype=np.int16)

            max_len = max(len(arr_sys), len(arr_mic))
            if len(arr_sys) < max_len:
                arr_sys = np.pad(arr_sys, (0, max_len - len(arr_sys)))
            if len(arr_mic) < max_len:
                arr_mic = np.pad(arr_mic, (0, max_len - len(arr_mic)))

            # Mix with 32-bit headroom and clamp to 16-bit PCM
            mixed = np.clip(arr_sys.astype(np.int32) + arr_mic.astype(np.int32), -32768, 32767).astype(np.int16)

            with wave.open(out_wav, 'wb') as w_out:
                w_out.setparams(params)
                w_out.writeframes(mixed.tobytes())
        print(f"[+] Successfully mixed system and microphone audio using wave + numpy: {out_wav}")
        return
    except Exception as e:
        print(f"[!] Error mixing audio: {e}")
        import shutil
        if has_sys:
            shutil.copy2(sys_wav, out_wav)
        elif has_mic:
            shutil.copy2(mic_wav, out_wav)
