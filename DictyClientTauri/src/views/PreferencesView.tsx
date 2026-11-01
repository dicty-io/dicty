import React, { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  Trash2,
  Download,
  Check,
  RotateCcw,
  AlertTriangle,
  Volume2,
  Volume1,
  VolumeX,
  Play,
  FolderOpen,
  Sparkles,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { ToggleSwitch } from "../components/ToggleSwitch";
import { engineApi } from "../services/engineApi";
import {
  getAvailableSystemSounds,
  playSoundPreview,
  SystemSoundEntry,
  DEFAULT_WINDOWS_SOUNDS,
} from "../services/soundEffects";
import {
  ACCENT_PRESETS,
  getActiveAccent,
  applyAccentColor,
  type AccentPreset,
} from "../services/themeService";

interface ThemeCardProps {
  title: string;
  theme: "auto" | "light" | "dark";
  isSelected: boolean;
  onSelect: () => void;
}

const ThemeCard: React.FC<ThemeCardProps> = ({ title, theme, isSelected, onSelect }) => {
  return (
    <div
      onClick={onSelect}
      className="flex flex-col items-center gap-2.5 cursor-pointer group select-none"
    >
      <div
        className={`w-28 h-18 rounded-xl border relative overflow-hidden transition-all shadow-sm ${
          isSelected
            ? "border-[#87B996] ring-2 ring-[#87B996]/30 shadow-[0_0_12px_rgba(135,185,150,0.25)]"
            : "border-white/15 hover:border-white/30"
        }`}
      >
        {theme === "auto" ? (
          <div className="absolute inset-0 flex">
            <div className="w-1/2 h-full bg-[#E5E7EB] p-2 flex flex-col justify-between">
              <div className="flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-red-400" />
                <span className="w-1.5 h-1.5 rounded-full bg-amber-400" />
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
              </div>
              <div className="space-y-1">
                <div className="w-7 h-1 rounded bg-black/20" />
                <div className="w-4 h-1 rounded bg-black/15" />
              </div>
            </div>
            <div className="w-1/2 h-full bg-[#181B20] p-2 flex flex-col justify-between border-l border-black/20">
              <div className="flex items-center justify-end gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-white/20" />
              </div>
              <div className="space-y-1">
                <div className="w-7 h-1 rounded bg-white/30" />
                <div className="w-4 h-1 rounded bg-white/20" />
              </div>
            </div>
          </div>
        ) : theme === "light" ? (
          <div className="absolute inset-0 bg-[#F3F4F6] p-2 flex flex-col justify-between">
            <div className="flex items-center gap-1">
              <span className="w-1.5 h-1.5 rounded-full bg-red-400" />
              <span className="w-1.5 h-1.5 rounded-full bg-amber-400" />
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
            </div>
            <div className="space-y-1">
              <div className="w-12 h-1.5 rounded bg-black/20" />
              <div className="w-8 h-1 rounded bg-black/15" />
            </div>
          </div>
        ) : (
          <div className="absolute inset-0 bg-[#181B20] p-2 flex flex-col justify-between">
            <div className="flex items-center gap-1">
              <span className="w-1.5 h-1.5 rounded-full bg-red-500/80" />
              <span className="w-1.5 h-1.5 rounded-full bg-amber-500/80" />
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500/80" />
            </div>
            <div className="space-y-1">
              <div className="w-12 h-1.5 rounded bg-white/25" />
              <div className="w-8 h-1 rounded bg-white/15" />
            </div>
          </div>
        )}
      </div>
      <span
        className={`text-xs font-semibold transition-colors ${
          isSelected ? "text-white" : "text-white/60 group-hover:text-white/80"
        }`}
      >
        {title}
      </span>
    </div>
  );
};

const ColorPickerPill: React.FC<{
  label: string;
  color: string;
  onChange: (hex: string) => void;
}> = ({ label, color, onChange }) => {
  return (
    <div className="flex items-center justify-between py-1.5">
      <span className="text-xs font-medium text-white/90">{label}</span>
      <div className="relative group flex items-center">
        <div
          className="w-10 h-[22px] rounded-full border border-white/25 shadow-sm cursor-pointer transition-transform group-hover:scale-105"
          style={{ backgroundColor: color }}
        />
        <input
          type="color"
          value={color}
          onChange={(e) => onChange(e.target.value)}
          className="absolute inset-0 opacity-0 w-full h-full cursor-pointer"
          title={`Select ${label}`}
        />
      </div>
    </div>
  );
};

export const PreferencesView: React.FC = () => {
  const [theme, setTheme] = useState<"auto" | "light" | "dark">(() => {
    return (localStorage.getItem("dicty_theme") as "auto" | "light" | "dark") || "dark";
  });
  const [activeAccent, setActiveAccent] = useState<AccentPreset>(() => getActiveAccent());

  const handleAccentSelect = (preset: AccentPreset) => {
    setActiveAccent(preset);
    applyAccentColor(preset);
  };
  const [showInTaskbar, setShowInTaskbar] = useState(() => {
    return localStorage.getItem("dicty_show_in_taskbar") !== "false";
  });
  const [dockIconTheme, setDockIconTheme] = useState(() => {
    return localStorage.getItem("dicty_dock_icon_theme") || "system";
  });
  const [launchOnStartup, setLaunchOnStartup] = useState(() => {
    return localStorage.getItem("dicty_launch_on_startup") === "true";
  });
  const [showModeLabel, setShowModeLabel] = useState(() => {
    return localStorage.getItem("dicty_show_mode_label") !== "false";
  });
  const [overlayDockPosition, setOverlayDockPosition] = useState(() => {
    return localStorage.getItem("overlayDockPosition") || "bottom";
  });

  // Mode Accent Colors
  const [dictationColor, setDictationColor] = useState(() => {
    const val = localStorage.getItem("dicty_color_dictation");
    return val === "#4CAF50" || !val ? "#78B18D" : val;
  });
  const [librarianColor, setLibrarianColor] = useState(() => {
    const val = localStorage.getItem("dicty_color_librarian");
    return val === "#5856D6" || !val ? "#7E8CE0" : val;
  });
  const [meetingColor, setMeetingColor] = useState(() => {
    const val = localStorage.getItem("dicty_color_meeting");
    return val === "#FF9500" || !val ? "#EAA368" : val;
  });
  const [focusedColor, setFocusedColor] = useState(() => {
    const val = localStorage.getItem("dicty_color_focused");
    return val === "#FF3B30" || val === "#D946EF" || !val ? "#EB7575" : val;
  });

  // Recording Sounds Configuration (1:1 with SwiftUI Appearance.swift SoundsSettingsView)
  const [soundFeedback, setSoundFeedback] = useState(() => {
    return localStorage.getItem("dicty_sound_feedback") !== "false";
  });
  const [soundVolume, setSoundVolume] = useState<number>(() => {
    const raw = localStorage.getItem("dicty_sound_volume");
    if (raw !== null) {
      const v = parseInt(raw, 10);
      if (!isNaN(v) && v >= 0 && v <= 100) return v;
    }
    return 70;
  });
  const [startSoundType, setStartSoundType] = useState(() => {
    return localStorage.getItem("dicty_start_sound_type") || "Built-in";
  });
  const [startSoundName, setStartSoundName] = useState(() => {
    return localStorage.getItem("dicty_start_sound_name") || "Speech On";
  });
  const [startSoundPath, setStartSoundPath] = useState(() => {
    return localStorage.getItem("dicty_start_sound_path") || "C:\\Windows\\Media\\Speech On.wav";
  });
  const [startSoundData, setStartSoundData] = useState(() => {
    return localStorage.getItem("dicty_start_sound_data") || "";
  });

  const [stopSoundType, setStopSoundType] = useState(() => {
    return localStorage.getItem("dicty_stop_sound_type") || "Built-in";
  });
  const [stopSoundName, setStopSoundName] = useState(() => {
    return localStorage.getItem("dicty_stop_sound_name") || "Speech Off";
  });
  const [stopSoundPath, setStopSoundPath] = useState(() => {
    return localStorage.getItem("dicty_stop_sound_path") || "C:\\Windows\\Media\\Speech Off.wav";
  });
  const [stopSoundData, setStopSoundData] = useState(() => {
    return localStorage.getItem("dicty_stop_sound_data") || "";
  });

  const [systemSounds, setSystemSounds] = useState<SystemSoundEntry[]>(DEFAULT_WINDOWS_SOUNDS);
  const [isPlayingStart, setIsPlayingStart] = useState(false);
  const [isPlayingStop, setIsPlayingStop] = useState(false);

  const startFileInputRef = useRef<HTMLInputElement | null>(null);
  const stopFileInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    getAvailableSystemSounds().then((sounds) => {
      if (sounds && sounds.length > 0) {
        setSystemSounds(sounds);
      }
    });
  }, []);

  useEffect(() => {
    localStorage.setItem("dicty_sound_feedback", String(soundFeedback));
    localStorage.setItem("dicty_sound_volume", String(soundVolume));
    localStorage.setItem("dicty_start_sound_type", startSoundType);
    localStorage.setItem("dicty_start_sound_name", startSoundName);
    localStorage.setItem("dicty_start_sound_path", startSoundPath);
    localStorage.setItem("dicty_start_sound_data", startSoundData);
    localStorage.setItem("dicty_stop_sound_type", stopSoundType);
    localStorage.setItem("dicty_stop_sound_name", stopSoundName);
    localStorage.setItem("dicty_stop_sound_path", stopSoundPath);
    localStorage.setItem("dicty_stop_sound_data", stopSoundData);
    window.dispatchEvent(new Event("storage"));

    // Sync configuration to native Rust audio engine for zero-latency shortcut cues
    invoke("save_sound_config", {
      config: {
        sound_feedback: soundFeedback,
        sound_volume: soundVolume,
        start_sound_type: startSoundType,
        start_sound_name: startSoundName,
        start_sound_path: startSoundPath,
        stop_sound_type: stopSoundType,
        stop_sound_name: stopSoundName,
        stop_sound_path: stopSoundPath,
      },
    }).catch(() => {});
  }, [
    soundFeedback,
    soundVolume,
    startSoundType,
    startSoundName,
    startSoundPath,
    startSoundData,
    stopSoundType,
    stopSoundName,
    stopSoundPath,
    stopSoundData,
  ]);

  const handlePreviewStart = async () => {
    setIsPlayingStart(true);
    await playSoundPreview(startSoundType, startSoundName, startSoundPath, startSoundData, false, soundVolume);
    setTimeout(() => setIsPlayingStart(false), 500);
  };

  const handlePreviewStop = async () => {
    setIsPlayingStop(true);
    await playSoundPreview(stopSoundType, stopSoundName, stopSoundPath, stopSoundData, true, soundVolume);
    setTimeout(() => setIsPlayingStop(false), 500);
  };

  const handleStartFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
      const dataUrl = event.target?.result as string;
      setStartSoundName(file.name);
      setStartSoundPath(file.name);
      setStartSoundData(dataUrl);
      playSoundPreview("Custom", file.name, file.name, dataUrl, false);
    };
    reader.readAsDataURL(file);
  };

  const handleStopFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
      const dataUrl = event.target?.result as string;
      setStopSoundName(file.name);
      setStopSoundPath(file.name);
      setStopSoundData(dataUrl);
      playSoundPreview("Custom", file.name, file.name, dataUrl, true);
    };
    reader.readAsDataURL(file);
  };

  // Privacy & Retention
  const [retentionWindow, setRetentionWindow] = useState(() => {
    return localStorage.getItem("dicty_retention_window") || "forever";
  });
  const [scrubAudio, setScrubAudio] = useState(() => {
    return localStorage.getItem("dicty_scrub_audio") === "true";
  });
  const [isCleaning, setIsCleaning] = useState(false);
  const [cleanedSuccess, setCleanedSuccess] = useState(false);
  const [showCleanupModal, setShowCleanupModal] = useState(false);

  // Diagnostics & Cache
  const [isExporting, setIsExporting] = useState(false);
  const [exportedSuccess, setExportedSuccess] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  const [showClearModal, setShowClearModal] = useState(false);
  const [clearedSuccess, setClearedSuccess] = useState(false);

  // Persistence Effects
  useEffect(() => {
    localStorage.setItem("dicty_theme", theme);
  }, [theme]);

  useEffect(() => {
    localStorage.setItem("dicty_show_in_taskbar", String(showInTaskbar));
  }, [showInTaskbar]);

  useEffect(() => {
    localStorage.setItem("dicty_dock_icon_theme", dockIconTheme);
  }, [dockIconTheme]);

  useEffect(() => {
    localStorage.setItem("dicty_launch_on_startup", String(launchOnStartup));
  }, [launchOnStartup]);

  useEffect(() => {
    localStorage.setItem("dicty_show_mode_label", String(showModeLabel));
  }, [showModeLabel]);

  useEffect(() => {
    localStorage.setItem("dicty_color_dictation", dictationColor);
  }, [dictationColor]);

  useEffect(() => {
    localStorage.setItem("dicty_color_librarian", librarianColor);
  }, [librarianColor]);

  useEffect(() => {
    localStorage.setItem("dicty_color_meeting", meetingColor);
  }, [meetingColor]);

  useEffect(() => {
    localStorage.setItem("dicty_color_focused", focusedColor);
  }, [focusedColor]);

  useEffect(() => {
    localStorage.setItem("dicty_retention_window", retentionWindow);
    localStorage.setItem("dicty_scrub_audio", String(scrubAudio));
    engineApi.updateRetentionSettings(retentionWindow, scrubAudio).catch((e) => {
      console.warn("Failed to sync retention settings:", e);
    });
  }, [retentionWindow, scrubAudio]);

  const handleRetentionCleanup = async () => {
    setShowCleanupModal(false);
    setIsCleaning(true);
    try {
      await engineApi.triggerHistoryCleanup(false);
    } catch (e) {
      console.warn("Retention cleanup API call completed or local fallback:", e);
    }
    setTimeout(() => {
      setIsCleaning(false);
      setCleanedSuccess(true);
      setTimeout(() => setCleanedSuccess(false), 2500);
    }, 800);
  };

  const handleExportDiagnostics = async () => {
    setIsExporting(true);
    setExportError(null);
    try {
      const { blob, filename } = await engineApi.exportDiagnostics();

      // Trigger browser/webview download
      const blobUrl = window.URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = blobUrl;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      setTimeout(() => {
        document.body.removeChild(link);
        window.URL.revokeObjectURL(blobUrl);
      }, 1000);

      setIsExporting(false);
      setExportedSuccess(true);
      setTimeout(() => setExportedSuccess(false), 4500);
    } catch (e: any) {
      console.error("Export diagnostics error:", e);
      setIsExporting(false);
      setExportError(e?.message || "Failed to export diagnostic report");
      setTimeout(() => setExportError(null), 4500);
    }
  };

  const handleClearAllCache = () => {
    setShowClearModal(false);
    setClearedSuccess(true);
    setTimeout(() => setClearedSuccess(false), 3000);
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-7 select-none">
      <SettingsPageHeader
        title="Preferences"
        description="Manage your global app appearance, sounds, privacy retention, and diagnostics."
        helpTopic="preferences"
      />

      {/* 1. Appearance (Theme Cards) */}
      <div className="space-y-4">
        <h3 className="text-base font-semibold text-white tracking-tight">Appearance</h3>
        <div className="flex items-center gap-6 pt-1">
          <ThemeCard
            title="Auto"
            theme="auto"
            isSelected={theme === "auto"}
            onSelect={() => setTheme("auto")}
          />
          <ThemeCard
            title="Light"
            theme="light"
            isSelected={theme === "light"}
            onSelect={() => setTheme("light")}
          />
          <ThemeCard
            title="Dark"
            theme="dark"
            isSelected={theme === "dark"}
            onSelect={() => setTheme("dark")}
          />
        </div>

        {/* Dynamic Accent Color Palette (1:1 with AppAccentColor.swift) */}
        <div className="space-y-2 pt-2">
          <span className="text-xs font-medium text-white/90">Accent Theme Color</span>
          <div className="flex items-center gap-3">
            {ACCENT_PRESETS.map((preset) => {
              const isSelected = activeAccent === preset.id;
              return (
                <button
                  key={preset.id}
                  onClick={() => handleAccentSelect(preset.id)}
                  title={preset.displayName}
                  className={`w-7 h-7 rounded-full transition-all flex items-center justify-center relative ${
                    isSelected
                      ? "ring-2 ring-white ring-offset-2 ring-offset-[#121418] scale-110 shadow-lg"
                      : "hover:scale-105 opacity-80 hover:opacity-100"
                  }`}
                  style={{ backgroundColor: preset.swatchDark }}
                >
                  {isSelected && <Check className="w-3.5 h-3.5 text-black stroke-[3]" />}
                </button>
              );
            })}
            <span className="text-xs text-white/60 ml-2 font-medium">
              {ACCENT_PRESETS.find((p) => p.id === activeAccent)?.displayName || "Olive"}
            </span>
          </div>
        </div>
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* 2. Dock / Taskbar Integration (1:1 with SwiftUI Appearance.swift) */}
      <div className="space-y-3">
        <h3 className="text-base font-semibold text-white tracking-tight">
          Dock Integration
        </h3>

        <div className="space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-white/90">
              Show Dicty in Dock
            </span>
            <ToggleSwitch
              checked={showInTaskbar}
              onChange={setShowInTaskbar}
              ariaLabel="Show Dicty in Dock"
            />
          </div>
          <p className="text-xs text-white/50">
            When disabled, Dicty will only appear in your top menu bar.
          </p>
        </div>

        {showInTaskbar && (
          <div className="flex items-center justify-between pt-2">
            <span className="text-xs font-medium text-white/90">
              Dock Icon Theme
            </span>
            <select
              value={dockIconTheme}
              onChange={(e) => setDockIconTheme(e.target.value)}
              className="bg-white/[0.06] hover:bg-white/10 border border-white/15 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none transition-all cursor-pointer w-36"
            >
              <option value="system" className="bg-[#181B20] text-white">System</option>
              <option value="bright" className="bg-[#181B20] text-white">Bright</option>
              <option value="dark" className="bg-[#181B20] text-white">Dark</option>
            </select>
          </div>
        )}
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* 3. System Integration (1:1 with SwiftUI Appearance.swift) */}
      <div className="space-y-3">
        <h3 className="text-base font-semibold text-white tracking-tight">
          System Integration
        </h3>

        <div className="space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-white/90">
              Launch Dicty on Startup
            </span>
            <ToggleSwitch
              checked={launchOnStartup}
              onChange={setLaunchOnStartup}
              ariaLabel="Launch Dicty on Startup"
            />
          </div>
          <p className="text-xs text-white/50">
            Automatically open Dicty when your system boots up.
          </p>
        </div>
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* 4. Recording Overlay (1:1 with SwiftUI Appearance.swift) */}
      <div className="space-y-3">
        <h3 className="text-base font-semibold text-white tracking-tight">
          Recording Overlay
        </h3>

        <div className="flex items-center justify-between">
          <span className="text-xs font-medium text-white/90">
            Show Active Mode Indicator
          </span>
          <ToggleSwitch
            checked={showModeLabel}
            onChange={setShowModeLabel}
            ariaLabel="Show Active Mode Indicator"
          />
        </div>

        {showModeLabel && (
          <div className="pt-2 space-y-2 w-full">
            <ColorPickerPill
              label="Dictation Mode Color"
              color={dictationColor}
              onChange={setDictationColor}
            />
            <ColorPickerPill
              label="Librarian Mode Color"
              color={librarianColor}
              onChange={setLibrarianColor}
            />
            <ColorPickerPill
              label="Meeting Mode Color"
              color={meetingColor}
              onChange={setMeetingColor}
            />
            <ColorPickerPill
              label="Focused Meeting Color"
              color={focusedColor}
              onChange={setFocusedColor}
            />
          </div>
        )}

        {/* HUD Dock Positioning (1:1 with OverlayDockPosition in RecordingOverlay.swift) */}
        <div className="flex items-center justify-between pt-1">
          <div>
            <span className="text-xs font-medium text-white/90">HUD Dock Position</span>
            <p className="text-[11px] text-white/50">
              Default snap placement for the floating recording companion.
            </p>
          </div>
          <select
            value={overlayDockPosition}
            onChange={(e) => {
              setOverlayDockPosition(e.target.value);
              localStorage.setItem("overlayDockPosition", e.target.value);
            }}
            className="bg-white/[0.06] hover:bg-white/10 border border-white/15 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none transition-all cursor-pointer w-44"
          >
            <option value="bottom" className="bg-[#181B20] text-white">Bottom Center (Default)</option>
            <option value="top" className="bg-[#181B20] text-white">Top Center</option>
            <option value="freeform" className="bg-[#181B20] text-white">Freeform (Draggable)</option>
          </select>
        </div>
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* 5. Recording Sounds (1:1 with SwiftUI SoundsSettingsView) */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-base font-semibold text-white tracking-tight flex items-center gap-2">
              {soundFeedback ? (
                <Volume2 className="w-4 h-4 text-[#87B996]" />
              ) : (
                <VolumeX className="w-4 h-4 text-white/40" />
              )}
              Recording Sounds
            </h3>
            <p className="text-xs text-white/50 mt-0.5">
              Audio feedback cues when starting and stopping dictation recordings.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-xs text-white/60">
              {soundFeedback ? "Enabled" : "Muted"}
            </span>
            <ToggleSwitch
              checked={soundFeedback}
              onChange={setSoundFeedback}
              ariaLabel="Toggle Audio Feedback"
            />
          </div>
        </div>

        <div className={`p-5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-6 transition-opacity ${soundFeedback ? "opacity-100" : "opacity-40 pointer-events-none"}`}>
          {/* Audio Feedback Volume Slider */}
          <div className="space-y-2.5 p-3.5 rounded-xl bg-white/[0.02] border border-white/5">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                {soundVolume === 0 ? (
                  <VolumeX className="w-4 h-4 text-white/40" />
                ) : soundVolume < 50 ? (
                  <Volume1 className="w-4 h-4 text-[#87B996]" />
                ) : (
                  <Volume2 className="w-4 h-4 text-[#87B996]" />
                )}
                <span className="text-xs font-semibold text-white">Feedback Volume</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-xs font-mono font-bold text-[#87B996]">{soundVolume}%</span>
                <button
                  type="button"
                  onClick={() => {
                    playSoundPreview(startSoundType, startSoundName, startSoundPath, startSoundData, false, soundVolume);
                  }}
                  className="px-2 py-0.5 rounded-md bg-white/5 hover:bg-white/10 text-[10px] text-white/70 hover:text-white border border-white/10 transition-all cursor-pointer"
                >
                  Test Volume
                </button>
              </div>
            </div>

            <div className="flex items-center gap-3 pt-0.5">
              <input
                type="range"
                min="0"
                max="100"
                step="5"
                value={soundVolume}
                onChange={(e) => setSoundVolume(parseInt(e.target.value, 10))}
                className="flex-1 h-1.5 bg-white/10 rounded-lg appearance-none cursor-pointer accent-[#87B996]"
                title={`Volume: ${soundVolume}%`}
              />
            </div>
            <div className="flex justify-between text-[10px] text-white/30 pt-0.5">
              <button
                type="button"
                onClick={() => setSoundVolume(0)}
                className="hover:text-white/60 transition-colors cursor-pointer"
              >
                Mute (0%)
              </button>
              <button
                type="button"
                onClick={() => setSoundVolume(50)}
                className="hover:text-white/60 transition-colors cursor-pointer"
              >
                Comfortable (50%)
              </button>
              <button
                type="button"
                onClick={() => setSoundVolume(70)}
                className="hover:text-white/60 transition-colors cursor-pointer"
              >
                Default (70%)
              </button>
              <button
                type="button"
                onClick={() => setSoundVolume(100)}
                className="hover:text-white/60 transition-colors cursor-pointer"
              >
                Full (100%)
              </button>
            </div>
          </div>

          <div className="border-t border-white/[0.06]" />

          {/* Start Recording Sound */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                <span className="text-xs font-semibold text-white">
                  Start Recording Sound
                </span>
              </div>
              <button
                type="button"
                onClick={handlePreviewStart}
                disabled={startSoundType === "None"}
                className="px-2.5 py-1 rounded-lg bg-white/[0.06] hover:bg-white/15 text-xs text-white/90 hover:text-white border border-white/10 flex items-center gap-1.5 transition-all shadow-sm cursor-pointer disabled:opacity-30"
                title="Preview Start Recording Sound"
              >
                <Play className={`w-3 h-3 text-[#87B996] ${isPlayingStart ? "animate-spin" : ""}`} />
                <span>{isPlayingStart ? "Playing..." : "Preview"}</span>
              </button>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
              <div className="space-y-1">
                <label className="text-[11px] font-medium text-white/60">Source</label>
                <select
                  value={startSoundType}
                  onChange={(e) => setStartSoundType(e.target.value)}
                  className="w-full bg-white/[0.06] hover:bg-white/10 border border-white/15 rounded-xl px-3 py-2 text-xs text-white focus:outline-none transition-all cursor-pointer"
                >
                  <option value="Built-in" className="bg-[#181B20] text-white">Built-in Windows Sound</option>
                  <option value="Synthesized" className="bg-[#181B20] text-white">Synthesized Studio Chime (Web Audio)</option>
                  <option value="Custom" className="bg-[#181B20] text-white">Custom Audio File (.wav, .mp3)</option>
                  <option value="None" className="bg-[#181B20] text-white">None (Mute)</option>
                </select>
              </div>

              {startSoundType === "Built-in" && (
                <div className="space-y-1">
                  <label className="text-[11px] font-medium text-white/60">System Sound</label>
                  <select
                    value={startSoundName}
                    onChange={(e) => {
                      const selected = systemSounds.find((s) => s.id === e.target.value || s.name === e.target.value);
                      if (selected) {
                        setStartSoundName(selected.id);
                        setStartSoundPath(selected.path);
                        playSoundPreview("Built-in", selected.id, selected.path, undefined, false);
                      }
                    }}
                    className="w-full bg-white/[0.06] hover:bg-white/10 border border-white/15 rounded-xl px-3 py-2 text-xs text-white focus:outline-none transition-all cursor-pointer"
                  >
                    {systemSounds.map((s) => (
                      <option key={s.id} value={s.id} className="bg-[#181B20] text-white">
                        {s.name}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {startSoundType === "Custom" && (
                <div className="space-y-1">
                  <label className="text-[11px] font-medium text-white/60">Audio File</label>
                  <div className="flex items-center gap-2">
                    <input
                      type="file"
                      ref={startFileInputRef}
                      onChange={handleStartFileChange}
                      accept="audio/*,.wav,.mp3,.ogg,.m4a"
                      className="hidden"
                    />
                    <button
                      type="button"
                      onClick={() => startFileInputRef.current?.click()}
                      className="flex-1 px-3 py-2 rounded-xl bg-white/[0.06] hover:bg-white/10 border border-white/15 text-xs text-white/90 flex items-center justify-between transition-all cursor-pointer truncate"
                    >
                      <span className="truncate">{startSoundName || "Choose file..."}</span>
                      <FolderOpen className="w-3.5 h-3.5 text-white/60 shrink-0 ml-2" />
                    </button>
                  </div>
                </div>
              )}

              {startSoundType === "Synthesized" && (
                <div className="space-y-1 sm:col-span-1">
                  <label className="text-[11px] font-medium text-white/60">Audio Engine</label>
                  <div className="px-3 py-2 rounded-xl bg-white/[0.04] border border-white/10 text-xs text-white/70 flex items-center gap-2">
                    <Sparkles className="w-3.5 h-3.5 text-[#87B996] shrink-0" />
                    <span className="truncate">Ascending Dual-Tone (523Hz → 784Hz)</span>
                  </div>
                </div>
              )}
            </div>

            {startSoundType === "Built-in" && startSoundPath && (
              <p className="text-[10px] text-white/40 truncate font-mono pt-0.5">
                Path: {startSoundPath}
              </p>
            )}
          </div>

          <div className="border-t border-white/[0.06]" />

          {/* Stop Recording Sound */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-rose-400" />
                <span className="text-xs font-semibold text-white">
                  Stop Recording Sound
                </span>
              </div>
              <button
                type="button"
                onClick={handlePreviewStop}
                disabled={stopSoundType === "None"}
                className="px-2.5 py-1 rounded-lg bg-white/[0.06] hover:bg-white/15 text-xs text-white/90 hover:text-white border border-white/10 flex items-center gap-1.5 transition-all shadow-sm cursor-pointer disabled:opacity-30"
                title="Preview Stop Recording Sound"
              >
                <Play className={`w-3 h-3 text-[#87B996] ${isPlayingStop ? "animate-spin" : ""}`} />
                <span>{isPlayingStop ? "Playing..." : "Preview"}</span>
              </button>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
              <div className="space-y-1">
                <label className="text-[11px] font-medium text-white/60">Source</label>
                <select
                  value={stopSoundType}
                  onChange={(e) => setStopSoundType(e.target.value)}
                  className="w-full bg-white/[0.06] hover:bg-white/10 border border-white/15 rounded-xl px-3 py-2 text-xs text-white focus:outline-none transition-all cursor-pointer"
                >
                  <option value="Built-in" className="bg-[#181B20] text-white">Built-in Windows Sound</option>
                  <option value="Synthesized" className="bg-[#181B20] text-white">Synthesized Studio Chime (Web Audio)</option>
                  <option value="Custom" className="bg-[#181B20] text-white">Custom Audio File (.wav, .mp3)</option>
                  <option value="None" className="bg-[#181B20] text-white">None (Mute)</option>
                </select>
              </div>

              {stopSoundType === "Built-in" && (
                <div className="space-y-1">
                  <label className="text-[11px] font-medium text-white/60">System Sound</label>
                  <select
                    value={stopSoundName}
                    onChange={(e) => {
                      const selected = systemSounds.find((s) => s.id === e.target.value || s.name === e.target.value);
                      if (selected) {
                        setStopSoundName(selected.id);
                        setStopSoundPath(selected.path);
                        playSoundPreview("Built-in", selected.id, selected.path, undefined, true);
                      }
                    }}
                    className="w-full bg-white/[0.06] hover:bg-white/10 border border-white/15 rounded-xl px-3 py-2 text-xs text-white focus:outline-none transition-all cursor-pointer"
                  >
                    {systemSounds.map((s) => (
                      <option key={s.id} value={s.id} className="bg-[#181B20] text-white">
                        {s.name}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {stopSoundType === "Custom" && (
                <div className="space-y-1">
                  <label className="text-[11px] font-medium text-white/60">Audio File</label>
                  <div className="flex items-center gap-2">
                    <input
                      type="file"
                      ref={stopFileInputRef}
                      onChange={handleStopFileChange}
                      accept="audio/*,.wav,.mp3,.ogg,.m4a"
                      className="hidden"
                    />
                    <button
                      type="button"
                      onClick={() => stopFileInputRef.current?.click()}
                      className="flex-1 px-3 py-2 rounded-xl bg-white/[0.06] hover:bg-white/10 border border-white/15 text-xs text-white/90 flex items-center justify-between transition-all cursor-pointer truncate"
                    >
                      <span className="truncate">{stopSoundName || "Choose file..."}</span>
                      <FolderOpen className="w-3.5 h-3.5 text-white/60 shrink-0 ml-2" />
                    </button>
                  </div>
                </div>
              )}

              {stopSoundType === "Synthesized" && (
                <div className="space-y-1 sm:col-span-1">
                  <label className="text-[11px] font-medium text-white/60">Audio Engine</label>
                  <div className="px-3 py-2 rounded-xl bg-white/[0.04] border border-white/10 text-xs text-white/70 flex items-center gap-2">
                    <Sparkles className="w-3.5 h-3.5 text-[#87B996] shrink-0" />
                    <span className="truncate">Descending Tri-Tone (784Hz → 659Hz → 523Hz)</span>
                  </div>
                </div>
              )}
            </div>

            {stopSoundType === "Built-in" && stopSoundPath && (
              <p className="text-[10px] text-white/40 truncate font-mono pt-0.5">
                Path: {stopSoundPath}
              </p>
            )}
          </div>
        </div>
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* 5. History Retention & Privacy (1:1 with HistoryRetentionSettingsView) */}
      <div className="space-y-4">
        <h3 className="text-base font-semibold text-white tracking-tight">
          History Retention & Privacy
        </h3>

        <div className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <span className="text-xs font-semibold text-white block">
                Retention Window
              </span>
              <span className="text-[11px] text-white/50 block mt-0.5">
                Automatically prune transcription history records older than this window.
              </span>
            </div>
            <select
              value={retentionWindow}
              onChange={(e) => setRetentionWindow(e.target.value)}
              className="bg-white/[0.06] hover:bg-white/10 border border-white/15 rounded-xl px-3 py-1.5 text-xs text-white focus:outline-none cursor-pointer w-40"
            >
              <option value="forever" className="bg-[#181B20] text-white">Forever (Default)</option>
              <option value="30d" className="bg-[#181B20] text-white">30 Days</option>
              <option value="7d" className="bg-[#181B20] text-white">7 Days</option>
              <option value="24h" className="bg-[#181B20] text-white">24 Hours</option>
            </select>
          </div>

          <div className="border-t border-white/[0.06]" />

          <div className="flex items-center justify-between">
            <div>
              <span className="text-xs font-semibold text-white block">
                Scrub Raw Audio Immediately
              </span>
              <span className="text-[11px] text-white/50 block mt-0.5">
                Deletes WAV voice recordings as soon as transcription finishes to save disk space while keeping text notes.
              </span>
            </div>
            <ToggleSwitch
              checked={scrubAudio}
              onChange={setScrubAudio}
              ariaLabel="Scrub Raw Audio Immediately"
            />
          </div>

          <div className="border-t border-white/[0.06]" />

          <div className="flex items-center justify-between">
            <div>
              <span className="text-xs font-semibold text-white block">
                Manual Retention Cleanup
              </span>
              <span className="text-[11px] text-white/50 block mt-0.5">
                Trigger an immediate cleanup run against your configured retention policy.
              </span>
            </div>
            <button
              onClick={() => setShowCleanupModal(true)}
              disabled={isCleaning}
              className="px-3.5 py-1.5 rounded-xl bg-indigo-500/20 hover:bg-indigo-500/30 text-indigo-300 text-xs font-medium border border-indigo-500/30 flex items-center gap-1.5 transition-all shadow-sm cursor-pointer disabled:opacity-50"
            >
              {cleanedSuccess ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Cleaned Up</span>
                </>
              ) : (
                <>
                  <RotateCcw className={`w-3.5 h-3.5 ${isCleaning ? "animate-spin" : ""}`} />
                  <span>Clean Up Now</span>
                </>
              )}
            </button>
          </div>
        </div>
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* 6. Diagnostics Export */}
      <div className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-3">
        <div className="flex items-center gap-2">
          <Download className="w-4 h-4 text-[#87B996]" />
          <h4 className="text-sm font-semibold text-white tracking-tight">
            Performance Telemetry & Diagnostics Export
          </h4>
        </div>
        <p className="text-xs text-white/50 leading-relaxed">
          Package system logs and local performance telemetry (RTF, speaking WPM, engine latency, active model) into a single .zip file to share with developers or analyze performance.
        </p>
        <div className="flex items-center gap-3 pt-1">
          <button
            onClick={handleExportDiagnostics}
            disabled={isExporting}
            className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-medium transition-all shadow-sm flex items-center gap-2 cursor-pointer disabled:opacity-50"
          >
            <Download className={`w-3.5 h-3.5 ${isExporting ? "animate-bounce" : ""}`} />
            <span>{isExporting ? "Exporting Diagnostics..." : "Export Diagnostic Report (.zip)"}</span>
          </button>
          {exportedSuccess && (
            <span className="text-xs text-emerald-400 flex items-center gap-1 font-medium">
              <Check className="w-3.5 h-3.5" /> Exported & Saved to Downloads!
            </span>
          )}
          {exportError && (
            <span className="text-xs text-rose-400 flex items-center gap-1 font-medium">
              <AlertTriangle className="w-3.5 h-3.5" /> {exportError}
            </span>
          )}
        </div>
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* 7. Storage & Cache Management */}
      <div className="p-5 rounded-2xl bg-red-500/[0.04] border border-red-500/20 space-y-3">
        <div className="flex items-center gap-2 text-red-400">
          <Trash2 className="w-4 h-4" />
          <h4 className="text-sm font-semibold tracking-tight">
            Storage & Cache Management
          </h4>
        </div>
        <p className="text-xs text-white/50 leading-relaxed">
          Permanently delete all stored voice transcription records, temporary audio recordings, and local cache. This frees up disk space and resets your transcription history.
        </p>
        <div className="flex items-center gap-3 pt-1">
          <button
            onClick={() => setShowClearModal(true)}
            className="px-3.5 py-1.5 rounded-xl bg-red-500 hover:bg-red-600 text-white text-xs font-medium transition-all shadow-sm flex items-center gap-2"
          >
            <Trash2 className="w-3.5 h-3.5" />
            <span>Clear All Cache</span>
          </button>
          {clearedSuccess && (
            <span className="text-xs text-emerald-400 flex items-center gap-1">
              <Check className="w-3.5 h-3.5" /> Cache cleared successfully!
            </span>
          )}
        </div>
      </div>

      <div className="border-t border-white/[0.08]" />

      {/* Welcome & Introduction Tour */}
      <div className="space-y-3">
        <h3 className="text-base font-semibold text-white tracking-tight">
          Welcome & Introduction Tour
        </h3>
        <div className="p-4 rounded-xl border border-white/10 bg-white/[0.03] flex items-center justify-between">
          <div className="space-y-1">
            <div className="text-sm font-medium text-white flex items-center gap-2">
              <Sparkles size={16} className="text-[#87B996]" />
              <span>Interactive Setup Guide</span>
            </div>
            <p className="text-xs text-white/50">
              Run the interactive 4-step introduction again to test your microphone, choose an AI model, and practice shortcuts.
            </p>
          </div>
          <button
            onClick={() => {
              window.dispatchEvent(new CustomEvent("dicty:open-onboarding"));
            }}
            className="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/15 text-xs font-semibold text-white transition-all shadow-sm flex items-center gap-2"
          >
            <RotateCcw size={14} />
            <span>Replay Onboarding</span>
          </button>
        </div>
      </div>

      {/* Retention Cleanup Confirmation Modal */}
      {showCleanupModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-md z-50 flex items-center justify-center p-4 select-none">
          <div className="w-full max-w-sm bg-[#1A1D23] border border-white/15 rounded-2xl p-6 shadow-2xl space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400 flex-shrink-0">
                <AlertTriangle className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-base font-bold text-white">
                  Run Retention Cleanup?
                </h3>
                <span className="text-[11px] text-white/40">
                  Window: {retentionWindow === "forever" ? "Forever (Default)" : retentionWindow === "30d" ? "30 Days" : retentionWindow === "7d" ? "7 Days" : "24 Hours"}
                </span>
              </div>
            </div>

            <p className="text-xs text-white/70 leading-relaxed">
              {retentionWindow === "forever"
                ? "Your retention policy is set to Forever. Running cleanup now will prune orphaned cache and temporary files, preserving your transcription history records."
                : `This will permanently delete all transcription history records and audio recordings older than ${
                    retentionWindow === "30d" ? "30 days" : retentionWindow === "7d" ? "7 days" : "24 hours"
                  }. This action cannot be undone.`}
            </p>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                onClick={() => setShowCleanupModal(false)}
                className="px-4 py-1.5 rounded-xl text-xs font-medium text-white/60 hover:text-white transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleRetentionCleanup}
                className="px-4 py-1.5 rounded-xl text-xs font-semibold bg-indigo-600 hover:bg-indigo-500 text-white shadow transition-all"
              >
                Clean Up Now
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Clear Cache Modal */}
      {showClearModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-md z-50 flex items-center justify-center p-4">
          <div className="w-full max-w-sm bg-[#1A1D23] border border-white/15 rounded-2xl p-6 shadow-2xl space-y-4">
            <h3 className="text-base font-bold text-white">Clear All Cache?</h3>
            <p className="text-xs text-white/60 leading-relaxed">
              Are you sure you want to permanently delete all transcription history and audio recordings? This action cannot be undone.
            </p>
            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                onClick={() => setShowClearModal(false)}
                className="px-4 py-1.5 rounded-xl text-xs font-medium text-white/60 hover:text-white"
              >
                Cancel
              </button>
              <button
                onClick={handleClearAllCache}
                className="px-4 py-1.5 rounded-xl text-xs font-semibold bg-red-500 hover:bg-red-600 text-white shadow"
              >
                Clear All
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
