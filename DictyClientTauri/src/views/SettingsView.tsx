import React, { useState } from "react";
import {
  Keyboard,
  Mic,
  Shield,
  FileText,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { ToggleSwitch } from "../components/ToggleSwitch";
import type { DictationFormatStyle } from "../types/engine";

export const SettingsView: React.FC = () => {
  const [hotkeyCombo] = useState("Ctrl + Space");
  const [hotkeyBehavior, setHotkeyBehavior] = useState<"toggle" | "hold">("hold");
  const [autoPaste, setAutoPaste] = useState(true);
  const [incognitoMode, setIncognitoMode] = useState(false);
  const [launchAtStartup, setLaunchAtStartup] = useState(true);

  const [dictationStyle, setDictationStyle] = useState<DictationFormatStyle>("punctuation_fast");
  const [customPrompt, setCustomPrompt] = useState(
    "Format with clean developer syntax, preserving camelCase and markdown formatting."
  );

  const [audioDevice, setAudioDevice] = useState("-1");

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-6 select-none">
      <SettingsPageHeader
        title="Preferences & Shortcuts"
        description="Configure your global hotkeys, active audio input, and clipboard auto-paste."
      />

      {/* Global Shortcut */}
      <div className="dicty-card p-5 space-y-3">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <Keyboard className="w-3.5 h-3.5 text-[#87B996]" />
          <span>Global Shortcut</span>
        </h3>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-[11px] font-medium text-white/60 mb-1">
              Record Hotkey
            </label>
            <div className="flex items-center justify-between px-3 py-2 rounded-xl bg-black/40 border border-white/10 text-xs text-white">
              <span className="font-mono">{hotkeyCombo}</span>
              <span className="text-[10px] text-white/40 uppercase font-semibold">Global Win32 Hook</span>
            </div>
          </div>

          <div>
            <label className="block text-[11px] font-medium text-white/60 mb-1">
              Trigger Behavior
            </label>
            <div className="flex gap-2">
              <button
                onClick={() => setHotkeyBehavior("hold")}
                className={`flex-1 py-1.5 rounded-lg text-xs font-medium transition-all ${
                  hotkeyBehavior === "hold"
                    ? "bg-[#5D6658] text-white shadow-sm"
                    : "bg-white/5 text-white/60 hover:text-white"
                }`}
              >
                Hold to Talk (Default)
              </button>
              <button
                onClick={() => setHotkeyBehavior("toggle")}
                className={`flex-1 py-1.5 rounded-lg text-xs font-medium transition-all ${
                  hotkeyBehavior === "toggle"
                    ? "bg-[#5D6658] text-white shadow-sm"
                    : "bg-white/5 text-white/60 hover:text-white"
                }`}
              >
                Toggle (Start / Stop)
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Dictation Format Style */}
      <div className="dicty-card p-5 space-y-3">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <FileText className="w-3.5 h-3.5 text-[#87B996]" />
          <span>Default Formatting Style</span>
        </h3>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
          {[
            { id: "punctuation_fast" as DictationFormatStyle, label: "Fast Punctuation", desc: "0ms latency" },
            { id: "raw" as DictationFormatStyle, label: "Raw Transcript", desc: "Verbatim speech" },
            { id: "email" as DictationFormatStyle, label: "Email", desc: "Professional tone" },
            { id: "note" as DictationFormatStyle, label: "Structured Note", desc: "Bulleted points" },
            { id: "book" as DictationFormatStyle, label: "Prose / Book", desc: "Literary rhythm" },
            { id: "message" as DictationFormatStyle, label: "Chat Message", desc: "Casual & short" },
            { id: "custom" as DictationFormatStyle, label: "Custom Prompt", desc: "LLM rule" },
          ].map((style) => (
            <button
              key={style.id}
              onClick={() => setDictationStyle(style.id)}
              className={`p-2.5 rounded-xl text-left border transition-all ${
                dictationStyle === style.id
                  ? "bg-[#5D6658]/20 border-[#5D6658] text-white"
                  : "bg-white/[0.02] border-white/5 text-white/60 hover:text-white"
              }`}
            >
              <div className="font-semibold text-xs text-white">{style.label}</div>
              <div className="text-[10px] text-white/40">{style.desc}</div>
            </button>
          ))}
        </div>

        {dictationStyle === "custom" && (
          <div className="pt-2">
            <textarea
              value={customPrompt}
              onChange={(e) => setCustomPrompt(e.target.value)}
              rows={2}
              className="w-full bg-black/40 border border-white/10 rounded-xl p-2.5 text-xs text-white focus:outline-none focus:border-[#5D6658]"
            />
          </div>
        )}
      </div>

      {/* Audio Hardware */}
      <div className="dicty-card p-5 space-y-3">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <Mic className="w-3.5 h-3.5 text-[#87B996]" />
          <span>Audio Hardware (WASAPI)</span>
        </h3>

        <div>
          <label className="block text-[11px] font-medium text-white/60 mb-1">
            Microphone Device
          </label>
          <select
            value={audioDevice}
            onChange={(e) => setAudioDevice(e.target.value)}
            className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:outline-none"
          >
            <option value="-1">System Default Microphone (Dynamic)</option>
            <option value="0">Microphone Array (Realtek Audio)</option>
            <option value="1">External USB Microphone</option>
          </select>
        </div>
      </div>

      {/* Toggles */}
      <div className="dicty-card p-5 space-y-3">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <Shield className="w-3.5 h-3.5 text-[#87B996]" />
          <span>Clipboard & System</span>
        </h3>

        <div className="space-y-3 divide-y divide-white/5">
          <div className="flex items-center justify-between pt-1">
            <div>
              <div className="text-xs font-semibold text-white">
                Auto-Paste into Focused App (Ctrl+V)
              </div>
              <div className="text-[11px] text-white/50">
                Transcribes, injects text into your cursor, and restores original clipboard.
              </div>
            </div>
            <ToggleSwitch
              checked={autoPaste}
              onChange={setAutoPaste}
              ariaLabel="Auto-Paste into Focused App"
            />
          </div>

          <div className="flex items-center justify-between pt-2.5">
            <div>
              <div className="text-xs font-semibold text-white">
                Incognito Mode
              </div>
              <div className="text-[11px] text-white/50">
                Audio is transcribed exclusively in volatile RAM — zero history is saved.
              </div>
            </div>
            <ToggleSwitch
              checked={incognitoMode}
              onChange={setIncognitoMode}
              ariaLabel="Incognito Mode"
            />
          </div>

          <div className="flex items-center justify-between pt-2.5">
            <div>
              <div className="text-xs font-semibold text-white">
                Launch at Windows Startup
              </div>
              <div className="text-[11px] text-white/50">
                Starts Dicty silently in the system tray when Windows boots.
              </div>
            </div>
            <ToggleSwitch
              checked={launchAtStartup}
              onChange={setLaunchAtStartup}
              ariaLabel="Launch at Windows Startup"
            />
          </div>
        </div>
      </div>
    </div>
  );
};
