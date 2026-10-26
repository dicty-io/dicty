import React, { useState, useRef } from "react";
import {
  UploadCloud,
  FileAudio,
  Copy,
  Check,
  RefreshCw,
  Sparkles,
  Layers,
  Languages,
} from "lucide-react";

import { WHISPER_LANGUAGES } from "./ModelsView";
import { ToggleSwitch } from "../components/ToggleSwitch";
import { FeatureHelpButton } from "../components/FeatureHelpModal";

export const TranscribeFileView: React.FC = () => {
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [targetModel, setTargetModel] = useState("Use Active System Model");
  const [language, setLanguage] = useState("auto");
  const [generateTimestamps, setGenerateTimestamps] = useState(true);
  const [isProcessing, setIsProcessing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [transcriptionResult, setTranscriptionResult] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      setSelectedFile(e.dataTransfer.files[0]);
    }
  };

  const handleStartTranscription = () => {
    if (!selectedFile) return;
    setIsProcessing(true);
    setProgress(10);

    const interval = setInterval(() => {
      setProgress((prev) => {
        if (prev >= 90) {
          clearInterval(interval);
          setTimeout(() => {
            setIsProcessing(false);
            setProgress(100);
            setTranscriptionResult(
              `[00:00.00 -> 00:04.20] In this design review, we are validating the client-side architecture.\n` +
                `[00:04.50 -> 00:08.80] All backend inference remains localized in the local Python engine.\n` +
                `[00:09.10 -> 00:14.30] This ensures zero network latency and complete privacy for voice recordings.`
            );
          }, 800);
          return 90;
        }
        return prev + 20;
      });
    }, 400);
  };

  const handleCopy = () => {
    if (transcriptionResult) {
      navigator.clipboard.writeText(transcriptionResult);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-6 select-none">
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2.5">
            <h2 className="text-xl font-bold text-white tracking-tight">
              Transcribe Local File
            </h2>
            <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-[#5D6658] text-white shadow">
              PRO
            </span>
            <FeatureHelpButton topic="transcribe" label="File Transcription Guide" />
          </div>
          <p className="text-xs text-white/50 mt-1">
            Drop any audio or video recording to transcribe it with your active local Whisper model.
          </p>
        </div>
      </div>

      {/* Configuration Strip */}
      <div className="grid grid-cols-3 gap-4">
        <div className="p-3.5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-1.5">
          <label className="text-[11px] font-semibold text-white/60 flex items-center gap-1.5">
            <Layers className="w-3 h-3 text-[#87B996]" />
            <span>Model Override</span>
          </label>
          <select
            value={targetModel}
            onChange={(e) => setTargetModel(e.target.value)}
            disabled={isProcessing}
            className="w-full bg-black/40 border border-white/10 rounded-xl px-2.5 py-1.5 text-xs text-white focus:outline-none"
          >
            <option>Use Active System Model</option>
            <option>ggml-base.bin (Fastest)</option>
            <option>ggml-small.bin (Balanced)</option>
            <option>ggml-medium.bin (High Accuracy)</option>
            <option>distil-large-v3 (Cloud / Pro)</option>
          </select>
        </div>

        <div className="p-3.5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-1.5">
          <label className="text-[11px] font-semibold text-white/60 flex items-center gap-1.5">
            <Languages className="w-3 h-3 text-indigo-400" />
            <span>Spoken Language</span>
          </label>
          <select
            value={language}
            onChange={(e) => setLanguage(e.target.value)}
            disabled={isProcessing}
            className="w-full bg-black/40 border border-white/10 rounded-xl px-2.5 py-1.5 text-xs text-white focus:outline-none"
          >
            {WHISPER_LANGUAGES.map((l) => (
              <option key={l.code} value={l.code}>
                {l.name}
              </option>
            ))}
          </select>
        </div>

        <div className="p-3.5 rounded-2xl bg-white/[0.03] border border-white/10 flex items-center justify-between">
          <div>
            <label className="text-[11px] font-semibold text-white/80 block">
              Generate Timestamps
            </label>
            <span className="text-[10px] text-white/40 block">
              Include [mm:ss] subtitle offsets
            </span>
          </div>
          <ToggleSwitch
            size="sm"
            checked={generateTimestamps}
            onChange={setGenerateTimestamps}
            ariaLabel="Generate Timestamps"
          />
        </div>
      </div>

      {/* Drag & Drop File Zone (1:1 with TranscribeFileView.swift) */}
      <div
        onDragOver={(e) => e.preventDefault()}
        onDrop={handleDrop}
        onClick={() => fileInputRef.current?.click()}
        className={`p-10 rounded-3xl border-2 border-dashed transition-all cursor-pointer text-center space-y-3 ${
          selectedFile
            ? "bg-white/[0.05] border-[#5D6658]"
            : "bg-white/[0.02] border-white/15 hover:border-white/30 hover:bg-white/[0.04]"
        }`}
      >
        <input
          ref={fileInputRef}
          type="file"
          accept="audio/*,video/*"
          className="hidden"
          onChange={(e) => {
            if (e.target.files?.[0]) setSelectedFile(e.target.files[0]);
          }}
        />

        <div className="w-14 h-14 rounded-2xl bg-white/[0.04] border border-white/10 flex items-center justify-center mx-auto text-[#87B996]">
          {selectedFile ? <FileAudio className="w-7 h-7 text-emerald-400" /> : <UploadCloud className="w-7 h-7" />}
        </div>

        <div>
          {selectedFile ? (
            <div>
              <span className="text-sm font-bold text-white block">
                {selectedFile.name}
              </span>
              <span className="text-xs text-white/40 block mt-0.5">
                {(selectedFile.size / (1024 * 1024)).toFixed(2)} MB • Ready to transcribe
              </span>
            </div>
          ) : (
            <div>
              <span className="text-sm font-semibold text-white block">
                Drop audio or video file here, or click to browse
              </span>
              <span className="text-xs text-white/40 block mt-1">
                Supports MP3, WAV, M4A, MP4, MOV, FLAC up to 500 MB
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Process Button & Progress */}
      {selectedFile && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <button
              onClick={handleStartTranscription}
              disabled={isProcessing}
              className="px-6 py-2.5 rounded-xl bg-gradient-to-r from-[#5D6658] to-[#278C40] hover:brightness-110 text-white text-xs font-bold shadow-lg shadow-[#278C40]/20 flex items-center gap-2 transition-all"
            >
              {isProcessing ? (
                <>
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                  <span>Transcribing Audio ({progress}%)...</span>
                </>
              ) : (
                <>
                  <Sparkles className="w-3.5 h-3.5" />
                  <span>Start Transcription</span>
                </>
              )}
            </button>

            {selectedFile && !isProcessing && (
              <button
                onClick={() => {
                  setSelectedFile(null);
                  setTranscriptionResult(null);
                }}
                className="text-xs text-white/40 hover:text-white"
              >
                Clear file
              </button>
            )}
          </div>

          {isProcessing && (
            <div className="w-full bg-white/10 rounded-full h-1.5 overflow-hidden">
              <div
                className="bg-gradient-to-r from-[#5D6658] to-emerald-400 h-full transition-all duration-300"
                style={{ width: `${progress}%` }}
              />
            </div>
          )}
        </div>
      )}

      {/* Result Container */}
      {transcriptionResult && (
        <div className="p-5 rounded-2xl bg-white/[0.04] border border-white/15 space-y-3 shadow-xl">
          <div className="flex items-center justify-between border-b border-white/10 pb-3">
            <div className="flex items-center gap-2 text-xs font-bold text-white">
              <Sparkles className="w-3.5 h-3.5 text-emerald-400" />
              <span>Transcription Output</span>
            </div>
            <button
              onClick={handleCopy}
              className="px-3 py-1 rounded-lg bg-white/[0.06] hover:bg-white/10 text-white text-xs font-medium flex items-center gap-1.5 transition-all"
            >
              {copied ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
              <span>{copied ? "Copied" : "Copy Text"}</span>
            </button>
          </div>

          <div className="font-mono text-xs text-white/90 leading-relaxed whitespace-pre-wrap select-text max-h-60 overflow-y-auto pr-2">
            {transcriptionResult}
          </div>
        </div>
      )}
    </div>
  );
};
