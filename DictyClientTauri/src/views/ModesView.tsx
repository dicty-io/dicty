import React, { useCallback, useEffect, useMemo, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  Plus,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  Check,
  Search,
  X,
  Trash2,
  RotateCcw,
  AlertTriangle,
  Wand2,
  Languages,
  AppWindow,
  Users,
  Loader2,
  SlidersHorizontal,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { FeatureHelpButton } from "../components/FeatureHelpModal";
import { ToggleSwitch } from "../components/ToggleSwitch";
import { engineApi } from "../services/engineApi";
import { AppRulesSettingsView } from "./AppRulesSettingsView";
import { PageTabBar } from "../components/PageTabBar";
import {
  modesStore,
  useModesStore,
  engineModeForProfile,
  capabilityForProfile,
  rulesForMode,
  isMeetingProfile,
  type ModesState,
} from "../services/modesStore";
import type {
  AppRule,
  DictationFormatStyle,
  EngineMode,
  ModeCapability,
} from "../types/engine";
import type { ActiveTab } from "../components/Navigation";
import {
  type ProfileItem,
  getStoredProfiles,
  saveStoredProfiles,
  AVAILABLE_PROFILE_ICONS,
  getProfileIcon,
  ALL_SPEECH_RECOGNITION_MODELS,
} from "../types/profiles";

// MARK: - Small constants

interface RunningAppItem {
  process_name: string;
  window_title: string;
  pid: number;
}

const KNOWN_APP_NAMES: Record<string, string> = {
  "zoom.exe": "Zoom Meetings",
  "ms-teams.exe": "Microsoft Teams",
  "teams.exe": "Microsoft Teams",
  "chrome.exe": "Google Chrome",
  "msedge.exe": "Microsoft Edge",
  "firefox.exe": "Mozilla Firefox",
  "brave.exe": "Brave Browser",
  "slack.exe": "Slack",
  "discord.exe": "Discord",
  "spotify.exe": "Spotify",
  "whatsapp.exe": "WhatsApp",
  "telegram.exe": "Telegram",
  "webex.exe": "Cisco Webex",
  "skype.exe": "Skype",
  "code.exe": "Visual Studio Code",
  "notepad.exe": "Notepad",
  "outlook.exe": "Outlook",
  "winword.exe": "Microsoft Word",
  "excel.exe": "Microsoft Excel",
  "powerpnt.exe": "Microsoft PowerPoint",
  "notion.exe": "Notion",
  "obsidian.exe": "Obsidian",
  "cursor.exe": "Cursor",
  "explorer.exe": "File Explorer",
  "windowsterminal.exe": "Windows Terminal",
  "powershell.exe": "PowerShell",
  "cmd.exe": "Command Prompt",
};

const getAppDisplayName = (process: string, title?: string): string => {
  const key = process.toLowerCase();
  if (KNOWN_APP_NAMES[key]) return KNOWN_APP_NAMES[key];
  if (title && title.trim().length > 0) {
    const cleaned = title.split(" - ").pop()?.trim();
    if (cleaned && cleaned.length > 1 && cleaned.length < 40) return cleaned;
  }
  const base = key.replace(/\.exe$/, "");
  return base.charAt(0).toUpperCase() + base.slice(1);
};

const slugify = (value: string): string =>
  value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || `mode-${Date.now()}`;

// Style picker options. Ids are the client's legacy style ids so the local
// profile (which the recording pipeline reads) keeps the same value.
const STYLE_OPTIONS: { id: string; label: string; hint: string }[] = [
  { id: "raw", label: "Exact words", hint: "Keeps every word." },
  { id: "punctuation_fast", label: "Clean punctuation", hint: "Adds commas and periods." },
  { id: "message", label: "Chat message", hint: "Short lines for chat." },
  { id: "email", label: "Email", hint: "Greeting and closing." },
  { id: "note", label: "Notes", hint: "Short bullet points." },
  { id: "book", label: "Book", hint: "Full paragraphs." },
  { id: "custom", label: "Custom", hint: "Your own instructions." },
];

const OPTION_TO_ENGINE: Record<string, string> = {
  raw: "exact",
  punctuation_fast: "clean",
  message: "message",
  email: "email",
  note: "note",
  book: "note",
  custom: "message",
};

const STYLE_EXAMPLES: Record<string, { before: string; after: string }> = {
  raw: {
    before: "so um I think we should ship it",
    after: "so um I think we should ship it",
  },
  punctuation_fast: {
    before: "okay so the plan is we meet on friday at three",
    after: "Okay, so the plan is we meet on Friday at three.",
  },
  message: {
    before: "hey are you free for lunch today around noon",
    after: "Hey, are you free for lunch today?\nAround noon?",
  },
  email: {
    before: "hi sarah thanks for the update the report looks good",
    after: "Hi Sarah,\n\nThanks for the update. The report looks good.\n\nBest,",
  },
  note: {
    before: "we shipped the login fix and then we started the new dashboard",
    after: "• Shipped the login fix\n• Started the new dashboard",
  },
  book: {
    before: "the wind picked up as the sun went down",
    after: "The wind picked up as the sun went down.",
  },
  custom: {
    before: "insert the notes from our standup meeting today",
    after: "Rewritten with your instructions.",
  },
};
import { WHISPER_LANGUAGES } from "./ModelsView";

const LANGUAGES: { id: string; label: string }[] = [
  { id: "none", label: "Off — keep my words" },
  ...WHISPER_LANGUAGES.filter((l) => l.code !== "auto").map((l) => ({
    id: l.code,
    label: l.name,
  })),
];

const styleLabel = (legacyId: string): string =>
  STYLE_OPTIONS.find((option) => option.id === legacyId)?.label || "Custom";

const capabilityText = (capability?: ModeCapability): string | null => {
  if (!capability?.missing) return null;
  if (capability.missing === "text_model") return "Needs a one-time model download";
  if (capability.missing === "cloud_access") return "Sign in for cloud cleanup";
  return "Needs a model";
};

const capabilityBannerText = (capability: ModeCapability): string => {
  if (capability.missing === "text_model") {
    const size = capability.size_mb ? ` (~${capability.size_mb} MB, one time)` : "";
    return `This mode needs a small text model${size}. Download it and Dicty cleans up your text on this PC.`;
  }
  if (capability.missing === "cloud_access") {
    return "This mode uses cloud cleanup. Sign in to turn it on.";
  }
  return "This mode needs a model that isn't ready yet.";
};

// MARK: - Modes page

interface ModesViewProps {
  onNavigateTab?: (tab: ActiveTab) => void;
}

export const ModesView: React.FC<ModesViewProps> = ({ onNavigateTab }) => {
  const state = useModesStore();
  const [profiles, setProfiles] = useState<ProfileItem[]>(() => getStoredProfiles());
  const [activeProfileId, setActiveProfileId] = useState<string>(() => {
    try {
      return localStorage.getItem("dicty_active_profile") || getStoredProfiles()[0]?.id || "";
    } catch {
      return getStoredProfiles()[0]?.id || "";
    }
  });
  const [selectedProfileId, setSelectedProfileId] = useState<string | null>(null);
  const [modesSubTab, setModesSubTab] = useState<"modes" | "app_rules">("modes");
  const [showAppRules, setShowAppRules] = useState(false);
  const [isCreating, setIsCreating] = useState(false);

  useEffect(() => {
    modesStore.refresh().then(() => modesStore.migrateIfNeeded(getStoredProfiles()));
  }, []);

  useEffect(() => {
    const syncActive = () => {
      try {
        const stored = localStorage.getItem("dicty_active_profile");
        if (stored) setActiveProfileId(stored);
      } catch {
        // Ignore storage restrictions.
      }
    };
    window.addEventListener("storage", syncActive);
    return () => window.removeEventListener("storage", syncActive);
  }, []);

  const saveProfiles = useCallback((next: ProfileItem[]) => {
    setProfiles(next);
    saveStoredProfiles(next);
  }, []);

  const syncProfileToRust = useCallback((profile: ProfileItem) => {
    if (profile.whisperModel) {
      invoke("set_profile_model", { profileId: profile.id, modelId: profile.whisperModel }).catch(() => {});
    }
    if (profile.formatStyle) {
      invoke("set_profile_format_style", { profileId: profile.id, formatStyle: profile.formatStyle }).catch(() => {});
    }
    if (profile.customPrompt !== undefined) {
      invoke("set_profile_custom_prompt", { profileId: profile.id, customPrompt: profile.customPrompt || "" }).catch(() => {});
    }
    if (profile.tags) {
      invoke("set_profile_tags", { profileId: profile.id, tags: profile.tags }).catch(() => {});
    }
  }, []);

  const updateProfile = useCallback(
    (updated: ProfileItem) => {
      saveProfiles(profiles.map((profile) => (profile.id === updated.id ? updated : profile)));
      syncProfileToRust(updated);
      if (updated.id === activeProfileId && updated.whisperModel) {
        try {
          localStorage.setItem("dicty_active_model", updated.whisperModel);
        } catch {
          // Ignore storage restrictions.
        }
        engineApi.setActiveModel(updated.whisperModel).catch(() => {});
      }
    },
    [profiles, saveProfiles, syncProfileToRust, activeProfileId]
  );

  const updateEngineForProfile = useCallback(
    (profile: ProfileItem, patch: Partial<EngineMode>) => {
      const mode = engineModeForProfile(state, profile);
      if (mode?.id) modesStore.updateModeFields(mode.id, patch);
    },
    [state]
  );

  const activateProfile = useCallback(
    (profile: ProfileItem) => {
      setActiveProfileId(profile.id);
      try {
        localStorage.setItem("dicty_active_profile", profile.id);
        if (profile.whisperModel) localStorage.setItem("dicty_active_model", profile.whisperModel);
      } catch {
        // Ignore storage restrictions.
      }
      syncProfileToRust(profile);
      if (profile.whisperModel) engineApi.setActiveModel(profile.whisperModel).catch(() => {});
      invoke("set_active_mode", { profileId: profile.id }).catch(() => {});
      const mode = engineModeForProfile(state, profile);
      if (mode?.id) modesStore.setActiveMode(mode.id);
      window.dispatchEvent(new Event("storage"));
    },
    [state, syncProfileToRust]
  );

  const createMode = useCallback(
    async (name: string, kind: string, iconName: string) => {
      const id = `prof_${Date.now()}`;
      const isMeeting = kind === "meeting" || kind === "focused_meeting";
      const newProfile: ProfileItem = {
        id,
        name,
        icon: getProfileIcon(iconName, id),
        iconName,
        modeType: kind,
        badgeText: isMeeting ? "Meeting" : kind === "librarian" ? "Librarian" : "Mode",
        badgeColor: isMeeting ? "text-amber-300" : kind === "librarian" ? "text-indigo-300" : "text-gray-300",
        badgeBg: isMeeting ? "bg-amber-500/20" : kind === "librarian" ? "bg-indigo-500/20" : "bg-gray-500/15",
        badgeBorder: isMeeting ? "border-amber-500/30" : kind === "librarian" ? "border-indigo-500/30" : "border-gray-500/30",
        formatStyle: isMeeting ? "note" : "punctuation_fast",
        whisperModel: isMeeting ? "large-v3-turbo" : "base.en",
        tags: isMeeting ? ["meeting"] : kind === "librarian" ? ["librarian"] : ["custom"],
        description: "",
        isDefault: false,
      };
      saveProfiles([...profiles, newProfile]);
      await modesStore.createMode({
        id: slugify(name),
        name,
        kind: isMeeting ? "meeting" : "dictation",
        style: isMeeting ? "note" : "clean",
        fix_corrections: !isMeeting,
        tags: newProfile.tags,
        icon: iconName,
        meeting: isMeeting
          ? {
              speaker_separation: "you_others",
              speaker_you_label: "You",
              show_timestamps: false,
              mute_microphone: false,
            }
          : {},
      });
      setSelectedProfileId(id);
      activateProfile(newProfile);
    },
    [profiles, saveProfiles, activateProfile]
  );

  const deleteProfile = useCallback(
    async (profile: ProfileItem) => {
      if (profile.isDefault || profiles.length <= 1) return;
      const next = profiles.filter((entry) => entry.id !== profile.id);
      saveProfiles(next);
      const mode = engineModeForProfile(state, profile);
      if (mode?.id) await modesStore.deleteMode(mode.id);
      if (activeProfileId === profile.id && next[0]) {
        activateProfile(next[0]);
      }
      setSelectedProfileId(null);
    },
    [profiles, saveProfiles, state, activeProfileId, activateProfile]
  );

  const selectedProfile = profiles.find((profile) => profile.id === selectedProfileId) || null;
  const dictationProfiles = profiles.filter((profile) => !isMeetingProfile(profile));
  const meetingProfiles = profiles.filter((profile) => isMeetingProfile(profile));

  return (
    <div className="flex-1 flex flex-col min-h-0 min-w-0 select-none">
      {/* Top Segmented Tabs: Modes | App Rules (1:1 with ModesView.swift) */}
      <div className="px-8 pt-5 pb-3 border-b border-white/10 shrink-0 bg-black/20 backdrop-blur-md">
        <PageTabBar
          selection={modesSubTab}
          onSelect={setModesSubTab}
          tabs={[
            { id: "modes", label: "Modes", icon: SlidersHorizontal },
            { id: "app_rules", label: "App Rules", icon: AppWindow },
          ]}
        />
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto">
        {modesSubTab === "app_rules" ? (
          <AppRulesSettingsView />
        ) : selectedProfile ? (
          <ModeDetail
            profile={selectedProfile}
            state={state}
            profilesCount={profiles.length}
            isActive={selectedProfile.id === activeProfileId}
            onBack={() => setSelectedProfileId(null)}
            onActivate={() => activateProfile(selectedProfile)}
            onUpdateProfile={updateProfile}
            onUpdateEngine={(patch) => updateEngineForProfile(selectedProfile, patch)}
            onDelete={() => deleteProfile(selectedProfile)}
            onNavigateTab={(tab) => onNavigateTab?.(tab)}
          />
        ) : (
          <div className="w-full overflow-x-hidden p-5 sm:p-8 max-w-4xl mx-auto space-y-6">
            <div className="flex items-start justify-between gap-3">
              <SettingsPageHeader
                title="Modes"
                description="One place for how Dicty writes. Each mode has its own style, corrections and apps."
                helpTopic="modes"
              />
              <button
                onClick={() => setIsCreating(true)}
                className="shrink-0 flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6A7565] text-white text-xs font-semibold transition-colors"
              >
                <Plus className="w-3.5 h-3.5" />
                <span>Create mode</span>
              </button>
            </div>

            {/* Automatic app rules */}
            <div className="dicty-card p-4 flex items-start justify-between gap-4">
              <div className="min-w-0 space-y-1">
                <div className="text-sm font-semibold text-white">Pick the mode by app automatically</div>
                <p className="text-xs text-white/55 leading-relaxed">
                  Dicty looks at the app in front of you and uses the mode you set for it.
                </p>
                <button
                  onClick={() => setModesSubTab("app_rules")}
                  className="text-[11px] font-medium text-[#87B996] hover:underline"
                >
                  See all app rules
                </button>
              </div>
              <ToggleSwitch
                checked={state.automaticAppRules}
                onChange={(value) => modesStore.setAutomaticAppRules(value)}
                ariaLabel="Pick the mode by app automatically"
              />
            </div>

            {state.errorMessage && (
              <div className="flex items-center gap-2 text-[11px] text-white/45">
                <AlertTriangle className="w-3.5 h-3.5" />
                <span>{state.errorMessage} Your modes still work from this PC.</span>
                <button onClick={() => modesStore.refresh()} className="text-[#87B996] hover:underline">
                  Try again
                </button>
              </div>
            )}

            <ModeGroup
              title="Dictation"
              profiles={dictationProfiles}
              state={state}
              activeProfileId={activeProfileId}
              onOpen={setSelectedProfileId}
            />
            <ModeGroup
              title="Meetings"
              profiles={meetingProfiles}
              state={state}
              activeProfileId={activeProfileId}
              onOpen={setSelectedProfileId}
            />

            {showAppRules && <AppRulesSheet state={state} onClose={() => setShowAppRules(false)} />}
            {isCreating && (
              <NewModeSheet onClose={() => setIsCreating(false)} onCreate={createMode} />
            )}
          </div>
        )}
      </div>
    </div>
  );
};

// MARK: - Groups & cards

const ModeGroup: React.FC<{
  title: string;
  profiles: ProfileItem[];
  state: ModesState;
  activeProfileId: string;
  onOpen: (id: string) => void;
}> = ({ title, profiles, state, activeProfileId, onOpen }) => {
  if (profiles.length === 0) return null;
  return (
    <div className="space-y-2">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-white/40 px-1">
        {title}
      </div>
      <div className="space-y-2">
        {profiles.map((profile) => (
          <ModeCard
            key={profile.id}
            profile={profile}
            state={state}
            isActive={profile.id === activeProfileId}
            onOpen={() => onOpen(profile.id)}
          />
        ))}
      </div>
    </div>
  );
};

const ModeCard: React.FC<{
  profile: ProfileItem;
  state: ModesState;
  isActive: boolean;
  onOpen: () => void;
}> = ({ profile, state, isActive, onOpen }) => {
  const Icon = profile.icon || getProfileIcon(profile.iconName, profile.id);
  const capability = capabilityForProfile(state, profile);
  const missing = capabilityText(capability);

  return (
    <button
      onClick={onOpen}
      className="dicty-card w-full text-left p-4 flex items-center gap-3.5"
    >
      <div className="w-10 h-10 rounded-xl bg-[#5D6658] flex items-center justify-center text-white shrink-0">
        <Icon className="w-5 h-5" />
      </div>
      <div className="flex-1 min-w-0 space-y-1">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-white truncate">{profile.name}</span>
          {isActive && (
            <span className="w-1.5 h-1.5 rounded-full bg-[#87B996] shrink-0" title="Active" />
          )}
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-[10px] px-2 py-0.5 rounded-full bg-white/[0.06] border border-white/10 text-white/70">
            {isMeetingProfile(profile) ? "Meeting" : styleLabel(profile.formatStyle)}
          </span>
          {missing && <span className="text-[10px] text-white/45">{missing}</span>}
        </div>
      </div>
      <ChevronRight className="w-4 h-4 text-white/30 shrink-0" />
    </button>
  );
};

// MARK: - Detail

interface ModeDetailProps {
  profile: ProfileItem;
  state: ModesState;
  profilesCount: number;
  isActive: boolean;
  onBack: () => void;
  onActivate: () => void;
  onUpdateProfile: (profile: ProfileItem) => void;
  onUpdateEngine: (patch: Partial<EngineMode>) => void;
  onDelete: () => void;
  onNavigateTab: (tab: ActiveTab) => void;
}

const ModeDetail: React.FC<ModeDetailProps> = ({
  profile,
  state,
  profilesCount,
  isActive,
  onBack,
  onActivate,
  onUpdateProfile,
  onUpdateEngine,
  onDelete,
  onNavigateTab,
}) => {
  const engineMode = engineModeForProfile(state, profile);
  const capability = capabilityForProfile(state, profile);
  const modeId = engineMode?.id;
  const targetRules = rulesForMode(state, modeId);
  const isMeeting = isMeetingProfile(profile);

  const [showMore, setShowMore] = useState(false);
  const [showAppPicker, setShowAppPicker] = useState(false);
  const [fixing, setFixing] = useState(false);

  const Icon = profile.icon || getProfileIcon(profile.iconName, profile.id);

  const meeting = engineMode?.meeting || {};
  const updateMeeting = (patch: Record<string, any>) => {
    onUpdateEngine({ meeting: { ...meeting, ...patch } });
  };

  const translateValue = engineMode?.translate_to || "none";

  const downloadTextModel = async () => {
    if (!modeId) return;
    setFixing(true);
    await modesStore.fix(modeId);
    setFixing(false);
  };

  return (
    <div className="w-full flex-1 overflow-y-auto overflow-x-hidden p-5 sm:p-8 max-w-4xl mx-auto space-y-5 select-none">
      {/* Navigation bar */}
      <div className="flex items-center justify-between pb-2 border-b border-white/10">
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-xs font-medium text-white/60 hover:text-white transition-colors"
        >
          <ChevronLeft className="w-4 h-4" />
          <span>Modes</span>
        </button>

        <div className="flex items-center gap-2">
          <FeatureHelpButton topic="modes" label="Mode Configuration Guide" />
          <button
            onClick={onActivate}
            disabled={isActive}
            className={`text-xs px-3 py-1.5 rounded-lg font-medium transition-colors ${
              isActive
                ? "bg-[#87B996]/15 text-[#87B996] border border-[#87B996]/30 cursor-default"
                : "bg-white/10 hover:bg-white/15 text-white"
            }`}
          >
            {isActive ? "Active" : "Activate"}
          </button>
        </div>
      </div>

      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="w-11 h-11 rounded-xl bg-[#5D6658] flex items-center justify-center text-white shrink-0">
          <Icon className="w-5 h-5" />
        </div>
        <div className="min-w-0">
          <h2 className="text-lg font-bold text-white tracking-tight truncate">{profile.name}</h2>
          <p className="text-xs text-white/50">
            {isMeeting ? "Meeting mode" : "Dictation mode"}
            {isActive ? " · in use now" : ""}
          </p>
        </div>
      </div>

      {/* Capability banner */}
      {capability?.missing && (
        <div className="p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/25 flex items-center gap-3">
          <AlertTriangle className="w-4 h-4 text-amber-300 shrink-0" />
          <span className="flex-1 text-xs text-white/85 leading-relaxed">
            {capabilityBannerText(capability)}
          </span>
          {capability.fix?.startsWith("download") && (
            <button
              onClick={downloadTextModel}
              disabled={fixing}
              className="shrink-0 flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[#5D6658] hover:bg-[#6A7565] text-white text-[11px] font-semibold transition-colors disabled:opacity-50"
            >
              {fixing && <Loader2 className="w-3 h-3 animate-spin" />}
              <span>Download</span>
            </button>
          )}
          {capability.fix === "sign_in" && (
            <button
              onClick={() => onNavigateTab("account")}
              className="shrink-0 px-3 py-1.5 rounded-lg bg-[#5D6658] hover:bg-[#6A7565] text-white text-[11px] font-semibold transition-colors"
            >
              Sign in
            </button>
          )}
        </div>
      )}

      {isMeeting ? (
        <MeetingOptionsCard meeting={meeting} onChange={updateMeeting} />
      ) : (
        <>
          {/* Style */}
          <div className="dicty-card p-5 space-y-4">
            <div className="flex items-center gap-2">
              <Wand2 className="w-4 h-4 text-[#87B996]" />
              <span className="text-sm font-semibold text-white">Style</span>
            </div>
            <p className="text-xs text-white/55">How should Dicty write what you say?</p>

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-1.5">
              {STYLE_OPTIONS.map((option) => {
                const selected = profile.formatStyle === option.id;
                return (
                  <button
                    key={option.id}
                    onClick={() => {
                      onUpdateProfile({ ...profile, formatStyle: option.id as DictationFormatStyle });
                      onUpdateEngine({ style: OPTION_TO_ENGINE[option.id] || "clean" });
                    }}
                    className={`text-left px-3 py-2 rounded-xl border transition-colors ${
                      selected
                        ? "bg-[#5D6658]/25 border-[#5D6658]/50"
                        : "bg-white/[0.02] border-white/10 hover:bg-white/[0.05]"
                    }`}
                  >
                    <span className="block text-xs font-semibold text-white">{option.label}</span>
                    <span className="block text-[10px] text-white/45">{option.hint}</span>
                  </button>
                );
              })}
            </div>

            <ExampleCompare styleId={profile.formatStyle} />

            {profile.formatStyle === "custom" && (
              <textarea
                value={profile.customPrompt || ""}
                onChange={(event) => {
                  onUpdateProfile({ ...profile, customPrompt: event.target.value });
                  onUpdateEngine({ custom_instructions: event.target.value });
                }}
                placeholder="Tell Dicty how to format your text..."
                rows={3}
                className="w-full text-xs text-white/85 bg-black/30 border border-white/10 focus:border-[#5D6658] rounded-xl p-3 focus:outline-none resize-y"
              />
            )}
          </div>

          {/* Fix my corrections */}
          <div className="dicty-card p-5 flex items-start justify-between gap-4">
            <div className="min-w-0 space-y-1">
              <span className="text-sm font-semibold text-white">Fix my corrections</span>
              <p className="text-xs text-white/55 leading-relaxed">
                Dicty fixes small slips, like turning &ldquo;kube&rdquo; into
                &ldquo;Kubernetes&rdquo;. It never guesses at your meaning.
              </p>
              <div className="flex items-center gap-2 text-[11px] pt-1">
                <span className="font-mono text-white/45">deploy the uh kube cluster</span>
                <ChevronRight className="w-3 h-3 text-white/30" />
                <span className="font-mono text-white/80">Deploy the Kubernetes cluster.</span>
              </div>
            </div>
            <ToggleSwitch
              checked={!!engineMode?.fix_corrections}
              onChange={(value) => onUpdateEngine({ fix_corrections: value })}
              ariaLabel="Fix my corrections"
            />
          </div>

          {/* Translate to */}
          <div className="dicty-card p-5 space-y-3">
            <div className="flex items-center gap-2">
              <Languages className="w-4 h-4 text-[#87B996]" />
              <span className="text-sm font-semibold text-white">Translate to</span>
            </div>
            <p className="text-xs text-white/55">
              Dictate in one language and Dicty types another. Leave it off to keep your words as
              spoken.
            </p>
            <select
              value={translateValue}
              onChange={(event) =>
                onUpdateEngine({ translate_to: event.target.value === "none" ? "" : event.target.value })
              }
              className="w-full bg-black/30 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#5D6658]"
            >
              {LANGUAGES.map((language) => (
                <option key={language.id} value={language.id} className="bg-[#141716]">
                  {language.label}
                </option>
              ))}
            </select>
          </div>
        </>
      )}

      {/* Use in these apps */}
      <div className="dicty-card p-5 space-y-3">
        <div className="flex items-center gap-2">
          <AppWindow className="w-4 h-4 text-[#87B996]" />
          <span className="text-sm font-semibold text-white">Use in these apps</span>
        </div>
        <p className="text-xs text-white/55">
          When one of these apps is in front, Dicty switches to this mode.
        </p>
        <div className="flex flex-wrap gap-1.5">
          {targetRules.length === 0 && (
            <span className="text-xs text-white/40">No apps yet.</span>
          )}
          {targetRules.map((rule) => (
            <span
              key={rule.id}
              className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/[0.06] border border-white/10 text-xs text-white/85"
            >
              {rule.display_name || rule.match.value}
              <button
                onClick={() => modeId && modesStore.removeAppRule(rule.match.value, modeId)}
                className="text-white/45 hover:text-white"
                title="Remove"
              >
                <X className="w-3 h-3" />
              </button>
            </span>
          ))}
        </div>
        <button
          onClick={() => setShowAppPicker(true)}
          className="flex items-center gap-1.5 text-[11px] font-medium text-[#87B996] hover:underline"
        >
          <Plus className="w-3 h-3" />
          <span>Add app</span>
        </button>
      </div>

      {/* More */}
      <div className="dicty-card p-0 overflow-hidden">
        <button
          onClick={() => setShowMore((prev) => !prev)}
          className="w-full p-4 flex items-center justify-between text-left"
        >
          <span className="text-sm font-semibold text-white">More</span>
          {showMore ? (
            <ChevronUp className="w-4 h-4 text-white/40" />
          ) : (
            <ChevronDown className="w-4 h-4 text-white/40" />
          )}
        </button>
        {showMore && (
          <div className="px-5 pb-5 pt-4 space-y-4 border-t border-white/10">
            <div className="space-y-1">
              <label className="text-[11px] font-medium text-white/50">Name</label>
              <input
                type="text"
                value={profile.name}
                onChange={(event) => onUpdateProfile({ ...profile, name: event.target.value })}
                className="w-full bg-black/30 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#5D6658]"
              />
            </div>

            <div className="space-y-1">
              <label className="text-[11px] font-medium text-white/50">Speech model</label>
              <select
                value={profile.whisperModel}
                onChange={(event) => onUpdateProfile({ ...profile, whisperModel: event.target.value })}
                className="w-full bg-black/30 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#5D6658]"
              >
                {ALL_SPEECH_RECOGNITION_MODELS.map((model) => (
                  <option key={model.id} value={model.id} className="bg-[#141716]">
                    {model.name} · {model.size}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <label className="text-[11px] font-medium text-white/50">Tags</label>
              <input
                type="text"
                value={(profile.tags || []).join(", ")}
                onChange={(event) =>
                  onUpdateProfile({
                    ...profile,
                    tags: event.target.value
                      .split(",")
                      .map((tag) => tag.trim())
                      .filter(Boolean),
                  })
                }
                placeholder="chat, work"
                className="w-full bg-black/30 border border-white/10 rounded-xl px-3 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658]"
              />
            </div>

            <div className="space-y-1">
              <label className="text-[11px] font-medium text-white/50">Edit instructions</label>
              <textarea
                value={profile.customPrompt || ""}
                onChange={(event) => {
                  onUpdateProfile({ ...profile, customPrompt: event.target.value });
                  onUpdateEngine({ custom_instructions: event.target.value });
                }}
                placeholder="Extra rules for this mode..."
                rows={3}
                className="w-full text-xs text-white/85 bg-black/30 border border-white/10 focus:border-[#5D6658] rounded-xl p-3 focus:outline-none resize-y"
              />
            </div>

            <button
              onClick={onDelete}
              disabled={profile.isDefault || profilesCount <= 1}
              title={
                profile.isDefault
                  ? "Built-in modes stay put."
                  : profilesCount <= 1
                  ? "Keep at least one mode."
                  : "Delete this mode"
              }
              className="flex items-center gap-1.5 text-[11px] font-medium text-red-400/80 hover:text-red-400 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span>Delete mode</span>
            </button>
          </div>
        )}
      </div>

      {showAppPicker && (
        <AppPickerSheet
          onPick={(bundleId, name) => {
            if (modeId) modesStore.addAppRule(bundleId, name, modeId);
            setShowAppPicker(false);
          }}
          onClose={() => setShowAppPicker(false)}
        />
      )}
    </div>
  );
};

// MARK: - Meeting options

const MeetingOptionsCard: React.FC<{
  meeting: Record<string, any>;
  onChange: (patch: Record<string, any>) => void;
}> = ({ meeting, onChange }) => {
  const separation = meeting.speaker_separation || "you_others";
  return (
    <div className="dicty-card p-5 space-y-4">
      <div className="flex items-center gap-2">
        <Users className="w-4 h-4 text-[#87B996]" />
        <span className="text-sm font-semibold text-white">Meeting options</span>
      </div>

      <div className="flex items-start justify-between gap-4">
        <div className="space-y-0.5">
          <span className="text-xs font-medium text-white">Mute my microphone</span>
          <p className="text-[11px] text-white/50">Record only the other people in the call.</p>
        </div>
        <ToggleSwitch
          checked={!!meeting.mute_microphone}
          onChange={(value) => onChange({ mute_microphone: value })}
          ariaLabel="Mute my microphone"
        />
      </div>

      <div className="flex items-start justify-between gap-4">
        <div className="space-y-0.5">
          <span className="text-xs font-medium text-white">Show turn timestamps</span>
          <p className="text-[11px] text-white/50">Add a time next to each speaker turn.</p>
        </div>
        <ToggleSwitch
          checked={!!meeting.show_timestamps}
          onChange={(value) => onChange({ show_timestamps: value })}
          ariaLabel="Show turn timestamps"
        />
      </div>

      <div className="space-y-1">
        <label className="text-[11px] font-medium text-white/50">Speakers</label>
        <select
          value={separation}
          onChange={(event) => onChange({ speaker_separation: event.target.value })}
          className="w-full bg-black/30 border border-white/10 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#5D6658]"
        >
          <option value="you_others" className="bg-[#141716]">
            You and everyone else
          </option>
          <option value="everyone" className="bg-[#141716]">
            Separate each person
          </option>
        </select>
      </div>
    </div>
  );
};

// MARK: - Before / after example

const ExampleCompare: React.FC<{ styleId: string }> = ({ styleId }) => {
  const example = STYLE_EXAMPLES[styleId] || STYLE_EXAMPLES.punctuation_fast;
  return (
    <div className="grid sm:grid-cols-2 gap-2.5">
      <div className="p-3 rounded-xl bg-white/[0.02] border border-white/10 space-y-1">
        <span className="text-[10px] font-semibold uppercase tracking-wide text-white/40">
          You say
        </span>
        <p className="text-xs text-white/55 whitespace-pre-line">{example.before}</p>
      </div>
      <div className="p-3 rounded-xl bg-[#5D6658]/15 border border-[#5D6658]/30 space-y-1">
        <span className="text-[10px] font-semibold uppercase tracking-wide text-white/40">
          Dicty writes
        </span>
        <p className="text-xs text-white/90 whitespace-pre-line">{example.after}</p>
      </div>
    </div>
  );
};

// MARK: - Sheets

const Sheet: React.FC<{
  title: string;
  description?: string;
  onClose: () => void;
  children: React.ReactNode;
}> = ({ title, description, onClose, children }) => (
  <div
    className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4"
    onClick={onClose}
  >
    <div
      className="w-full max-w-lg max-h-[82vh] overflow-y-auto rounded-2xl bg-[#141716] border border-white/15 p-5 space-y-4"
      onClick={(event) => event.stopPropagation()}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="space-y-0.5">
          <h3 className="text-sm font-bold text-white">{title}</h3>
          {description && <p className="text-xs text-white/50">{description}</p>}
        </div>
        <button onClick={onClose} className="text-white/45 hover:text-white">
          <X className="w-4 h-4" />
        </button>
      </div>
      {children}
    </div>
  </div>
);

const AppRulesSheet: React.FC<{ state: ModesState; onClose: () => void }> = ({ state, onClose }) => {
  const rules = state.appRules.rules;
  return (
    <Sheet
      title="App rules"
      description="Dicty uses the mode you pick when this app is in front."
      onClose={onClose}
    >
      {rules.length === 0 ? (
        <p className="text-xs text-white/45 py-6 text-center">
          No rules yet. Add an app from a mode&rsquo;s page.
        </p>
      ) : (
        <div className="space-y-2">
          {rules.map((rule: AppRule) => (
            <div
              key={rule.id}
              className="flex items-center gap-2.5 p-2.5 rounded-xl bg-white/[0.03] border border-white/10"
            >
              <div className="flex-1 min-w-0">
                <div className="text-xs font-medium text-white truncate">
                  {rule.display_name || rule.match.value}
                </div>
                <div className="text-[10px] text-white/40 truncate">{rule.match.value}</div>
              </div>
              <select
                value={rule.mode_id}
                onChange={(event) => modesStore.setAppRuleMode(rule.id, event.target.value)}
                className="bg-black/30 border border-white/10 rounded-lg px-2 py-1 text-[11px] text-white focus:outline-none focus:border-[#5D6658] max-w-[150px]"
              >
                {state.engineModes.map((mode) => (
                  <option key={mode.id} value={mode.id} className="bg-[#141716]">
                    {mode.name}
                  </option>
                ))}
                {!state.engineModes.some((mode) => mode.id === rule.mode_id) && (
                  <option value={rule.mode_id} className="bg-[#141716]">
                    {rule.mode_id}
                  </option>
                )}
              </select>
              <ToggleSwitch
                size="sm"
                checked={rule.enabled !== false}
                onChange={(value) => modesStore.setAppRuleEnabled(rule.id, value)}
                ariaLabel={`Enable rule for ${rule.display_name || rule.match.value}`}
              />
              <button
                onClick={() => modesStore.resetAppRule(rule.id)}
                className="p-1.5 rounded-lg text-white/45 hover:text-white hover:bg-white/10"
                title="Reset"
              >
                <RotateCcw className="w-3.5 h-3.5" />
              </button>
            </div>
          ))}
        </div>
      )}
    </Sheet>
  );
};

const AppPickerSheet: React.FC<{
  onPick: (bundleId: string, name: string) => void;
  onClose: () => void;
}> = ({ onPick, onClose }) => {
  const [apps, setApps] = useState<RunningAppItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [query, setQuery] = useState("");
  const [customInput, setCustomInput] = useState("");

  useEffect(() => {
    let cancelled = false;
    invoke<RunningAppItem[]>("get_running_applications")
      .then((result) => {
        if (!cancelled && Array.isArray(result)) setApps(result);
      })
      .catch(() => {})
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const filtered = useMemo(() => {
    const trimmed = query.trim().toLowerCase();
    if (!trimmed) return apps;
    return apps.filter(
      (app) =>
        app.process_name.toLowerCase().includes(trimmed) ||
        (app.window_title || "").toLowerCase().includes(trimmed)
    );
  }, [apps, query]);

  return (
    <Sheet title="Add app" description="Pick an app so Dicty uses this mode there." onClose={onClose}>
      <div className="relative">
        <Search className="w-3.5 h-3.5 text-white/40 absolute left-3 top-1/2 -translate-y-1/2" />
        <input
          type="text"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search running apps"
          className="w-full bg-black/30 border border-white/10 rounded-xl pl-9 pr-3 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658]"
        />
      </div>

      <div className="space-y-1.5 max-h-[40vh] overflow-y-auto">
        {isLoading && (
          <div className="flex items-center gap-2 text-xs text-white/45 py-4 justify-center">
            <Loader2 className="w-3.5 h-3.5 animate-spin" />
            <span>Looking for apps...</span>
          </div>
        )}
        {!isLoading && filtered.length === 0 && (
          <p className="text-xs text-white/45 py-4 text-center">No running apps found.</p>
        )}
        {filtered.map((app) => {
          const name = getAppDisplayName(app.process_name, app.window_title);
          return (
            <button
              key={app.process_name}
              onClick={() => onPick(app.process_name.toLowerCase(), name)}
              className="w-full text-left p-2.5 rounded-xl bg-white/[0.03] hover:bg-white/[0.07] border border-white/10 flex items-center gap-2.5"
            >
              <AppWindow className="w-3.5 h-3.5 text-white/50 shrink-0" />
              <div className="min-w-0">
                <div className="text-xs font-medium text-white truncate">{name}</div>
                <div className="text-[10px] text-white/40 truncate">{app.process_name}</div>
              </div>
            </button>
          );
        })}
      </div>

      <div className="space-y-1.5 pt-2 border-t border-white/10">
        <label className="text-[11px] font-medium text-white/50">Or type a program name</label>
        <div className="flex items-center gap-2">
          <input
            type="text"
            value={customInput}
            onChange={(event) => setCustomInput(event.target.value)}
            placeholder="e.g. notepad.exe"
            className="flex-1 bg-black/30 border border-white/10 rounded-xl px-3 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658]"
          />
          <button
            onClick={() => {
              const value = customInput.trim();
              if (value) onPick(value.toLowerCase(), getAppDisplayName(value));
            }}
            disabled={!customInput.trim()}
            className="px-3 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6A7565] disabled:opacity-40 text-white text-xs font-semibold"
          >
            Add
          </button>
        </div>
      </div>
    </Sheet>
  );
};

const NewModeSheet: React.FC<{
  onClose: () => void;
  onCreate: (name: string, kind: string, iconName: string) => void;
}> = ({ onClose, onCreate }) => {
  const [name, setName] = useState("");
  const [kind, setKind] = useState("dictation");
  const [iconName, setIconName] = useState("mic");

  const kinds = [
    { id: "dictation", label: "Dictation" },
    { id: "meeting", label: "Meeting" },
    { id: "focused_meeting", label: "Meeting (one app)" },
    { id: "librarian", label: "Librarian" },
  ];

  const canCreate = name.trim().length > 0;

  return (
    <Sheet title="Create mode" description="Give it a name and pick what it's for." onClose={onClose}>
      <div className="space-y-1">
        <label className="text-[11px] font-medium text-white/50">Name</label>
        <input
          type="text"
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="e.g. Client emails"
          className="w-full bg-black/30 border border-white/10 rounded-xl px-3 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658]"
        />
      </div>

      <div className="space-y-1">
        <label className="text-[11px] font-medium text-white/50">Type</label>
        <div className="grid grid-cols-2 gap-1.5">
          {kinds.map((option) => (
            <button
              key={option.id}
              onClick={() => setKind(option.id)}
              className={`px-3 py-2 rounded-xl border text-xs font-medium transition-colors ${
                kind === option.id
                  ? "bg-[#5D6658]/25 border-[#5D6658]/50 text-white"
                  : "bg-white/[0.02] border-white/10 text-white/70 hover:bg-white/[0.05]"
              }`}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      <div className="space-y-1">
        <label className="text-[11px] font-medium text-white/50">Icon</label>
        <div className="grid grid-cols-6 gap-1.5 max-h-40 overflow-y-auto">
          {AVAILABLE_PROFILE_ICONS.map((icon) => {
            const IconComp = icon.icon;
            const selected = iconName === icon.id;
            return (
              <button
                key={icon.id}
                onClick={() => setIconName(icon.id)}
                title={icon.label}
                className={`aspect-square rounded-xl flex items-center justify-center transition-colors ${
                  selected ? "bg-[#5D6658] text-white" : "bg-white/[0.03] text-white/60 hover:bg-white/[0.08]"
                }`}
              >
                <IconComp className="w-4 h-4" />
              </button>
            );
          })}
        </div>
      </div>

      <button
        onClick={() => {
          if (canCreate) onCreate(name.trim(), kind, iconName);
          onClose();
        }}
        disabled={!canCreate}
        className="w-full flex items-center justify-center gap-1.5 py-2.5 rounded-xl bg-[#5D6658] hover:bg-[#6A7565] disabled:opacity-40 text-white text-xs font-semibold transition-colors"
      >
        <Check className="w-3.5 h-3.5" />
        <span>Create mode</span>
      </button>
    </Sheet>
  );
};
