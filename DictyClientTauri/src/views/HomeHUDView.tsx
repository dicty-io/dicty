import React, { useState, useEffect } from "react";
import {
  Mic,
  Square,
  Pause,
  Play,
  Eye,
  EyeOff,
  Sparkles,
  BookOpen,
  Users,
  Maximize2,
  Minimize2,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { engineApi } from "../services/engineApi";
import { playStartSound, playStopSound } from "../services/soundEffects";
import { copyToClipboardAndPaste } from "../services/pasteService";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import type { DictyMode } from "../types/engine";

export const HomeHUDView: React.FC = () => {
  const [isRecording, setIsRecording] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [isIncognito, setIsIncognito] = useState(false);
  const [isExpanded, setIsExpanded] = useState(false);
  const [mode, setMode] = useState<DictyMode>("dictation");
  const [partialText, setPartialText] = useState("");
  const [volume, setVolume] = useState(0.3);
  const [elapsed, setElapsed] = useState(0);

  // Equalizer pulse
  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;
    if (isRecording && !isPaused) {
      interval = setInterval(() => {
        setVolume(0.2 + Math.random() * 0.8);
      }, 100);
    }
    return () => {
      if (interval) clearInterval(interval);
    };
  }, [isRecording, isPaused]);

  // Timer
  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;
    if (isRecording && !isPaused) {
      timer = setInterval(() => setElapsed((e) => e + 1), 1000);
    } else if (!isRecording) {
      setElapsed(0);
      setPartialText("");
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [isRecording, isPaused]);

  const toggleRecording = async () => {
    let currentWin: any = null;
    try {
      currentWin = getCurrentWebviewWindow();
    } catch {}

    if (!isRecording) {
      playStartSound();
      if (currentWin) {
        try {
          await currentWin.show();
          await currentWin.setAlwaysOnTop(true);
        } catch {}
      }
      setIsRecording(true);
      setIsPaused(false);
      try {
        await engineApi.startRecording({ mode });
      } catch (err) {
        console.error("Failed to start recording:", err);
      }
    } else {
      playStopSound();
      setIsRecording(false);
      try {
        const res = await engineApi.stopRecording();
        if (res?.text) {
          await copyToClipboardAndPaste(res.text);
        }
      } catch (err) {
        console.error("Failed to stop recording:", err);
      } finally {
        if (currentWin) {
          try {
            await currentWin.hide();
          } catch {}
        }
      }
    }
  };

  // Listen for global shortcut activation combo (Ctrl+Space) from native Tauri layer
  useEffect(() => {
    let unlisten: (() => void) | null = null;
    import("@tauri-apps/api/event")
      .then(({ listen }) => {
        listen("dicty:toggle-recording", () => {
          toggleRecording();
        }).then((fn) => {
          unlisten = fn;
        });
      })
      .catch(() => {});

    return () => {
      if (unlisten) unlisten();
    };
  }, [isRecording, mode]);

  const formatTime = (secs: number) => {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}:${s < 10 ? "0" : ""}${s}`;
  };

  const getModeColor = (m: DictyMode) => {
    switch (m) {
      case "librarian":
        return "#7E8CE0"; // Pastel periwinkle
      case "meeting":
        return "#EAA368"; // Pastel apricot
      case "focused_meeting":
        return "#EB7575"; // Pastel coral rose
      default:
        return "#78B18D"; // Pastel sage green
    }
  };

  const getModeLetter = (m: DictyMode) => {
    switch (m) {
      case "librarian":
        return "L";
      case "meeting":
        return "M";
      case "focused_meeting":
        return "F";
      default:
        return "D";
    }
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-8 select-none">
      <SettingsPageHeader
        title="Floating HUD"
        description="The zero-latency overlay widget that stays pinned on top of your Windows desktop while speaking."
      />

      {/* Floating HUD Simulator Canvas */}
      <div className="p-12 rounded-2xl bg-black/40 border border-white/10 flex flex-col items-center justify-center min-h-[260px] relative overflow-hidden shadow-2xl">
        {/* Subtle background ambient blur */}
        <div className="absolute w-72 h-72 rounded-full bg-emerald-500/10 blur-3xl pointer-events-none -top-10"></div>

        {/* The Exact Dicty Floating HUD Widget */}
        <div className="transition-all duration-300">
          {!isExpanded ? (
            /* --- MINI CAPSULE (The Iconic Dicty Pill) --- */
            <div className="dicty-capsule rounded-full px-4 py-2 flex items-center gap-3.5 shadow-2xl border border-white/15">
              {/* Mode Circle Indicator */}
              <div
                className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white shadow"
                style={{ backgroundColor: getModeColor(mode) }}
              >
                {getModeLetter(mode)}
              </div>

              {/* Incognito Icon if active */}
              {isIncognito && (
                <EyeOff className="w-3.5 h-3.5 text-white/70" />
              )}

              {/* State Indicator */}
              {isRecording ? (
                isPaused ? (
                  <div className="flex items-center gap-1.5 px-2">
                    <span className="w-1.5 h-1.5 rounded-full bg-amber-400"></span>
                    <span className="text-[10px] font-bold tracking-wider text-white/90">
                      PAUSED
                    </span>
                  </div>
                ) : (
                  /* 5-Bar Animated Equalizer */
                  <div className="flex items-center gap-1 h-5 px-1">
                    {[0.4, 0.8, 1.0, 0.8, 0.4].map((mult, idx) => (
                      <div
                        key={idx}
                        className="w-1 bg-white rounded-full transition-all duration-100"
                        style={{
                          height: `${Math.max(4, mult * volume * 20)}px`,
                        }}
                      />
                    ))}
                  </div>
                )
              ) : (
                <div className="w-7 h-1.5 bg-white/20 rounded-full"></div>
              )}

              {/* Record / Stop Button */}
              <button
                onClick={toggleRecording}
                className={`p-1.5 rounded-full transition-transform active:scale-95 ${
                  isRecording
                    ? "bg-red-500 text-white"
                    : "bg-[#5D6658] hover:bg-[#41493E] text-white"
                }`}
                title={isRecording ? "Stop Recording (Ctrl+Space)" : "Start Recording"}
              >
                {isRecording ? (
                  <Square className="w-3 h-3 fill-current" />
                ) : (
                  <Mic className="w-3 h-3" />
                )}
              </button>

              {/* Expand to banner button */}
              <button
                onClick={() => setIsExpanded(true)}
                className="p-1 text-white/40 hover:text-white transition-colors"
                title="Expand HUD"
              >
                <Maximize2 className="w-3 h-3" />
              </button>
            </div>
          ) : (
            /* --- EXPANDED CAPSULE --- */
            <div className="dicty-capsule rounded-2xl px-6 py-4 flex flex-col gap-3 min-w-[380px] shadow-2xl border border-white/15">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div
                    className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white shadow-sm"
                    style={{ backgroundColor: getModeColor(mode) }}
                    title={`${mode} mode`}
                  >
                    {getModeLetter(mode)}
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  {isRecording && (
                    <span className="text-xs font-mono text-emerald-400 font-bold tabular-nums">
                      {formatTime(elapsed)}
                    </span>
                  )}
                  <button
                    onClick={() => setIsExpanded(false)}
                    className="text-white/40 hover:text-white transition-colors"
                  >
                    <Minimize2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>

              {/* Streaming Transcript Preview */}
              <div className="bg-black/30 rounded-xl p-3 border border-white/5 min-h-[44px] flex items-center">
                <p className="text-xs text-white/80 italic leading-relaxed">
                  {isRecording
                    ? partialText || (isPaused ? "Paused..." : "Listening...")
                    : "Press Ctrl+Space or tap Record to dictate anywhere"}
                </p>
              </div>

              {/* Action Toolbar */}
              <div className="flex items-center justify-between pt-1">
                <div className="flex items-center gap-1.5">
                  <button
                    onClick={() => setIsIncognito(!isIncognito)}
                    className={`p-1.5 rounded-lg text-xs flex items-center gap-1 transition-colors ${
                      isIncognito
                        ? "bg-amber-500/20 text-amber-300 border border-amber-500/30"
                        : "text-white/50 hover:text-white"
                    }`}
                    title="Toggle Incognito"
                  >
                    {isIncognito ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                    <span className="text-[11px]">Incognito</span>
                  </button>

                  {isRecording && (
                    <button
                      onClick={() => setIsPaused(!isPaused)}
                      className="p-1.5 rounded-lg text-xs text-white/70 hover:text-white flex items-center gap-1"
                    >
                      {isPaused ? <Play className="w-3.5 h-3.5" /> : <Pause className="w-3.5 h-3.5" />}
                      <span className="text-[11px]">{isPaused ? "Resume" : "Pause"}</span>
                    </button>
                  )}
                </div>

                <button
                  onClick={toggleRecording}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1.5 transition-colors ${
                    isRecording
                      ? "bg-red-500 hover:bg-red-600 text-white"
                      : "bg-[#5D6658] hover:bg-[#41493E] text-white"
                  }`}
                >
                  {isRecording ? <Square className="w-3.5 h-3.5 fill-current" /> : <Mic className="w-3.5 h-3.5" />}
                  <span>{isRecording ? "Stop & Paste" : "Start"}</span>
                </button>
              </div>
            </div>
          )}
        </div>

        <p className="text-xs text-white/40 mt-8">
          Tip: In Windows, the widget floats natively over all full-screen games and apps without stealing window focus.
        </p>
      </div>

      {/* Quick Mode Switcher Row */}
      <div className="space-y-3">
        <h3 className="text-xs font-semibold uppercase tracking-wider text-white/50">
          Select Active Mode
        </h3>
        <div className="grid grid-cols-3 gap-3">
          {[
            { id: "dictation" as DictyMode, title: "General Dictation", icon: Sparkles, desc: "Punctuation & fast typing" },
            { id: "librarian" as DictyMode, title: "Librarian Mode", icon: BookOpen, desc: "Captures docs for Obsidian" },
            { id: "meeting" as DictyMode, title: "Meeting Assistant", icon: Users, desc: "Mic + System audio loopback" },
          ].map((m) => {
            const Icon = m.icon;
            const isSelected = mode === m.id;
            return (
              <button
                key={m.id}
                onClick={() => setMode(m.id)}
                className={`p-4 text-left rounded-xl transition-all ${
                  isSelected
                    ? "dicty-card-active shadow-lg"
                    : "dicty-card"
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <Icon
                    className="w-4 h-4"
                    style={{ color: getModeColor(m.id) }}
                  />
                  <span className="font-semibold text-xs text-white">
                    {m.title}
                  </span>
                </div>
                <p className="text-[11px] text-white/50">{m.desc}</p>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
