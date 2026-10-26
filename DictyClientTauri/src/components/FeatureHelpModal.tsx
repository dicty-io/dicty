import React, { useState, useEffect, useMemo } from "react";
import { createPortal } from "react-dom";
import {
  HelpCircle,
  X,
  Search,
  Cpu,
  Layers,
  BookOpen,
  Keyboard,
  History,
  Settings,
  Key,
  FileAudio,
  FolderKanban,
  Sparkles,
  Lightbulb,
  CheckCircle2,
  ChevronRight,
  SlidersHorizontal,
  AppWindow,
  Wand2,
  TextSelect,
  BookA,
  Globe,
} from "lucide-react";

export type FeatureHelpTopic =
  | "models"
  | "modes"
  | "vocabulary"
  | "shortcuts"
  | "history"
  | "preferences"
  | "api_keys"
  | "transcribe"
  | "projects"
  | "sync_backup";

export interface HelpSection {
  title: string;
  items: {
    label: string;
    description: string;
  }[];
}

export interface FeatureGuide {
  id: FeatureHelpTopic;
  title: string;
  badge: string;
  icon: React.ComponentType<{ className?: string }>;
  summary: string;
  sections: HelpSection[];
  proTip: string;
}

export const FEATURE_GUIDES: FeatureGuide[] = [
  {
    id: "models",
    title: "Speech Models & Quantization",
    badge: "Core Engine",
    icon: Cpu,
    summary:
      "Dicty uses OpenAI Whisper and CTranslate2 running locally on your hardware for high-speed, 100% private offline voice recognition.",
    sections: [
      {
        title: "Local Offline vs Cloud Models",
        items: [
          {
            label: "Local Offline Models",
            description:
              "Run entirely on your CPU or NVIDIA GPU with zero internet connection. Your voice data never leaves your computer, offering total privacy and sub-second transcription latency.",
          },
          {
            label: "Cloud Speech Models (API)",
            description:
              "Utilize remote cloud APIs (OpenAI Whisper-1, Nvidia Parakeet). Great for long recordings or resource-constrained laptops where local GPU memory is limited.",
          },
        ],
      },
      {
        title: "Quantization Options (Q5, F16, Q4)",
        items: [
          {
            label: "Optimized (Q5) — Recommended",
            description:
              "5-bit quantization. Delivers ~99% studio accuracy while reducing RAM and disk usage by 50%. The best balanced choice for everyday dictation.",
          },
          {
            label: "Studio Original (F16)",
            description:
              "16-bit uncompressed acoustic weights. Offers maximum recognition fidelity for difficult accents, heavy technical jargon, or noisy backgrounds.",
          },
          {
            label: "Fast (Q4)",
            description:
              "4-bit integer weights. Minimal memory footprint and ultra-rapid inference, ideal for older or battery-conserving laptops.",
          },
        ],
      },
      {
        title: "Performance Metrics & Languages",
        items: [
          {
            label: "SPD (Inference Speed)",
            description:
              "Indicates how fast the model transcribes audio relative to real-time speech. A higher percentage means faster text delivery.",
          },
          {
            label: "ACC (Benchmark Accuracy)",
            description:
              "Benchmark acoustic precision score. Higher accuracy models make fewer spelling mistakes on complex, fast, or accented speech.",
          },
          {
            label: "Multilingual vs English-only (.en)",
            description:
              "Multilingual models (planet icon) support 99+ languages with automatic language detection. English-only models (.en) contain weights specifically tuned for English.",
          },
        ],
      },
    ],
    proTip:
      "On Windows, model weights are stored once in the HuggingFace cache. Switching precision (e.g. between Q5 and F16) updates runtime compute precision instantly in memory without re-downloading hundreds of megabytes!",
  },
  {
    id: "modes",
    title: "Modes & Workflow Profiles",
    badge: "Productivity",
    icon: Layers,
    summary:
      "Modes allow you to tailor dictation formatting, custom AI prompts, and speech models for specific tasks like coding, meeting notes, or drafting.",
    sections: [
      {
        title: "Why Use Different Modes?",
        items: [
          {
            label: "Task-Specific Formatting",
            description:
              "Standard dictation inserts raw words. An 'Engineering' mode can enforce camelCase and code blocks, while an 'Email' mode adds professional greeting and sign-off formatting.",
          },
          {
            label: "Dedicated Model Overrides",
            description:
              "Assign specific speech models to individual modes (e.g., assign lightning-fast 'Turbo' for casual messaging, and heavy 'Max / Large-v3' for technical architecture).",
          },
        ],
      },
      {
        title: "Mode Configuration Options",
        items: [
          {
            label: "Voice Prompts",
            description:
              "Guide punctuation, capitalization, and formatting style using natural language prompt instructions.",
          },
          {
            label: "Context Tags",
            description:
              "Tag entries (e.g. #architecture, #meeting) to automatically categorize your voice recordings in History.",
          },
          {
            label: "Profile Colors & Icons",
            description:
              "Customize the visual accent and HUD indicator badge for instant recognition while recording.",
          },
        ],
      },
    ],
    proTip:
      "Press Alt + Shift + M from any Windows app to open the quick Mode Switcher HUD, or click the colored profile letter in the recording overlay to switch modes instantly.",
  },
  {
    id: "vocabulary",
    title: "Custom Vocabulary & Whisper Bias",
    badge: "Acoustic Tuning",
    icon: BookOpen,
    summary:
      "Train Dicty to accurately transcribe company names, industry acronyms, technical terms, and accented speech that speech models usually misspell.",
    sections: [
      {
        title: "How Custom Vocabulary Works",
        items: [
          {
            label: "Acoustic Prompt Biasing",
            description:
              "Whisper models accept an initial dictionary prompt. Dicty feeds your vocabulary into the neural decoder so it actively listens for your specific terminology.",
          },
          {
            label: "Instant Text Replacement",
            description:
              "Set exact replacement rules (Original -> Replacement) to automatically correct phonetic mistakes (e.g. 'fast api' -> 'FastAPI') before text is pasted.",
          },
        ],
      },
      {
        title: "Best Practices",
        items: [
          {
            label: "Case Sensitivity",
            description:
              "Enter words exactly as you want them spelled (e.g. 'TypeScript', 'Kubernetes', 'OAuth').",
          },
          {
            label: "Starter Pack",
            description:
              "Use the 'Starter Pack (10)' button to instantly import 10 common software engineering terms.",
          },
        ],
      },
    ],
    proTip:
      "Keep vocabulary focused on 10-30 of your most frequently used specialized terms. A concise list gives the highest acoustic biasing accuracy without slowing down transcription.",
  },
  {
    id: "shortcuts",
    title: "Keyboard Shortcuts & Hotkeys",
    badge: "Global Controls",
    icon: Keyboard,
    summary:
      "Control Dicty globally from any Windows application (IDE, browser, Slack, Word) using global system hotkeys.",
    sections: [
      {
        title: "Dictation Triggers",
        items: [
          {
            label: "Toggle Dictation (Ctrl + Space)",
            description:
              "Press once to start recording, speak naturally, and press again to finish. Dicty transcribes and automatically pastes into your active cursor position.",
          },
          {
            label: "Pause / Resume (Ctrl + Shift + P)",
            description:
              "Temporarily freeze recording if interrupted without losing the current dictation session.",
          },
          {
            label: "Mode Switcher (Alt + Shift + M)",
            description:
              "Summon the floating Mode Switcher HUD to change active profiles on the fly.",
          },
        ],
      },
      {
        title: "Advanced Trigger Options",
        items: [
          {
            label: "Double-Tap Modifiers",
            description:
              "Optionally trigger dictation by quickly double-tapping a single modifier key like Ctrl, Alt, or Shift for effortless one-finger activation.",
          },
          {
            label: "Custom Key Rebinding",
            description:
              "Click any shortcut field in this view and press your desired key combination to customize.",
          },
        ],
      },
    ],
    proTip:
      "Dicty operates as a system-wide background hook. You do not need to bring Dicty to the front — simply place your cursor where you want text and hit Ctrl + Space.",
  },
  {
    id: "history",
    title: "Transcription History & Snippets",
    badge: "Archive",
    icon: History,
    summary:
      "Browse, search, listen to, and re-process your local speech-to-text dictation archive with zero external telemetry.",
    sections: [
      {
        title: "Key Features",
        items: [
          {
            label: "Audio Playback",
            description:
              "Listen back to your original recorded voice clip to verify what was spoken.",
          },
          {
            label: "Re-Transcribe With Any Model",
            description:
              "If a quick recording missed a word, re-run the audio clip through a higher-precision model (like Large-v3 or Studio F16) with one click.",
          },
          {
            label: "Smart Summaries & Copy",
            description:
              "Copy cleaned text, generate markdown summaries, or review architectural updates created during your session.",
          },
        ],
      },
    ],
    proTip:
      "Your audio cache is saved locally in your user data directory. You can clear history anytime from Preferences without affecting your custom vocabulary or modes.",
  },
  {
    id: "preferences",
    title: "Preferences & Audio Setup",
    badge: "Configuration",
    icon: Settings,
    summary:
      "Configure your microphone input hardware, audio chime feedback, theme appearance, and Windows background launch behavior.",
    sections: [
      {
        title: "Audio & Hardware Setup",
        items: [
          {
            label: "Microphone Selection & Live Meter",
            description:
              "Select your preferred audio input device and check live input sensitivity to ensure clear acoustic capture.",
          },
          {
            label: "Audio Chimes & Sound Effects",
            description:
              "Configure subtle start and stop chimes so you always know when Dicty begins and finishes recording.",
          },
          {
            label: "Launch on Windows Startup",
            description:
              "Keep Dicty running silently in the system tray so global hotkeys are instantly available when you turn on your PC.",
          },
        ],
      },
    ],
    proTip:
      "If you experience silent recordings, make sure Windows microphone privacy settings allow desktop apps to access your microphone.",
  },
  {
    id: "api_keys",
    title: "Cloud AI & API Providers",
    badge: "Cloud AI",
    icon: Key,
    summary:
      "Optionally connect cloud LLM providers (OpenRouter, OpenAI, Groq, Anthropic) to enable live translations and smart rewriting.",
    sections: [
      {
        title: "Local vs Cloud AI",
        items: [
          {
            label: "100% Offline Capability",
            description:
              "Dicty does not require an API key to function. Local Whisper models perform complete speech recognition locally on your PC.",
          },
          {
            label: "Why Connect Cloud AI?",
            description:
              "Connecting OpenRouter or OpenAI enables advanced features like multi-language voice translation, meeting action-item extraction, and AI formatting.",
          },
          {
            label: "OpenRouter Catalog",
            description:
              "Access 400+ frontier models (Claude 3.7, GPT-4o, DeepSeek) through a single unified OpenRouter API key.",
          },
        ],
      },
    ],
    proTip:
      "When using cloud AI for dictation cleanup, choose '⚡ Fast' models (like GPT-4o Mini or Claude 3.5 Haiku) for immediate text paste latency.",
  },
  {
    id: "transcribe",
    title: "Audio & Video File Transcription",
    badge: "Batch Processing",
    icon: FileAudio,
    summary:
      "Transcribe pre-recorded voice memos, meetings, podcasts, and video files directly on your computer without playing them aloud.",
    sections: [
      {
        title: "File Support & Features",
        items: [
          {
            label: "Supported Formats",
            description:
              "Supports .mp3, .wav, .m4a, .aac, .flac, .ogg, .mp4, .mov, and .mkv files.",
          },
          {
            label: "Batch Processing",
            description:
              "Drop multiple audio files to transcribe in the background while you continue working in other applications.",
          },
        ],
      },
    ],
    proTip:
      "Large files are split into high-speed audio chunks to utilize multiple CPU cores or GPU threads for rapid transcription.",
  },
  {
    id: "projects",
    title: "Projects & Librarian Architecture",
    badge: "Knowledge Base",
    icon: FolderKanban,
    summary:
      "Synthesize voice thoughts into structured architectural documentation, PR summaries, and repository knowledge bases.",
    sections: [
      {
        title: "How Librarian Works",
        items: [
          {
            label: "Voice Thought Staging",
            description:
              "Record quick engineering thoughts as you code. Dicty groups them by Git branch and repository context.",
          },
          {
            label: "Architectural Synthesis",
            description:
              "Librarian compiles staged voice thoughts into cohesive architectural decision records (ADRs) and updates your docs automatically.",
          },
        ],
      },
    ],
    proTip:
      "Link your local Git repositories to have Librarian automatically detect your active branch and tag documentation commits.",
  },
  {
    id: "sync_backup",
    title: "Cloud Sync & Data Portability",
    badge: "Backup",
    icon: Sparkles,
    summary:
      "Synchronize your custom vocabulary, mode profiles, and shortcuts seamlessly across your Windows and Mac devices.",
    sections: [
      {
        title: "Sync Features",
        items: [
          {
            label: "Automatic Cloud Sync",
            description:
              "When signed in, Dicty automatically syncs custom vocabulary and mode profiles to your secure cloud account.",
          },
          {
            label: "Local Offline Backups",
            description:
              "Export all your settings and custom vocabulary as a JSON file anytime for manual backup.",
          },
        ],
      },
    ],
    proTip:
      "Syncing is non-destructive. If you add words while offline, Dicty merges them with your cloud vocabulary next time you connect.",
  },
];

interface FeatureHelpModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialTopic?: FeatureHelpTopic;
}

/// "What Dicty can do" — six short cards. Each has a one-line example and a
/// button that opens the page where that feature is set up.
const CAPABILITY_CARDS: {
  title: string;
  example: string;
  icon: React.ComponentType<{ className?: string }>;
  tab: "modes" | "words";
  wordsTab?: "vocabulary" | "snippets";
}[] = [
  { title: "Modes", example: "Long ideas for notes, short lines for chat.", icon: SlidersHorizontal, tab: "modes" },
  { title: "Apps", example: "Different style in Slack than in Mail.", icon: AppWindow, tab: "modes" },
  { title: "Fix corrections", example: 'Turns "uhm" and "kube" into clean words.', icon: Wand2, tab: "modes" },
  { title: "Snippets", example: 'Say "sig" to insert your signature.', icon: TextSelect, tab: "words", wordsTab: "snippets" },
  { title: "Vocabulary", example: 'Add "OpenRouter" so it types right.', icon: BookA, tab: "words", wordsTab: "vocabulary" },
  { title: "Translate", example: "Speak English, type Spanish.", icon: Globe, tab: "modes" },
];

export const FeatureHelpModal: React.FC<FeatureHelpModalProps> = ({
  isOpen,
  onClose,
  initialTopic = "models",
}) => {
  const [selectedTopicId, setSelectedTopicId] = useState<FeatureHelpTopic>(initialTopic);
  const [searchQuery, setSearchQuery] = useState("");

  useEffect(() => {
    if (initialTopic) {
      setSelectedTopicId(initialTopic);
    }
  }, [initialTopic]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  // Filter topics based on search query
  const filteredGuides = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return FEATURE_GUIDES;

    return FEATURE_GUIDES.filter((guide) => {
      if (
        guide.title.toLowerCase().includes(q) ||
        guide.summary.toLowerCase().includes(q) ||
        guide.proTip.toLowerCase().includes(q)
      ) {
        return true;
      }
      return guide.sections.some((s) =>
        s.items.some(
          (item) =>
            item.label.toLowerCase().includes(q) ||
            item.description.toLowerCase().includes(q)
        )
      );
    });
  }, [searchQuery]);

  const activeGuide = useMemo(() => {
    return (
      filteredGuides.find((g) => g.id === selectedTopicId) ||
      filteredGuides[0] ||
      FEATURE_GUIDES[0]
    );
  }, [filteredGuides, selectedTopicId]);

  if (!isOpen) return null;
  if (typeof document === "undefined") return null;

  const ActiveIcon = activeGuide.icon;

  return createPortal(
    <div
      onClick={onClose}
      className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-black/75 backdrop-blur-md animate-in fade-in duration-150"
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-4xl max-h-[85vh] bg-[#16181D] border border-white/15 rounded-2xl shadow-2xl flex flex-col overflow-hidden text-white animate-in zoom-in-95 duration-150 relative"
      >
        {/* Header Bar */}
        <div className="px-5 py-3.5 border-b border-white/10 flex items-center justify-between bg-white/[0.02]">
          <div className="flex items-center gap-2.5">
            <div className="w-7 h-7 rounded-lg bg-[#5D6658]/30 border border-[#87B996]/40 flex items-center justify-center text-[#87B996]">
              <HelpCircle className="w-4 h-4" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-bold text-white tracking-tight">
                  Dicty Feature Guide
                </h2>
                <span className="px-1.5 py-0.2 rounded text-[9px] font-bold bg-white/10 text-white/70">
                  In-App Help
                </span>
              </div>
              <p className="text-[11px] text-white/50">
                Concise explanations & pro-tips for every feature — no external documentation needed
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-white/10 text-white/50 hover:text-white transition-colors"
            title="Close (Esc)"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Search Bar */}
        <div className="px-5 py-2.5 bg-black/20 border-b border-white/10 flex items-center gap-2">
          <Search className="w-3.5 h-3.5 text-white/40 flex-shrink-0" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search features (e.g. quantization, spd, shortcuts, vocabulary, hotkeys)..."
            className="w-full bg-transparent text-xs text-white placeholder-white/30 focus:outline-none"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery("")}
              className="text-white/40 hover:text-white text-xs px-1"
            >
              Clear
            </button>
          )}
        </div>

        {/* Modal Body: Sidebar + Main Content */}
        <div className="flex-1 flex min-h-0 overflow-hidden">
          {/* Topics Sidebar */}
          <div className="w-48 sm:w-56 border-r border-white/10 overflow-y-auto p-2 space-y-1 bg-black/10 flex-shrink-0 custom-scrollbar">
            <div className="px-2 py-1 text-[9.5px] font-bold text-white/40 uppercase tracking-wider">
              Topics ({filteredGuides.length})
            </div>
            {filteredGuides.map((guide) => {
              const Icon = guide.icon;
              const isSelected = guide.id === activeGuide.id;
              return (
                <button
                  key={guide.id}
                  onClick={() => setSelectedTopicId(guide.id)}
                  className={`w-full flex items-center justify-between px-2.5 py-2 rounded-xl text-left text-xs transition-all ${
                    isSelected
                      ? "bg-[#5D6658]/35 border border-[#87B996]/50 text-white font-semibold shadow-sm"
                      : "text-white/70 hover:bg-white/[0.04] hover:text-white border border-transparent"
                  }`}
                >
                  <div className="flex items-center gap-2 min-w-0">
                    <Icon className={`w-3.5 h-3.5 flex-shrink-0 ${isSelected ? "text-[#87B996]" : "text-white/50"}`} />
                    <span className="truncate">{guide.title.split("&")[0].trim()}</span>
                  </div>
                  {isSelected && <ChevronRight className="w-3 h-3 text-[#87B996] flex-shrink-0" />}
                </button>
              );
            })}
          </div>

          {/* Topic Detail View */}
          <div className="flex-1 overflow-y-auto p-5 sm:p-6 space-y-5 custom-scrollbar">
            {/* What Dicty can do */}
            <div className="space-y-2.5">
              <h3 className="text-sm font-bold text-white tracking-tight">What Dicty can do</h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                {CAPABILITY_CARDS.map((card) => {
                  const IconComp = card.icon;
                  return (
                    <div
                      key={card.title}
                      className="p-3 rounded-xl bg-white/[0.03] border border-white/10 flex flex-col gap-1.5"
                    >
                      <div className="flex items-center gap-2">
                        <IconComp className="w-3.5 h-3.5 text-[#87B996]" />
                        <span className="text-xs font-semibold text-white">{card.title}</span>
                      </div>
                      <p className="text-[11px] text-white/55 leading-relaxed flex-1">{card.example}</p>
                      <button
                        onClick={() => {
                          if (card.wordsTab) {
                            try {
                              localStorage.setItem("dicty_words_tab", card.wordsTab);
                            } catch {
                              // Ignore storage restrictions.
                            }
                          }
                          onClose();
                          window.dispatchEvent(
                            new CustomEvent("dicty:navigate", { detail: { tab: card.tab } })
                          );
                        }}
                        className="self-start text-[11px] font-semibold text-[#87B996] hover:underline"
                      >
                        Set up
                      </button>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Topic Header Card */}
            <div className="p-4 rounded-xl bg-white/[0.03] border border-white/10 space-y-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-[#5D6658]/20 border border-[#87B996]/30 flex items-center justify-center text-[#87B996]">
                    <ActiveIcon className="w-4 h-4" />
                  </div>
                  <div>
                    <h3 className="text-base font-bold text-white tracking-tight">
                      {activeGuide.title}
                    </h3>
                    <span className="px-1.5 py-0.2 rounded text-[9px] font-bold bg-[#278C40]/20 text-[#87B996] border border-[#278C40]/30">
                      {activeGuide.badge}
                    </span>
                  </div>
                </div>
              </div>
              <p className="text-xs text-white/75 leading-relaxed pt-1">
                {activeGuide.summary}
              </p>
            </div>

            {/* Sections */}
            <div className="space-y-4">
              {activeGuide.sections.map((section, sIdx) => (
                <div key={sIdx} className="space-y-2">
                  <h4 className="text-xs font-bold text-white/90 uppercase tracking-wider flex items-center gap-1.5">
                    <span className="w-1.5 h-1.5 rounded-full bg-[#87B996]" />
                    {section.title}
                  </h4>
                  <div className="grid grid-cols-1 gap-2">
                    {section.items.map((item, iIdx) => (
                      <div
                        key={iIdx}
                        className="p-3 rounded-xl bg-black/30 border border-white/[0.08] hover:border-white/15 transition-colors space-y-1"
                      >
                        <div className="text-xs font-semibold text-white flex items-center gap-1.5">
                          <CheckCircle2 className="w-3 h-3 text-[#87B996] flex-shrink-0" />
                          <span>{item.label}</span>
                        </div>
                        <p className="text-[11px] text-white/60 leading-relaxed pl-4.5">
                          {item.description}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>

            {/* Pro-Tip Box */}
            {activeGuide.proTip && (
              <div className="p-3.5 rounded-xl bg-amber-500/[0.08] border border-amber-500/25 flex items-start gap-2.5 text-xs text-amber-200">
                <Lightbulb className="w-4 h-4 text-amber-400 flex-shrink-0 mt-0.5" />
                <div className="space-y-0.5">
                  <span className="font-bold text-amber-300 block">Pro Tip</span>
                  <p className="text-[11.5px] text-amber-100/80 leading-relaxed">
                    {activeGuide.proTip}
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="px-5 py-2.5 border-t border-white/10 bg-white/[0.02] flex items-center justify-between text-[11px] text-white/40">
          <span>Click any topic in the sidebar or press Esc to close</span>
          <button
            onClick={onClose}
            className="px-3 py-1 rounded-lg bg-white/10 hover:bg-white/15 text-white text-xs font-medium transition-colors"
          >
            Got it
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
};

interface FeatureHelpButtonProps {
  topic: FeatureHelpTopic;
  className?: string;
  label?: string;
  size?: "sm" | "md";
}

export const FeatureHelpButton: React.FC<FeatureHelpButtonProps> = ({
  topic,
  className = "",
  label = "Feature Guide",
  size = "md",
}) => {
  const [isOpen, setIsOpen] = useState(false);

  const isSmall = size === "sm";

  return (
    <>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setIsOpen(true);
        }}
        title={`Help: ${label} (?)`}
        className={`group inline-flex items-center gap-1 rounded-full bg-white/[0.06] hover:bg-[#87B996]/20 border border-white/10 hover:border-[#87B996]/50 text-white/60 hover:text-white transition-all cursor-pointer select-none ${
          isSmall ? "px-1.5 py-0.5 text-[10px]" : "px-2 py-0.5 text-xs"
        } ${className}`}
      >
        <HelpCircle
          className={`${
            isSmall ? "w-2.5 h-2.5" : "w-3 h-3"
          } text-white/50 group-hover:text-[#87B996] transition-colors`}
        />
        <span className="font-semibold text-[10.5px]">?</span>
      </button>

      <FeatureHelpModal
        isOpen={isOpen}
        onClose={() => setIsOpen(false)}
        initialTopic={topic}
      />
    </>
  );
};
