import React, { useState, useEffect } from "react";
import { Mic, Square, Pause, Play, X, Sparkles, BookOpen, Users } from "lucide-react";
import { engineApi } from "../services/engineApi";
import { engineWebSocket } from "../services/engineClient";
import type { DictyMode } from "../types/engine";

export const OverlayHUDView: React.FC = () => {
  const [isRecording, setIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [mode, setMode] = useState<DictyMode>("dictation");
  const [partialText, setPartialText] = useState("");
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [volume, setVolume] = useState(0.2);

  // Connect to engine WebSocket for partial text
  useEffect(() => {
    let ws: WebSocket | null = null;
    let cancelled = false;

    engineWebSocket("/ws/transcribe/stream")
      .then((socket) => {
        if (cancelled) {
          socket.close();
          return;
        }
        ws = socket;
        ws.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            if (data.status === "partial" && data.text) {
              setPartialText(data.text);
            }
          } catch {}
        };
      })
      .catch(() => {});

    return () => {
      cancelled = true;
      ws?.close();
    };
  }, []);

  // Timer simulation
  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;
    if (isRecording && !isPaused) {
      timer = setInterval(() => setElapsedSeconds((s) => s + 1), 1000);
    } else if (!isRecording) {
      setElapsedSeconds(0);
      setPartialText("");
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [isRecording, isPaused]);

  // Audio wave pulse animation simulation
  useEffect(() => {
    let waveInterval: ReturnType<typeof setInterval> | null = null;
    if (isRecording && !isPaused) {
      waveInterval = setInterval(() => {
        setVolume(0.2 + Math.random() * 0.8);
      }, 100);
    }
    return () => {
      if (waveInterval) clearInterval(waveInterval);
    };
  }, [isRecording, isPaused]);

  // Listen for native OS hotkey / tray state changes from Tauri Rust layer
  useEffect(() => {
    let unlisten: (() => void) | null = null;
    import("@tauri-apps/api/event")
      .then(({ listen }) => {
        listen("dicty:recording-state-changed", (event: any) => {
          const payload = event.payload;
          if (payload) {
            if (typeof payload.is_recording === "boolean") {
              setIsRecording(payload.is_recording);
            }
            if (typeof payload.is_paused === "boolean") {
              setIsPaused(payload.is_paused);
            }
          }
        }).then((fn) => {
          unlisten = fn;
        });
      })
      .catch(() => {});

    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const handleToggleRecord = async () => {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      await invoke("toggle_dictation");
      return;
    } catch {}

    if (!isRecording) {
      setIsRecording(true);
      setIsPaused(false);
      try {
        await engineApi.startRecording({ mode });
      } catch (e) {
        console.warn("Local engine not reachable yet", e);
      }
    } else {
      setIsRecording(false);
      try {
        await engineApi.stopRecording();
      } catch (e) {
        console.warn("Local engine not reachable yet", e);
      }
    }
  };

  const handleTogglePause = async () => {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      await invoke("toggle_pause");
      return;
    } catch {}

    if (isPaused) {
      setIsPaused(false);
      try {
        await engineApi.resumeRecording();
      } catch {}
    } else {
      setIsPaused(true);
      try {
        await engineApi.pauseRecording();
      } catch {}
    }
  };

  const handleCancel = async () => {
    setIsRecording(false);
    setIsPaused(false);
    try {
      await engineApi.cancelRecording();
    } catch {}
  };

  const formatTime = (secs: number) => {
    const mins = Math.floor(secs / 60);
    const rem = secs % 60;
    return `${mins}:${rem < 10 ? "0" : ""}${rem}`;
  };

  return (
    <div className="flex-1 flex flex-col items-center justify-center p-8 relative overflow-hidden">
      {/* Background ambient lighting */}
      <div className="absolute w-96 h-96 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none -top-20 -right-20"></div>
      <div className="absolute w-80 h-80 bg-purple-500/10 rounded-full blur-3xl pointer-events-none -bottom-20 -left-20"></div>

      <div className="w-full max-w-xl space-y-6">
        <div className="text-center space-y-2">
          <h2 className="text-2xl font-bold text-white tracking-tight">Floating HUD Preview</h2>
          <p className="text-sm text-white/50">
            This floating widget stays pinned above target Windows apps (Obsidian, VS Code, Slack, Word).
          </p>
        </div>

        {/* The Exact Floating Glass HUD Widget */}
        <div className="p-4 flex items-center justify-center">
          <div className="glass-panel rounded-full px-6 py-3.5 flex items-center gap-4 text-sm font-medium border border-white/15 shadow-2xl transition-all duration-300">
            {/* Mode Indicator Pill */}
            <div className="flex items-center gap-1.5 px-3 py-1 rounded-full bg-white/10 text-xs font-semibold text-white/90 shadow-inner">
              {mode === "librarian" ? (
                <BookOpen className="w-3.5 h-3.5 text-purple-400" />
              ) : mode === "meeting" ? (
                <Users className="w-3.5 h-3.5 text-amber-400" />
              ) : (
                <Sparkles className="w-3.5 h-3.5 text-emerald-400" />
              )}
              <span className="capitalize">{mode}</span>
            </div>

            {/* Reactive Waveform Bars */}
            <div className="flex items-center gap-1 h-6 px-1">
              {[0.4, 0.7, 1.0, 0.6, 0.85, 0.5, 0.9, 0.3].map((scale, i) => (
                <div
                  key={i}
                  className="w-1 bg-emerald-400 rounded-full transition-all duration-100"
                  style={{
                    height: isRecording && !isPaused ? `${Math.max(4, scale * volume * 24)}px` : "4px",
                    opacity: isRecording ? 1 : 0.3,
                  }}
                />
              ))}
            </div>

            {/* Real-time Streaming Speech Preview */}
            <div className="max-w-[200px] truncate text-xs text-white/80 italic min-w-[140px]">
              {isRecording ? (
                partialText || (isPaused ? "Paused..." : "Listening...")
              ) : (
                <span className="not-italic text-white/40">Ready (Ctrl+Space)</span>
              )}
            </div>

            {/* Timer */}
            {isRecording && (
              <div className="font-mono text-xs text-emerald-300 font-semibold tabular-nums">
                {formatTime(elapsedSeconds)}
              </div>
            )}

            {/* Controls */}
            <div className="flex items-center gap-1.5">
              <button
                onClick={handleToggleRecord}
                className={`p-2.5 rounded-full transition-all shadow-md ${
                  isRecording
                    ? "bg-red-500/90 hover:bg-red-600 text-white animate-pulse"
                    : "bg-emerald-600 hover:bg-emerald-500 text-white"
                }`}
                title={isRecording ? "Stop & Paste (Ctrl+V)" : "Start Recording"}
              >
                {isRecording ? <Square className="w-4 h-4" /> : <Mic className="w-4 h-4" />}
              </button>

              {isRecording && (
                <>
                  <button
                    onClick={handleTogglePause}
                    className="p-2 rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors"
                    title={isPaused ? "Resume" : "Pause"}
                  >
                    {isPaused ? <Play className="w-3.5 h-3.5" /> : <Pause className="w-3.5 h-3.5" />}
                  </button>

                  <button
                    onClick={handleCancel}
                    className="p-2 rounded-full bg-white/10 hover:bg-red-500/30 text-white/70 hover:text-red-300 transition-colors"
                    title="Cancel Recording (Esc)"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Mode Selector Cards */}
        <div className="grid grid-cols-3 gap-3 pt-4 border-t border-white/10">
          <button
            onClick={() => setMode("dictation")}
            className={`p-4 rounded-xl text-left border transition-all ${
              mode === "dictation"
                ? "bg-emerald-500/10 border-emerald-500/40 shadow-lg shadow-emerald-500/5"
                : "bg-white/5 border-white/10 hover:bg-white/10"
            }`}
          >
            <div className="flex items-center gap-2 mb-1.5 font-semibold text-sm text-white">
              <Sparkles className="w-4 h-4 text-emerald-400" />
              Dictation
            </div>
            <p className="text-xs text-white/50 leading-relaxed">
              Auto-pastes polished text directly into your active Windows editor.
            </p>
          </button>

          <button
            onClick={() => setMode("librarian")}
            className={`p-4 rounded-xl text-left border transition-all ${
              mode === "librarian"
                ? "bg-purple-500/10 border-purple-500/40 shadow-lg shadow-purple-500/5"
                : "bg-white/5 border-white/10 hover:bg-white/10"
            }`}
          >
            <div className="flex items-center gap-2 mb-1.5 font-semibold text-sm text-white">
              <BookOpen className="w-4 h-4 text-purple-400" />
              Librarian
            </div>
            <p className="text-xs text-white/50 leading-relaxed">
              Captures spontaneous architectural thoughts for Obsidian & Confluence.
            </p>
          </button>

          <button
            onClick={() => setMode("meeting")}
            className={`p-4 rounded-xl text-left border transition-all ${
              mode === "meeting"
                ? "bg-amber-500/10 border-amber-500/40 shadow-lg shadow-amber-500/5"
                : "bg-white/5 border-white/10 hover:bg-white/10"
            }`}
          >
            <div className="flex items-center gap-2 mb-1.5 font-semibold text-sm text-white">
              <Users className="w-4 h-4 text-amber-400" />
              Meeting
            </div>
            <p className="text-xs text-white/50 leading-relaxed">
              Records mic and WASAPI system loopback audio with speaker separation.
            </p>
          </button>
        </div>
      </div>
    </div>
  );
};
