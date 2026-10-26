import React, { useState, useEffect, useRef, useMemo } from "react";
import {
  Square,
  Pause,
  Play,
  X,
  Maximize2,
  Minimize2,
  Loader2,
  GripVertical,
  AlertCircle,
  ChevronDown,
  Sparkles,
  Check,
  RotateCcw,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { engineWebSocket } from "../services/engineClient";
import { engineApi } from "../services/engineApi";
import { type ProfileItem, getStoredProfiles } from "../types/profiles";

type DictyMode = "dictation" | "librarian" | "meeting" | "focused_meeting";

export const RecordingOverlayHUD: React.FC = () => {
  const [isRecording, setIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [backendError, setBackendError] = useState<string | null>(null);
  const [activeProfileId, setActiveProfileId] = useState<string>(() => {
    try {
      return localStorage.getItem("dicty_active_profile") || "prof_1";
    } catch {
      return "prof_1";
    }
  });
  const [activeProfileName, setActiveProfileName] = useState<string>("General Dictation");
  const [activeMode, setActiveMode] = useState<DictyMode>("dictation");
  const [elapsed, setElapsed] = useState(0);
  const [partialText, setPartialText] = useState("");
  const [isMini, setIsMini] = useState(false);
  const [isHovered, setIsHovered] = useState(false);
  const [volumePulse, setVolumePulse] = useState(0.6);

  // App rules & resolved mode state
  const [targetAppId, setTargetAppId] = useState<string | null>(null);
  const [targetAppName, setTargetAppName] = useState<string | null>(null);
  const [resolvedMode, setResolvedMode] = useState<string | null>(null);
  const [isChipMenuOpen, setIsChipMenuOpen] = useState(false);
  const [isManualOverrideActive, setIsManualOverrideActive] = useState(false);
  const [suggestionBanner, setSuggestionBanner] = useState<{
    app_id: string;
    app_name: string;
    mode_id: string;
  } | null>(null);
  const [alwaysApplied, setAlwaysApplied] = useState(false);
  const [profiles, setProfiles] = useState<ProfileItem[]>(() => getStoredProfiles());

  const selectableProfiles = profiles.filter(
    (p) => p.modeType !== "meeting" && p.modeType !== "focused_meeting"
  );

  const displayResolvedModeName = useMemo(() => {
    if (resolvedMode) {
      const found = profiles.find((p) => p.id === resolvedMode);
      if (found) return found.name;
    }
    return activeProfileName;
  }, [resolvedMode, profiles, activeProfileName]);


  // Dynamic user-configured shortcuts synced from Settings & Tauri
  const [toggleKey, setToggleKey] = useState(() => {
    try {
      return localStorage.getItem("dicty_shortcut_toggle") || "Ctrl + Space";
    } catch {
      return "Ctrl + Space";
    }
  });
  const [pauseKey, setPauseKey] = useState(() => {
    try {
      return localStorage.getItem("dicty_shortcut_pause") || "Ctrl + Shift + P";
    } catch {
      return "Ctrl + Shift + P";
    }
  });
  const [modeKey, setModeKey] = useState(() => {
    try {
      return localStorage.getItem("dicty_shortcut_mode") || "Alt + Shift + M";
    } catch {
      return "Alt + Shift + M";
    }
  });

  const pauseKeyRef = useRef(pauseKey);
  const toggleKeyRef = useRef(toggleKey);
  const modeKeyRef = useRef(modeKey);
  pauseKeyRef.current = pauseKey;
  toggleKeyRef.current = toggleKey;
  modeKeyRef.current = modeKey;

  const wsRef = useRef<WebSocket | null>(null);
  const wasRecordingRef = useRef<boolean>(false);

  // Sync shortcut settings across windows and from Tauri
  useEffect(() => {
    const updateKeys = () => {
      try {
        const t = localStorage.getItem("dicty_shortcut_toggle");
        const p = localStorage.getItem("dicty_shortcut_pause");
        const m = localStorage.getItem("dicty_shortcut_mode");
        if (t) setToggleKey(t);
        if (p) setPauseKey(p);
        if (m) setModeKey(m);
      } catch {}
    };
    updateKeys();

    const handleStorage = (e: StorageEvent) => {
      if (e.key === "dicty_shortcut_toggle" && e.newValue) setToggleKey(e.newValue);
      if (e.key === "dicty_shortcut_pause" && e.newValue) setPauseKey(e.newValue);
      if (e.key === "dicty_shortcut_mode" && e.newValue) setModeKey(e.newValue);
      if (e.key === "dicty_active_profile" && e.newValue) setActiveProfileId(e.newValue);
    };
    window.addEventListener("storage", handleStorage);

    let unlisten: (() => void) | null = null;
    listen<{ toggle_key?: string; pause_key?: string; mode_key?: string; toggleKey?: string; pauseKey?: string; modeKey?: string }>(
      "dicty:shortcuts-changed",
      (event) => {
        const t = event.payload?.toggleKey || event.payload?.toggle_key;
        const p = event.payload?.pauseKey || event.payload?.pause_key;
        const m = event.payload?.modeKey || event.payload?.mode_key;
        if (t) setToggleKey(t);
        if (p) setPauseKey(p);
        if (m) setModeKey(m);
      }
    ).then((unsub) => {
      unlisten = unsub;
    }).catch(() => {});

    return () => {
      window.removeEventListener("storage", handleStorage);
      if (unlisten) unlisten();
    };
  }, []);

  // Ensure transparent background for the overlay window
  useEffect(() => {
    document.documentElement.classList.add("is-overlay");
    document.body.classList.add("is-overlay");
    document.body.style.background = "transparent";
  }, []);

  // 1. Native OS Window Dragging (Tao / Win32 startDragging): Zero lag, zero listener feedback loop
  const handleDragMouseDown = async (e: React.MouseEvent) => {
    if (e.button !== 0 || (e.target as HTMLElement).closest("button, a, input, select, textarea, [role='button']")) {
      return;
    }
    try {
      const { getCurrentWebviewWindow } = await import("@tauri-apps/api/webviewWindow");
      const appWindow = getCurrentWebviewWindow();
      await appWindow.startDragging();
    } catch {
      invoke("start_drag_overlay").catch(() => {});
    }
  };

  // 2. WebSocket stream for live partial transcription
  useEffect(() => {
    let isMounted = true;

    const connectWs = async () => {
      try {
        const ws = await engineWebSocket("/ws/transcribe/stream");
        if (!isMounted) {
          ws.close();
          return;
        }
        wsRef.current = ws;

        ws.onmessage = (event) => {
          if (!isMounted) return;
          try {
            const data = JSON.parse(event.data);
            if (data.status === "partial" && typeof data.text === "string") {
              setPartialText(data.text);
            }
          } catch {
            // Ignore parse errors
          }
        };

        ws.onerror = () => {
          // Socket error
        };

        ws.onclose = () => {
          if (isMounted) {
            setTimeout(connectWs, 2000);
          }
        };
      } catch {
        if (isMounted) {
          setTimeout(connectWs, 2000);
        }
      }
    };

    connectWs();

    return () => {
      isMounted = false;
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  // 3. Listen for native recording and pause state changes from Tauri backend
  useEffect(() => {
    let unlisten: (() => void) | null = null;

    invoke<any>("get_active_mode")
      .then((info) => {
        if (info?.profile_id) setActiveProfileId(info.profile_id);
        if (info?.profile_name) setActiveProfileName(info.profile_name);
        if (info?.mode) setActiveMode(info.mode);
      })
      .catch(() => {});

    listen<any>("dicty:recording-state-changed", (event) => {
      const payload = event.payload || {};
      if (typeof payload.is_recording === "boolean") {
        setIsRecording(payload.is_recording);
        if (payload.is_recording) {
          if (!wasRecordingRef.current) {
            wasRecordingRef.current = true;
          }
          setElapsed(0);
          setProfiles(getStoredProfiles());
        } else if (!payload.is_recording && wasRecordingRef.current) {
          wasRecordingRef.current = false;
        }
      }
      if (typeof payload.is_paused === "boolean") {
        setIsPaused(payload.is_paused);
      }
      if (payload.profile_id) setActiveProfileId(payload.profile_id);
      if (payload.profile_name) setActiveProfileName(payload.profile_name);
      if (payload.mode) setActiveMode(payload.mode);
      if (payload.app_id) setTargetAppId(payload.app_id);
      if (payload.app_name) setTargetAppName(payload.app_name);
      if (payload.resolved_mode) setResolvedMode(payload.resolved_mode);
      if (typeof payload.manual_override_active === "boolean") {
        setIsManualOverrideActive(payload.manual_override_active);
      }
      if (payload.status === "processing") {
        setIsProcessing(true);
        if (wasRecordingRef.current) {
          wasRecordingRef.current = false;
        }
      } else if (payload.is_recording === false) {
        setIsProcessing(false);
        setPartialText("");
        setElapsed(0);
      }
    }).then((fn) => {
      unlisten = fn;
    });

    let unlistenResolved: (() => void) | null = null;
    listen<any>("dicty:resolved-mode-changed", (event) => {
      const p = event.payload || {};
      if (p.resolved_mode) setResolvedMode(p.resolved_mode);
      if (p.app_id) setTargetAppId(p.app_id);
      if (p.target_app_name) setTargetAppName(p.target_app_name);
      if (p.resolved_mode) {
        const found = profiles.find((prof) => prof.id === p.resolved_mode);
        if (found) {
          setActiveProfileId(found.id);
          setActiveProfileName(found.name);
          setActiveMode(found.modeType as DictyMode);
        }
      }
    }).then((fn) => {
      unlistenResolved = fn;
    });

    let unlistenSuggestion: (() => void) | null = null;
    listen<any>("dicty:app-rule-suggestion", (event) => {
      const p = event.payload || {};
      if (p.app_id && p.mode_id) {
        setSuggestionBanner({
          app_id: p.app_id,
          app_name: p.app_name || p.app_id,
          mode_id: p.mode_id,
        });
      }
    }).then((fn) => {
      unlistenSuggestion = fn;
    });

    let unlistenMode: (() => void) | null = null;
    listen<any>("dicty:mode-changed", (event) => {
      if (event.payload?.profile_id) setActiveProfileId(event.payload.profile_id);
      if (event.payload?.profile_name) setActiveProfileName(event.payload.profile_name);
      if (event.payload?.mode) setActiveMode(event.payload.mode);
      if (event.payload?.whisper_model) {
        localStorage.setItem("dicty_active_model", event.payload.whisper_model);
      }
    }).then((fn) => {
      unlistenMode = fn;
    });

    let unlistenError: (() => void) | null = null;
    listen<any>("dicty:backend-error", (event) => {
      const msg = typeof event.payload === "string" ? event.payload : event.payload?.error || "Model error";
      setBackendError(msg);
      setTimeout(() => setBackendError(null), 6000);
    }).then((fn) => {
      unlistenError = fn;
    });

    return () => {
      if (unlisten) unlisten();
      if (unlistenResolved) unlistenResolved();
      if (unlistenSuggestion) unlistenSuggestion();
      if (unlistenMode) unlistenMode();
      if (unlistenError) unlistenError();
    };
  }, [profiles]);

  // 4. Audio volume equalizer simulation (only pulses when active & not paused)
  useEffect(() => {
    if (!isRecording || isPaused || isProcessing) return;

    const interval = setInterval(() => {
      setVolumePulse(0.3 + Math.random() * 0.7);
    }, 110);

    return () => clearInterval(interval);
  }, [isRecording, isPaused, isProcessing]);

  // 5. Elapsed timer (freezes when paused)
  useEffect(() => {
    if (!isRecording || isPaused || isProcessing) return;

    const timer = setInterval(() => {
      setElapsed((prev) => prev + 1);
    }, 1000);

    return () => clearInterval(timer);
  }, [isRecording, isPaused, isProcessing]);

  // 6. Native window resizing when toggling between Mini and Expanded modes
  const handleToggleMini = async (targetMini: boolean) => {
    setIsMini(targetMini);
    try {
      await invoke("set_overlay_mode", { mini: targetMini });
    } catch {
      // Fallback
    }
  };

  // 7. Responsive Pause Toggle with instant 0ms optimistic UI update
  const handleTogglePause = async (e?: React.MouseEvent) => {
    e?.stopPropagation();
    e?.preventDefault();
    const nextPaused = !isPaused;
    setIsPaused(nextPaused);
    try {
      await invoke("toggle_pause");
    } catch (err) {
      console.error("Failed to toggle pause:", err);
      setIsPaused(!nextPaused);
    }
  };

  const handleStopRecording = async (e?: React.MouseEvent) => {
    e?.stopPropagation();
    e?.preventDefault();
    setIsProcessing(true);
    try {
      await invoke("toggle_dictation");
    } catch (err) {
      console.error("Failed to stop dictation:", err);
      setIsProcessing(false);
    }
  };

  // Auto-reset processing state if backend takes more than 45s
  useEffect(() => {
    if (!isProcessing) return;
    const timeout = setTimeout(() => {
      console.warn("Processing timeout reached, auto-resetting HUD state");
      setIsProcessing(false);
      setElapsed(0);
      setPartialText("");
    }, 45000);
    return () => clearTimeout(timeout);
  }, [isProcessing]);

  // App Rule Handlers
  const handlePickModeOverride = async (modeId: string, modeName: string) => {
    try {
      await invoke("set_recording_mode_override", { modeId: modeId });
      setActiveProfileId(modeId);
      setActiveProfileName(modeName);
      setResolvedMode(modeId);
      setIsManualOverrideActive(true);
      setIsChipMenuOpen(false);
    } catch (err) {
      console.warn("Failed to set recording mode override:", err);
    }
  };

  const handleAlwaysUseForApp = async () => {
    if (!targetAppId) return;
    try {
      await engineApi.createAppRule({
        app_id: targetAppId,
        app_name: targetAppName || targetAppId,
        mode_id: activeProfileId,
        enabled: true,
      });
      setAlwaysApplied(true);
      setTimeout(() => {
        setAlwaysApplied(false);
        setIsChipMenuOpen(false);
      }, 1000);
    } catch (err) {
      console.warn("Failed to save app rule:", err);
    }
  };

  const handleResumeAutoMode = async () => {
    try {
      await invoke("set_manual_override_active", { active: false });
      await invoke("set_recording_mode_override", { modeId: null });
      setIsManualOverrideActive(false);
      setIsChipMenuOpen(false);
    } catch (err) {
      console.warn("Failed to resume auto mode:", err);
    }
  };

  const handleAcceptSuggestion = async (sug: { app_id: string; app_name: string; mode_id: string }) => {
    try {
      await engineApi.acceptAppRuleSuggestion(sug.app_id, sug.mode_id, sug.app_name);
      setSuggestionBanner(null);
    } catch (err) {
      console.warn("Failed to accept rule suggestion:", err);
    }
  };

  const handleSuppressSuggestion = async (appId: string) => {
    try {
      await engineApi.suppressAppRuleSuggestion(appId);
      setSuggestionBanner(null);
    } catch (err) {
      console.warn("Failed to suppress rule suggestion:", err);
    }
  };

  const handleCancelRecording = async (e?: React.MouseEvent) => {
    e?.stopPropagation();
    e?.preventDefault();
    setIsProcessing(false);
    setIsRecording(false);
    setElapsed(0);
    setPartialText("");
    try {
      await invoke("cancel_dictation");
    } catch (err) {
      console.error("Failed to cancel dictation:", err);
    }
  };

  const handleSwitchMode = async (e?: React.MouseEvent) => {
    e?.stopPropagation();
    e?.preventDefault();
    try {
      await invoke("switch_mode");
    } catch (err) {
      console.error("Failed to switch mode:", err);
    }
  };

  const matchesShortcut = (e: KeyboardEvent, shortcutStr: string): boolean => {
    if (!shortcutStr) return false;
    const parts = shortcutStr.split("+").map((p) => p.trim().toLowerCase());
    const hasCtrl = parts.includes("ctrl") || parts.includes("control");
    const hasAlt = parts.includes("alt");
    const hasShift = parts.includes("shift");
    const hasWin = parts.includes("win") || parts.includes("super") || parts.includes("meta");

    if (e.ctrlKey !== hasCtrl) return false;
    if (e.altKey !== hasAlt) return false;
    if (e.shiftKey !== hasShift) return false;
    if (e.metaKey !== hasWin) return false;

    const keyPart = parts.filter(
      (p) => !["ctrl", "control", "alt", "shift", "win", "super", "meta"].includes(p)
    )[0];

    if (!keyPart) return false;

    const eventKey = e.key.toLowerCase();
    const eventCode = e.code.toLowerCase();

    if (keyPart === "space") return eventCode === "space" || eventKey === " ";
    if (keyPart === eventKey) return true;
    if (eventCode.replace("key", "") === keyPart) return true;
    if (eventCode.replace("digit", "") === keyPart) return true;
    return eventCode === keyPart;
  };

  // 8. Keyboard shortcut listeners while overlay window is focused
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        handleCancelRecording();
      } else if (
        matchesShortcut(e, pauseKeyRef.current) ||
        e.key === "F7" ||
        (e.altKey && (e.key === "p" || e.key === "P"))
      ) {
        e.preventDefault();
        handleTogglePause();
      } else if (
        matchesShortcut(e, toggleKeyRef.current) ||
        e.key === "F8"
      ) {
        e.preventDefault();
        handleStopRecording();
      } else if (matchesShortcut(e, modeKeyRef.current)) {
        e.preventDefault();
        handleSwitchMode();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isPaused]);

  const formatTime = (seconds: number) => {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${s < 10 ? "0" : ""}${s}`;
  };

  const getProfileMeta = (profileId: string, mode: DictyMode, name: string) => {
    const firstChar = name?.trim() ? name.trim().charAt(0).toUpperCase() : "D";
    switch (profileId) {
      case "prof_1":
        return { letter: "D", color: "#10B981" };
      case "prof_2":
        return { letter: "C", color: "#3B82F6" };
      case "prof_3":
        return { letter: "L", color: "#6366F1" };
      case "prof_4":
        return { letter: "M", color: "#F59E0B" };
      case "prof_5":
        return { letter: "B", color: "#A855F7" };
      default:
        if (mode === "librarian") return { letter: firstChar || "L", color: "#6366F1" };
        if (mode === "meeting") return { letter: firstChar || "M", color: "#F59E0B" };
        if (mode === "focused_meeting") return { letter: firstChar || "F", color: "#EF4444" };
        return { letter: firstChar || "D", color: "#10B981" };
    }
  };

  const profileMeta = getProfileMeta(activeProfileId, activeMode, activeProfileName);

  // -------------------------------------------------------------
  // MINI PILL MODE (Compact ~180px x 48px)
  // -------------------------------------------------------------
  if (isMini) {
    return (
      <div
        data-tauri-drag-region
        onMouseDown={handleDragMouseDown}
        onMouseEnter={() => setIsHovered(true)}
        onMouseLeave={() => setIsHovered(false)}
        className="w-full h-full flex items-center justify-center p-1 bg-transparent select-none cursor-grab active:cursor-grabbing box-border overflow-hidden"
      >
        <div
          data-tauri-drag-region
          onMouseDown={handleDragMouseDown}
          className="relative flex items-center gap-2 px-3 py-1.5 rounded-full backdrop-blur-2xl border transition-all duration-150 shadow-2xl box-border cursor-grab active:cursor-grabbing"
          style={{
            backgroundColor: isPaused ? "rgba(28, 22, 14, 0.96)" : "rgba(18, 22, 20, 0.94)",
            borderColor: isPaused ? "rgba(245, 158, 11, 0.45)" : "rgba(255, 255, 255, 0.18)",
            boxShadow: isPaused
              ? "0 8px 32px rgba(245, 158, 11, 0.2), 0 4px 16px rgba(0, 0, 0, 0.6)"
              : "0 8px 32px rgba(0, 0, 0, 0.6)",
          }}
        >
          {/* Subtle drag handle dots */}
          <GripVertical className="w-3 h-3 text-white/30 -ml-1 cursor-grab flex-shrink-0" />

          {isHovered ? (
            /* Hover Controls: Quick Actions */
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={handleTogglePause}
                title={isPaused ? `Resume Recording (${pauseKey})` : `Pause Recording (${pauseKey})`}
                className={`w-6 h-6 rounded-full flex items-center justify-center transition-all ${
                  isPaused
                    ? "bg-amber-500/35 text-amber-300 hover:bg-amber-500/50 border border-amber-500/50 shadow-[0_0_8px_rgba(245,158,11,0.3)]"
                    : "bg-white/10 hover:bg-white/20 text-white"
                }`}
              >
                {isPaused ? (
                  <Play className="w-3 h-3 fill-amber-300 text-amber-300 ml-0.5" />
                ) : (
                  <Pause className="w-3 h-3 fill-white text-white" />
                )}
              </button>

              <button
                type="button"
                onClick={handleStopRecording}
                title={`Stop & Paste (${toggleKey})`}
                className="w-6 h-6 rounded-full flex items-center justify-center bg-red-500/85 hover:bg-red-500 text-white transition-colors shadow"
              >
                <Square className="w-3 h-3 fill-white text-white" />
              </button>

              <button
                type="button"
                onClick={() => handleToggleMini(false)}
                title="Expand Window"
                className="w-6 h-6 rounded-full flex items-center justify-center bg-white/10 hover:bg-white/20 text-white/80 hover:text-white transition-colors"
              >
                <Maximize2 className="w-3 h-3" />
              </button>
            </div>
          ) : (
            /* Non-Hover View: Glowing Indicator + Equalizer / Paused */
            <div data-tauri-drag-region onMouseDown={handleDragMouseDown} className="flex items-center gap-2 cursor-grab active:cursor-grabbing">
              {/* Mode Circle - clickable to switch */}
              <button
                type="button"
                onClick={handleSwitchMode}
                title={`Mode: ${activeProfileName} (${modeKey})`}
                className="w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-bold text-white shadow flex-shrink-0 hover:scale-110 transition-transform cursor-pointer"
                style={{ backgroundColor: profileMeta.color }}
              >
                {profileMeta.letter}
              </button>

              {backendError ? (
                <div className="flex items-center gap-1.5 text-xs text-red-300">
                  <AlertCircle className="w-3.5 h-3.5 text-red-400 flex-shrink-0" />
                  <span className="text-[10px] font-medium truncate max-w-[160px]">{backendError}</span>
                </div>
              ) : isProcessing ? (
                <div className="flex items-center gap-1.5 text-xs text-white/80">
                  <Loader2 className="w-3.5 h-3.5 animate-spin text-emerald-400" />
                  <span className="text-[11px] font-medium">Processing</span>
                </div>
              ) : isPaused ? (
                /* Frozen Paused State without redundant text */
                <div className="flex items-center gap-1.5">
                  <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
                  <span className="text-[11px] font-mono text-amber-300 font-semibold">
                    {formatTime(elapsed)}
                  </span>
                </div>
              ) : (
                /* Live Pulsing Equalizer 5-bar */
                <div className="flex items-center gap-1 h-4">
                  {[0.4, 0.8, 1.0, 0.8, 0.4].map((mult, i) => (
                    <div
                      key={i}
                      className="w-0.5 bg-emerald-400 rounded-full transition-all duration-100"
                      style={{
                        height: `${Math.max(4, mult * volumePulse * 16)}px`,
                      }}
                    />
                  ))}
                  <span className="text-[11px] font-mono text-white/80 ml-1">
                    {formatTime(elapsed)}
                  </span>
                </div>
              )}

              {/* Mini expand trigger icon */}
              <button
                type="button"
                onClick={() => handleToggleMini(false)}
                className="text-white/40 hover:text-white transition-colors p-0.5 ml-0.5"
                title="Expand Window"
              >
                <Maximize2 className="w-2.5 h-2.5" />
              </button>
            </div>
          )}
        </div>
      </div>
    );
  }

  // -------------------------------------------------------------
  // EXPANDED MODE (~430px x 136px)
  // -------------------------------------------------------------
  return (
    <div
      data-tauri-drag-region
      onMouseDown={handleDragMouseDown}
      className="w-full h-full flex items-center justify-center p-1.5 bg-transparent select-none cursor-grab active:cursor-grabbing overflow-hidden box-border"
    >
      <div
        data-tauri-drag-region
        onMouseDown={handleDragMouseDown}
        className="w-full h-full flex flex-col justify-between px-3.5 py-2 rounded-2xl backdrop-blur-2xl border shadow-2xl transition-all duration-150 box-border overflow-hidden cursor-grab active:cursor-grabbing"
        style={{
          backgroundColor: isPaused ? "rgba(28, 22, 14, 0.96)" : "rgba(18, 22, 20, 0.94)",
          borderColor: isPaused ? "rgba(245, 158, 11, 0.45)" : "rgba(255, 255, 255, 0.16)",
          boxShadow: isPaused
            ? "0 12px 40px rgba(245, 158, 11, 0.2), 0 8px 30px rgba(0, 0, 0, 0.7)"
            : "0 12px 40px rgba(0, 0, 0, 0.65)",
        }}
      >
        {/* Top Header Row: Grip Handle, Mode Badge, Status / Timer, Collapse Button */}
        <div data-tauri-drag-region onMouseDown={handleDragMouseDown} className="flex items-center justify-between h-6 flex-shrink-0">
          <div data-tauri-drag-region className="flex items-center gap-1.5">
            <GripVertical className="w-3.5 h-3.5 text-white/30 -ml-1 cursor-grab flex-shrink-0" />
            <button
              type="button"
              onClick={handleSwitchMode}
              title={`Mode: ${activeProfileName} (Click or ${modeKey} to switch)`}
              className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white shadow-sm flex-shrink-0 hover:scale-110 transition-transform cursor-pointer"
              style={{ backgroundColor: profileMeta.color }}
            >
              {profileMeta.letter}
            </button>

            {/* If paused, show prominent amber status chip */}
            {isPaused && (
              <span className="px-2 py-0.5 rounded-full text-[9px] font-bold tracking-wider bg-amber-500/25 text-amber-300 border border-amber-500/50 animate-pulse">
                PAUSED
              </span>
            )}

            {/* Overlay Chip: [App Icon/Name] · [Resolved Mode] with Popup Menu */}
            {(targetAppName || targetAppId) && (
              <div className="relative">
                <button
                  type="button"
                  onClick={() => setIsChipMenuOpen((prev) => !prev)}
                  className="flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-medium bg-white/10 hover:bg-white/15 text-white/90 border border-white/15 transition-all max-w-[210px] truncate cursor-pointer shadow-sm"
                  title="Click to configure mode for this application"
                >
                  <span className="truncate max-w-[85px] font-semibold text-emerald-300">
                    {targetAppName || targetAppId}
                  </span>
                  <span className="text-white/40">·</span>
                  <span className="truncate max-w-[85px] text-white/80">
                    {displayResolvedModeName}
                  </span>
                  <ChevronDown className="w-2.5 h-2.5 text-white/50 flex-shrink-0" />
                </button>
              </div>
            )}
          </div>

          <div data-tauri-drag-region className="flex items-center gap-2 flex-shrink-0">
            <span className={`text-[11px] font-mono font-semibold ${isPaused ? "text-amber-300" : "text-emerald-400"}`}>
              {formatTime(elapsed)}
            </span>

            {/* Minimize / Collapse Button */}
            <button
              type="button"
              onClick={() => handleToggleMini(true)}
              title="Minimize to Pill"
              className="text-white/50 hover:text-white transition-colors p-1 rounded-md hover:bg-white/10"
            >
              <Minimize2 className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* Center Row: Dynamic Equalizer Waveform / Frozen Equalizer / Live Transcription */}
        <div data-tauri-drag-region onMouseDown={handleDragMouseDown} className="flex-1 min-h-0 flex flex-col items-center justify-center my-0.5">
          {backendError ? (
            <div className="flex items-center gap-2 px-3 py-1 rounded-lg bg-red-500/15 border border-red-500/30 text-red-200 text-xs max-w-full">
              <AlertCircle className="w-4 h-4 text-red-400 flex-shrink-0" />
              <span className="text-[11px] font-medium leading-tight truncate">{backendError}</span>
            </div>
          ) : isProcessing ? (
            <div className="flex items-center gap-2 text-xs text-white/90">
              <Loader2 className="w-4 h-4 animate-spin text-emerald-400" />
              <span className="text-[12px] font-medium">Transcribing & pasting...</span>
            </div>
          ) : (
            <div data-tauri-drag-region className="w-full flex flex-col items-center">
              {/* 32-Bar Voice Sensitivity Equalizer: Actively pulsing when recording, FROZEN when paused */}
              <div data-tauri-drag-region className="flex items-center justify-center gap-[3px] h-5 w-full">
                {Array.from({ length: 32 }).map((_, i) => {
                  const x = i / 31;
                  const dome = Math.sin(x * Math.PI);
                  const jagged =
                    0.5 +
                    0.3 * Math.sin(x * 45) +
                    0.2 * Math.cos(x * 85) +
                    0.1 * Math.sin(x * 130);
                  const multiplier = dome * jagged * 1.6;

                  // When paused: freeze bar height flat to minimal sensitivity floor (3px)
                  const barHeight = isPaused ? 3 : Math.max(3, volumePulse * multiplier * 20);

                  // Color: Warm Amber when paused, Emerald/White when active
                  const barColor = isPaused
                    ? "#F59E0B"
                    : i % 4 === 0
                    ? "#34D399"
                    : i % 2 === 0
                    ? "#6EE7B7"
                    : "#FFFFFF";

                  return (
                    <div
                      key={i}
                      className="w-[2.5px] rounded-full transition-all duration-100"
                      style={{
                        height: `${Math.min(20, barHeight)}px`,
                        backgroundColor: barColor,
                        opacity: isPaused ? 0.6 : 0.85,
                      }}
                    />
                  );
                })}
              </div>

              {/* Status or transcription text preview - strictly one line */}
              {partialText ? (
                <p className="text-[10px] text-white/90 italic truncate max-w-[310px] mt-1 text-center font-sans">
                  "{partialText}"
                </p>
              ) : isPaused ? (
                <p className="text-[10px] text-amber-300 font-medium tracking-wide mt-1 text-center">
                  Paused • Press {pauseKey} to resume
                </p>
              ) : (
                <p className="text-[9px] text-white/30 tracking-widest uppercase mt-1 text-center font-mono">
                  Listening...
                </p>
              )}
            </div>
          )}
        </div>

        {/* Bottom Action Controls Row: Always fixed height, NEVER pushed down or clipped */}
        <div data-tauri-drag-region className="flex items-center justify-between pt-1.5 border-t border-white/10 h-8 flex-shrink-0 w-full">
          <div className="flex items-center gap-2 min-w-0">
            {/* Pause / Resume Button with distinct states and clear hotkey tags */}
            <button
              type="button"
              onClick={handleTogglePause}
              disabled={isProcessing}
              title={isPaused ? `Resume Recording (${pauseKey})` : `Pause Recording (${pauseKey})`}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all whitespace-nowrap ${
                isPaused
                  ? "bg-amber-500/35 text-amber-300 border border-amber-500/60 hover:bg-amber-500/50 shadow-[0_0_12px_rgba(245,158,11,0.3)]"
                  : "bg-white/10 text-white/90 hover:bg-white/15"
              }`}
            >
              {isPaused ? (
                <>
                  <Play className="w-3 h-3 fill-amber-300 text-amber-300 flex-shrink-0" />
                  <span>Resume</span>
                  <span className="text-[9px] opacity-85 ml-0.5 bg-black/40 px-1.5 py-0.5 rounded font-mono font-medium">{pauseKey}</span>
                </>
              ) : (
                <>
                  <Pause className="w-3 h-3 fill-white text-white flex-shrink-0" />
                  <span>Pause</span>
                  <span className="text-[9px] opacity-85 ml-0.5 bg-black/40 px-1.5 py-0.5 rounded font-mono font-medium">{pauseKey}</span>
                </>
              )}
            </button>

            {/* Cancel Button */}
            <button
              type="button"
              onClick={handleCancelRecording}
              disabled={isProcessing}
              title="Cancel Recording (Esc)"
              className="flex items-center gap-1 px-2.5 py-1 rounded-lg text-[11px] font-medium text-white/60 hover:text-white/90 hover:bg-white/10 transition-all whitespace-nowrap"
            >
              <X className="w-3 h-3 flex-shrink-0" />
              <span>Cancel</span>
              <span className="text-[9px] opacity-60 ml-0.5 bg-black/30 px-1.5 py-0.5 rounded font-mono font-medium">Esc</span>
            </button>
          </div>

          {/* Stop & Transcribe Button with dynamic toggleKey tag */}
          <button
            type="button"
            onClick={handleStopRecording}
            disabled={isProcessing}
            title={`Stop & Paste (${toggleKey})`}
            className="flex items-center gap-1.5 px-3 py-1 rounded-lg text-[11px] font-semibold bg-red-500/90 hover:bg-red-500 text-white shadow-md transition-all whitespace-nowrap flex-shrink-0"
          >
            <Square className="w-3 h-3 fill-white flex-shrink-0" />
            <span>Stop</span>
            <span className="text-[9px] opacity-85 ml-0.5 bg-black/40 px-1.5 py-0.5 rounded font-mono font-medium">{toggleKey}</span>
          </button>
        </div>

        {/* Chip Menu Popover */}
        {isChipMenuOpen && (
          <div className="absolute inset-x-2 top-2 bottom-2 z-40 bg-[#16191f]/98 backdrop-blur-2xl rounded-xl border border-white/20 p-2.5 shadow-2xl flex flex-col justify-between text-left animate-in fade-in zoom-in-95 duration-100">
            <div className="flex items-center justify-between pb-1.5 border-b border-white/10">
              <div className="flex items-center gap-1.5 min-w-0">
                <span className="text-[11px] font-bold text-white truncate">
                  {targetAppName || targetAppId}
                </span>
                {targetAppId && (
                  <span className="text-[9px] text-white/50 font-mono truncate">({targetAppId})</span>
                )}
              </div>
              <button
                type="button"
                onClick={() => setIsChipMenuOpen(false)}
                className="text-white/40 hover:text-white p-0.5 rounded"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>

            {/* Section 1: This recording only */}
            <div className="space-y-1">
              <span className="text-[10px] font-semibold text-white/60 uppercase tracking-wider block">
                This recording only:
              </span>
              <div className="flex flex-wrap gap-1">
                {selectableProfiles.map((p) => {
                  const isCurrent = p.id === activeProfileId;
                  return (
                    <button
                      key={p.id}
                      type="button"
                      onClick={() => handlePickModeOverride(p.id, p.name)}
                      className={`px-2 py-0.5 rounded-lg text-[10px] font-medium transition-all ${
                        isCurrent
                          ? "bg-emerald-500/25 text-emerald-200 border border-emerald-500/50 shadow-sm"
                          : "bg-white/5 hover:bg-white/15 text-white/70 border border-white/10"
                      }`}
                    >
                      {p.name}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Section 2: Always use in [App] & Resume Auto */}
            <div className="flex items-center justify-between pt-1 border-t border-white/10 gap-2">
              <button
                type="button"
                onClick={handleAlwaysUseForApp}
                disabled={alwaysApplied}
                className="flex-1 py-1 px-2 rounded-lg text-[10px] font-semibold bg-white/10 hover:bg-white/20 text-white transition-all border border-white/10 flex items-center justify-center gap-1 truncate"
              >
                {alwaysApplied ? (
                  <>
                    <Check className="w-3 h-3 text-emerald-400" />
                    <span className="text-emerald-300">Saved for {targetAppName || targetAppId}</span>
                  </>
                ) : (
                  <span className="truncate">Always use {activeProfileName} in {targetAppName || targetAppId}</span>
                )}
              </button>

              {isManualOverrideActive && (
                <button
                  type="button"
                  onClick={handleResumeAutoMode}
                  className="py-1 px-2 rounded-lg text-[10px] font-semibold bg-blue-500/20 hover:bg-blue-500/30 text-blue-200 transition-all border border-blue-500/40 flex items-center gap-1 flex-shrink-0"
                >
                  <RotateCcw className="w-2.5 h-2.5" />
                  <span>Resume Auto</span>
                </button>
              )}
            </div>
          </div>
        )}

        {/* Learning Suggestion Banner */}
        {suggestionBanner && (
          <div className="absolute inset-x-2 top-2 bottom-2 z-50 bg-[#1e232d]/98 backdrop-blur-2xl rounded-xl border border-amber-500/50 p-2.5 shadow-2xl flex flex-col justify-between animate-in fade-in slide-in-from-top-1 duration-150">
            <div className="flex items-start justify-between">
              <div className="flex items-center gap-1.5 text-amber-300 font-semibold text-xs">
                <Sparkles className="w-4 h-4 text-amber-400 flex-shrink-0" />
                <span>
                  Always use {profiles.find((p) => p.id === suggestionBanner.mode_id)?.name || suggestionBanner.mode_id} in {suggestionBanner.app_name}?
                </span>
              </div>
              <button
                type="button"
                onClick={() => setSuggestionBanner(null)}
                className="text-white/40 hover:text-white p-0.5 rounded"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>

            <div className="flex items-center justify-end gap-2 pt-1 border-t border-white/10">
              <button
                type="button"
                onClick={() => handleSuppressSuggestion(suggestionBanner.app_id)}
                className="text-[10px] text-white/50 hover:text-white px-2 py-0.5 rounded hover:bg-white/10 transition-colors"
              >
                Don't ask for this app
              </button>
              <button
                type="button"
                onClick={() => setSuggestionBanner(null)}
                className="text-[10px] text-white/70 hover:text-white px-2 py-0.5 rounded bg-white/10 hover:bg-white/15 transition-colors"
              >
                Not now
              </button>
              <button
                type="button"
                onClick={() => handleAcceptSuggestion(suggestionBanner)}
                className="text-[10px] font-semibold text-white bg-emerald-600 hover:bg-emerald-500 px-3 py-0.5 rounded shadow-md transition-colors"
              >
                Yes
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
