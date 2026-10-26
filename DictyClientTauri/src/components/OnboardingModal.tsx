import React, { useState, useEffect, useRef } from "react";
import {
  Mic,
  Cpu,
  Cloud,
  Check,
  ArrowRight,
  ArrowLeft,
  Sparkles,
  Keyboard,
  ShieldCheck,
  CheckCircle2,
  AlertCircle,
  Square,
  Loader2,
  X,
  MessageSquare,
  Mail,
  Terminal,
  FileText,
  Laptop,
  Download,
} from "lucide-react";
import { engineApi } from "../services/engineApi";
import { modesStore, useModesStore } from "../services/modesStore";
import { listen } from "@tauri-apps/api/event";

interface OnboardingModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const TOTAL_STEPS = 6;

/// Apps most people type in, with the writing style Dicty should use there.
const TYPING_CHOICES: {
  id: string;
  name: string;
  icon: React.ComponentType<{ size?: number; className?: string }>;
  style: string;
}[] = [
  { id: "slack.exe", name: "Slack / chat", icon: MessageSquare, style: "message" },
  { id: "outlook.exe", name: "Email", icon: Mail, style: "email" },
  { id: "code.exe", name: "Code", icon: Terminal, style: "code" },
  { id: "notepad.exe", name: "Notes", icon: FileText, style: "note" },
];

export const OnboardingModal: React.FC<OnboardingModalProps> = ({ isOpen, onClose }) => {
  const [currentStep, setCurrentStep] = useState(0);
  const modesState = useModesStore();

  // --- Step 2: Mic Test State ---
  const [devices, setDevices] = useState<{ id: number; name: string }[]>([]);
  const [selectedDeviceId, setSelectedDeviceId] = useState<number>(-1);
  const [hasMicPermission, setHasMicPermission] = useState(false);
  const [audioLevels, setAudioLevels] = useState<number[]>(new Array(28).fill(8));
  const [detectedVoice, setDetectedVoice] = useState(false);
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const animFrameRef = useRef<number | null>(null);

  // --- Step 3: Model Selection & Starter Model State ---
  const [selectedModelType, setSelectedModelType] = useState<"local" | "cloud">("local");
  const [activeModelId, setActiveModelId] = useState("tiny.en");
  const [isModelReady, setIsModelReady] = useState(false);
  const [isModelDownloading, setIsModelDownloading] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(0);

  // --- Step 4: Where do you type most? ---
  const [typingApps, setTypingApps] = useState<Set<string>>(new Set());

  // --- Step 5: Private on this PC, or cloud when better? ---
  const [aiLocation, setAiLocation] = useState<"local" | "cloud_when_better">("local");
  const [offlineModels, setOfflineModels] = useState<
    { id: string; name: string; size?: string; is_downloaded?: boolean }[]
  >([]);
  const [modelDownloads, setModelDownloads] = useState<Record<string, number>>({});
  const downloadIntervalsRef = useRef<Record<string, number>>({});

  // --- Step 6: Shortcut Test & Sandbox State ---
  const [shortcutKey, setShortcutKey] = useState(() => {
    return localStorage.getItem("dicty_shortcut_toggle") || "Ctrl + Space";
  });
  const [isTestRecording, setIsTestRecording] = useState(false);
  const [isTestProcessing, setIsTestProcessing] = useState(false);
  const [transcribedText, setTranscribedText] = useState("");
  const [sandboxError, setSandboxError] = useState<string | null>(null);

  // Ensure starter model (tiny.en) is ready and pre-warmed for the onboarding sandbox
  const ensureStarterModelReady = async () => {
    try {
      const res = await engineApi.getModels();
      const models = res?.models || [];
      const activeRes = await engineApi.getActiveModel();
      const currentActive = activeRes?.active_model || "";

      // Windows fast starter model: 75 MB, ultra-fast <150ms startup
      const starterId = "tiny.en";

      // If active model is empty, cloud, or distil, default to local starter model for onboarding
      if (!currentActive || currentActive.includes("whisper-1") || currentActive.includes("openrouter") || currentActive.includes("/")) {
        setActiveModelId(starterId);
        setSelectedModelType("local");
        await engineApi.setActiveModel(starterId).catch(() => {});
      } else {
        setActiveModelId(currentActive);
        setSelectedModelType(currentActive.includes("/") ? "cloud" : "local");
      }

      // Check if starter model is downloaded in HF cache or local models dir
      const starterModel = models.find((m: any) => m.id === starterId || m.id === "tiny" || m.id === "base.en");
      const isDownloaded = starterModel?.is_downloaded === true;
      setIsModelReady(isDownloaded);

      if (isDownloaded) {
        // Pre-warm model onto GPU immediately so practice step has 0ms cold-start
        engineApi.prewarmModel(starterId).catch(() => {});
      } else {
        // Silently download the 75 MB starter model in the background if not already cached
        setIsModelDownloading(true);
        setDownloadProgress(15);
        engineApi.downloadModel(starterId).catch(() => {});
      }
    } catch (err) {
      console.warn("Failed to check starter model ready state:", err);
    }
  };

  // Load devices and ensure starter model on mount
  useEffect(() => {
    if (!isOpen) return;

    // Load available sound input devices from engine
    engineApi.getDevices().then((res) => {
      if (res && Array.isArray(res.devices)) {
        setDevices(res.devices);
      }
    }).catch(() => {});

    ensureStarterModelReady();
    modesStore.refresh();
  }, [isOpen]);

  // Poll download progress while starter model is downloading
  useEffect(() => {
    if (!isOpen || isModelReady) return;

    const interval = setInterval(async () => {
      try {
        const progressRes = await engineApi.getDownloadProgress();
        const prog = progressRes?.progress?.[activeModelId] ?? progressRes?.progress?.["tiny.en"] ?? 0;
        if (prog >= 100) {
          setIsModelDownloading(false);
          setIsModelReady(true);
          setDownloadProgress(100);
          engineApi.prewarmModel(activeModelId).catch(() => {});
        } else if (prog > 0) {
          setDownloadProgress(prog);
          setIsModelDownloading(true);
        } else {
          // Check getModels to see if download finished
          const modelsRes = await engineApi.getModels();
          const target = modelsRes?.models?.find((x: any) => x.id === activeModelId || x.id === "tiny.en" || x.id === "tiny");
          if (target?.is_downloaded) {
            setIsModelDownloading(false);
            setIsModelReady(true);
            setDownloadProgress(100);
          }
        }
      } catch {}
    }, 1000);

    return () => clearInterval(interval);
  }, [isOpen, isModelReady, activeModelId]);

  // Sync shortcut from localStorage
  useEffect(() => {
    const saved = localStorage.getItem("dicty_shortcut_toggle") || "Ctrl + Space";
    setShortcutKey(saved);
  }, [isOpen]);

  // --- Live Microphone Visualizer (Step 1) ---
  const startMicMonitoring = async () => {
    try {
      if (mediaStreamRef.current) {
        mediaStreamRef.current.getTracks().forEach((t) => t.stop());
      }
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaStreamRef.current = stream;
      setHasMicPermission(true);

      const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
      const ctx = new AudioContextClass();
      audioContextRef.current = ctx;

      const analyser = ctx.createAnalyser();
      analyser.fftSize = 64;
      analyserRef.current = analyser;

      const source = ctx.createMediaStreamSource(stream);
      source.connect(analyser);

      const dataArray = new Uint8Array(analyser.frequencyBinCount);

      const updateMeter = () => {
        if (!analyserRef.current) return;
        analyserRef.current.getByteFrequencyData(dataArray);

        let sum = 0;
        const newLevels = Array.from({ length: 28 }, (_, i) => {
          const val = dataArray[i] || 0;
          sum += val;
          return Math.max(8, Math.min(42, (val / 255) * 42));
        });

        setAudioLevels(newLevels);
        if (sum / dataArray.length > 15) {
          setDetectedVoice(true);
        }

        animFrameRef.current = requestAnimationFrame(updateMeter);
      };

      updateMeter();
    } catch (err) {
      console.warn("Microphone access denied or unavailable in webview:", err);
      setHasMicPermission(false);
    }
  };

  const stopMicMonitoring = () => {
    if (animFrameRef.current) {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = null;
    }
    if (mediaStreamRef.current) {
      mediaStreamRef.current.getTracks().forEach((t) => t.stop());
      mediaStreamRef.current = null;
    }
    if (audioContextRef.current && audioContextRef.current.state !== "closed") {
      audioContextRef.current.close().catch(() => {});
      audioContextRef.current = null;
    }
    setAudioLevels(new Array(28).fill(8));
  };

  useEffect(() => {
    if (isOpen && currentStep === 1) {
      startMicMonitoring();
    } else {
      stopMicMonitoring();
    }
    return () => {
      stopMicMonitoring();
    };
  }, [isOpen, currentStep]);

  // --- Listen to global hotkey events for Step 6 ---
  useEffect(() => {
    if (!isOpen || currentStep !== 5) return;

    let unlisten: (() => void) | undefined;
    listen<{ is_recording: boolean; is_paused?: boolean; status?: string; text?: string; message?: string; error?: string }>(
      "dicty:recording-state-changed",
      (event) => {
        const payload = event.payload;
        if (payload.is_recording) {
          setIsTestRecording(true);
          setIsTestProcessing(false);
          setSandboxError(null);
        } else if (payload.status === "processing") {
          setIsTestRecording(false);
          setIsTestProcessing(true);
        } else {
          setIsTestRecording(false);
          setIsTestProcessing(false);
          if (payload.text && payload.text.trim()) {
            setTranscribedText(payload.text.trim());
            setSandboxError(null);
          } else if (payload.message) {
            setSandboxError(payload.message);
          } else if (payload.error) {
            setSandboxError(payload.error);
          }
        }
      }
    ).then((fn) => {
      unlisten = fn;
    });

    return () => {
      if (unlisten) unlisten();
    };
  }, [isOpen, currentStep]);

  // Handle Model Selection
  const handleSelectModel = (type: "local" | "cloud") => {
    setSelectedModelType(type);
    const targetId = type === "local" ? "tiny.en" : "openai/whisper-1";
    setActiveModelId(targetId);
    engineApi.setActiveModel(targetId).catch(() => {});
    if (type === "local") {
      engineApi.prewarmModel(targetId).catch(() => {});
      engineApi.getModels().then((res) => {
        const m = res?.models?.find((x: any) => x.id === targetId || x.id === "tiny" || x.id === "base.en");
        if (m?.is_downloaded) {
          setIsModelReady(true);
          setIsModelDownloading(false);
          engineApi.prewarmModel(targetId).catch(() => {});
        } else {
          setIsModelReady(false);
          setIsModelDownloading(true);
          engineApi.downloadModel(targetId).catch(() => {});
        }
      }).catch(() => {});
    }
  };

  // Pre-warm active model as soon as user navigates to model selection or practice step
  useEffect(() => {
    if (isOpen && currentStep >= 2 && selectedModelType === "local") {
      engineApi.prewarmModel(activeModelId).catch(() => {});
    }
  }, [isOpen, currentStep, activeModelId, selectedModelType]);

  // Handle Manual Test Recording Toggle
  const handleToggleTestRecord = async () => {
    if (isTestRecording) {
      setIsTestRecording(false);
      setIsTestProcessing(true);
      setSandboxError(null);
      try {
        const res = await engineApi.stopRecording();
        setIsTestProcessing(false);
        if (res && res.text && res.text.trim()) {
          const text = res.text.trim();
          setTranscribedText(text);
          setSandboxError(null);
          try {
            await navigator.clipboard.writeText(text);
          } catch {}
        } else if (res && res.status === "ignored") {
          setSandboxError("Audio was too quiet or background noise. Speak a sentence clearly into your mic!");
        } else if (res && res.status === "error") {
          setSandboxError(res.message || "Transcription failed. Please check your mic and try again.");
        } else {
          // Check clipboard fallback (identical to macOS OnboardingView)
          try {
            const clip = await navigator.clipboard.readText();
            if (clip && clip.trim() && clip !== transcribedText) {
              setTranscribedText(clip.trim());
              setSandboxError(null);
            } else {
              setSandboxError("No clear speech detected. Speak a sentence and click Stop Recording.");
            }
          } catch {
            setSandboxError("No clear speech detected. Speak a sentence and click Stop Recording.");
          }
        }
      } catch (err: any) {
        setIsTestProcessing(false);
        setSandboxError(err?.message || "Communication with Dicty engine failed. Please try again.");
      }
    } else {
      setIsTestRecording(true);
      setIsTestProcessing(false);
      setSandboxError(null);
      try {
        await engineApi.startRecording({ mode: "dictation" });
      } catch {
        setIsTestRecording(false);
        setSandboxError("Could not start recording. Check microphone permissions in Step 2.");
      }
    }
  };

  // --- Step 5: models worth having when "On this PC" is chosen ---
  useEffect(() => {
    if (!isOpen || currentStep !== 4) return;
    modesStore.refresh();
    engineApi
      .getModels()
      .then((res) => {
        const models = res?.models || [];
        let active = "base.en";
        try {
          active = localStorage.getItem("dicty_active_model") || "base.en";
        } catch {}
        const ids = Array.from(new Set<string>([active, "base.en", "qwen2.5-1.5b-instruct"]));
        setOfflineModels(
          ids.map((id) => {
            const found = models.find((m: any) => m.id === id);
            return found || { id, name: id, size: "", is_downloaded: false };
          })
        );
      })
      .catch(() => {});

    return () => {
      Object.values(downloadIntervalsRef.current).forEach((handle) => clearInterval(handle));
      downloadIntervalsRef.current = {};
    };
  }, [isOpen, currentStep]);

  const downloadOfflineModel = (id: string) => {
    engineApi.downloadModel(id).catch(() => {});
    setModelDownloads((prev) => ({ ...prev, [id]: prev[id] ?? 1 }));
    if (downloadIntervalsRef.current[id]) return;
    downloadIntervalsRef.current[id] = window.setInterval(async () => {
      try {
        const res = await engineApi.getDownloadProgress();
        const prog = res?.progress?.[id];
        if (typeof prog === "number" && prog > 0) {
          setModelDownloads((prev) => ({ ...prev, [id]: prog }));
          if (prog >= 100) {
            clearInterval(downloadIntervalsRef.current[id]);
            delete downloadIntervalsRef.current[id];
            setOfflineModels((prev) =>
              prev.map((m) => (m.id === id ? { ...m, is_downloaded: true } : m))
            );
          }
        } else {
          const modelsRes = await engineApi.getModels();
          const found = modelsRes?.models?.find((m: any) => m.id === id);
          if (found?.is_downloaded) {
            clearInterval(downloadIntervalsRef.current[id]);
            delete downloadIntervalsRef.current[id];
            setOfflineModels((prev) =>
              prev.map((m) => (m.id === id ? { ...m, is_downloaded: true } : m))
            );
          }
        }
      } catch {}
    }, 1000);
  };

  // --- Step 4: turn the picked apps into app rules ---
  const applyTypingApps = async () => {
    if (typingApps.size === 0) return;
    const dictationModes = modesState.engineModes.filter((mode) => mode.kind === "dictation");
    for (const choice of TYPING_CHOICES) {
      if (!typingApps.has(choice.id)) continue;
      const mode = dictationModes.find((m) => m.style === choice.style) || dictationModes[0];
      if (mode?.id) await modesStore.addAppRule(choice.id, choice.name, mode.id);
    }
  };

  const handleContinue = async () => {
    if (currentStep === 3) await applyTypingApps();
    if (currentStep === 4) await modesStore.setAILocation(aiLocation);
    setCurrentStep((prev) => prev + 1);
  };

  // Complete Onboarding
  const handleComplete = () => {
    localStorage.setItem("dicty_has_seen_onboarding", "true");
    localStorage.setItem("dicty_onboarding_version", "1.0.0");
    stopMicMonitoring();
    onClose();
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md animate-in fade-in duration-200">
      {/* Modal Card with Glassmorphism & Ambient Glow */}
      <div className="relative w-[780px] h-[600px] max-h-[92vh] rounded-2xl bg-[#16181D]/95 border border-white/15 shadow-2xl flex flex-col overflow-hidden text-white select-none">
        {/* Glowing ambient background orbs */}
        <div
          className="absolute -top-24 -left-20 w-80 h-80 rounded-full blur-[90px] pointer-events-none"
          style={{ background: "rgba(74, 101, 114, 0.28)" }}
        />
        <div
          className="absolute -bottom-24 -right-20 w-80 h-80 rounded-full blur-[90px] pointer-events-none"
          style={{ background: "rgba(93, 102, 88, 0.32)" }}
        />

        {/* Top Header & Progress Bar (Fixed) */}
        <div className="relative z-10 px-8 pt-6 pb-4 flex flex-col gap-3.5 border-b border-white/10 shrink-0">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <span className="w-2.5 h-2.5 rounded-full bg-[#87B996] shadow-[0_0_8px_rgba(135,185,150,0.8)]" />
              <span className="text-xs uppercase tracking-widest font-bold text-white/60">
                Dicty Setup Guide • Step {currentStep + 1} of {TOTAL_STEPS}
              </span>
            </div>
            <button
              onClick={handleComplete}
              className="text-white/40 hover:text-white/80 transition-colors p-1 rounded-lg hover:bg-white/10"
              title="Skip setup"
            >
              <X size={18} />
            </button>
          </div>

          {/* 4-Step Progress Segments */}
          <div className="flex items-center gap-2">
            {Array.from({ length: TOTAL_STEPS }, (_, idx) => (
              <div
                key={idx}
                className="flex-1 h-1.5 rounded-full transition-all duration-300"
                style={{
                  background:
                    idx <= currentStep
                      ? "linear-gradient(90deg, #87B996, #5D6658)"
                      : "rgba(255, 255, 255, 0.12)",
                }}
              />
            ))}
          </div>
        </div>

        {/* Main Content Area (Scrollable Body) */}
        <div className="relative z-10 flex-1 min-h-0 px-8 py-5 flex flex-col overflow-y-auto">
          {/* STEP 0: Welcome & Architecture */}
          {currentStep === 0 && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-semibold text-[#87B996]">
                <Sparkles size={14} />
                <span>Welcome to Dicty</span>
              </div>
              <h2 className="text-2xl font-bold tracking-tight text-white">
                Speech-to-Text, Everywhere.
              </h2>
              <p className="text-sm text-white/70 leading-relaxed max-w-xl">
                Dicty converts your voice into text in real time and automatically types it into any Windows application at your cursor.
              </p>

              {/* 3 Pillars */}
              <div className="grid grid-cols-3 gap-3.5 pt-2">
                <div className="p-4 rounded-xl bg-white/[0.04] border border-white/10 flex flex-col gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-[#5D6658]/30 flex items-center justify-center text-[#87B996]">
                    <Keyboard size={18} />
                  </div>
                  <h3 className="text-sm font-semibold text-white">Global Shortcut</h3>
                  <p className="text-xs text-white/60 leading-relaxed">
                    Press <code className="px-1 py-0.5 rounded bg-white/10 text-white font-mono text-[11px]">{shortcutKey}</code> anywhere to instantly begin dictating.
                  </p>
                </div>

                <div className="p-4 rounded-xl bg-white/[0.04] border border-white/10 flex flex-col gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-[#4A6572]/30 flex items-center justify-center text-[#A4C4D3]">
                    <Cpu size={18} />
                  </div>
                  <h3 className="text-sm font-semibold text-white">100% Offline AI</h3>
                  <p className="text-xs text-white/60 leading-relaxed">
                    Audio is processed locally in RAM on your PC. Complete privacy with zero cloud latency.
                  </p>
                </div>

                <div className="p-4 rounded-xl bg-white/[0.04] border border-white/10 flex flex-col gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-emerald-500/20 flex items-center justify-center text-emerald-400">
                    <ShieldCheck size={18} />
                  </div>
                  <h3 className="text-sm font-semibold text-white">System Tray</h3>
                  <p className="text-xs text-white/60 leading-relaxed">
                    Closing the window minimizes Dicty quietly to the taskbar tray near your system clock.
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* STEP 1: Microphone Test */}
          {currentStep === 1 && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-semibold text-[#87B996]">
                <Mic size={14} />
                <span>Microphone Check</span>
              </div>
              <h2 className="text-2xl font-bold tracking-tight text-white">
                Test your microphone
              </h2>
              <p className="text-sm text-white/70 leading-relaxed">
                Speak aloud to verify Dicty detects your voice. If the waveform below doesn't move, select your primary microphone from the list.
              </p>

              {/* Device Selector */}
              <div className="flex items-center gap-3 pt-1">
                <span className="text-xs font-medium text-white/60">Input Device:</span>
                <select
                  value={selectedDeviceId}
                  onChange={(e) => setSelectedDeviceId(Number(e.target.value))}
                  className="bg-white/10 border border-white/15 text-white text-xs rounded-lg px-3 py-1.5 outline-none focus:border-[#87B996] transition-colors max-w-sm"
                >
                  <option value={-1} className="bg-[#1a1d24] text-white">
                    System Default Microphone
                  </option>
                  {devices.map((d) => (
                    <option key={d.id} value={d.id} className="bg-[#1a1d24] text-white">
                      {d.name}
                    </option>
                  ))}
                </select>
              </div>

              {/* Live Waveform Visualizer Box */}
              <div className="p-5 rounded-2xl bg-black/30 border border-white/10 flex flex-col items-center justify-center gap-3.5 min-h-[130px] relative overflow-hidden">
                {!hasMicPermission ? (
                  <div className="flex flex-col items-center gap-2.5 text-center">
                    <AlertCircle className="text-amber-400" size={24} />
                    <p className="text-xs text-white/70">
                      Click below to grant Dicty permission to monitor microphone levels.
                    </p>
                    <button
                      onClick={startMicMonitoring}
                      className="px-4 py-1.5 rounded-lg bg-white/10 hover:bg-white/15 text-xs font-semibold text-white transition-colors"
                    >
                      Enable Microphone Access
                    </button>
                  </div>
                ) : (
                  <>
                    {/* Animated Equalizer Bars */}
                    <div className="flex items-center justify-center gap-1.5 h-11 w-full max-w-md">
                      {audioLevels.map((lvl, i) => (
                        <div
                          key={i}
                          className="w-2 rounded-full transition-all duration-75"
                          style={{
                            height: `${lvl}px`,
                            background: detectedVoice
                              ? "linear-gradient(180deg, #87B996 0%, #4A6572 100%)"
                              : "rgba(255, 255, 255, 0.2)",
                          }}
                        />
                      ))}
                    </div>

                    {/* Status indicator */}
                    <div className="flex items-center gap-2 text-xs font-medium">
                      {detectedVoice ? (
                        <span className="flex items-center gap-1.5 text-emerald-400">
                          <CheckCircle2 size={14} />
                          <span>Voice signal detected! Your microphone is working cleanly.</span>
                        </span>
                      ) : (
                        <span className="text-white/50">
                          Listening... Speak a few words into your mic to test.
                        </span>
                      )}
                    </div>
                  </>
                )}
              </div>
            </div>
          )}

          {/* STEP 2: Model Selection */}
          {currentStep === 2 && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-semibold text-[#87B996]">
                <Cpu size={14} />
                <span>AI Speech Engine</span>
              </div>
              <h2 className="text-2xl font-bold tracking-tight text-white">
                Choose your transcription engine
              </h2>
              <p className="text-sm text-white/70 leading-relaxed">
                Dicty can process your voice entirely on your PC for maximum privacy, or connect to cloud models for specialized vocabulary.
              </p>

              {/* Cards */}
              <div className="grid grid-cols-2 gap-4 pt-1">
                {/* On-Device Card */}
                <div
                  onClick={() => handleSelectModel("local")}
                  className={`p-5 rounded-2xl border cursor-pointer transition-all flex flex-col justify-between min-h-[200px] ${
                    selectedModelType === "local"
                      ? "bg-[#5D6658]/25 border-[#87B996] ring-1 ring-[#87B996]/40 shadow-lg"
                      : "bg-white/[0.03] border-white/10 hover:border-white/20 hover:bg-white/[0.05]"
                  }`}
                >
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="w-10 h-10 rounded-xl bg-[#5D6658]/40 flex items-center justify-center text-[#87B996]">
                        <Cpu size={22} />
                      </div>
                      <span className="px-2.5 py-0.5 rounded-full bg-[#87B996]/20 text-[#87B996] text-[11px] font-bold tracking-wide">
                        Recommended
                      </span>
                    </div>
                    <div>
                      <h3 className="text-base font-bold text-white">On-Device Local AI</h3>
                      <p className="text-xs text-white/60 mt-1 leading-relaxed">
                        Runs 100% offline in RAM with faster-whisper. Ultra-fast response with zero data leaving your machine.
                      </p>
                    </div>
                  </div>
                  <div className="pt-3.5 mt-2 border-t border-white/5 flex items-center justify-between text-xs font-semibold text-white/80">
                    <div className="flex items-center gap-2.5 truncate">
                      <div
                        className={`w-4 h-4 rounded-full border flex items-center justify-center shrink-0 ${
                          selectedModelType === "local"
                            ? "border-[#87B996] bg-[#87B996] text-black"
                            : "border-white/30"
                        }`}
                      >
                        {selectedModelType === "local" && <Check size={10} strokeWidth={3} />}
                      </div>
                      <span className="truncate">Active: {activeModelId}</span>
                    </div>
                    {isModelReady ? (
                      <span className="flex items-center gap-1 text-[11px] text-emerald-400 shrink-0 font-medium">
                        <CheckCircle2 size={12} />
                        <span>Ready in RAM (75 MB)</span>
                      </span>
                    ) : isModelDownloading ? (
                      <span className="flex items-center gap-1 text-[11px] text-amber-300 shrink-0 font-medium animate-pulse">
                        <Loader2 size={12} className="animate-spin" />
                        <span>Downloading {Math.round(downloadProgress)}%</span>
                      </span>
                    ) : (
                      <span className="text-[11px] text-white/50 shrink-0">75 MB Starter</span>
                    )}
                  </div>
                </div>

                {/* Cloud Card */}
                <div
                  onClick={() => handleSelectModel("cloud")}
                  className={`p-5 rounded-2xl border cursor-pointer transition-all flex flex-col justify-between min-h-[200px] ${
                    selectedModelType === "cloud"
                      ? "bg-[#4A6572]/25 border-[#A4C4D3] ring-1 ring-[#A4C4D3]/40 shadow-lg"
                      : "bg-white/[0.03] border-white/10 hover:border-white/20 hover:bg-white/[0.05]"
                  }`}
                >
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="w-10 h-10 rounded-xl bg-[#4A6572]/40 flex items-center justify-center text-[#A4C4D3]">
                        <Cloud size={22} />
                      </div>
                      <span className="px-2.5 py-0.5 rounded-full bg-white/10 text-white/60 text-[11px] font-semibold tracking-wide">
                        Requires API Key
                      </span>
                    </div>
                    <div>
                      <h3 className="text-base font-bold text-white">Cloud Whisper AI</h3>
                      <p className="text-xs text-white/60 mt-1 leading-relaxed">
                        Uses OpenAI Whisper or OpenRouter for multi-language transcription and complex technical terms.
                      </p>
                    </div>
                  </div>
                  <div className="pt-3.5 mt-2 border-t border-white/5 flex items-center gap-2.5 text-xs font-semibold text-white/80">
                    <div
                      className={`w-4 h-4 rounded-full border flex items-center justify-center shrink-0 ${
                        selectedModelType === "cloud"
                          ? "border-[#A4C4D3] bg-[#A4C4D3] text-black"
                          : "border-white/30"
                      }`}
                    >
                      {selectedModelType === "cloud" && <Check size={10} strokeWidth={3} />}
                    </div>
                    <span className="truncate">OpenAI whisper-1 / Custom</span>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* STEP 3: Where do you type most? */}
          {currentStep === 3 && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-semibold text-[#87B996]">
                <Keyboard size={14} />
                <span>Where you type</span>
              </div>
              <h2 className="text-2xl font-bold tracking-tight text-white">
                Where do you type most?
              </h2>
              <p className="text-sm text-white/70 leading-relaxed">
                Dicty uses the right writing style in each app you pick. You can change this any
                time in Modes.
              </p>

              <div className="grid grid-cols-2 gap-3 pt-1">
                {TYPING_CHOICES.map((choice) => {
                  const IconComp = choice.icon;
                  const isOn = typingApps.has(choice.id);
                  return (
                    <button
                      key={choice.id}
                      onClick={() =>
                        setTypingApps((prev) => {
                          const next = new Set(prev);
                          if (next.has(choice.id)) next.delete(choice.id);
                          else next.add(choice.id);
                          return next;
                        })
                      }
                      className={`flex items-center gap-2.5 p-3.5 rounded-xl border text-left transition-all ${
                        isOn
                          ? "bg-[#5D6658]/25 border-[#87B996]/50"
                          : "bg-white/[0.04] border-white/10 hover:bg-white/[0.07]"
                      }`}
                    >
                      <IconComp size={16} className={isOn ? "text-[#87B996]" : "text-white/50"} />
                      <span className="text-sm font-medium text-white flex-1">{choice.name}</span>
                      {isOn && <Check size={16} strokeWidth={3} className="text-[#87B996]" />}
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* STEP 4: Private on this PC, or cloud when better? */}
          {currentStep === 4 && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-semibold text-[#87B996]">
                <ShieldCheck size={14} />
                <span>Where AI runs</span>
              </div>
              <h2 className="text-2xl font-bold tracking-tight text-white">
                Private on this PC, or cloud when better?
              </h2>
              <p className="text-sm text-white/70 leading-relaxed">
                You can switch any time on the Models page.
              </p>

              <div className="grid grid-cols-2 gap-3">
                {[
                  { tag: "local", icon: Laptop, title: "On this PC", subtitle: "Private, works offline." },
                  {
                    tag: "cloud_when_better",
                    icon: Cloud,
                    title: "Cloud when better",
                    subtitle: "Faster or better on hard tasks. Needs sign-in or an API key.",
                  },
                ].map((option) => {
                  const IconComp = option.icon;
                  const isOn = aiLocation === option.tag;
                  return (
                    <button
                      key={option.tag}
                      onClick={() => setAiLocation(option.tag as "local" | "cloud_when_better")}
                      className={`text-left p-4 rounded-2xl border transition-all ${
                        isOn
                          ? "bg-[#5D6658]/25 border-[#87B996]/50"
                          : "bg-white/[0.03] border-white/10 hover:bg-white/[0.06]"
                      }`}
                    >
                      <div className="flex items-center gap-2">
                        <IconComp size={16} className={isOn ? "text-[#87B996]" : "text-white/50"} />
                        <span className="text-sm font-semibold text-white flex-1">{option.title}</span>
                        {isOn && <Check size={16} strokeWidth={3} className="text-[#87B996]" />}
                      </div>
                      <p className="text-[11px] text-white/55 mt-1.5 leading-snug">{option.subtitle}</p>
                    </button>
                  );
                })}
              </div>

              {aiLocation === "local" && offlineModels.length > 0 && (
                <div className="rounded-2xl bg-white/[0.03] border border-white/10 p-3.5 space-y-2.5">
                  <p className="text-xs text-white/55">
                    Dicty can download these so it works offline:
                  </p>
                  {offlineModels.map((model) => {
                    const downloading = modelDownloads[model.id];
                    return (
                      <div key={model.id} className="flex items-center gap-3">
                        {model.is_downloaded ? (
                          <CheckCircle2 size={16} className="text-[#87B996] shrink-0" />
                        ) : (
                          <Download size={16} className="text-white/45 shrink-0" />
                        )}
                        <div className="flex-1 min-w-0">
                          <div className="text-xs font-medium text-white truncate">{model.name}</div>
                          {model.size && <div className="text-[10px] text-white/40">{model.size}</div>}
                        </div>
                        {model.is_downloaded ? (
                          <span className="text-[11px] text-white/45">Ready</span>
                        ) : typeof downloading === "number" ? (
                          <span className="text-[11px] text-amber-300">
                            {Math.round(downloading)}%
                          </span>
                        ) : (
                          <button
                            onClick={() => downloadOfflineModel(model.id)}
                            className="text-[11px] font-semibold text-[#87B996] hover:underline"
                          >
                            Download
                          </button>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {/* STEP 5: Interactive Practice & Shortcut Test */}
          {currentStep === 5 && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-semibold text-[#87B996]">
                <Keyboard size={14} />
                <span>Interactive Practice</span>
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-2xl font-bold tracking-tight text-white">
                    Try dictating a sample sentence
                  </h2>
                  <p className="text-sm text-white/70 leading-relaxed">
                    Press your shortcut or click the record button to test the transcription sandbox.
                  </p>
                </div>
                <div className="px-3.5 py-1.5 rounded-xl bg-white/10 border border-white/15 font-mono text-sm font-bold text-white shadow-inner">
                  {shortcutKey}
                </div>
              </div>

              {/* Practice Sandbox */}
              <div className="rounded-2xl border border-white/15 bg-black/40 p-4 space-y-3 relative overflow-hidden">
                {/* Status Bar */}
                <div className="flex items-center justify-between pb-2 border-b border-white/10">
                  <div className="flex items-center gap-2">
                    {isTestRecording ? (
                      <div className="flex items-center gap-2 text-rose-400 text-xs font-semibold animate-pulse">
                        <span className="w-2.5 h-2.5 rounded-full bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.8)]" />
                        <span>Recording... Speak now!</span>
                      </div>
                    ) : isTestProcessing ? (
                      <div className="flex items-center gap-2 text-amber-300 text-xs font-semibold">
                        <Loader2 className="animate-spin" size={14} />
                        <span>Transcribing audio in RAM...</span>
                      </div>
                    ) : (
                      <span className="text-xs text-white/50">
                        {transcribedText ? "Transcription successful!" : "Ready to dictate"}
                      </span>
                    )}
                  </div>

                  {/* On-screen Record Button */}
                  <button
                    onClick={handleToggleTestRecord}
                    disabled={isTestProcessing}
                    className={`px-3.5 py-1.5 rounded-xl text-xs font-semibold flex items-center gap-2 transition-all shadow-md ${
                      isTestRecording
                        ? "bg-rose-600 hover:bg-rose-500 text-white animate-pulse"
                        : "bg-[#5D6658] hover:bg-[#6c7766] text-white"
                    }`}
                  >
                    {isTestRecording ? (
                      <>
                        <Square size={12} fill="currentColor" />
                        <span>Stop Recording</span>
                      </>
                    ) : (
                      <>
                        <Mic size={14} />
                        <span>Test Dictation</span>
                      </>
                    )}
                  </button>
                </div>

                {/* Side-by-side: what you said vs what Dicty wrote */}
                <div className="grid grid-cols-2 gap-3">
                  <div className="rounded-xl bg-black/30 border border-white/10 p-3 space-y-1.5">
                    <span className="text-[10px] uppercase tracking-wide font-bold text-white/40">
                      You say
                    </span>
                    <p className="text-xs text-white/60 italic leading-relaxed">
                      &ldquo;This is my first voice recording with Dicty on Windows!&rdquo;
                    </p>
                  </div>
                  <div className="rounded-xl bg-[#5D6658]/15 border border-[#5D6658]/30 p-3 space-y-1.5 min-h-[72px]">
                    <span className="text-[10px] uppercase tracking-wide font-bold text-white/40">
                      Dicty wrote
                    </span>
                    {transcribedText ? (
                      <p className="text-xs text-white font-medium leading-relaxed animate-in fade-in duration-200">
                        &ldquo;{transcribedText}&rdquo;
                      </p>
                    ) : (
                      <p className="text-xs text-white/35 italic leading-relaxed">
                        Your words will appear here.
                      </p>
                    )}
                  </div>
                </div>
              </div>

              {/* Diagnostic Error Alert */}
              {sandboxError && !isTestRecording && !isTestProcessing && (
                <div className="flex items-center justify-between gap-2 px-3.5 py-2.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-xs text-amber-300 animate-in fade-in duration-200">
                  <div className="flex items-center gap-2">
                    <AlertCircle size={15} className="shrink-0 text-amber-400" />
                    <span>{sandboxError}</span>
                  </div>
                  <button
                    onClick={handleToggleTestRecord}
                    className="px-2.5 py-1 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 text-amber-200 font-semibold shrink-0 transition-colors"
                  >
                    Try Again
                  </button>
                </div>
              )}

              {transcribedText && (
                <div className="flex items-center gap-2 px-3 py-2 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-xs text-emerald-400 animate-in fade-in duration-200">
                  <CheckCircle2 size={16} />
                  <span>
                    Great job! Your audio was transcribed and copied to your clipboard. In real use, it types automatically at your cursor!
                  </span>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Dedicated Bottom Footer Bar (Fixed, never clipped) */}
        <div className="relative z-10 px-8 py-4 border-t border-white/10 bg-[#13151A]/90 backdrop-blur-md flex items-center justify-between shrink-0">
          {currentStep > 0 ? (
            <button
              onClick={() => setCurrentStep((prev) => prev - 1)}
              className="px-4 py-2 rounded-xl text-white/70 hover:text-white hover:bg-white/5 text-sm font-medium flex items-center gap-1.5 transition-colors"
            >
              <ArrowLeft size={16} />
              <span>Back</span>
            </button>
          ) : (
            <div />
          )}

          {currentStep < TOTAL_STEPS - 1 ? (
            <button
              onClick={handleContinue}
              disabled={currentStep === 2 && selectedModelType === "local" && !isModelReady && isModelDownloading}
              className={`px-6 py-2.5 rounded-xl font-semibold text-sm flex items-center gap-2 shadow-lg transition-all ${
                currentStep === 2 && selectedModelType === "local" && !isModelReady && isModelDownloading
                  ? "bg-white/10 text-white/40 cursor-not-allowed"
                  : "bg-[#5D6658] hover:bg-[#6c7766] active:scale-95 text-white"
              }`}
            >
              {currentStep === 2 && selectedModelType === "local" && !isModelReady && isModelDownloading ? (
                <>
                  <Loader2 size={16} className="animate-spin text-[#87B996]" />
                  <span>Preparing model ({Math.round(downloadProgress)}%)...</span>
                </>
              ) : (
                <>
                  <span>Continue</span>
                  <ArrowRight size={16} />
                </>
              )}
            </button>
          ) : (
            <button
              onClick={handleComplete}
              className="px-6 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 active:scale-95 text-white font-semibold text-sm flex items-center gap-2 shadow-xl hover:shadow-emerald-600/30 transition-all"
            >
              <Check size={16} strokeWidth={3} />
              <span>Start Using Dicty</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
