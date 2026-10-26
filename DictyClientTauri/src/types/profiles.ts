import {
  Mic,
  Terminal,
  Book,
  Users,
  Sparkles,
  Layers,
  AppWindow,
  MessageSquare,
  Briefcase,
  Radio,
  Zap,
  Flame,
  Brain,
  Video,
  Headphones,
  Target,
  FileText,
} from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import type { DictationFormatStyle } from "./engine";

export interface ProfileItem {
  id: string;
  name: string;
  icon: any;
  iconName?: string;
  modeType: string;
  badgeText: string;
  badgeColor: string;
  badgeBg: string;
  badgeBorder: string;
  formatStyle: DictationFormatStyle;
  whisperModel: string;
  customPrompt?: string;
  tags: string[];
  description: string;
  targetApps?: string[];
  isDefault?: boolean;
}

export const AVAILABLE_PROFILE_ICONS: { id: string; label: string; icon: any }[] = [
  { id: "mic", label: "Microphone", icon: Mic },
  { id: "terminal", label: "Terminal / Code", icon: Terminal },
  { id: "book", label: "Documentation", icon: Book },
  { id: "users", label: "Meeting Assistant", icon: Users },
  { id: "layers", label: "Focused App", icon: Layers },
  { id: "window", label: "App Window", icon: AppWindow },
  { id: "sparkles", label: "Prose / Creative", icon: Sparkles },
  { id: "target", label: "Target / Focus", icon: Target },
  { id: "message", label: "Chat Message", icon: MessageSquare },
  { id: "briefcase", label: "Work / Executive", icon: Briefcase },
  { id: "radio", label: "Broadcast / Audio", icon: Radio },
  { id: "zap", label: "Fast / Quick", icon: Zap },
  { id: "flame", label: "Hot / Priority", icon: Flame },
  { id: "brain", label: "Brain / Thought", icon: Brain },
  { id: "video", label: "Video Call", icon: Video },
  { id: "headphones", label: "Listening", icon: Headphones },
  { id: "file", label: "Document", icon: FileText },
];

export const getProfileIcon = (iconName?: string, id?: string): any => {
  if (iconName) {
    const found = AVAILABLE_PROFILE_ICONS.find((i) => i.id === iconName);
    if (found) return found.icon;
  }
  switch (id) {
    case "prof_1":
      return Mic;
    case "prof_2":
      return Terminal;
    case "prof_3":
      return Book;
    case "prof_4":
      return Users;
    case "prof_focused_meeting":
      return Layers;
    case "prof_5":
      return Sparkles;
    default:
      return Mic;
  }
};

export const DEFAULT_PROFILES: ProfileItem[] = [
  {
    id: "prof_1",
    name: "General Dictation",
    icon: Mic,
    iconName: "mic",
    modeType: "dictation",
    badgeText: "Fast Punctuation",
    badgeColor: "text-emerald-300",
    badgeBg: "bg-emerald-500/15",
    badgeBorder: "border-emerald-500/30",
    formatStyle: "punctuation_fast",
    whisperModel: "base.en",
    tags: ["general", "typing"],
    description: "Transcribes spoken voice directly to the Windows clipboard for fast typing into any active app.",
    isDefault: true,
  },
  {
    id: "prof_2",
    name: "Code & Architecture",
    icon: Terminal,
    iconName: "terminal",
    modeType: "dictation",
    badgeText: "Code",
    badgeColor: "text-blue-300",
    badgeBg: "bg-blue-500/15",
    badgeBorder: "border-blue-500/30",
    formatStyle: "custom",
    whisperModel: "base.en",
    customPrompt: "Format with clean developer syntax, preserving camelCase, snake_case, and markdown backticks.",
    tags: ["dev", "coding", "syntax"],
    description: "Preserves camelCase, snake_case, terminal commands, and Markdown backticks.",
    isDefault: true,
  },
  {
    id: "prof_3",
    name: "Architecture Librarian",
    icon: Book,
    iconName: "book",
    modeType: "librarian",
    badgeText: "Librarian",
    badgeColor: "text-indigo-300",
    badgeBg: "bg-indigo-500/20",
    badgeBorder: "border-indigo-500/30",
    formatStyle: "note",
    whisperModel: "small.en",
    tags: ["architecture", "adr", "obsidian"],
    description: "Autonomous documentation assistant that records voice, queries your connected workspace, and updates knowledge base docs.",
    isDefault: true,
  },
  {
    id: "prof_4",
    name: "Meeting Assistant",
    icon: Users,
    iconName: "users",
    modeType: "meeting",
    badgeText: "Meeting",
    badgeColor: "text-amber-300",
    badgeBg: "bg-amber-500/20",
    badgeBorder: "border-amber-500/30",
    formatStyle: "note",
    whisperModel: "large-v3-turbo",
    tags: ["meetings", "summary"],
    description: "Continuous recording with speaker detection, structured summaries, and action item extraction.",
    isDefault: true,
  },
  {
    id: "prof_focused_meeting",
    name: "Focused App Meeting",
    icon: Layers,
    iconName: "layers",
    modeType: "focused_meeting",
    badgeText: "Focused App",
    badgeColor: "text-rose-300",
    badgeBg: "bg-rose-500/20",
    badgeBorder: "border-rose-500/30",
    formatStyle: "note",
    whisperModel: "large-v3-turbo",
    tags: ["meeting", "app", "focused"],
    description: "Records your microphone AND audio from specific applications (Zoom, Teams, Slack, Chrome) simultaneously.",
    targetApps: [],
    isDefault: true,
  },
  {
    id: "prof_5",
    name: "Book & Prose",
    icon: Sparkles,
    iconName: "sparkles",
    modeType: "dictation",
    badgeText: "Book Prose",
    badgeColor: "text-purple-300",
    badgeBg: "bg-purple-500/20",
    badgeBorder: "border-purple-500/30",
    formatStyle: "book",
    whisperModel: "small.en",
    tags: ["writing", "prose"],
    description: "Formatted continuous dictation into publication-ready book text with automatic paragraph indents.",
    isDefault: true,
  },
];

export const getStoredProfiles = (): ProfileItem[] => {
  try {
    const raw = localStorage.getItem("dicty_profiles_v2");
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) {
        // If user already had stored profiles but prof_focused_meeting is missing, add it automatically
        const hasFocusedMeeting = parsed.some((p: any) => p.id === "prof_focused_meeting" || p.modeType === "focused_meeting");
        let list = [...parsed];
        if (!hasFocusedMeeting) {
          const focusedDef = DEFAULT_PROFILES.find((d) => d.id === "prof_focused_meeting");
          if (focusedDef) {
            // Insert right after prof_4 (Meeting Assistant)
            const mIdx = list.findIndex((p: any) => p.id === "prof_4");
            if (mIdx >= 0) {
              list.splice(mIdx + 1, 0, focusedDef);
            } else {
              list.push(focusedDef);
            }
          }
        }

        return list.map((p: any) => {
          const def = DEFAULT_PROFILES.find((d) => d.id === p.id);
          const icon = getProfileIcon(p.iconName || def?.iconName, p.id);
          return {
            ...def,
            ...p,
            name: p.name || def?.name || "Custom Mode",
            description: p.description || def?.description || "",
            badgeText: p.badgeText || def?.badgeText || (p.modeType === "focused_meeting" ? "Focused App" : "Mode"),
            badgeColor: p.badgeColor || def?.badgeColor || (p.modeType === "focused_meeting" ? "text-rose-300" : "text-gray-300"),
            badgeBg: p.badgeBg || def?.badgeBg || (p.modeType === "focused_meeting" ? "bg-rose-500/20" : "bg-gray-500/15"),
            badgeBorder: p.badgeBorder || def?.badgeBorder || (p.modeType === "focused_meeting" ? "border-rose-500/30" : "border-gray-500/30"),
            icon,
            iconName: p.iconName || def?.iconName || "mic",
            whisperModel: p.whisperModel || def?.whisperModel || "base.en",
            tags: p.tags || def?.tags || [],
            formatStyle: p.formatStyle || def?.formatStyle || "custom",
            modeType: p.modeType || def?.modeType || "dictation",
            targetApps: Array.isArray(p.targetApps) ? p.targetApps : (def?.targetApps || []),
            isDefault: p.isDefault !== undefined ? p.isDefault : def?.isDefault || false,
          };
        });
      }
    }
  } catch {}
  return DEFAULT_PROFILES;
};

export const syncProfilesToRust = (profs: ProfileItem[]) => {
  try {
    const payload = profs.map((p) => ({
      id: p.id,
      name: p.name,
      mode_type: p.modeType,
      format_style: p.formatStyle,
      whisper_model: p.whisperModel,
      custom_prompt: p.customPrompt || null,
      tags: p.tags || [],
      target_apps: p.targetApps || [],
    }));
    invoke("sync_profiles", { profiles: payload }).catch((err) => {
      console.warn("Failed to sync profiles to Rust backend:", err);
    });
  } catch {}
};

export const saveStoredProfiles = (profs: ProfileItem[]) => {
  try {
    const serializable = profs.map(({ icon, ...rest }) => rest);
    localStorage.setItem("dicty_profiles_v2", JSON.stringify(serializable));
    syncProfilesToRust(profs);
  } catch {}
};

export interface SpeechRecognitionModelOption {
  id: string;
  name: string;
  size: string;
  isCloud: boolean;
  desc: string;
}

export const ALL_SPEECH_RECOGNITION_MODELS: SpeechRecognitionModelOption[] = [
  // Local Whisper Models
  { id: "tiny.en", name: "Nano (EN)", size: "75 MB", isCloud: false, desc: "Ultra-fast, lightweight English model with minimal memory footprint." },
  { id: "tiny", name: "Nano (Multilingual)", size: "75 MB", isCloud: false, desc: "Ultra-fast, lightweight multilingual model for resource-constrained systems." },
  { id: "base.en", name: "Base (EN)", size: "140 MB", isCloud: false, desc: "Fast, reliable baseline model for everyday clear English speech." },
  { id: "base", name: "Base (Multilingual)", size: "140 MB", isCloud: false, desc: "Balanced multilingual baseline model for everyday transcription across 90+ languages." },
  { id: "small.en", name: "Fast (EN)", size: "460 MB", isCloud: false, desc: "The ideal balance of high accuracy and rapid speed for English dictation." },
  { id: "small", name: "Fast (Multilingual)", size: "460 MB", isCloud: false, desc: "High-speed multilingual model offering great accuracy across 90+ languages." },
  { id: "distil-large-v3", name: "Turbo Distil (EN)", size: "1.5 GB", isCloud: false, desc: "Ultra-fast distilled model delivering near-maximum accuracy for English speech." },
  { id: "medium.en", name: "Pro (EN)", size: "1.5 GB", isCloud: false, desc: "Professional-grade English accuracy, highly tuned for complex vocabulary." },
  { id: "medium", name: "Pro (Multilingual)", size: "1.5 GB", isCloud: false, desc: "Professional-grade multilingual accuracy for nuanced vocabulary and accents." },
  { id: "large-v3-turbo", name: "Turbo", size: "1.6 GB", isCloud: false, desc: "OpenAI's flagship turbo architecture with blazing fast speed across all languages." },
  { id: "large-v3", name: "Max", size: "3.1 GB", isCloud: false, desc: "Maximum-precision open-source model for complex audio, dialects, and quiet speech." },
  { id: "large-v3-turbo-ja", name: "Turbo (Japanese)", size: "1.6 GB", isCloud: false, desc: "Turbo architecture fine-tuned specifically for natural Japanese transcription." },
  { id: "large-v2-zh", name: "BELLE (Chinese)", size: "3.1 GB", isCloud: false, desc: "Specialized Chinese model optimized for Mandarin and regional dialects." },
  { id: "large-v2-french", name: "Large (French)", size: "3.1 GB", isCloud: false, desc: "Specialized French model optimized on native speech to eliminate silent letter errors." },

  // Cloud Speech Models
  { id: "openai/whisper-1", name: "Cloud Whisper 1", size: "Cloud API", isCloud: true, desc: "Official OpenAI Whisper cloud API for ultra-high accuracy speech recognition." },
  { id: "groq/whisper-large-v3-turbo", name: "Groq Whisper (Turbo)", size: "Cloud API", isCloud: true, desc: "OpenAI large-v3-turbo running on Groq LPU for near-instant transcription." },
  { id: "deepgram/nova-3", name: "Deepgram Nova 3", size: "Cloud API", isCloud: true, desc: "Deepgram's fastest and most accurate model, perfect for dictation." },
  { id: "nvidia/parakeet-tdt-0.6b-v3", name: "Nvidia Parakeet", size: "Cloud API", isCloud: true, desc: "Blazing-fast cloud speech recognition powered by Nvidia Parakeet." },
  { id: "elevenlabs/scribe-v2", name: "ElevenLabs Scribe V2", size: "Cloud API", isCloud: true, desc: "ElevenLabs' highly accurate Scribe V2 model for conversational nuances." },
];
