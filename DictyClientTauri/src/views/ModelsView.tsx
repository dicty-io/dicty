import React, { useState, useEffect, useMemo } from "react";
import {
  Folder,
  Star,
  Info,
  Globe,
  Cpu,
  Cloud,
  CheckCircle2,
  HardDrive,
  PlayCircle,
  ArrowDownCircle,
  XCircle,
  AudioWaveform,
  Sparkles,
  X,
  ChevronDown,
  ChevronUp,
  ChevronRight,
  Check,
  Settings2,
  MemoryStick,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { engineApi } from "../services/engineApi";
import { getProviderIcon } from "../components/BrandIcons";
import { OpenRouterExplorerModal } from "../components/OpenRouterExplorerModal";
import { ToggleSwitch } from "../components/ToggleSwitch";
import { FeatureHelpButton } from "../components/FeatureHelpModal";
import { AILocationCard } from "../components/AILocationCard";

export const WHISPER_LANGUAGES = [
  { name: "Auto Detect", code: "auto" },
  { name: "Afrikaans", code: "af" },
  { name: "Amharic", code: "am" },
  { name: "Arabic", code: "ar" },
  { name: "Armenian", code: "hy" },
  { name: "Assamese", code: "as" },
  { name: "Azerbaijani", code: "az" },
  { name: "Bashkir", code: "ba" },
  { name: "Basque", code: "eu" },
  { name: "Belarusian", code: "be" },
  { name: "Bengali", code: "bn" },
  { name: "Bosnian", code: "bs" },
  { name: "Breton", code: "br" },
  { name: "Bulgarian", code: "bg" },
  { name: "Burmese", code: "my" },
  { name: "Catalan", code: "ca" },
  { name: "Chinese", code: "zh" },
  { name: "Croatian", code: "hr" },
  { name: "Czech", code: "cs" },
  { name: "Danish", code: "da" },
  { name: "Dutch", code: "nl" },
  { name: "English", code: "en" },
  { name: "Estonian", code: "et" },
  { name: "Faroese", code: "fo" },
  { name: "Finnish", code: "fi" },
  { name: "French", code: "fr" },
  { name: "Galician", code: "gl" },
  { name: "Georgian", code: "ka" },
  { name: "German", code: "de" },
  { name: "Greek", code: "el" },
  { name: "Gujarati", code: "gu" },
  { name: "Haitian Creole", code: "ht" },
  { name: "Hausa", code: "ha" },
  { name: "Hawaiian", code: "haw" },
  { name: "Hebrew", code: "he" },
  { name: "Hindi", code: "hi" },
  { name: "Hungarian", code: "hu" },
  { name: "Icelandic", code: "is" },
  { name: "Indonesian", code: "id" },
  { name: "Italian", code: "it" },
  { name: "Japanese", code: "ja" },
  { name: "Javanese", code: "jv" },
  { name: "Kannada", code: "kn" },
  { name: "Kazakh", code: "kk" },
  { name: "Khmer", code: "km" },
  { name: "Korean", code: "ko" },
  { name: "Lao", code: "lo" },
  { name: "Latin", code: "la" },
  { name: "Latvian", code: "lv" },
  { name: "Lingala", code: "ln" },
  { name: "Lithuanian", code: "lt" },
  { name: "Luxembourgish", code: "lb" },
  { name: "Macedonian", code: "mk" },
  { name: "Malagasy", code: "mg" },
  { name: "Malay", code: "ms" },
  { name: "Malayalam", code: "ml" },
  { name: "Maltese", code: "mt" },
  { name: "Maori", code: "mi" },
  { name: "Marathi", code: "mr" },
  { name: "Mongolian", code: "mn" },
  { name: "Nepali", code: "ne" },
  { name: "Norwegian", code: "no" },
  { name: "Nynorsk", code: "nn" },
  { name: "Occitan", code: "oc" },
  { name: "Pashto", code: "ps" },
  { name: "Persian", code: "fa" },
  { name: "Polish", code: "pl" },
  { name: "Portuguese", code: "pt" },
  { name: "Punjabi", code: "pa" },
  { name: "Romanian", code: "ro" },
  { name: "Russian", code: "ru" },
  { name: "Sanskrit", code: "sa" },
  { name: "Serbian", code: "sr" },
  { name: "Shona", code: "sn" },
  { name: "Sindhi", code: "sd" },
  { name: "Sinhala", code: "si" },
  { name: "Slovak", code: "sk" },
  { name: "Slovenian", code: "sl" },
  { name: "Somali", code: "so" },
  { name: "Spanish", code: "es" },
  { name: "Sundanese", code: "su" },
  { name: "Swahili", code: "sw" },
  { name: "Swedish", code: "sv" },
  { name: "Tagalog", code: "tl" },
  { name: "Tajik", code: "tg" },
  { name: "Tamil", code: "ta" },
  { name: "Tatar", code: "tt" },
  { name: "Telugu", code: "te" },
  { name: "Thai", code: "th" },
  { name: "Tibetan", code: "bo" },
  { name: "Turkish", code: "tr" },
  { name: "Turkmen", code: "tk" },
  { name: "Ukrainian", code: "uk" },
  { name: "Urdu", code: "ur" },
  { name: "Uzbek", code: "uz" },
  { name: "Vietnamese", code: "vi" },
  { name: "Welsh", code: "cy" },
  { name: "Yiddish", code: "yi" },
  { name: "Yoruba", code: "yo" },
];

export interface DictyModel {
  id: string;
  name: string;
  size: string;
  speed: number;
  accuracy: number;
  is_downloaded?: boolean;
  is_cloud?: boolean;
  category?: "voice" | "text";
  description?: string;
  supports_translation?: boolean;
  quantization?: string;
}

// ALL models from models_config.json matching macOS DictyClient 1:1
const ALL_MODELS: DictyModel[] = [
  // --- Section 1: Local Voice Recognition Models (Whisper.cpp) ---
  {
    id: "tiny.en",
    name: "Nano",
    size: "75 MB",
    speed: 1.0,
    accuracy: 0.4,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Ultra-fast, lightweight English model with minimal memory footprint.",
  },
  {
    id: "tiny",
    name: "Nano",
    size: "75 MB",
    speed: 1.0,
    accuracy: 0.4,
    is_cloud: false,
    category: "voice",
    is_downloaded: true,
    quantization: "q5_0",
    description: "Ultra-fast, lightweight multilingual model for resource-constrained systems.",
  },
  {
    id: "base.en",
    name: "Base",
    size: "140 MB",
    speed: 0.8,
    accuracy: 0.6,
    is_cloud: false,
    category: "voice",
    is_downloaded: true,
    quantization: "q5_0",
    description: "Fast, reliable baseline model for everyday clear English speech.",
  },
  {
    id: "base",
    name: "Base",
    size: "140 MB",
    speed: 0.8,
    accuracy: 0.6,
    is_cloud: false,
    category: "voice",
    is_downloaded: true,
    quantization: "q5_0",
    description: "Balanced multilingual baseline model for everyday transcription across 90+ languages.",
  },
  {
    id: "small.en",
    name: "Fast",
    size: "460 MB",
    speed: 0.6,
    accuracy: 0.8,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "The ideal balance of high accuracy and rapid speed for English dictation.",
  },
  {
    id: "small",
    name: "Fast",
    size: "460 MB",
    speed: 0.6,
    accuracy: 0.8,
    is_cloud: false,
    category: "voice",
    is_downloaded: true,
    quantization: "q5_0",
    description: "High-speed multilingual model offering great accuracy across 90+ languages.",
  },
  {
    id: "distil-large-v3",
    name: "Turbo (Distil)",
    size: "1.5 GB",
    speed: 1.0,
    accuracy: 0.98,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Ultra-fast distilled model delivering near-maximum accuracy, optimized specifically for English speech.",
  },
  {
    id: "medium.en",
    name: "Pro",
    size: "1.5 GB",
    speed: 0.4,
    accuracy: 0.9,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Professional-grade English accuracy, highly tuned for complex and technical vocabulary.",
  },
  {
    id: "medium",
    name: "Pro",
    size: "1.5 GB",
    speed: 0.4,
    accuracy: 0.9,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Professional-grade multilingual accuracy, excellent for nuanced vocabulary and accents.",
  },
  {
    id: "large-v3-turbo",
    name: "Turbo",
    size: "1.6 GB",
    speed: 0.8,
    accuracy: 0.98,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "OpenAI's flagship turbo architecture, delivering near-maximum accuracy with blazing fast speed across all languages.",
  },
  {
    id: "large-v3",
    name: "Max",
    size: "3.1 GB",
    speed: 0.2,
    accuracy: 1.0,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Maximum-precision open-source model, offering highest accuracy for complex audio, dialects, and quiet speech.",
  },
  {
    id: "large-v3-turbo-ja",
    name: "Turbo (Japanese)",
    size: "1.6 GB",
    speed: 0.8,
    accuracy: 0.98,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Turbo architecture fine-tuned specifically for natural, accurate Japanese transcription.",
  },
  {
    id: "large-v2-zh",
    name: "BELLE (Chinese)",
    size: "3.1 GB",
    speed: 0.2,
    accuracy: 0.95,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Specialized Chinese model optimized for Mandarin and regional dialect recognition.",
  },
  {
    id: "large-v2-french",
    name: "Large (French)",
    size: "3.1 GB",
    speed: 0.2,
    accuracy: 0.95,
    is_cloud: false,
    category: "voice",
    is_downloaded: false,
    description: "Specialized French model optimized on extensive native speech to eliminate silent letter errors.",
  },

  // --- Section 1B: Cloud Speech Models ---
  {
    id: "openai/whisper-1",
    name: "Cloud Whisper 1",
    size: "Cloud",
    speed: 1.0,
    accuracy: 0.99,
    is_cloud: true,
    category: "voice",
    is_downloaded: true,
    description: "Official OpenAI Whisper cloud API for ultra-high accuracy speech recognition across all languages.",
  },
  {
    id: "nvidia/parakeet-tdt-0.6b-v3",
    name: "Nvidia Parakeet",
    size: "Cloud",
    speed: 1.0,
    accuracy: 0.98,
    is_cloud: true,
    category: "voice",
    is_downloaded: true,
    description: "Blazing-fast cloud speech recognition powered by Nvidia Parakeet architecture.",
  },
  {
    id: "deepgram/nova-3",
    name: "Nova 3",
    size: "Cloud",
    speed: 1.0,
    accuracy: 0.98,
    is_cloud: true,
    category: "voice",
    is_downloaded: true,
    description: "Deepgram's fastest and most accurate model, perfect for general dictation and formatting.",
  },
  {
    id: "groq/whisper-large-v3-turbo",
    name: "Groq Whisper (Turbo)",
    size: "Cloud",
    speed: 1.0,
    accuracy: 0.98,
    is_cloud: true,
    category: "voice",
    is_downloaded: true,
    description: "OpenAI's large-v3-turbo running on Groq LPU for near-instant transcription.",
  },
  {
    id: "elevenlabs/scribe-v2",
    name: "Scribe V2",
    size: "Cloud",
    speed: 0.9,
    accuracy: 0.99,
    is_cloud: true,
    category: "voice",
    is_downloaded: true,
    description: "ElevenLabs' highly accurate Scribe V2 model, tuned for complex conversational nuances.",
  },

  // --- Section 2: Local Text Models (GGUF) ---
  {
    id: "qwen2.5-1.5b-instruct",
    name: "Qwen 2.5 1.5B",
    size: "980 MB",
    speed: 0.9,
    accuracy: 0.95,
    is_cloud: false,
    category: "text",
    is_downloaded: true,
    quantization: "q5_0",
    description: "Fast, lightweight local model for 100% offline text formatting and punctuation.",
    supports_translation: true,
  },
  {
    id: "llama-3.2-3b-instruct",
    name: "Llama 3.2 3B",
    size: "1.9 GB",
    speed: 0.7,
    accuracy: 0.98,
    is_cloud: false,
    category: "text",
    is_downloaded: false,
    description: "High-capability 3B local model for nuanced offline text editing and grammar correction.",
    supports_translation: true,
  },

  // --- Section 2B: Cloud Text Models (OpenRouter / Cloud) ---
  {
    id: "anthropic/claude-opus-5",
    name: "Claude Opus 5",
    size: "Cloud",
    speed: 0.85,
    accuracy: 1.0,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Anthropic's ultimate flagship intelligence for high-level creative synthesis and nuanced book editing.",
    supports_translation: true,
  },
  {
    id: "anthropic/claude-sonnet-5",
    name: "Claude Sonnet 5",
    size: "Cloud",
    speed: 0.95,
    accuracy: 1.0,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Anthropic's premier frontier model combining deep reasoning with exceptional writing speed.",
    supports_translation: true,
  },
  {
    id: "anthropic/claude-haiku-4.5",
    name: "Claude Haiku 4.5",
    size: "Cloud",
    speed: 1.0,
    accuracy: 0.98,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Ultra-fast, lightweight Anthropic model engineered for instant dictation cleanup and syntax punctuation.",
    supports_translation: true,
  },
  {
    id: "openai/gpt-5.6-sol",
    name: "GPT-5.6 Sol",
    size: "Cloud",
    speed: 0.9,
    accuracy: 1.0,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "OpenAI's flagship powerhouse for high-fidelity text transformations and complex multi-speaker prose.",
    supports_translation: true,
  },
  {
    id: "openai/gpt-5.5",
    name: "GPT-5.5",
    size: "Cloud",
    speed: 0.95,
    accuracy: 0.99,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "OpenAI's standard high-accuracy model with balanced latency and comprehensive language coverage.",
    supports_translation: true,
  },
  {
    id: "openai/gpt-5.6-luna",
    name: "GPT-5.6 Luna",
    size: "Cloud",
    speed: 1.0,
    accuracy: 0.98,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Lightweight, ultra-responsive OpenAI workhorse for instantaneous live dictation structuring.",
    supports_translation: true,
  },
  {
    id: "google/gemini-3.1-pro-preview",
    name: "Gemini 3.1 Pro",
    size: "Cloud",
    speed: 0.85,
    accuracy: 1.0,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Google's maximum-intelligence multimodal model with deep context and superior structural understanding.",
    supports_translation: true,
  },
  {
    id: "google/gemini-3.7-flash",
    name: "Gemini 3.7 Flash",
    size: "Cloud",
    speed: 1.0,
    accuracy: 0.99,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Google's newest ultra-fast reasoning model delivering instant responses and massive context length.",
    supports_translation: true,
  },
  {
    id: "deepseek/deepseek-v4-pro",
    name: "DeepSeek V4 Pro",
    size: "Cloud",
    speed: 0.9,
    accuracy: 1.0,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Next-generation DeepSeek frontier model offering top-tier reasoning and literary prose styling.",
    supports_translation: true,
  },
  {
    id: "x-ai/grok-4.6",
    name: "Grok 4.6",
    size: "Cloud",
    speed: 0.9,
    accuracy: 0.99,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "xAI's flagship reasoning model with bold comprehension, direct tone, and nuanced vocabulary.",
    supports_translation: true,
  },
  {
    id: "qwen/qwen3-next-80b",
    name: "Qwen3 Next 80B",
    size: "Cloud",
    speed: 0.95,
    accuracy: 0.99,
    is_cloud: true,
    category: "text",
    is_downloaded: true,
    description: "Alibaba's latest dense frontier model with world-class multilingual fluency and literary synthesis.",
    supports_translation: true,
  },
];

export type QuantizationType = "q5_0" | "f16" | "q4_0";

export const QUANTIZATION_OPTIONS = [
  {
    id: "q5_0" as QuantizationType,
    label: "Q5",
    shortTitle: "Optimized (Q5)",
    badge: "Recommended",
    description: "~99% studio accuracy with 50% RAM & disk savings. Best for all-round use.",
  },
  {
    id: "f16" as QuantizationType,
    label: "F16",
    shortTitle: "Studio (F16)",
    badge: "Original",
    description: "Original 16-bit uncompressed weights. Highest acoustic precision for noisy audio.",
  },
  {
    id: "q4_0" as QuantizationType,
    label: "Q4",
    shortTitle: "Fast (Q4)",
    badge: "Fastest",
    description: "4-bit integer weights. Minimal memory footprint and ultra-rapid inference.",
  },
];

export function calculateEstimatedSize(baseSize: string, q: QuantizationType): string {
  const parts = baseSize.trim().split(/\s+/);
  if (parts.length < 2) return baseSize;
  const val = parseFloat(parts[0]);
  const unit = parts[1].toUpperCase();
  if (isNaN(val)) return baseSize;

  if (q === "q5_0") {
    return baseSize;
  } else if (q === "f16") {
    const f16 = val * 3.3;
    if (unit === "MB") {
      return f16 >= 1000 ? `~${(f16 / 1000).toFixed(1)} GB` : `~${Math.round(f16)} MB`;
    }
    return `~${f16.toFixed(1)} GB`;
  } else {
    const q4 = val * 0.75;
    if (unit === "MB") {
      return `~${Math.round(q4)} MB`;
    }
    return q4 < 1.0 ? `~${Math.round(q4 * 1000)} MB` : `~${q4.toFixed(1)} GB`;
  }
}

export type LanguageCategory = "all" | "multilingual" | "english" | "specialized";

export interface ModelLanguageInfo {
  type: "multilingual" | "english" | "specialized" | "text";
  label: string;
  badge: string;
  tooltip: string;
  langCode: string;
}

export function getModelLanguage(model: DictyModel): ModelLanguageInfo {
  if (model.category === "text") {
    return {
      type: "text",
      label: "Multilingual AI",
      badge: "Text / Code",
      tooltip: "Reasoning and code synthesis across 90+ languages.",
      langCode: "AI",
    };
  }

  if (model.id.endsWith(".en") || model.id === "distil-large-v3") {
    return {
      type: "english",
      label: "English Only",
      badge: "EN",
      tooltip: "Specialized English acoustic weights. Does not support other languages.",
      langCode: "EN",
    };
  }

  if (model.id.includes("-ja") || model.id.includes("japanese")) {
    return {
      type: "specialized",
      label: "Japanese Only",
      badge: "JA",
      tooltip: "Fine-tuned specifically for Japanese speech transcription.",
      langCode: "JA",
    };
  }

  if (model.id.includes("-zh") || model.id.includes("chinese")) {
    return {
      type: "specialized",
      label: "Chinese Only",
      badge: "ZH",
      tooltip: "Specialized for Mandarin and regional Chinese dialects.",
      langCode: "ZH",
    };
  }

  if (model.id.includes("french") || model.id.includes("-fr")) {
    return {
      type: "specialized",
      label: "French Only",
      badge: "FR",
      tooltip: "Optimized on native French speech to eliminate silent letter errors.",
      langCode: "FR",
    };
  }

  return {
    type: "multilingual",
    label: "Multilingual",
    badge: "99+ (RU, EN...)",
    tooltip: "Recognizes 99+ languages including Russian, English, German, Spanish, French, etc.",
    langCode: "MULTI",
  };
}

export const ModelsView: React.FC = () => {
  const [activeModelId, setActiveModelId] = useState<string>(() => {
    return localStorage.getItem("dicty_active_model") || "base.en";
  });
  const [modelsList, setModelsList] = useState<DictyModel[]>(ALL_MODELS);
  const [selectedLangFilter, setSelectedLangFilter] = useState<LanguageCategory>("all");
  const [selectedModelId, setSelectedModelId] = useState<string | null>(null);
  const [favorites, setFavorites] = useState<Set<string>>(new Set(["base.en", "base"]));
  const [useDictyCloud, setUseDictyCloud] = useState<boolean>(false);
  const [inspectedModel, setInspectedModel] = useState<DictyModel | null>(null);
  const [showHeaderInfo, setShowHeaderInfo] = useState<boolean>(false);
  const [downloadingIds, setDownloadingIds] = useState<Map<string, number>>(new Map());
  const [selectedQuantizations, setSelectedQuantizations] = useState<Record<string, QuantizationType>>({});
  const [openDropdownId, setOpenDropdownId] = useState<string | null>(null);

  // States for OpenRouter Explorer and Advanced Model Settings
  const [showOpenRouterExplorer, setShowOpenRouterExplorer] = useState<boolean>(false);
  const [showAllCloudTextModels, setShowAllCloudTextModels] = useState<boolean>(false);
  const [customCloudModels, setCustomCloudModels] = useState<DictyModel[]>([]);
  const [isAdvancedSettingsExpanded, setIsAdvancedSettingsExpanded] = useState<boolean>(true);
  const [showModelPicker, setShowModelPicker] = useState<boolean>(() => {
    // Open by default only if the user changed a model before.
    try {
      const active = localStorage.getItem("dicty_active_model");
      const favorites = localStorage.getItem("favorite_models");
      return (!!active && active !== "base.en") || !!favorites;
    } catch {
      return false;
    }
  });
  const [spokenLanguage, setSpokenLanguage] = useState<string>("auto");
  const [keepModelInRam, setKeepModelInRam] = useState<boolean>(true);
  const [activeTooltip, setActiveTooltip] = useState<string | null>(null);

  const fetchLiveModels = async () => {
    try {
      const res = await engineApi.getModels();
      if (res && Array.isArray(res.models) && res.models.length > 0) {
        setModelsList((prev) => {
          const updated = [...prev];
          for (const m of res.models) {
            const existingIdx = updated.findIndex((item) => item.id === m.id);
            if (existingIdx !== -1) {
              updated[existingIdx] = {
                ...updated[existingIdx],
                is_downloaded: m.is_downloaded ?? updated[existingIdx].is_downloaded,
                quantization: m.quantization || updated[existingIdx].quantization,
              };
            } else {
              updated.push(m);
            }
          }
          return updated;
        });
      }
    } catch (err) {
      console.warn("Could not fetch models from engine:", err);
    }
  };

  // Sync active model and download progress from backend if available
  useEffect(() => {
    let isMounted = true;
    engineApi.getActiveModel().then((res) => {
      if (isMounted && res?.active_model) {
        setActiveModelId(res.active_model);
        localStorage.setItem("dicty_active_model", res.active_model);
      }
    }).catch(() => {});

    fetchLiveModels();

    // Listen for global mode changes from shortcuts, HUD, or ModesView
    let unlisten: (() => void) | null = null;
    listen<any>("dicty:mode-changed", (event) => {
      if (event.payload?.whisper_model) {
        setActiveModelId(event.payload.whisper_model);
        localStorage.setItem("dicty_active_model", event.payload.whisper_model);
      }
    }).then((fn) => {
      unlisten = fn;
    });

    const handleStorage = () => {
      const stored = localStorage.getItem("dicty_active_model");
      if (stored) setActiveModelId(stored);
    };
    window.addEventListener("storage", handleStorage);

    // Close any open quantization dropdown when clicking outside
    const handleDocumentClick = () => {
      setOpenDropdownId(null);
      setActiveTooltip(null);
    };
    document.addEventListener("click", handleDocumentClick);
    return () => {
      isMounted = false;
      document.removeEventListener("click", handleDocumentClick);
      window.removeEventListener("storage", handleStorage);
      if (unlisten) unlisten();
    };
  }, []);

  const getSelectedQuality = (modelId: string): QuantizationType => {
    return selectedQuantizations[modelId] || "q5_0";
  };

  const toggleFavorite = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setFavorites((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleApplyPrecision = async (modelId: string, quality: QuantizationType, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    try {
      await engineApi.downloadModel(modelId, quality);
      await fetchLiveModels();
    } catch (err) {
      console.warn("Failed to apply precision:", err);
    }
  };

  const handleDownload = async (id: string, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    const quality = getSelectedQuality(id);

    try {
      const res = await engineApi.downloadModel(id, quality);
      if (res && res.status === "already_downloaded") {
        await fetchLiveModels();
        return;
      }
      setDownloadingIds((prev) => new Map(prev).set(id, 5));
    } catch (err) {
      console.warn("Download initiation failed:", err);
      return;
    }

    const interval = setInterval(async () => {
      try {
        const progRes = await engineApi.getDownloadProgress();
        const progressMap = progRes?.progress || {};
        const pct = progressMap[id];

        if (pct !== undefined && pct >= 0) {
          if (pct >= 100) {
            clearInterval(interval);
            setDownloadingIds((prev) => {
              const next = new Map(prev);
              next.delete(id);
              return next;
            });
            await fetchLiveModels();
          } else {
            setDownloadingIds((prev) => new Map(prev).set(id, Math.round(pct)));
          }
        } else if (pct === -1.0) {
          clearInterval(interval);
          setDownloadingIds((prev) => {
            const next = new Map(prev);
            next.delete(id);
            return next;
          });
        }
      } catch {
        // Continue polling
      }
    }, 500);
  };

  const handleCancelDownload = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await engineApi.cancelDownload();
    } catch {}
    setDownloadingIds((prev) => {
      const next = new Map(prev);
      next.delete(id);
      return next;
    });
  };

  const handleOpenFolder = async () => {
    try {
      await invoke("open_models_folder");
    } catch (tauriErr) {
      console.warn("Tauri open_models_folder failed, falling back to engineApi:", tauriErr);
      try {
        await engineApi.openModelsFolder();
      } catch (fallbackErr) {
        console.error("Failed to open models folder:", fallbackErr);
      }
    }
  };

  // Partition models exactly matching ModelsLibraryView.swift
  const localVoiceModels = modelsList.filter(
    (m) => m.category === "voice" && !m.is_cloud
  );
  const cloudVoiceModels = modelsList.filter(
    (m) => m.category === "voice" && m.is_cloud
  );
  const localTextModels = modelsList.filter(
    (m) => m.category === "text" && !m.is_cloud
  );
  const baseCloudTextModels = modelsList.filter(
    (m) => m.category === "text" && m.is_cloud
  );

  const filteredLocalVoiceModels = useMemo(() => {
    if (selectedLangFilter === "all") return localVoiceModels;
    return localVoiceModels.filter((m) => {
      const info = getModelLanguage(m);
      if (selectedLangFilter === "multilingual") return info.type === "multilingual";
      if (selectedLangFilter === "english") return info.type === "english";
      if (selectedLangFilter === "specialized") return info.type === "specialized";
      return true;
    });
  }, [localVoiceModels, selectedLangFilter]);

  const filteredCloudVoiceModels = useMemo(() => {
    if (selectedLangFilter === "all") return cloudVoiceModels;
    return cloudVoiceModels.filter((m) => {
      const info = getModelLanguage(m);
      if (selectedLangFilter === "multilingual") return info.type === "multilingual";
      if (selectedLangFilter === "english") return info.type === "english";
      if (selectedLangFilter === "specialized") return info.type === "specialized";
      return true;
    });
  }, [cloudVoiceModels, selectedLangFilter]);

  // Injected custom models picked from OpenRouter at the top
  const cloudTextModels = useMemo(() => {
    return [...customCloudModels, ...baseCloudTextModels];
  }, [customCloudModels, baseCloudTextModels]);

  const displayedCloudTextModels = useMemo(() => {
    if (showAllCloudTextModels) return cloudTextModels;
    return cloudTextModels.slice(0, 4);
  }, [showAllCloudTextModels, cloudTextModels]);

  const renderModelRow = (model: DictyModel) => {
    const isActive = activeModelId === model.id;
    const isSelected = selectedModelId === model.id;
    const isFav = favorites.has(model.id);
    const isDownloading = downloadingIds.has(model.id);
    const progress = downloadingIds.get(model.id) || 0;
    const langInfo = getModelLanguage(model);
    const currentQuality = getSelectedQuality(model.id);
    const isDropdownOpen = openDropdownId === model.id;

    return (
      <div key={model.id} className="space-y-1">
        {/* Model Main Row */}
        <div
          onClick={() => {
            // Selecting the model lets user view & choose quantization options
            setSelectedModelId(selectedModelId === model.id ? null : model.id);
            if (model.is_downloaded || model.is_cloud) {
              setActiveModelId(model.id);
              localStorage.setItem("dicty_active_model", model.id);
              engineApi.setActiveModel(model.id).catch(() => {});

              // Associate selected model with the currently active mode profile
              try {
                const activeProfId = localStorage.getItem("dicty_active_profile") || "prof_1";
                const rawProfiles = localStorage.getItem("dicty_profiles_v2");
                let profilesList: any[] = rawProfiles ? JSON.parse(rawProfiles) : [];
                if (!Array.isArray(profilesList) || profilesList.length === 0) {
                  profilesList = [
                    { id: "prof_1", whisperModel: "base.en" },
                    { id: "prof_2", whisperModel: "base.en" },
                    { id: "prof_3", whisperModel: "small.en" },
                    { id: "prof_4", whisperModel: "base" },
                    { id: "prof_5", whisperModel: "small.en" },
                  ];
                }
                const idx = profilesList.findIndex((p: any) => p.id === activeProfId);
                if (idx !== -1) {
                  profilesList[idx].whisperModel = model.id;
                } else {
                  profilesList.push({ id: activeProfId, whisperModel: model.id });
                }
                localStorage.setItem("dicty_profiles_v2", JSON.stringify(profilesList));
                invoke("set_profile_model", { profileId: activeProfId, modelId: model.id }).catch(() => {});
                window.dispatchEvent(new Event("storage"));
              } catch (err) {
                console.warn("Failed to persist model to active profile:", err);
              }
            }
          }}
          className={`group flex items-center h-8 px-2 sm:px-2.5 rounded-lg text-xs transition-all cursor-pointer w-full min-w-0 ${
            isActive
              ? "bg-[#278C40]/20 border border-[#278C40]/40 text-white"
              : isSelected
              ? "bg-[#5D6658]/20 border border-[#5D6658]/40 text-white"
              : "text-white/80 hover:bg-white/[0.04] border border-transparent"
          }`}
        >
          {/* Favorite Star (width: 16-20px) */}
          <button
            onClick={(e) => toggleFavorite(model.id, e)}
            className="w-4 sm:w-5 flex items-center justify-start flex-shrink-0"
          >
            <Star
              className={`w-3 h-3 transition-colors ${
                isFav
                  ? "text-amber-400 fill-amber-400"
                  : "text-white/20 group-hover:text-white/40"
              }`}
            />
          </button>

          {/* Name + Info Button (high priority, guaranteed minimum width so never squashed) */}
          <div className="flex-1 min-w-[130px] sm:min-w-[170px] flex items-center gap-1 sm:gap-1.5 pr-1 sm:pr-2">
            {getProviderIcon(model.id, 12)}
            {model.category === "text" && (
              <Cpu className="w-3.5 h-3.5 text-[#5A8BA8] flex-shrink-0" />
            )}
            <span
              className={`truncate text-xs sm:text-sm font-medium ${
                isActive ? "font-semibold text-white" : "text-white/90"
              }`}
            >
              {model.name}
            </span>
            <button
              onClick={(e) => {
                e.stopPropagation();
                setInspectedModel(model);
              }}
              className="text-white/30 hover:text-white p-0.5 flex-shrink-0"
              title="Inspect model details & quality specifications"
            >
              <Info className="w-3 h-3" />
            </button>
          </div>

          {/* Dedicated Language Support Column (flexible label squashes on narrow windows) */}
          <div className="w-[100px] sm:w-[140px] flex items-center flex-shrink min-w-[60px] px-1">
            {langInfo.type === "multilingual" ? (
              <span
                className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-white/[0.04] border border-white/10 text-white/70 min-w-0 max-w-full"
                title={langInfo.tooltip}
              >
                <Globe className="w-2.5 h-2.5 text-[#5A8BA8] flex-shrink-0" />
                <span className="truncate">Multi (99+ RU, EN...)</span>
              </span>
            ) : langInfo.type === "english" ? (
              <span
                className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-white/[0.04] border border-white/10 text-white/70 min-w-0 max-w-full"
                title={langInfo.tooltip}
              >
                <span className="text-[8.5px] font-bold px-1 rounded bg-white/10 text-white/80">EN</span>
                <span className="truncate">English Only</span>
              </span>
            ) : langInfo.type === "specialized" ? (
              <span
                className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-white/[0.04] border border-white/10 text-white/70 min-w-0 max-w-full"
                title={langInfo.tooltip}
              >
                <span className="text-[8.5px] font-bold px-1 rounded bg-white/10 text-white/80">
                  {langInfo.badge}
                </span>
                <span className="truncate">{langInfo.label}</span>
              </span>
            ) : (
              <span
                className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-white/[0.04] border border-white/10 text-white/70 min-w-0 max-w-full"
                title={langInfo.tooltip}
              >
                <Cpu className="w-2.5 h-2.5 text-[#5A8BA8] flex-shrink-0" />
                <span className="truncate">Text AI</span>
              </span>
            )}
          </div>

          {/* Speed & Accuracy Dual Micro-Meters (width: 64-80px) */}
          <div
            className="w-[64px] sm:w-[80px] flex flex-col justify-center gap-0.5 sm:gap-1 flex-shrink-0 cursor-help"
            title={`Speed: ${Math.round(model.speed * 100)}% | Accuracy: ${Math.round(model.accuracy * 100)}%`}
          >
            {/* SPD Bar */}
            <div className="flex items-center gap-1" title={`Speed (Скорость инференса): ${Math.round(model.speed * 100)}%`}>
              <span className="text-[7px] sm:text-[7.5px] font-mono font-bold text-[#5A8BA8] w-3.5 sm:w-4">
                SPD
              </span>
              <div className="w-8 sm:w-11 h-1 bg-white/10 rounded-full overflow-hidden">
                <div
                  className="h-full bg-[#5A8BA8] rounded-full"
                  style={{ width: `${Math.min(model.speed * 100, 100)}%` }}
                />
              </div>
            </div>
            {/* ACC Bar */}
            <div className="flex items-center gap-1" title={`Accuracy (Точность распознавания речи): ${Math.round(model.accuracy * 100)}%`}>
              <span className="text-[7px] sm:text-[7.5px] font-mono font-bold text-[#5D6658] w-3.5 sm:w-4">
                ACC
              </span>
              <div className="w-8 sm:w-11 h-1 bg-white/10 rounded-full overflow-hidden">
                <div
                  className="h-full bg-[#278C40] rounded-full"
                  style={{ width: `${Math.min(model.accuracy * 100, 100)}%` }}
                />
              </div>
            </div>
          </div>

          {/* Quantization / Type Column (width: 68-80px) */}
          <div className="w-[68px] sm:w-[80px] flex items-center justify-center sm:justify-start gap-1 text-[10px] sm:text-[11px] font-medium flex-shrink-0 relative">
            {model.is_cloud ? (
              <div className="flex items-center gap-1 sm:gap-1.5">
                <Cloud className="w-3 h-3 text-sky-400" />
                <span className="text-sky-300">Cloud</span>
              </div>
            ) : (
              /* Interactive Quantization Selector Dropdown */
              <div className="relative" onClick={(e) => e.stopPropagation()}>
                <button
                  type="button"
                  onClick={() => setOpenDropdownId(isDropdownOpen ? null : model.id)}
                  className={`flex items-center gap-0.5 sm:gap-1 px-1 sm:px-1.5 py-0.5 rounded text-[9.5px] sm:text-[10px] font-mono font-semibold transition-all border ${
                    model.is_downloaded
                      ? "bg-emerald-500/15 border-emerald-500/30 text-emerald-300 hover:bg-emerald-500/25"
                      : "bg-white/[0.06] border-white/15 text-white/80 hover:bg-white/10"
                  }`}
                  title="Choose Quantization Type"
                >
                  <HardDrive className="w-2.5 h-2.5 opacity-70" />
                  <span>{currentQuality.toUpperCase().replace("_0", "")}</span>
                  <ChevronDown className="w-2.5 h-2.5 opacity-60" />
                </button>

                {/* Dropdown Menu for Quantization Choice */}
                {isDropdownOpen && (
                  <div className="absolute top-6 right-0 sm:left-0 z-50 w-52 bg-[#181B20] border border-white/15 rounded-xl shadow-2xl p-1.5 space-y-1 select-none animate-fadeIn">
                    <div className="px-2 py-1 text-[9.5px] font-bold text-white/40 uppercase tracking-wider">
                      Select Quantization
                    </div>
                    {QUANTIZATION_OPTIONS.map((opt) => {
                      const isChosen = currentQuality === opt.id;
                      const est = calculateEstimatedSize(model.size, opt.id);
                      return (
                        <button
                          key={opt.id}
                          type="button"
                          onClick={() => {
                            setSelectedQuantizations((prev) => ({
                              ...prev,
                              [model.id]: opt.id,
                            }));
                            setOpenDropdownId(null);
                            if (model.is_downloaded) {
                              handleApplyPrecision(model.id, opt.id);
                            }
                          }}
                          className={`w-full flex items-center justify-between px-2 py-1.5 rounded-lg text-left text-xs transition-colors ${
                            isChosen
                              ? "bg-[#5D6658]/30 text-white font-bold"
                              : "text-white/70 hover:bg-white/[0.06] hover:text-white"
                          }`}
                        >
                          <div className="flex items-center gap-1.5">
                            {isChosen ? (
                              <Check className="w-3 h-3 text-emerald-400" />
                            ) : (
                              <div className="w-3 h-3" />
                            )}
                            <span>{opt.label}</span>
                            <span className="text-[10px] text-white/40 font-normal">
                              ({opt.badge})
                            </span>
                          </div>
                          <span className="font-mono text-[10px] text-white/60">
                            {est}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Status / Action Column (width: 36-48px, aligned right) */}
          <div className="w-[36px] sm:w-[48px] flex items-center justify-end flex-shrink-0">
            {isDownloading ? (
              <div className="flex items-center gap-1">
                <span className="text-[10px] font-mono font-bold text-emerald-400">
                  {progress}%
                </span>
                <button
                  onClick={(e) => handleCancelDownload(model.id, e)}
                  className="text-white/40 hover:text-red-400 p-0.5"
                  title="Cancel download"
                >
                  <XCircle className="w-3 h-3" />
                </button>
              </div>
            ) : model.is_cloud || model.is_downloaded ? (
              isActive ? (
                <div className="w-4 h-4 rounded-full bg-emerald-500 text-black flex items-center justify-center font-bold text-[10px] shadow-sm" title="Active Model">
                  ✓
                </div>
              ) : (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveModelId(model.id);
                    localStorage.setItem("dicty_active_model", model.id);
                    engineApi.setActiveModel(model.id).catch(() => {});
                  }}
                  className="text-white/30 hover:text-white transition-colors p-1"
                  title="Activate model"
                >
                  <PlayCircle className="w-4 h-4" />
                </button>
              )
            ) : (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  handleDownload(model.id, e);
                }}
                className={`transition-colors p-1 ${
                  isActive ? "text-amber-400 hover:text-amber-300" : "text-white/30 hover:text-emerald-400"
                }`}
                title={
                  isActive
                    ? `Active model not yet downloaded to local folder. Click to download (${calculateEstimatedSize(model.size, currentQuality)})`
                    : `Download in ${currentQuality.toUpperCase().replace("_0", "")} (${calculateEstimatedSize(model.size, currentQuality)})`
                }
              >
                <ArrowDownCircle className="w-4 h-4" />
              </button>
            )}
          </div>
        </div>

        {/* Expandable Quantization & Quality Selection Panel when Model is Selected */}
        {isSelected && !model.is_cloud && (
          <div
            onClick={(e) => e.stopPropagation()}
            className="mx-2 mb-2 p-3.5 rounded-xl bg-white/[0.03] border border-[#5D6658]/40 space-y-3 animate-fadeIn shadow-lg shadow-black/40"
          >
            {/* Header with Title and Current State */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-white tracking-tight">
                  Download & Quantization Options
                </span>
                <span className="text-[10px] text-white/50">
                  ({model.name} • {model.size} Base)
                </span>
              </div>
              <div className="flex items-center gap-2">
                {model.is_downloaded ? (
                  <span className="px-2 py-0.5 rounded-md bg-[#278C40]/20 border border-[#278C40]/40 text-[#87B996] text-[10px] font-semibold">
                    Installed: {(model.quantization || "q5_0").toUpperCase().replace("_0", "")}
                  </span>
                ) : (
                  <span className="px-2 py-0.5 rounded-md bg-white/[0.06] border border-white/10 text-white/50 text-[10px] font-semibold">
                    Select Precision to Download
                  </span>
                )}
                <button
                  onClick={() => setSelectedModelId(null)}
                  className="text-white/30 hover:text-white p-0.5"
                  title="Collapse panel"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            {/* 3 Selectable Quantization Options (Q5, F16, Q4) */}
            <div className="grid grid-cols-3 gap-2">
              {QUANTIZATION_OPTIONS.map((opt) => {
                const isOptSelected = currentQuality === opt.id;
                const estSize = calculateEstimatedSize(model.size, opt.id);
                return (
                  <button
                    key={opt.id}
                    type="button"
                    onClick={() => {
                      setSelectedQuantizations((prev) => ({
                        ...prev,
                        [model.id]: opt.id,
                      }));
                    }}
                    className={`p-2.5 rounded-xl border text-left transition-all relative flex flex-col justify-between ${
                      isOptSelected
                        ? "bg-[#5D6658]/25 border-[#87B996] text-white shadow-sm ring-1 ring-[#87B996]/30"
                        : "bg-black/30 border-white/10 text-white/70 hover:bg-white/[0.04]"
                    }`}
                  >
                    <div className="space-y-1">
                      <div className="flex items-center justify-between gap-1 min-w-0">
                        <div className="flex items-center gap-1.5 min-w-0">
                          <div
                            className={`w-3 h-3 rounded-full border flex-shrink-0 flex items-center justify-center ${
                              isOptSelected
                                ? "border-[#87B996] bg-[#87B996]"
                                : "border-white/30"
                            }`}
                          >
                            {isOptSelected && (
                              <div className="w-1 h-1 rounded-full bg-black" />
                            )}
                          </div>
                          <span className="text-xs font-bold text-white truncate">
                            {opt.shortTitle}
                          </span>
                        </div>
                        <span
                          className={`px-1.5 py-0.5 rounded text-[8.5px] font-bold flex-shrink-0 whitespace-nowrap ${
                            opt.id === "q5_0"
                              ? "bg-[#278C40]/25 text-[#87B996]"
                              : "bg-white/[0.08] text-white/60"
                          }`}
                        >
                          {opt.badge}
                        </span>
                      </div>
                      <p className="text-[10px] text-white/60 leading-tight">
                        {opt.description}
                      </p>
                    </div>
                    <div className="pt-2 flex items-center justify-between border-t border-white/[0.06] mt-2">
                      <span className="text-[9.5px] text-white/40">Est. Size</span>
                      <span className="font-mono text-[11px] font-bold text-white">
                        {estSize}
                      </span>
                    </div>
                  </button>
                );
              })}
            </div>

            {/* Bottom Action Row */}
            <div className="flex items-center justify-between pt-1">
              <div className="flex items-center gap-1.5 text-[11px] text-white/50">
                <Info className="w-3.5 h-3.5 text-[#87B996]" />
                <span>
                  {currentQuality === "q5_0"
                    ? "Q5 offers ~99% studio accuracy with 50% RAM savings — recommended for all users."
                    : currentQuality === "f16"
                    ? "F16 provides uncompressed 16-bit acoustic weights for maximum transcription fidelity."
                    : "Q4 utilizes 4-bit quantization for minimal memory usage and lightning-fast inference."}
                </span>
              </div>

              <div>
                {isDownloading ? (
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono font-bold text-emerald-400">
                      Downloading ({progress}%)...
                    </span>
                    <button
                      onClick={(e) => handleCancelDownload(model.id, e)}
                      className="px-2.5 py-1 rounded-lg bg-red-500/20 text-red-300 text-xs font-medium hover:bg-red-500/30"
                    >
                      Cancel
                    </button>
                  </div>
                ) : model.is_downloaded ? (
                  model.quantization === currentQuality ? (
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-emerald-400 font-medium flex items-center gap-1">
                        <CheckCircle2 className="w-3.5 h-3.5" /> Ready Offline
                      </span>
                      <button
                        onClick={() => {
                          setActiveModelId(model.id);
                          localStorage.setItem("dicty_active_model", model.id);
                          engineApi.setActiveModel(model.id).catch(() => {});
                        }}
                        className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${
                          isActive
                            ? "bg-emerald-500 text-black cursor-default"
                            : "bg-white/10 hover:bg-white/20 text-white"
                        }`}
                      >
                        {isActive ? "Active Model" : "Set Active"}
                      </button>
                    </div>
                  ) : (
                    <button
                      onClick={(e) => handleApplyPrecision(model.id, currentQuality, e)}
                      className="px-4 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 text-white text-xs font-bold border border-white/15 flex items-center gap-1.5 transition-all shadow-sm"
                    >
                      <Check className="w-3.5 h-3.5 text-emerald-400" />
                      <span>
                        Apply Precision: {currentQuality.toUpperCase().replace("_0", "")}
                      </span>
                    </button>
                  )
                ) : (
                  <button
                    onClick={(e) => handleDownload(model.id, e)}
                    className="px-4 py-1.5 rounded-xl bg-gradient-to-r from-[#5D6658] to-[#278C40] hover:brightness-110 text-white text-xs font-bold shadow-md shadow-[#278C40]/20 flex items-center gap-1.5 transition-all"
                  >
                    <ArrowDownCircle className="w-3.5 h-3.5" />
                    <span>
                      Download in {currentQuality.toUpperCase().replace("_0", "")} ({calculateEstimatedSize(model.size, currentQuality)})
                    </span>
                  </button>
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="w-full flex-1 overflow-y-auto overflow-x-hidden p-3.5 sm:p-6 max-w-4xl mx-auto space-y-4 select-none relative min-w-0">
      {/* Header: Title and Controls (1:1 with ModelsLibraryView.swift lines 160-230) */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2.5 sm:gap-4 min-w-0 pt-1">
        <div className="flex items-center gap-2 min-w-0">
          <h2 className="text-lg font-bold text-white tracking-tight truncate">
            Available Models
          </h2>
          <FeatureHelpButton topic="models" label="Models & Quantization Guide" />
        </div>

        <div className="flex items-center gap-2 sm:gap-3 flex-wrap flex-shrink-0 self-start sm:self-auto">
          {/* Use Dicty Cloud Toggle with PRO badge */}
          <div className="flex items-center gap-2 bg-white/[0.03] border border-white/10 px-2.5 py-1.5 rounded-xl">
            <div className="flex items-center gap-1.5 text-xs text-white/70 font-medium">
              <Cloud className="w-3.5 h-3.5 text-white/50" />
              <span>Use Dicty Cloud</span>
            </div>
            <span className="px-1.5 py-0.2 rounded bg-white/10 text-white/70 text-[9px] font-bold tracking-wider">
              PRO
            </span>
            <ToggleSwitch
              size="sm"
              checked={useDictyCloud}
              onChange={setUseDictyCloud}
              ariaLabel="Use Dicty Cloud"
            />
          </div>

          {/* Open Folder Button */}
          <button
            onClick={handleOpenFolder}
            className="px-2.5 sm:px-3 py-1.5 rounded-xl bg-white/[0.04] hover:bg-white/10 text-white text-xs font-medium border border-white/10 flex items-center gap-1.5 transition-all flex-shrink-0"
          >
            <Folder className="w-3.5 h-3.5 text-[#87B996]" />
            <span>Open Folder</span>
          </button>
        </div>
      </div>

      {/* Where should Dicty run AI? */}
      <AILocationCard />

      {/* Header Info Banner (if toggled) */}
      {showHeaderInfo && (
        <div className="p-4 rounded-2xl bg-white/[0.04] border border-white/10 text-xs text-white/70 space-y-2 relative animate-fadeIn">
          <button
            onClick={() => setShowHeaderInfo(false)}
            className="absolute top-3 right-3 text-white/40 hover:text-white"
          >
            <X className="w-3.5 h-3.5" />
          </button>
          <span className="font-bold text-white block">
            Why Quantization Matters:
          </span>
          <ul className="space-y-1 text-[11px] list-disc list-inside text-white/60">
            <li>
              <strong className="text-white/80">Q5 (Recommended):</strong> Retains ~99% studio accuracy while cutting RAM and disk usage in half.
            </li>
            <li>
              <strong className="text-white/80">F16 (Original):</strong> 16-bit uncompressed weights. Maximum precision for difficult accents or noisy audio.
            </li>
            <li>
              <strong className="text-white/80">Q4 (Ultra Light):</strong> 4-bit integer weights. Blazing fast inference and minimal memory footprint.
            </li>
          </ul>
        </div>
      )}

      {/* Choose models yourself */}
      <button
        type="button"
        onClick={() => setShowModelPicker(!showModelPicker)}
        className="w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl bg-white/[0.03] hover:bg-white/[0.06] border border-white/[0.08] transition-all"
      >
        <div className="flex items-center gap-2">
          <ChevronRight
            className={`w-3.5 h-3.5 text-white/50 transition-transform duration-200 ${
              showModelPicker ? "rotate-90" : ""
            }`}
          />
          <Settings2 className="w-4 h-4 text-[#87B996]" />
          <span className="text-xs font-bold text-white tracking-tight">
            Choose models yourself
          </span>
        </div>
        <span className="text-xs font-medium text-white/40 hover:text-white/80 transition-colors">
          {showModelPicker ? "Hide" : "Show"}
        </span>
      </button>

      {showModelPicker && (
        <>
      {/* Informative Language Tip Banner (subtle grey and light blue style matching Dicty) */}
      <div className="flex items-center gap-2.5 p-2.5 rounded-xl bg-white/[0.03] border border-white/10 text-xs text-white/75">
        <Globe className="w-4 h-4 text-[#5A8BA8] flex-shrink-0" />
        <div className="flex-1 min-w-0 text-[11px] sm:text-xs">
          <span className="font-semibold text-white/90">Language Support: </span>
          <span className="text-white/60">
            Multilingual models (Nano, Base, Fast, Turbo, Max) automatically detect and transcribe <strong>Russian, English, German, Spanish</strong> and 95+ other languages.
          </span>
        </div>
      </div>

      {/* Language Filter Buttons */}
      <div className="flex items-center justify-between gap-2 flex-wrap pt-0.5">
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className="text-[11px] font-medium text-white/40 mr-1">Filter Language:</span>
          {[
            { id: "all", label: "All Models" },
            { id: "multilingual", label: "🌐 Multilingual (RU, EN, DE...)" },
            { id: "english", label: "EN English Only" },
            { id: "specialized", label: "Regional (JA, ZH, FR)" },
          ].map((tab) => (
            <button
              key={tab.id}
              type="button"
              onClick={() => setSelectedLangFilter(tab.id as LanguageCategory)}
              className={`px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all ${
                selectedLangFilter === tab.id
                  ? "bg-[#5A8BA8]/20 text-white border border-[#5A8BA8]/40 shadow-sm"
                  : "bg-white/[0.03] text-white/60 hover:text-white hover:bg-white/[0.07] border border-white/5"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
        {selectedLangFilter !== "all" && (
          <button
            type="button"
            onClick={() => setSelectedLangFilter("all")}
            className="text-[11px] text-[#5A8BA8] hover:text-white underline cursor-pointer"
          >
            Reset filter
          </button>
        )}
      </div>

      {/* Table Column Headers (1:1 alignment with renderModelRow) */}
      <div className="flex items-center text-[11px] font-medium text-white/40 px-2 sm:px-2.5 pb-1 border-b border-white/10 w-full min-w-0">
        <span className="w-4 sm:w-5 flex-shrink-0" />
        <span className="flex-1 min-w-[130px] sm:min-w-[170px] pl-1 truncate">Model name</span>
        <span
          className="w-[100px] sm:w-[140px] flex-shrink min-w-[60px] px-1 truncate cursor-help hover:text-white/70 transition-colors"
          title="Language support: 🌐 Multilingual (Russian, English, etc.) vs EN (English only) vs Specialized"
        >
          Language
        </span>
        <div
          className="w-[64px] sm:w-[80px] flex items-center flex-shrink-0 cursor-help hover:opacity-100 transition-opacity"
          title="Performance: SPD (Inference Speed) / ACC (Speech Recognition Accuracy benchmark)"
        >
          <span className="text-[#5A8BA8]">Speed</span>
          <span className="text-white/30 px-0.5 sm:px-1">/</span>
          <span className="text-[#5D6658]">Acc.</span>
        </div>
        <span
          className="w-[68px] sm:w-[80px] flex-shrink-0 text-center sm:text-left cursor-help hover:text-white/70 transition-colors"
          title="Quantization precision: Q5 (Balanced), F16 (Studio original), Q4 (Fast)"
        >
          Quantization
        </span>
        <span className="w-[36px] sm:w-[48px] text-right flex-shrink-0">Status</span>
      </div>

      {/* Grouped Table Cards (1:1 with ModelsLibraryView.swift) */}
      <div className="space-y-5 w-full min-w-0">
        {/* SECTION 1: VOICE RECOGNITION MODELS (ASR) */}
        <div className="p-2 sm:p-3 rounded-2xl bg-white/[0.02] border border-white/[0.07] space-y-2 w-full min-w-0">
          {/* Section Header */}
          <div className="flex items-center gap-1.5 px-2 pt-1">
            <AudioWaveform className="w-4 h-4 text-[#87B996]" />
            <h3 className="text-xs font-bold text-white tracking-tight">
              Voice Recognition Models (ASR)
            </h3>
            <Info className="w-3 h-3 text-white/30" />
          </div>

          {/* Subtitle: Local Speech Models */}
          <div className="text-[10px] font-bold uppercase tracking-wider text-white/40 px-2 pt-1 flex items-center justify-between">
            <span>Local Speech Models</span>
            {selectedLangFilter !== "all" && (
              <span className="text-[9px] text-emerald-400/80 lowercase">
                ({filteredLocalVoiceModels.length} shown)
              </span>
            )}
          </div>
          <div className="space-y-0.5">
            {filteredLocalVoiceModels.length > 0 ? (
              filteredLocalVoiceModels.map((m) => renderModelRow(m))
            ) : (
              <div className="py-4 text-center text-xs text-white/40 italic">
                No local speech models match the selected language filter.
              </div>
            )}
          </div>

          {/* Subtitle: Cloud Speech Models */}
          <div className="flex items-center gap-2 px-2 pt-3">
            <span className="text-[10px] font-bold uppercase tracking-wider text-white/40">
              Cloud Speech Models
            </span>
            <span className="px-1 py-0.1 rounded bg-white/10 text-white/60 text-[8px] font-bold tracking-wider">
              PRO
            </span>
            {selectedLangFilter !== "all" && (
              <span className="text-[9px] text-emerald-400/80 lowercase">
                ({filteredCloudVoiceModels.length} shown)
              </span>
            )}
          </div>
          <div className="space-y-0.5">
            {filteredCloudVoiceModels.length > 0 ? (
              filteredCloudVoiceModels.map((m) => renderModelRow(m))
            ) : (
              <div className="py-4 text-center text-xs text-white/40 italic">
                No cloud speech models match the selected language filter.
              </div>
            )}
          </div>
        </div>

        {/* SECTION 2: AI & TEXT MODELS */}
        <div className="p-2 sm:p-3 rounded-2xl bg-white/[0.02] border border-white/[0.07] space-y-2 w-full min-w-0">
          {/* Section Header */}
          <div className="flex items-center gap-1.5 px-2 pt-1">
            <Sparkles className="w-4 h-4 text-[#87B996]" />
            <h3 className="text-xs font-bold text-white tracking-tight">
              AI & Text Models
            </h3>
            <Info className="w-3 h-3 text-white/30" />
          </div>

          {/* Subtitle: Local Text Models (GGUF) */}
          <div className="text-[10px] font-bold uppercase tracking-wider text-white/40 px-2 pt-1">
            Local Text Models (Downloadable GGUF)
          </div>
          <div className="space-y-0.5">
            {localTextModels.map((m) => renderModelRow(m))}
          </div>

          {/* Subtitle: Cloud Text Models with PRO badge & Explore 400+ Models button */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between px-2 pt-3 pb-1 gap-2 min-w-0">
            <div className="flex items-center gap-2">
              <span className="text-[10px] font-bold uppercase tracking-wider text-white/40">
                Cloud Text Models
              </span>
              <span className="px-1.5 py-0.2 rounded bg-white/10 text-white/70 text-[9px] font-bold tracking-wider">
                PRO
              </span>
            </div>

            {/* Explore 400+ Models Button (1:1 with ModelsLibraryView.swift line 371) */}
            <button
              type="button"
              onClick={() => setShowOpenRouterExplorer(true)}
              className="self-start sm:self-auto px-2.5 py-1 rounded-lg bg-white/[0.06] hover:bg-white/15 border border-white/10 text-white text-xs font-semibold flex items-center gap-1.5 transition-all shadow-sm group flex-shrink-0"
            >
              <Sparkles className="w-3 h-3 text-amber-400 group-hover:scale-110 transition-transform" />
              <span>Explore 400+ Models</span>
            </button>
          </div>

          <div className="space-y-0.5">
            {displayedCloudTextModels.map((m) => renderModelRow(m))}
          </div>

          {/* Show More / Show Less Models Button */}
          {cloudTextModels.length > 4 && (
            <button
              type="button"
              onClick={() => setShowAllCloudTextModels(!showAllCloudTextModels)}
              className="w-full mt-2 py-1.5 px-4 rounded-xl bg-white/[0.03] hover:bg-white/[0.07] border border-white/10 text-white/60 hover:text-white text-xs font-semibold flex items-center justify-center gap-1.5 transition-all"
            >
              <span>{showAllCloudTextModels ? "Show Less Models" : "Show More Models"}</span>
              {showAllCloudTextModels ? (
                <ChevronUp className="w-3.5 h-3.5 text-white/50" />
              ) : (
                <ChevronDown className="w-3.5 h-3.5 text-white/50" />
              )}
            </button>
          )}
        </div>
      </div>
        </>
      )}

      {/* SECTION 3: ADVANCED MODEL SETTINGS (1:1 with ModelsLibraryView.swift lines 463-735) */}
      <div className="space-y-2">
          {/* Collapsible Header Button */}
          <button
            type="button"
            onClick={() => setIsAdvancedSettingsExpanded(!isAdvancedSettingsExpanded)}
            className="w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl bg-white/[0.03] hover:bg-white/[0.06] border border-white/[0.08] transition-all"
          >
            <div className="flex items-center gap-2">
              <ChevronRight
                className={`w-3.5 h-3.5 text-white/50 transition-transform duration-200 ${
                  isAdvancedSettingsExpanded ? "rotate-90" : ""
                }`}
              />
              <Settings2 className="w-4 h-4 text-[#87B996]" />
              <span className="text-xs font-bold text-white tracking-tight">
                Performance
              </span>
            </div>

            <span className="text-xs font-medium text-white/40 hover:text-white/80 transition-colors">
              {isAdvancedSettingsExpanded ? "Hide" : "Show"}
            </span>
          </button>

          {/* Collapsible Settings Content */}
          {isAdvancedSettingsExpanded && (
            <div className="space-y-2 animate-fadeIn">
              {/* Card 1: Spoken Language and Keep in RAM */}
              <div className="p-3 rounded-2xl bg-white/[0.02] border border-white/[0.07] divide-y divide-white/[0.06]">
                {/* Row 1: Spoken Language (Full list of 100 languages) */}
                <div className="flex items-center justify-between py-2 first:pt-0">
                  <div className="flex items-center gap-2">
                    <Globe className="w-4 h-4 text-[#87B996]" />
                    <span className="text-xs font-medium text-white">
                      Spoken language
                    </span>
                    <div className="relative">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setActiveTooltip(
                            activeTooltip === "spokenLanguage" ? null : "spokenLanguage"
                          );
                        }}
                        className="text-white/30 hover:text-white"
                        title="Spoken Language Info"
                      >
                        <Info className="w-3.5 h-3.5" />
                      </button>
                      {activeTooltip === "spokenLanguage" && (
                        <div
                          onClick={(e) => e.stopPropagation()}
                          className="absolute left-6 top-0 z-50 w-64 p-2.5 rounded-xl bg-[#1A1D24] border border-white/20 shadow-2xl text-[11px] text-white/80"
                        >
                          Select the language you will speak. &apos;Auto Detect&apos; works well for most languages, but choosing your exact language makes transcription even faster and more accurate.
                        </div>
                      )}
                    </div>
                  </div>

                  <div className="relative" onClick={(e) => e.stopPropagation()}>
                    <select
                      disabled={activeModelId.endsWith(".en") || activeModelId === "distil-large-v3"}
                      value={
                        activeModelId.endsWith(".en") || activeModelId === "distil-large-v3"
                          ? "en"
                          : spokenLanguage
                      }
                      onChange={(e) => setSpokenLanguage(e.target.value)}
                      className={`bg-white/[0.04] hover:bg-white/[0.08] border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white/90 focus:outline-none focus:border-[#87B996] appearance-none pr-8 cursor-pointer font-medium ${
                        activeModelId.endsWith(".en") || activeModelId === "distil-large-v3"
                          ? "opacity-60 cursor-not-allowed"
                          : ""
                      }`}
                    >
                      {activeModelId.endsWith(".en") || activeModelId === "distil-large-v3" ? (
                        <option value="en" className="bg-[#181B20] text-white">
                          English (Model Only)
                        </option>
                      ) : (
                        WHISPER_LANGUAGES.map((lang) => (
                          <option key={lang.code} value={lang.code} className="bg-[#181B20] text-white">
                            {lang.name}
                          </option>
                        ))
                      )}
                    </select>
                    <ChevronDown className="w-3 h-3 text-white/40 absolute right-2.5 top-2.5 pointer-events-none" />
                  </div>
                </div>

                {/* Row 2: Keep Model in RAM (Fast) */}
                <div className="flex items-center justify-between py-2 last:pb-0">
                  <div className="flex items-center gap-2">
                    <MemoryStick className="w-4 h-4 text-[#87B996]" />
                    <span className="text-xs font-medium text-white">
                      Keep model in RAM (Fast)
                    </span>
                    <div className="relative">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setActiveTooltip(
                            activeTooltip === "keepRam" ? null : "keepRam"
                          );
                        }}
                        className="text-white/30 hover:text-white"
                        title="Keep Model in RAM Info"
                      >
                        <Info className="w-3.5 h-3.5" />
                      </button>
                      {activeTooltip === "keepRam" && (
                        <div
                          onClick={(e) => e.stopPropagation()}
                          className="absolute left-6 bottom-0 z-50 w-64 p-2.5 rounded-xl bg-[#1A1D24] border border-white/20 shadow-2xl text-[11px] text-white/80"
                        >
                          Keeps speech recognition model warm in memory for instant, zero-delay typing. If turned off, takes ~2 seconds to warm up before each recording, but frees system RAM.
                        </div>
                      )}
                    </div>
                  </div>

                  {/* macOS Styled Green Switch */}
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      setKeepModelInRam(!keepModelInRam);
                    }}
                    className={`w-11 h-6 rounded-full transition-all relative flex items-center p-0.5 ${
                      keepModelInRam
                        ? "bg-[#278C40]"
                        : "bg-white/20 hover:bg-white/30"
                    }`}
                  >
                    <div
                      className={`w-5 h-5 rounded-full bg-white transition-transform duration-200 shadow-md ${
                        keepModelInRam ? "translate-x-5" : "translate-x-0"
                      }`}
                    />
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>

      {/* Model Details Modal (1:1 with ModelDetailsPopoverView.swift lines 1055-1240) */}
      {inspectedModel && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-md z-50 flex items-center justify-center p-4">
          <div className="w-full max-w-md bg-[#181B20] border border-white/15 rounded-2xl p-6 shadow-2xl space-y-4 select-none animate-fadeIn">
            <div className="flex items-center justify-between border-b border-white/10 pb-3">
              <div className="flex items-center gap-2">
                <h3 className="text-base font-bold text-white tracking-tight">
                  {inspectedModel.name}
                </h3>
                <span
                  className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                    inspectedModel.is_cloud
                      ? "bg-sky-500/15 text-sky-300 border border-sky-500/20"
                      : inspectedModel.is_downloaded
                      ? "bg-emerald-500/15 text-emerald-300 border border-emerald-500/20"
                      : "bg-white/[0.06] text-white/50 border border-white/10"
                  }`}
                >
                  {inspectedModel.is_cloud
                    ? "Cloud API"
                    : inspectedModel.is_downloaded
                    ? "Ready • Offline"
                    : "Local Download"}
                </span>
              </div>
              <button
                onClick={() => setInspectedModel(null)}
                className="text-white/40 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <p className="text-xs text-white/70 leading-relaxed">
              {inspectedModel.description}
            </p>

            {/* Specifications & Quantization Selection (1:1 with Swift ModelDetailsPopoverView) */}
            <div className="border-t border-white/10 pt-3 space-y-3 text-xs">
              <span className="font-bold text-white/60 text-[11px] block">
                Specifications & Quality
              </span>

              {inspectedModel.is_cloud ? (
                <div className="flex items-center justify-between text-white/80 bg-black/30 p-2.5 rounded-xl border border-white/10">
                  <span className="flex items-center gap-1.5">
                    <Cloud className="w-3.5 h-3.5 text-sky-400" />
                    <span>Cloud Processing (Zero Local RAM Required)</span>
                  </span>
                  <span className="font-mono font-bold text-white">Cloud</span>
                </div>
              ) : (
                <div className="space-y-2">
                  <span className="text-[11px] text-white/50 block">
                    {inspectedModel.is_downloaded
                      ? "Select Quality Option to Switch / Re-download:"
                      : "Select Download Quality Option:"}
                  </span>

                  {/* Quantization Radio Options (q5_0, f16, q4_0) */}
                  <div className="space-y-1.5">
                    {[
                      {
                        id: "q5_0" as QuantizationType,
                        title: "Optimized Studio (Q5)",
                        sub: "Best balance of accuracy & speed",
                        size: calculateEstimatedSize(inspectedModel.size, "q5_0"),
                      },
                      {
                        id: "f16" as QuantizationType,
                        title: "Uncompressed (F16)",
                        sub: "Max studio accuracy, high RAM usage",
                        size: calculateEstimatedSize(inspectedModel.size, "f16"),
                      },
                      {
                        id: "q4_0" as QuantizationType,
                        title: "Ultra Light (Q4)",
                        sub: "Fastest speed, minimal memory footprint",
                        size: calculateEstimatedSize(inspectedModel.size, "q4_0"),
                      },
                    ].map((opt) => {
                      const currentQ = selectedQuantizations[inspectedModel.id] || "q5_0";
                      const isSelected = currentQ === opt.id;
                      return (
                        <button
                          key={opt.id}
                          type="button"
                          onClick={() => {
                            setSelectedQuantizations((prev) => ({
                              ...prev,
                              [inspectedModel.id]: opt.id,
                            }));
                          }}
                          className={`w-full p-2.5 rounded-xl border text-left flex items-center justify-between transition-all ${
                            isSelected
                              ? "bg-[#5D6658]/20 border-[#5D6658] text-white shadow-sm"
                              : "bg-black/30 border-white/10 text-white/70 hover:bg-white/[0.04]"
                          }`}
                        >
                          <div className="flex items-center gap-2.5">
                            <div
                              className={`w-3.5 h-3.5 rounded-full border flex items-center justify-center ${
                                isSelected
                                  ? "border-emerald-400 bg-emerald-500"
                                  : "border-white/30"
                              }`}
                            >
                              {isSelected && (
                                <div className="w-1.5 h-1.5 rounded-full bg-black" />
                              )}
                            </div>
                            <div>
                              <span className="text-xs font-semibold block leading-tight">
                                {opt.title}
                              </span>
                              <span className="text-[10px] text-white/40 block">
                                {opt.sub}
                              </span>
                            </div>
                          </div>
                          <span className="font-mono text-xs font-bold text-white/80">
                            {opt.size}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Speed & Accuracy Visual Meters */}
              <div className="grid grid-cols-2 gap-2 pt-1">
                <div className="bg-black/30 p-2 rounded-xl border border-white/10 space-y-1">
                  <span className="text-[10px] text-white/40 block">
                    Relative Speed
                  </span>
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-[11px] text-[#5A8BA8]">
                      ■ ■ ■ ■ □
                    </span>
                    <span className="font-mono font-bold text-white text-xs">
                      {(inspectedModel.speed * 100).toFixed(0)}%
                    </span>
                  </div>
                </div>

                <div className="bg-black/30 p-2 rounded-xl border border-white/10 space-y-1">
                  <span className="text-[10px] text-white/40 block">
                    Transcription Accuracy
                  </span>
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-[11px] text-[#278C40]">
                      ■ ■ ■ ■ ■
                    </span>
                    <span className="font-mono font-bold text-white text-xs">
                      {(inspectedModel.accuracy * 100).toFixed(0)}%
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Bottom Actions */}
            <div className="flex items-center justify-between pt-2 border-t border-white/10">
              <button
                onClick={() => setInspectedModel(null)}
                className="px-4 py-1.5 rounded-xl bg-white/[0.06] hover:bg-white/10 text-white text-xs font-semibold transition-all"
              >
                Close
              </button>

              {!inspectedModel.is_cloud && (
                <button
                  onClick={(e) => {
                    handleDownload(inspectedModel.id, e);
                    setInspectedModel(null);
                  }}
                  className="px-5 py-2 rounded-xl bg-gradient-to-r from-[#5D6658] to-[#278C40] hover:brightness-110 text-white text-xs font-bold shadow-lg shadow-[#278C40]/20 flex items-center gap-1.5 transition-all"
                >
                  <ArrowDownCircle className="w-3.5 h-3.5" />
                  <span>
                    {inspectedModel.is_downloaded ? "Re-download Model" : "Download Model"}
                  </span>
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      {/* OpenRouter Model Explorer Modal (400+ Models Catalog) */}
      <OpenRouterExplorerModal
        isOpen={showOpenRouterExplorer}
        onClose={() => setShowOpenRouterExplorer(false)}
        selectedModelId={activeModelId}
        onSelectModel={(modelId, modelName) => {
          const exists =
            modelsList.some((m) => m.id === modelId) ||
            customCloudModels.some((m) => m.id === modelId);
          if (!exists) {
            const newCustomModel: DictyModel = {
              id: modelId,
              name: modelName,
              size: "Cloud",
              speed: 0.95,
              accuracy: 0.99,
              is_cloud: true,
              category: "text",
              is_downloaded: true,
              description: `Selected from OpenRouter Catalog (${modelId})`,
              supports_translation: true,
            };
            setCustomCloudModels((prev) => [newCustomModel, ...prev]);
          }
          setActiveModelId(modelId);
          localStorage.setItem("dicty_active_model", modelId);
          engineApi.setActiveModel(modelId).catch(() => {});
        }}
      />
    </div>
  );
};
