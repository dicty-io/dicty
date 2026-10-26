use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SoundConfig {
    #[serde(default = "default_true")]
    pub sound_feedback: bool,
    #[serde(default = "default_volume")]
    pub sound_volume: u32,
    #[serde(default = "default_start_type")]
    pub start_sound_type: String,
    #[serde(default = "default_start_name")]
    pub start_sound_name: String,
    #[serde(default = "default_start_path")]
    pub start_sound_path: String,
    #[serde(default = "default_stop_type")]
    pub stop_sound_type: String,
    #[serde(default = "default_stop_name")]
    pub stop_sound_name: String,
    #[serde(default = "default_stop_path")]
    pub stop_sound_path: String,
}

fn default_true() -> bool {
    true
}
fn default_volume() -> u32 {
    70
}
fn default_start_type() -> String {
    "Built-in".to_string()
}
fn default_start_name() -> String {
    "Speech On".to_string()
}
fn default_start_path() -> String {
    "C:\\Windows\\Media\\Speech On.wav".to_string()
}
fn default_stop_type() -> String {
    "Built-in".to_string()
}
fn default_stop_name() -> String {
    "Speech Off".to_string()
}
fn default_stop_path() -> String {
    "C:\\Windows\\Media\\Speech Off.wav".to_string()
}

impl Default for SoundConfig {
    fn default() -> Self {
        Self {
            sound_feedback: default_true(),
            sound_volume: default_volume(),
            start_sound_type: default_start_type(),
            start_sound_name: default_start_name(),
            start_sound_path: default_start_path(),
            stop_sound_type: default_stop_type(),
            stop_sound_name: default_stop_name(),
            stop_sound_path: default_stop_path(),
        }
    }
}

static SOUND_CONFIG: Mutex<Option<SoundConfig>> = Mutex::new(None);

fn get_config_file_path() -> PathBuf {
    if let Some(app_data) = std::env::var_os("APPDATA") {
        let dir = PathBuf::from(app_data).join("Dicty");
        let _ = fs::create_dir_all(&dir);
        return dir.join("sound_config.json");
    }
    PathBuf::from("sound_config.json")
}

pub fn get_sound_config() -> SoundConfig {
    let mut guard = SOUND_CONFIG.lock().unwrap();
    if let Some(ref cfg) = *guard {
        return cfg.clone();
    }
    let p = get_config_file_path();
    let cfg = if p.exists() {
        if let Ok(content) = fs::read_to_string(&p) {
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            SoundConfig::default()
        }
    } else {
        SoundConfig::default()
    };
    *guard = Some(cfg.clone());
    cfg
}

pub fn set_sound_config(cfg: SoundConfig) {
    let p = get_config_file_path();
    if let Ok(content) = serde_json::to_string_pretty(&cfg) {
        let _ = fs::write(&p, content);
    }
    let mut guard = SOUND_CONFIG.lock().unwrap();
    *guard = Some(cfg);
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct SystemSoundInfo {
    pub id: String,
    pub name: String,
    pub path: String,
}

#[cfg(target_os = "windows")]
#[link(name = "winmm")]
extern "system" {
    fn PlaySoundW(pszSound: *const u16, hmod: *mut std::ffi::c_void, fdwSound: u32) -> i32;
}

const SND_SYNC: u32 = 0x0000;
const SND_NODEFAULT: u32 = 0x0002;
const SND_MEMORY: u32 = 0x0004;
const SND_FILENAME: u32 = 0x00020000;

/// Scales raw WAV PCM audio samples to the requested volume percentage (0-100%).
/// Supports 16-bit signed PCM and 8-bit unsigned PCM.
fn scale_wav_volume(wav_bytes: &[u8], volume_percent: u32) -> Option<Vec<u8>> {
    if wav_bytes.len() < 44 {
        return None;
    }
    if &wav_bytes[0..4] != b"RIFF" || &wav_bytes[8..12] != b"WAVE" {
        return None;
    }

    let ratio = (volume_percent.min(100) as f32) / 100.0;
    let mut modified = wav_bytes.to_vec();
    let mut offset = 12;
    let mut bits_per_sample = 16u16;

    while offset + 8 <= modified.len() {
        let chunk_id = &modified[offset..offset + 4];
        let chunk_size = u32::from_le_bytes([
            modified[offset + 4],
            modified[offset + 5],
            modified[offset + 6],
            modified[offset + 7],
        ]) as usize;

        if chunk_id == b"fmt " && chunk_size >= 16 {
            let fmt_start = offset + 8;
            if fmt_start + 16 <= modified.len() {
                let audio_format = u16::from_le_bytes([modified[fmt_start], modified[fmt_start + 1]]);
                bits_per_sample = u16::from_le_bytes([modified[fmt_start + 14], modified[fmt_start + 15]]);
                // 1 = uncompressed PCM
                if audio_format != 1 {
                    return None;
                }
            }
        } else if chunk_id == b"data" {
            let data_start = offset + 8;
            let data_end = (data_start + chunk_size).min(modified.len());

            if bits_per_sample == 16 {
                let mut i = data_start;
                while i + 1 < data_end {
                    let sample = i16::from_le_bytes([modified[i], modified[i + 1]]);
                    let scaled = ((sample as f32) * ratio)
                        .round()
                        .clamp(i16::MIN as f32, i16::MAX as f32) as i16;
                    let bytes = scaled.to_le_bytes();
                    modified[i] = bytes[0];
                    modified[i + 1] = bytes[1];
                    i += 2;
                }
            } else if bits_per_sample == 8 {
                let mut i = data_start;
                while i < data_end {
                    let sample = modified[i] as f32 - 128.0;
                    let scaled = (sample * ratio).round().clamp(-128.0, 127.0) + 128.0;
                    modified[i] = scaled as u8;
                    i += 1;
                }
            }
            return Some(modified);
        }

        // Chunks are padded to 2-byte word boundary
        let padded_size = (chunk_size + 1) & !1;
        offset += 8 + padded_size;
    }

    None
}

/// Plays audio file with precise independent volume control (0-100%).
/// For PCM WAV files, scales samples directly in memory and plays via PlaySoundW(SND_MEMORY).
/// Completely immune to MCI command limitations or system mixer changes.
pub fn play_system_sound_with_volume(path: &str, volume_percent: u32) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::ffi::OsStrExt;

        let p = Path::new(path);
        if !p.exists() {
            return Err(format!("Sound file not found: {}", path));
        }

        if volume_percent == 0 {
            return Ok(());
        }

        let path_buf = p.to_path_buf();

        std::thread::spawn(move || {
            // Attempt in-memory PCM volume scaling
            if let Ok(bytes) = fs::read(&path_buf) {
                if let Some(scaled_bytes) = scale_wav_volume(&bytes, volume_percent) {
                    unsafe {
                        PlaySoundW(
                            scaled_bytes.as_ptr() as *const u16,
                            std::ptr::null_mut(),
                            SND_MEMORY | SND_SYNC | SND_NODEFAULT,
                        );
                    }
                    return;
                }
            }

            // Fallback to direct file playback if format cannot be scaled
            let wide: Vec<u16> = std::ffi::OsStr::new(&path_buf)
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            unsafe {
                PlaySoundW(
                    wide.as_ptr(),
                    std::ptr::null_mut(),
                    SND_FILENAME | SND_SYNC | SND_NODEFAULT,
                );
            }
        });

        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (path, volume_percent);
        Ok(())
    }
}

#[tauri::command]
pub fn play_system_sound(path: String, volume: Option<u32>) -> Result<(), String> {
    let vol = volume.unwrap_or_else(|| get_sound_config().sound_volume);
    play_system_sound_with_volume(&path, vol)
}

/// Plays the configured start or stop recording sound cue natively.
/// Immune to webview focus, hidden status, or Chromium audio throttling.
pub fn play_recording_sound(is_start: bool) {
    let config = get_sound_config();
    if !config.sound_feedback || config.sound_volume == 0 {
        println!("[*] [SOUND] Audio feedback muted or volume is 0");
        return;
    }

    let (sound_type, sound_path) = if is_start {
        (&config.start_sound_type, &config.start_sound_path)
    } else {
        (&config.stop_sound_type, &config.stop_sound_path)
    };

    if sound_type.eq_ignore_ascii_case("None") {
        return;
    }

    let resolved_path = if sound_path.is_empty() {
        if is_start {
            "C:\\Windows\\Media\\Speech On.wav"
        } else {
            "C:\\Windows\\Media\\Speech Off.wav"
        }
    } else {
        sound_path.as_str()
    };

    println!(
        "[*] [SOUND] Playing recording {} cue (volume={}%): type='{}', path='{}'",
        if is_start { "START" } else { "STOP" },
        config.sound_volume,
        sound_type,
        resolved_path
    );

    let _ = play_system_sound_with_volume(resolved_path, config.sound_volume);
}

pub fn play_mode_switch_sound() {
    let config = get_sound_config();
    if !config.sound_feedback || config.sound_volume == 0 {
        return;
    }

    let candidates = [
        "C:\\Windows\\Media\\Speech Sleep.wav",
        "C:\\Windows\\Media\\Windows Navigation Start.wav",
        "C:\\Windows\\Media\\Windows Ding.wav",
        "C:\\Windows\\Media\\ding.wav",
    ];

    for path in &candidates {
        if Path::new(path).exists() {
            let _ = play_system_sound_with_volume(path, config.sound_volume);
            return;
        }
    }
}

#[tauri::command]
pub fn save_sound_config(config: SoundConfig) -> Result<(), String> {
    set_sound_config(config);
    Ok(())
}

#[tauri::command]
pub fn load_sound_config() -> SoundConfig {
    get_sound_config()
}

#[tauri::command]
pub fn play_dictation_sound(is_start: bool, volume: Option<u32>) {
    if let Some(vol) = volume {
        let config = get_sound_config();
        if !config.sound_feedback || vol == 0 {
            return;
        }
        let sound_path = if is_start {
            &config.start_sound_path
        } else {
            &config.stop_sound_path
        };
        let resolved_path = if sound_path.is_empty() {
            if is_start {
                "C:\\Windows\\Media\\Speech On.wav"
            } else {
                "C:\\Windows\\Media\\Speech Off.wav"
            }
        } else {
            sound_path.as_str()
        };
        let _ = play_system_sound_with_volume(resolved_path, vol);
    } else {
        play_recording_sound(is_start);
    }
}

#[tauri::command]
pub fn get_available_system_sounds() -> Vec<SystemSoundInfo> {
    let mut sounds: Vec<SystemSoundInfo> = Vec::new();

    #[cfg(target_os = "windows")]
    {
        let media_dir = Path::new("C:\\Windows\\Media");
        if media_dir.exists() && media_dir.is_dir() {
            if let Ok(entries) = fs::read_dir(media_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        if let Some(ext) = path.extension() {
                            if ext.to_string_lossy().eq_ignore_ascii_case("wav") {
                                if let Some(file_stem) = path.file_stem() {
                                    let name = file_stem.to_string_lossy().to_string();
                                    sounds.push(SystemSoundInfo {
                                        id: name.clone(),
                                        name: name.clone(),
                                        path: path.to_string_lossy().to_string(),
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Sort alphabetically
    sounds.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    sounds
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_dummy_wav_16bit(samples: &[i16]) -> Vec<u8> {
        let mut bytes = Vec::new();
        let data_len = (samples.len() * 2) as u32;
        let file_len = 36 + data_len;

        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&file_len.to_le_bytes());
        bytes.extend_from_slice(b"WAVE");

        // fmt chunk (16 bytes)
        bytes.extend_from_slice(b"fmt ");
        bytes.extend_from_slice(&16u32.to_le_bytes());
        bytes.extend_from_slice(&1u16.to_le_bytes()); // PCM format
        bytes.extend_from_slice(&1u16.to_le_bytes()); // Mono
        bytes.extend_from_slice(&44100u32.to_le_bytes()); // Sample rate
        bytes.extend_from_slice(&88200u32.to_le_bytes()); // Byte rate
        bytes.extend_from_slice(&2u16.to_le_bytes()); // Block align
        bytes.extend_from_slice(&16u16.to_le_bytes()); // Bits per sample

        // data chunk
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&data_len.to_le_bytes());
        for &s in samples {
            bytes.extend_from_slice(&s.to_le_bytes());
        }

        bytes
    }

    #[test]
    fn test_scale_wav_volume_50_percent() {
        let original_samples = vec![10000, -20000, 0, 30000];
        let wav = create_dummy_wav_16bit(&original_samples);

        let scaled = scale_wav_volume(&wav, 50).expect("Should scale successfully");
        assert_eq!(scaled.len(), wav.len());

        // Check scaled data values
        let data_start = 44;
        let s0 = i16::from_le_bytes([scaled[data_start], scaled[data_start + 1]]);
        let s1 = i16::from_le_bytes([scaled[data_start + 2], scaled[data_start + 3]]);
        let s2 = i16::from_le_bytes([scaled[data_start + 4], scaled[data_start + 5]]);
        let s3 = i16::from_le_bytes([scaled[data_start + 6], scaled[data_start + 7]]);

        assert_eq!(s0, 5000);
        assert_eq!(s1, -10000);
        assert_eq!(s2, 0);
        assert_eq!(s3, 15000);
    }

    #[test]
    fn test_scale_wav_volume_10_percent() {
        let original_samples = vec![10000];
        let wav = create_dummy_wav_16bit(&original_samples);

        let scaled = scale_wav_volume(&wav, 10).expect("Should scale successfully");
        let data_start = 44;
        let s0 = i16::from_le_bytes([scaled[data_start], scaled[data_start + 1]]);
        assert_eq!(s0, 1000);
    }

    #[test]
    fn test_scale_wav_volume_invalid_magic() {
        let fake = vec![0u8; 100];
        assert!(scale_wav_volume(&fake, 50).is_none());
    }
}

