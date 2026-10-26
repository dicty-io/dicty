// Dicty Audio Feedback Service
// Supports:
// 1. Built-in Windows Media Sounds (Speech On, Speech Off, Windows Ding, Chimes, etc.) via native PlaySoundW
// 2. Synthesized Studio Chimes via Web Audio API (zero external assets required)
// 3. Custom user-selected audio files (.wav, .mp3, .ogg, .m4a) via HTML5 Audio / Data URL

import { invoke } from "@tauri-apps/api/core";

export interface SystemSoundEntry {
  id: string;
  name: string;
  path: string;
}

export const DEFAULT_WINDOWS_SOUNDS: SystemSoundEntry[] = [
  { id: "Speech On", name: "Speech On (Recommended Start)", path: "C:\\Windows\\Media\\Speech On.wav" },
  { id: "Speech Off", name: "Speech Off (Recommended Stop)", path: "C:\\Windows\\Media\\Speech Off.wav" },
  { id: "Windows Ding", name: "Windows Ding", path: "C:\\Windows\\Media\\Windows Ding.wav" },
  { id: "Windows Notify", name: "Windows Notify", path: "C:\\Windows\\Media\\Windows Notify.wav" },
  { id: "Windows Generic", name: "Windows Generic Notification", path: "C:\\Windows\\Media\\Windows Notify System Generic.wav" },
  { id: "Navigation Start", name: "Navigation Start", path: "C:\\Windows\\Media\\Windows Navigation Start.wav" },
  { id: "Hardware Insert", name: "Hardware Insert", path: "C:\\Windows\\Media\\Windows Hardware Insert.wav" },
  { id: "Hardware Remove", name: "Hardware Remove", path: "C:\\Windows\\Media\\Windows Hardware Remove.wav" },
  { id: "Chimes", name: "Chimes", path: "C:\\Windows\\Media\\chimes.wav" },
  { id: "Chord", name: "Chord", path: "C:\\Windows\\Media\\chord.wav" },
  { id: "Ding", name: "Ding", path: "C:\\Windows\\Media\\ding.wav" },
  { id: "Notify", name: "Notify", path: "C:\\Windows\\Media\\notify.wav" },
  { id: "Tada", name: "Tada", path: "C:\\Windows\\Media\\tada.wav" },
  { id: "Speech Sleep", name: "Speech Sleep", path: "C:\\Windows\\Media\\Speech Sleep.wav" },
  { id: "Windows Balloon", name: "Windows Balloon", path: "C:\\Windows\\Media\\Windows Balloon.wav" },
];

let audioCtx: AudioContext | null = null;
let lastStartSoundTime = 0;
let lastStopSoundTime = 0;

function getAudioContext(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
    if (AudioContextClass) {
      audioCtx = new AudioContextClass();
    }
  }
  if (audioCtx && audioCtx.state === "suspended") {
    audioCtx.resume().catch(() => {});
  }
  return audioCtx;
}

export function getStoredVolume(): number {
  if (typeof window === "undefined") return 70;
  const raw = localStorage.getItem("dicty_sound_volume");
  if (raw !== null) {
    const parsed = parseInt(raw, 10);
    if (!isNaN(parsed) && parsed >= 0 && parsed <= 100) return parsed;
  }
  return 70;
}

/**
 * Ascending chime: C5 (523Hz) -> G5 (784Hz) using Web Audio API
 */
export function playSynthesizedStartChime(volPercent?: number) {
  const ctx = getAudioContext();
  if (!ctx) return;

  const vol = (volPercent ?? getStoredVolume()) / 100;
  if (vol <= 0) return;

  const now = ctx.currentTime;
  const notes = [
    { freq: 523.25, time: now, duration: 0.12 },
    { freq: 783.99, time: now + 0.08, duration: 0.22 },
  ];

  notes.forEach(({ freq, time, duration }) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = "sine";
    osc.frequency.setValueAtTime(freq, time);

    gain.gain.setValueAtTime(0.001, time);
    gain.gain.exponentialRampToValueAtTime(0.22 * vol, time + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, time + duration);

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.start(time);
    osc.stop(time + duration);
  });
}

/**
 * Descending chime: G5 (784Hz) -> E5 (659Hz) -> C5 (523Hz) using Web Audio API
 */
export function playSynthesizedStopChime(volPercent?: number) {
  const ctx = getAudioContext();
  if (!ctx) return;

  const vol = (volPercent ?? getStoredVolume()) / 100;
  if (vol <= 0) return;

  const now = ctx.currentTime;
  const notes = [
    { freq: 783.99, time: now, duration: 0.09 },
    { freq: 659.25, time: now + 0.06, duration: 0.09 },
    { freq: 523.25, time: now + 0.12, duration: 0.22 },
  ];

  notes.forEach(({ freq, time, duration }) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = "sine";
    osc.frequency.setValueAtTime(freq, time);

    gain.gain.setValueAtTime(0.001, time);
    gain.gain.exponentialRampToValueAtTime(0.18 * vol, time + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, time + duration);

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.start(time);
    osc.stop(time + duration);
  });
}

/**
 * Fetches all available system sounds from Windows Media directory via Tauri,
 * falling back to the curated default catalog.
 */
export async function getAvailableSystemSounds(): Promise<SystemSoundEntry[]> {
  try {
    const systemSounds = await invoke<SystemSoundEntry[]>("get_available_system_sounds");
    if (systemSounds && systemSounds.length > 0) {
      // Prioritize Speech On and Speech Off at top of list
      const prioritized = ["Speech On", "Speech Off", "Windows Ding", "Windows Notify", "chimes", "chord", "ding", "notify", "tada"];
      return [...systemSounds].sort((a, b) => {
        const indexA = prioritized.indexOf(a.id);
        const indexB = prioritized.indexOf(b.id);
        if (indexA !== -1 && indexB !== -1) return indexA - indexB;
        if (indexA !== -1) return -1;
        if (indexB !== -1) return 1;
        return a.name.localeCompare(b.name);
      });
    }
  } catch (err) {
    console.debug("Native get_available_system_sounds unavailable, using default catalog:", err);
  }
  return DEFAULT_WINDOWS_SOUNDS;
}

/**
 * Previews any selected sound configuration immediately in the UI.
 */
export async function playSoundPreview(
  type: string,
  _name: string,
  path: string,
  dataUrl?: string,
  isStopSound: boolean = false,
  volPercent?: number
) {
  if (type === "None") {
    return;
  }

  const vol = volPercent ?? getStoredVolume();
  if (vol <= 0) return;

  if (type === "Synthesized") {
    if (isStopSound) {
      playSynthesizedStopChime(vol);
    } else {
      playSynthesizedStartChime(vol);
    }
    return;
  }

  if (type === "Custom") {
    if (dataUrl) {
      try {
        const audio = new Audio(dataUrl);
        audio.volume = (vol / 100) * 0.85;
        await audio.play();
        return;
      } catch (e) {
        console.warn("Failed to play custom audio dataUrl:", e);
      }
    }
    if (path) {
      try {
        await invoke("play_system_sound", { path, volume: vol });
        return;
      } catch (e) {
        console.warn("Failed to play custom audio path natively:", e);
      }
    }
    // Fallback if custom file failed
    if (isStopSound) playSynthesizedStopChime(vol);
    else playSynthesizedStartChime(vol);
    return;
  }

  // Built-in system sound
  if (path) {
    try {
      await invoke("play_system_sound", { path, volume: vol });
      return;
    } catch (e) {
      console.debug("play_system_sound via Tauri failed, falling back to Web Audio:", e);
    }
  }

  // Fallback to Web Audio synthesis
  if (isStopSound) {
    playSynthesizedStopChime(vol);
  } else {
    playSynthesizedStartChime(vol);
  }
}

/**
 * Plays configured start recording sound.
 */
export function playStartSound() {
  if (typeof window === "undefined") return;
  if (localStorage.getItem("dicty_sound_feedback") === "false") {
    return;
  }

  const now = Date.now();
  if (now - lastStartSoundTime < 250) {
    return; // Debounce rapid triggers
  }
  lastStartSoundTime = now;

  const vol = getStoredVolume();
  invoke("play_dictation_sound", { isStart: true, volume: vol }).catch(() => {
    // Fallback if running outside Tauri
    const type = localStorage.getItem("dicty_start_sound_type") || "Built-in";
    const name = localStorage.getItem("dicty_start_sound_name") || "Speech On";
    const path = localStorage.getItem("dicty_start_sound_path") || "C:\\Windows\\Media\\Speech On.wav";
    const dataUrl = localStorage.getItem("dicty_start_sound_data") || "";
    playSoundPreview(type, name, path, dataUrl, false, vol);
  });
}

/**
 * Plays configured stop recording sound.
 */
export function playStopSound() {
  if (typeof window === "undefined") return;
  if (localStorage.getItem("dicty_sound_feedback") === "false") {
    return;
  }

  const now = Date.now();
  if (now - lastStopSoundTime < 250) {
    return; // Debounce rapid triggers
  }
  lastStopSoundTime = now;

  const vol = getStoredVolume();
  invoke("play_dictation_sound", { isStart: false, volume: vol }).catch(() => {
    // Fallback if running outside Tauri
    const type = localStorage.getItem("dicty_stop_sound_type") || "Built-in";
    const name = localStorage.getItem("dicty_stop_sound_name") || "Speech Off";
    const path = localStorage.getItem("dicty_stop_sound_path") || "C:\\Windows\\Media\\Speech Off.wav";
    const dataUrl = localStorage.getItem("dicty_stop_sound_data") || "";
    playSoundPreview(type, name, path, dataUrl, true, vol);
  });
}
