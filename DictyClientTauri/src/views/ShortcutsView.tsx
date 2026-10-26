import React, { useState, useEffect, useCallback, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { emit } from "@tauri-apps/api/event";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { ToggleSwitch } from "../components/ToggleSwitch";
import { AlertCircle, RotateCcw, Keyboard } from "lucide-react";

interface ShortcutCardProps {
  title: string;
  description: string;
  shortcutDisplay: string;
  isRecording: boolean;
  liveCombo?: string;
  requireDoubleTap: boolean;
  onRecord: () => void;
  onCancelRecord?: () => void;
  onDoubleTapToggle: (val: boolean) => void;
}

const ShortcutCard: React.FC<ShortcutCardProps> = ({
  title,
  description,
  shortcutDisplay,
  isRecording,
  liveCombo,
  requireDoubleTap,
  onRecord,
  onCancelRecord,
  onDoubleTapToggle,
}) => {
  return (
    <div
      className={`p-5 rounded-2xl border transition-all space-y-3 ${
        isRecording
          ? "bg-white/[0.06] border-amber-500/40 ring-1 ring-amber-500/30"
          : "bg-white/[0.03] border-white/10 hover:border-white/15"
      }`}
    >
      <div className="flex items-center justify-between">
        <div>
          <h4 className="text-sm font-bold text-white tracking-tight">{title}</h4>
          <p className="text-xs text-white/50">{description}</p>
        </div>

        <div className="flex items-center gap-2">
          {isRecording && (
            <button
              onClick={onCancelRecord}
              className="px-2.5 py-1.5 rounded-lg text-xs font-medium text-white/50 hover:text-white hover:bg-white/10 transition-colors"
            >
              Cancel (Esc)
            </button>
          )}
          <button
            onClick={onRecord}
            className={`px-3.5 py-1.5 rounded-xl border text-xs font-mono font-bold tracking-wide transition-all shadow-sm ${
              isRecording
                ? "bg-amber-500/20 text-amber-300 border-amber-500/40 animate-pulse"
                : "bg-white/[0.06] hover:bg-white/10 text-white border-white/15"
            }`}
          >
            {isRecording ? (liveCombo || "Press keys...") : shortcutDisplay}
          </button>
        </div>
      </div>

      <div className="pt-3 border-t border-white/[0.06] flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-white/80">Require Double-Tap to Trigger</span>
            {requireDoubleTap && (
              <span className="px-1.5 py-0.5 rounded bg-[#87B996]/15 text-[#87B996] border border-[#87B996]/30 text-[9px] font-bold tracking-wider">
                ACTIVE
              </span>
            )}
          </div>
          <p className="text-[11px] text-white/40 mt-0.5">Press twice quickly to trigger.</p>
        </div>
        <ToggleSwitch
          checked={requireDoubleTap}
          onChange={onDoubleTapToggle}
          ariaLabel={`Require Double-Tap for ${title}`}
        />
      </div>
    </div>
  );
};

export const ShortcutsView: React.FC = () => {
  const [toggleKey, setToggleKey] = useState(() => localStorage.getItem("dicty_shortcut_toggle") || "Ctrl + Space");
  const [pauseKey, setPauseKey] = useState(() => localStorage.getItem("dicty_shortcut_pause") || "Ctrl + Shift + P");
  const [modeKey, setModeKey] = useState(() => localStorage.getItem("dicty_shortcut_mode") || "Alt + Shift + M");

  const [recordingTarget, setRecordingTarget] = useState<string | null>(null);
  const [liveCombo, setLiveCombo] = useState<string>("");
  const [recordingError, setRecordingError] = useState<string | null>(null);

  const [doubleTapToggle, setDoubleTapToggle] = useState(() => localStorage.getItem("dicty_double_tap_toggle") === "true");
  const [doubleTapPause, setDoubleTapPause] = useState(() => localStorage.getItem("dicty_double_tap_pause") === "true");
  const [doubleTapMode, setDoubleTapMode] = useState(() => localStorage.getItem("dicty_double_tap_mode") === "true");

  const [activationStyle, setActivationStyle] = useState<"toggle" | "hold">(() => 
    (localStorage.getItem("dicty_activation_style") as "toggle" | "hold") || "toggle"
  );
  const [autoPaste, setAutoPaste] = useState(() => localStorage.getItem("dicty_auto_paste") !== "false");
  const [soundFeedback, setSoundFeedback] = useState(() => localStorage.getItem("dicty_sound_feedback") !== "false");

  const toggleKeyRef = useRef(toggleKey);
  const pauseKeyRef = useRef(pauseKey);
  const modeKeyRef = useRef(modeKey);
  toggleKeyRef.current = toggleKey;
  pauseKeyRef.current = pauseKey;
  modeKeyRef.current = modeKey;

  const doubleTapToggleRef = useRef(doubleTapToggle);
  const doubleTapPauseRef = useRef(doubleTapPause);
  const doubleTapModeRef = useRef(doubleTapMode);
  doubleTapToggleRef.current = doubleTapToggle;
  doubleTapPauseRef.current = doubleTapPause;
  doubleTapModeRef.current = doubleTapMode;

  const recordingCompletedRef = useRef(false);

  const syncHotkeysToTauri = useCallback((
    toggle: string,
    pause: string,
    mode: string,
    dtToggle?: boolean,
    dtPause?: boolean,
    dtMode?: boolean
  ) => {
    invoke("register_custom_hotkeys", {
      toggleKey: toggle,
      pauseKey: pause,
      modeKey: mode,
      doubleTapToggle: dtToggle ?? doubleTapToggleRef.current,
      doubleTapPause: dtPause ?? doubleTapPauseRef.current,
      doubleTapMode: dtMode ?? doubleTapModeRef.current,
    }).catch((err) => {
      console.warn("Tauri register_custom_hotkeys notice:", err);
    });
  }, []);

  // Sync on initial load and when keys change
  useEffect(() => {
    localStorage.setItem("dicty_shortcut_toggle", toggleKey);
    localStorage.setItem("dicty_shortcut_pause", pauseKey);
    localStorage.setItem("dicty_shortcut_mode", modeKey);
    emit("dicty:shortcuts-changed", { toggleKey, pauseKey, modeKey }).catch(() => {});
    syncHotkeysToTauri(toggleKey, pauseKey, modeKey, doubleTapToggle, doubleTapPause, doubleTapMode);
  }, [toggleKey, pauseKey, modeKey]);

  useEffect(() => {
    localStorage.setItem("dicty_double_tap_toggle", String(doubleTapToggle));
    syncHotkeysToTauri(toggleKey, pauseKey, modeKey, doubleTapToggle, doubleTapPause, doubleTapMode);
  }, [doubleTapToggle]);

  useEffect(() => {
    localStorage.setItem("dicty_double_tap_pause", String(doubleTapPause));
    syncHotkeysToTauri(toggleKey, pauseKey, modeKey, doubleTapToggle, doubleTapPause, doubleTapMode);
  }, [doubleTapPause]);

  useEffect(() => {
    localStorage.setItem("dicty_double_tap_mode", String(doubleTapMode));
    syncHotkeysToTauri(toggleKey, pauseKey, modeKey, doubleTapToggle, doubleTapPause, doubleTapMode);
  }, [doubleTapMode]);

  useEffect(() => {
    localStorage.setItem("dicty_activation_style", activationStyle);
  }, [activationStyle]);

  useEffect(() => {
    localStorage.setItem("dicty_auto_paste", String(autoPaste));
  }, [autoPaste]);

  useEffect(() => {
    localStorage.setItem("dicty_sound_feedback", String(soundFeedback));
  }, [soundFeedback]);

  // Handle keyboard event listening for shortcut combination recording
  const recordingTargetRef = useRef(recordingTarget);
  recordingTargetRef.current = recordingTarget;

  const cancelRecording = useCallback(() => {
    setRecordingTarget(null);
    setLiveCombo("");
    setRecordingError(null);
    invoke("resume_global_shortcuts", {
      toggleKey,
      pauseKey,
      modeKey,
      doubleTapToggle,
      doubleTapPause,
      doubleTapMode,
    }).catch(() => {});
  }, [toggleKey, pauseKey, modeKey, doubleTapToggle, doubleTapPause, doubleTapMode]);

  const handleResetDefaults = () => {
    const defaultToggle = "Ctrl + Space";
    const defaultPause = "Ctrl + Shift + P";
    const defaultMode = "Alt + Shift + M";
    setToggleKey(defaultToggle);
    setPauseKey(defaultPause);
    setModeKey(defaultMode);
    setDoubleTapToggle(false);
    setDoubleTapPause(false);
    setDoubleTapMode(false);
    invoke("resume_global_shortcuts", {
      toggleKey: defaultToggle,
      pauseKey: defaultPause,
      modeKey: defaultMode,
      doubleTapToggle: false,
      doubleTapPause: false,
      doubleTapMode: false,
    }).catch(() => {});
    cancelRecording();
  };

  useEffect(() => {
    if (!recordingTarget) return;

    const onKeyDown = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();

      // Cancel on Escape
      if (e.key === "Escape") {
        cancelRecording();
        return;
      }

      const isModifierKey = ["Control", "Alt", "Shift", "Meta"].includes(e.key);

      // Collect active modifier keys
      const mods: string[] = [];
      if (e.ctrlKey) mods.push("Ctrl");
      if (e.altKey) mods.push("Alt");
      if (e.shiftKey) mods.push("Shift");
      if (e.metaKey) mods.push("Win");

      if (isModifierKey) {
        // User is currently holding down modifier keys; show live preview and wait for key completion
        setLiveCombo(mods.join(" + ") + " + ...");
        setRecordingError(null);
        return;
      }

      // Non-modifier key was pressed: finalize the shortcut (single button, double combo, or triple combo)
      let primaryKey = "";
      if (e.code === "Space" || e.key === " ") {
        primaryKey = "Space";
      } else if (/^F[0-9]{1,2}$/i.test(e.code) || /^F[0-9]{1,2}$/i.test(e.key)) {
        primaryKey = (e.code || e.key).toUpperCase();
      } else if (e.code.startsWith("Key")) {
        primaryKey = e.code.replace("Key", "");
      } else if (e.code.startsWith("Digit")) {
        primaryKey = e.code.replace("Digit", "");
      } else if (e.code.startsWith("Numpad")) {
        primaryKey = e.code;
      } else if ([
        "Backspace", "Tab", "Enter", "Delete", "Insert",
        "Home", "End", "PageUp", "PageDown", "Pause",
        "ScrollLock", "NumLock", "CapsLock", "PrintScreen"
      ].includes(e.key) || [
        "Backspace", "Tab", "Enter", "Delete", "Insert",
        "Home", "End", "PageUp", "PageDown", "Pause",
        "ScrollLock", "NumLock", "CapsLock", "PrintScreen"
      ].includes(e.code)) {
        primaryKey = e.code || e.key;
      } else if (e.code === "Backquote") {
        primaryKey = "`";
      } else if (e.code === "Minus") {
        primaryKey = "-";
      } else if (e.code === "Equal") {
        primaryKey = "=";
      } else if (e.code === "BracketLeft") {
        primaryKey = "[";
      } else if (e.code === "BracketRight") {
        primaryKey = "]";
      } else if (e.code === "Backslash") {
        primaryKey = "\\";
      } else if (e.code === "Semicolon") {
        primaryKey = ";";
      } else if (e.code === "Quote") {
        primaryKey = "'";
      } else if (e.code === "Comma") {
        primaryKey = ",";
      } else if (e.code === "Period") {
        primaryKey = ".";
      } else if (e.code === "Slash") {
        primaryKey = "/";
      } else if (e.key.length === 1) {
        primaryKey = e.key.toUpperCase();
      } else {
        primaryKey = e.key || e.code;
      }

      // Maximum flexibility: Any combination allowed:
      // Single button (e.g. F8, Pause, Space, Insert, M)
      // Double combo (e.g. Ctrl + Space, Alt + Space, Ctrl + M)
      // Triple combo (e.g. Ctrl + Shift + M, Alt + Shift + Space)
      const combo = [...mods, primaryKey].join(" + ");
      const currentTarget = recordingTargetRef.current;

      let newToggle = toggleKey;
      let newPause = pauseKey;
      let newMode = modeKey;

      if (currentTarget === "toggle") {
        newToggle = combo;
        setToggleKey(combo);
      } else if (currentTarget === "pause") {
        newPause = combo;
        setPauseKey(combo);
      } else if (currentTarget === "mode") {
        newMode = combo;
        setModeKey(combo);
      }

      recordingCompletedRef.current = true;
      invoke("resume_global_shortcuts", {
        toggleKey: newToggle,
        pauseKey: newPause,
        modeKey: newMode,
        doubleTapToggle,
        doubleTapPause,
        doubleTapMode,
      }).catch(() => {});
      setRecordingTarget(null);
      setLiveCombo("");
      setRecordingError(null);
    };

    const onKeyUp = (e: KeyboardEvent) => {
      // If user releases modifiers without pressing a terminal key, update preview
      const mods: string[] = [];
      if (e.ctrlKey) mods.push("Ctrl");
      if (e.altKey) mods.push("Alt");
      if (e.shiftKey) mods.push("Shift");
      if (e.metaKey) mods.push("Win");
      setLiveCombo(mods.length > 0 ? mods.join(" + ") + " + ..." : "Press any key or combination...");
    };

    const onBlur = () => {
      cancelRecording();
    };

    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", onBlur);

    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", onBlur);
      if (!recordingCompletedRef.current) {
        invoke("resume_global_shortcuts", {
          toggleKey: toggleKeyRef.current,
          pauseKey: pauseKeyRef.current,
          modeKey: modeKeyRef.current,
          doubleTapToggle: doubleTapToggleRef.current,
          doubleTapPause: doubleTapPauseRef.current,
          doubleTapMode: doubleTapModeRef.current,
        }).catch(() => {});
      }
    };
  }, [recordingTarget, toggleKey, pauseKey, modeKey, cancelRecording, syncHotkeysToTauri]);

  const startRecording = (target: string) => {
    recordingCompletedRef.current = false;
    setRecordingTarget(target);
    setLiveCombo("Press any key or combination...");
    setRecordingError(null);
    invoke("pause_global_shortcuts").catch(() => {});
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-6 select-none">
      <div className="flex items-start justify-between">
        <SettingsPageHeader
          title="Keyboard Shortcuts"
          description="Configure global hotkeys to start dictation, switch modes, and control playback from any Windows application."
          helpTopic="shortcuts"
        />
        <button
          onClick={handleResetDefaults}
          className="mt-2 flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-white/[0.04] hover:bg-white/[0.08] text-white/60 hover:text-white text-xs font-medium border border-white/10 transition-colors"
          title="Restore standard Dicty hotkeys"
        >
          <RotateCcw className="w-3.5 h-3.5" />
          <span>Reset Defaults</span>
        </button>
      </div>

      {/* Recording in progress indicator bar */}
      {recordingTarget && (
        <div className="p-3.5 rounded-xl bg-amber-500/10 border border-amber-500/30 flex items-center justify-between text-xs text-amber-200 animate-in fade-in">
          <div className="flex items-center gap-2">
            <Keyboard className="w-4 h-4 text-amber-400 animate-pulse" />
            <span>
              Press any single button or combination (e.g. <strong>F8</strong>, <strong>Space</strong>, <strong>Pause</strong>, <strong>Ctrl + Space</strong>, <strong>Alt + Shift + M</strong>). Press <strong>Esc</strong> to cancel.
            </span>
          </div>
          {recordingError && (
            <div className="flex items-center gap-1.5 text-red-300 text-xs font-medium">
              <AlertCircle className="w-3.5 h-3.5 text-red-400" />
              <span>{recordingError}</span>
            </div>
          )}
        </div>
      )}

      {/* Main Shortcuts List */}
      <div className="space-y-3.5">
        <ShortcutCard
          title="Toggle Recording"
          description="Starts or stops global speech-to-text recording anywhere on Windows."
          shortcutDisplay={toggleKey}
          isRecording={recordingTarget === "toggle"}
          liveCombo={liveCombo}
          requireDoubleTap={doubleTapToggle}
          onRecord={() => startRecording("toggle")}
          onCancelRecord={cancelRecording}
          onDoubleTapToggle={setDoubleTapToggle}
        />

        <ShortcutCard
          title="Pause / Resume Recording"
          description="Temporarily pauses or resumes audio capture during an active session."
          shortcutDisplay={pauseKey}
          isRecording={recordingTarget === "pause"}
          liveCombo={liveCombo}
          requireDoubleTap={doubleTapPause}
          onRecord={() => startRecording("pause")}
          onCancelRecord={cancelRecording}
          onDoubleTapToggle={setDoubleTapPause}
        />

        <ShortcutCard
          title="Switch Active Mode"
          description="Cycles through your active profiles (General, Code, Librarian, Meeting, Prose) anywhere on Windows."
          shortcutDisplay={modeKey}
          isRecording={recordingTarget === "mode"}
          liveCombo={liveCombo}
          requireDoubleTap={doubleTapMode}
          onRecord={() => startRecording("mode")}
          onCancelRecord={cancelRecording}
          onDoubleTapToggle={setDoubleTapMode}
        />
      </div>

      {/* Activation Style & Auto-Paste Section */}
      <div className="space-y-3.5 pt-2">
        <div className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 flex items-center justify-between">
          <div>
            <h4 className="text-sm font-bold text-white tracking-tight">
              Activation Style
            </h4>
            <p className="text-xs text-white/50">
              Choose whether pressing the hotkey acts as a toggle or push-to-talk.
            </p>
          </div>

          <div className="inline-flex p-1 rounded-xl bg-white/[0.05] border border-white/10">
            <button
              onClick={() => setActivationStyle("toggle")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                activationStyle === "toggle"
                  ? "bg-[#5D6658] text-white shadow"
                  : "text-white/60 hover:text-white"
              }`}
            >
              Toggle (Click to start/stop)
            </button>
            <button
              onClick={() => setActivationStyle("hold")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                activationStyle === "hold"
                  ? "bg-[#5D6658] text-white shadow"
                  : "text-white/60 hover:text-white"
              }`}
            >
              Hold to Record
            </button>
          </div>
        </div>

        <div className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 flex items-center justify-between">
          <div>
            <h4 className="text-sm font-bold text-white tracking-tight">
              Auto-Paste Dictation
            </h4>
            <p className="text-xs text-white/50">
              Automatically simulate Ctrl+V keystroke into the active window when transcription finishes.
            </p>
          </div>

          <ToggleSwitch
            checked={autoPaste}
            onChange={setAutoPaste}
            ariaLabel="Auto-Paste Dictation"
          />
        </div>

        <div className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 flex items-center justify-between">
          <div>
            <h4 className="text-sm font-bold text-white tracking-tight">
              Audio Feedback Chimes
            </h4>
            <p className="text-xs text-white/50">
              Play a subtle auditory ping when recording starts and finishes.
            </p>
          </div>

          <ToggleSwitch
            checked={soundFeedback}
            onChange={setSoundFeedback}
            ariaLabel="Audio Feedback Chimes"
          />
        </div>
      </div>
    </div>
  );
};
