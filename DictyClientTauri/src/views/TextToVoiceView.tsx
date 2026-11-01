import React, { useState, useRef } from "react";
import {
  Volume2,
  Play,
  Square,
  AudioWaveform,
  Globe,
  CheckCircle2,
  RefreshCw,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { engineFetch } from "../services/engineClient";

interface VoiceModel {
  id: string;
  name: string;
  gender: "female" | "male";
  accent: string;
  flag: string;
}

const KOKORO_VOICES: VoiceModel[] = [
  { id: "af_heart", name: "Heart (Warm & Natural)", gender: "female", accent: "American", flag: "🇺🇸" },
  { id: "am_adam", name: "Adam (Deep & Narrator)", gender: "male", accent: "American", flag: "🇺🇸" },
  { id: "bf_emma", name: "Emma (Clear & Conversational)", gender: "female", accent: "British", flag: "🇬🇧" },
  { id: "bm_george", name: "George (Articulate & Professional)", gender: "male", accent: "British", flag: "🇬🇧" },
  { id: "af_bella", name: "Bella (Expressive)", gender: "female", accent: "American", flag: "🇺🇸" },
  { id: "am_michael", name: "Michael (Energetic)", gender: "male", accent: "American", flag: "🇺🇸" },
];

export const TextToVoiceView: React.FC = () => {
  const [activeEngine, setActiveEngine] = useState<"kokoro" | "system">("kokoro");
  const [selectedVoice, setSelectedVoice] = useState<string>("af_heart");
  const [playbackSpeed, setPlaybackSpeed] = useState<number>(1.0);
  const [saveToHistory, setSaveToHistory] = useState<boolean>(false);
  const [sampleText, setSampleText] = useState<string>(
    "Dicty transforms written text into clear, natural speech. Adjust cadence, timing, and voice persona to hear the difference immediately."
  );
  const [isGenerating, setIsGenerating] = useState<boolean>(false);
  const [isPlaying, setIsPlaying] = useState<boolean>(false);

  const audioRef = useRef<HTMLAudioElement | null>(null);

  const handleSpeak = async () => {
    if (isPlaying) {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.currentTime = 0;
      }
      setIsPlaying(false);
      return;
    }

    if (!sampleText.trim()) return;

    setIsGenerating(true);
    try {
      // Send synthesis request to Dicty engine
      const res = await engineFetch("/tts/synthesize", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text: sampleText,
          voice: selectedVoice,
          engine: activeEngine,
          speed: playbackSpeed,
          save_history: saveToHistory,
        }),
      });

      if (res.ok) {
        const blob = await res.blob();
        const audioUrl = URL.createObjectURL(blob);
        if (audioRef.current) {
          audioRef.current.src = audioUrl;
          audioRef.current.playbackRate = playbackSpeed;
          audioRef.current.play();
          setIsPlaying(true);
        }
      } else {
        // Fallback: Web Speech API synthesis if local neural TTS engine is not compiled on this host
        if ("speechSynthesis" in window) {
          const utterance = new SpeechSynthesisUtterance(sampleText);
          utterance.rate = playbackSpeed;
          utterance.onend = () => setIsPlaying(false);
          utterance.onerror = () => setIsPlaying(false);
          window.speechSynthesis.cancel();
          window.speechSynthesis.speak(utterance);
          setIsPlaying(true);
        }
      }
    } catch {
      // Fallback to browser Web Speech API
      if ("speechSynthesis" in window) {
        const utterance = new SpeechSynthesisUtterance(sampleText);
        utterance.rate = playbackSpeed;
        utterance.onend = () => setIsPlaying(false);
        utterance.onerror = () => setIsPlaying(false);
        window.speechSynthesis.cancel();
        window.speechSynthesis.speak(utterance);
        setIsPlaying(true);
      }
    } finally {
      setIsGenerating(false);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-7 select-none">
      <SettingsPageHeader
        title="Text-to-Voice (TTS)"
        description="Transform written articles, documentation, or highlighted sentences into lifelike speech with neural personas."
      />

      <audio
        ref={audioRef}
        onEnded={() => setIsPlaying(false)}
        onError={() => setIsPlaying(false)}
        className="hidden"
      />

      {/* Engine Architecture Switcher */}
      <div className="p-5 rounded-2xl bg-white/[0.025] border border-white/10 space-y-3">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <AudioWaveform className="w-4 h-4 text-[#87B996]" />
          <span>Neural Speech Engine</span>
        </h3>

        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => setActiveEngine("kokoro")}
            className={`p-3.5 rounded-xl border text-left transition-all ${
              activeEngine === "kokoro"
                ? "bg-[#5D6658]/30 border-[#87B996]/50 shadow-sm"
                : "bg-white/[0.02] border-white/10 hover:border-white/20"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-white">Kokoro Neural</span>
              {activeEngine === "kokoro" && (
                <CheckCircle2 className="w-3.5 h-3.5 text-[#87B996]" />
              )}
            </div>
            <p className="text-[11px] text-white/50 mt-1">
              82M parameter lightweight transformer for ultra-fast, natural voice cadence.
            </p>
          </button>

          <button
            onClick={() => setActiveEngine("system")}
            className={`p-3.5 rounded-xl border text-left transition-all ${
              activeEngine === "system"
                ? "bg-[#5D6658]/30 border-[#87B996]/50 shadow-sm"
                : "bg-white/[0.02] border-white/10 hover:border-white/20"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-white">Windows SAPI / System</span>
              {activeEngine === "system" && (
                <CheckCircle2 className="w-3.5 h-3.5 text-[#87B996]" />
              )}
            </div>
            <p className="text-[11px] text-white/50 mt-1">
              Zero-latency native Windows voice synthesizer.
            </p>
          </button>
        </div>
      </div>

      {/* Voice Personas */}
      <div className="p-5 rounded-2xl bg-white/[0.025] border border-white/10 space-y-3">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <Globe className="w-4 h-4 text-[#87B996]" />
          <span>Voice Persona</span>
        </h3>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
          {KOKORO_VOICES.map((v) => {
            const isSelected = selectedVoice === v.id;
            return (
              <button
                key={v.id}
                onClick={() => setSelectedVoice(v.id)}
                className={`p-3 rounded-xl border text-left flex items-center justify-between transition-all ${
                  isSelected
                    ? "bg-[#5D6658]/30 border-[#87B996]/50 shadow-sm text-white"
                    : "bg-white/[0.02] border-white/10 text-white/70 hover:bg-white/[0.04]"
                }`}
              >
                <div className="flex items-center gap-2.5">
                  <span className="text-base">{v.flag}</span>
                  <div>
                    <div className="text-xs font-semibold text-white">{v.name}</div>
                    <div className="text-[10px] text-white/45">
                      {v.accent} · {v.gender}
                    </div>
                  </div>
                </div>
                {isSelected && <CheckCircle2 className="w-4 h-4 text-[#87B996]" />}
              </button>
            );
          })}
        </div>
      </div>

      {/* Interactive Speech Studio */}
      <div className="p-5 rounded-2xl bg-white/[0.025] border border-white/10 space-y-4">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <Volume2 className="w-4 h-4 text-[#87B996]" />
          <span>Speech Studio & Preview</span>
        </h3>

        <textarea
          value={sampleText}
          onChange={(e) => setSampleText(e.target.value)}
          rows={3}
          placeholder="Enter text to synthesize into speech..."
          className="w-full bg-black/40 border border-white/10 rounded-xl p-3 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658] resize-none leading-relaxed"
        />

        <div className="flex flex-wrap items-center justify-between gap-4 pt-1">
          {/* Cadence Speed Control & History Option */}
          <div className="flex items-center gap-6">
            <div className="flex items-center gap-3">
              <span className="text-[11px] font-medium text-white/60">Speed:</span>
              <input
                type="range"
                min="0.5"
                max="2.0"
                step="0.05"
                value={playbackSpeed}
                onChange={(e) => setPlaybackSpeed(parseFloat(e.target.value))}
                className="w-28 accent-[#87B996] cursor-pointer"
              />
              <span className="text-xs font-mono font-bold text-white w-10">
                {playbackSpeed.toFixed(2)}x
              </span>
            </div>

            <label className="flex items-center gap-2 cursor-pointer text-[11px] text-white/60 hover:text-white">
              <input
                type="checkbox"
                checked={saveToHistory}
                onChange={(e) => setSaveToHistory(e.target.checked)}
                className="rounded accent-[#87B996] cursor-pointer"
              />
              <span>Save to History</span>
            </label>
          </div>

          {/* Action Trigger */}
          <button
            onClick={handleSpeak}
            disabled={isGenerating || !sampleText.trim()}
            className="px-5 py-2.5 rounded-xl bg-[#5D6658] hover:bg-[#6c7766] disabled:opacity-50 text-white text-xs font-semibold shadow-md flex items-center gap-2 transition-all"
          >
            {isGenerating ? (
              <>
                <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                <span>Synthesizing...</span>
              </>
            ) : isPlaying ? (
              <>
                <Square className="w-3.5 h-3.5 fill-current" />
                <span>Stop Playback</span>
              </>
            ) : (
              <>
                <Play className="w-3.5 h-3.5 fill-current" />
                <span>Speak Now</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
