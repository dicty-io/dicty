import { useState, useEffect } from "react";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { AlertCircle } from "lucide-react";
import { Navigation, type ActiveTab } from "./components/Navigation";
import { HomeView } from "./views/HomeView";
import { ModesView } from "./views/ModesView";
import { getStoredProfiles } from "./types/profiles";
import { ModelsView } from "./views/ModelsView";
import { VoiceQueueView } from "./views/VoiceQueueView";
import { ProjectsView } from "./views/ProjectsView";
import { KnowledgeBaseView } from "./views/KnowledgeBaseView";
import { PendingUpdatesView } from "./views/PendingUpdatesView";
import { PromptsSettingsView } from "./views/PromptsSettingsView";
import { WordsView } from "./views/WordsView";
import { AccountView } from "./views/AccountView";
import { TranscribeFileView } from "./views/TranscribeFileView";
import { APISettingsView } from "./views/APISettingsView";
import { ShortcutsView } from "./views/ShortcutsView";
import { PreferencesView } from "./views/PreferencesView";
import { SyncBackupView } from "./views/SyncBackupView";
import { HistoryView } from "./views/HistoryView";
import { UpdatesView } from "./views/UpdatesView";
import { RecordingOverlayHUD } from "./views/RecordingOverlayHUD";
import { ModeSwitcherHUDView } from "./views/ModeSwitcherHUDView";
import { OnboardingModal } from "./components/OnboardingModal";
import { engineApi } from "./services/engineApi";
import { engineFetch } from "./services/engineClient";
import { useArchitectureTask } from "./services/architectureTaskService";

const VALID_TABS: ActiveTab[] = [
  "home", "modes", "models", "voice_queue", "projects", "knowledge",
  "pending_updates", "prompts", "words", "vocabulary", "account", "transcribe",
  "api_keys", "shortcuts", "preferences", "sync_backup", "history", "updates"
];

/// Tabs removed or merged keep working: a saved or deep-linked old value lands
/// on the page that holds them now.
function normalizeLegacyTab(tab: ActiveTab | null): ActiveTab | null {
  if (tab === "vocabulary") return "words";
  return tab;
}

// Determine window role safely across both Tauri and browser environments
let currentWindowLabel = "main";
try {
  const currentWin = getCurrentWebviewWindow();
  if (currentWin?.label) {
    currentWindowLabel = currentWin.label;
  }
} catch {
  // Browser preview mode fallback
}

export default function App() {
  const [activeTab, setActiveTab] = useState<ActiveTab>(() => {
    if (typeof window !== "undefined") {
      const params = new URLSearchParams(window.location.search);
      const tabParam = (params.get("tab") || params.get("window")) as ActiveTab | null;
      if (tabParam && VALID_TABS.includes(tabParam)) {
        return normalizeLegacyTab(tabParam) as ActiveTab;
      }
      try {
        const savedTab = localStorage.getItem("dicty_active_tab") as ActiveTab | null;
        if (savedTab && VALID_TABS.includes(savedTab)) {
          return normalizeLegacyTab(savedTab) as ActiveTab;
        }
      } catch {
        // Ignore localStorage restrictions
      }
    }
    return "home";
  });

  const { isGenerating: isGeneratingArchitecture } = useArchitectureTask();
  const [stagedThoughtsCount, setStagedThoughtsCount] = useState(0);
  const [pendingUpdatesCount, setPendingUpdatesCount] = useState(0);
  const [backendError, setBackendError] = useState<string | null>(null);
  const [showOnboarding, setShowOnboarding] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    return localStorage.getItem("dicty_has_seen_onboarding") !== "true";
  });

  useEffect(() => {
    const handleOpenOnboarding = () => setShowOnboarding(true);
    window.addEventListener("dicty:open-onboarding", handleOpenOnboarding);
    return () => {
      window.removeEventListener("dicty:open-onboarding", handleOpenOnboarding);
    };
  }, []);

  useEffect(() => {
    let unlistenBackend: (() => void) | undefined;
    let unlistenAuth: (() => void) | undefined;

    const showError = (message: string) => {
      setBackendError(message);
      setTimeout(() => setBackendError(null), 8000);
    };

    listen<{ error: string }>("dicty:backend-error", (event) => {
      showError(event.payload.error);
    }).then((fn) => {
      unlistenBackend = fn;
    });

    listen<{ error: string }>("engine-auth-failed", (event) => {
      showError(event.payload.error);
    }).then((fn) => {
      unlistenAuth = fn;
    });

    const handleDomAuthFailure = (event: Event) => {
      const message = (event as CustomEvent<{ error?: string }>).detail?.error;
      showError(message || "Dicty's engine rejected this session. Restart the engine.");
    };
    window.addEventListener("dicty:engine-auth-failed", handleDomAuthFailure);

    return () => {
      if (unlistenBackend) unlistenBackend();
      if (unlistenAuth) unlistenAuth();
      window.removeEventListener("dicty:engine-auth-failed", handleDomAuthFailure);
    };
  }, []);

  // Synchronize stored sound preferences to native Rust audio engine on startup
  useEffect(() => {
    try {
      const soundFeedback = localStorage.getItem("dicty_sound_feedback") !== "false";
      const startSoundType = localStorage.getItem("dicty_start_sound_type") || "Built-in";
      const startSoundName = localStorage.getItem("dicty_start_sound_name") || "Speech On";
      const startSoundPath = localStorage.getItem("dicty_start_sound_path") || "C:\\Windows\\Media\\Speech On.wav";
      const stopSoundType = localStorage.getItem("dicty_stop_sound_type") || "Built-in";
      const stopSoundName = localStorage.getItem("dicty_stop_sound_name") || "Speech Off";
      const stopSoundPath = localStorage.getItem("dicty_stop_sound_path") || "C:\\Windows\\Media\\Speech Off.wav";

      invoke("save_sound_config", {
        config: {
          sound_feedback: soundFeedback,
          start_sound_type: startSoundType,
          start_sound_name: startSoundName,
          start_sound_path: startSoundPath,
          stop_sound_type: stopSoundType,
          stop_sound_name: stopSoundName,
          stop_sound_path: stopSoundPath,
        },
      }).catch(() => {});

      // Synchronize stored hotkeys and double-tap preferences to Tauri on startup
      const toggleKey = localStorage.getItem("dicty_shortcut_toggle") || "Ctrl + Space";
      const pauseKey = localStorage.getItem("dicty_shortcut_pause") || "Ctrl + Shift + P";
      const modeKey = localStorage.getItem("dicty_shortcut_mode") || "Alt + Shift + M";
      const doubleTapToggle = localStorage.getItem("dicty_double_tap_toggle") === "true";
      const doubleTapPause = localStorage.getItem("dicty_double_tap_pause") === "true";
      const doubleTapMode = localStorage.getItem("dicty_double_tap_mode") === "true";

      invoke("register_custom_hotkeys", {
        toggleKey,
        pauseKey,
        modeKey,
        doubleTapToggle,
        doubleTapPause,
        doubleTapMode,
      }).catch((err) => {
        console.warn("Failed to register custom hotkeys on startup:", err);
      });

      // Synchronize all stored profiles (models, format styles, custom prompts, tags) to Rust layer
      try {
        const storedProfs = getStoredProfiles();
        const syncPromises: Promise<any>[] = [];
        storedProfs.forEach((p) => {
          if (p.whisperModel) syncPromises.push(invoke("set_profile_model", { profileId: p.id, modelId: p.whisperModel }).catch(() => {}));
          if (p.formatStyle) syncPromises.push(invoke("set_profile_format_style", { profileId: p.id, formatStyle: p.formatStyle }).catch(() => {}));
          if (p.customPrompt !== undefined) syncPromises.push(invoke("set_profile_custom_prompt", { profileId: p.id, customPrompt: p.customPrompt || "" }).catch(() => {}));
          if (p.tags) syncPromises.push(invoke("set_profile_tags", { profileId: p.id, tags: p.tags }).catch(() => {}));
        });

        Promise.all(syncPromises).then(() => {
          // Synchronize active mode profile AFTER format styles and models are loaded into Rust
          const activeProfile = localStorage.getItem("dicty_active_profile");
          if (activeProfile) {
            invoke("set_active_mode", { profileId: activeProfile }).catch(() => {});
          }
        });
      } catch {}

      // Synchronize LLM configuration to Rust layer
      try {
        const llmProvider = localStorage.getItem("llmProvider") || "openrouter";
        const llmModel = localStorage.getItem("llmModel") || "qwen/qwen-3.5-flash";
        const llmApiKey = localStorage.getItem("llmApiKey") || localStorage.getItem("openaiApiKey") || "";
        const llmBaseUrl = localStorage.getItem("llmBaseUrl") || "http://localhost:1234/v1";
        invoke("set_llm_config", {
          provider: llmProvider,
          model: llmModel,
          apiKey: llmApiKey,
          baseUrl: llmBaseUrl,
        }).catch(() => {});
      } catch {}
    } catch {}
  }, []);

  // Auto-sync settings & vocabulary on startup if logged in with Dicty (safe against offline / no internet)
  useEffect(() => {
    let isMounted = true;
    const triggerAutoSync = async () => {
      try {
        const token = localStorage.getItem("dicty_jwt_token") || localStorage.getItem("auth_token");
        if (!token) return;

        const cloudRes = await engineApi.downloadSettingsFromCloud(token);
        if (isMounted && cloudRes) {
          if (cloudRes.vocabulary && Array.isArray(cloudRes.vocabulary)) {
            const vocabRes = await engineApi.getVocabulary().catch(() => null);
            const existing = new Set((vocabRes?.vocabulary || []).map((v: any) => `${v.word.toLowerCase()}|${v.replacement}`));
            for (const v of cloudRes.vocabulary) {
              const key = `${v.word.toLowerCase()}|${v.replacement}`;
              if (!existing.has(key)) {
                await engineApi.addVocabulary(v.word, v.replacement);
              }
            }
          }
          if (cloudRes.customPrompts && Array.isArray(cloudRes.customPrompts)) {
            for (const p of cloudRes.customPrompts) {
              if (p.is_custom && p.key && p.active_value) {
                await engineApi.updatePrompt(p.key, p.active_value);
              }
            }
          }
        }
      } catch {
        // Offline / network failure - never crash or throw
      }
    };
    triggerAutoSync();
    return () => {
      isMounted = false;
    };
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    import("@tauri-apps/api/event").then(({ listen }) => {
      listen<string>("oauth-token", async (event) => {
        if (event.payload) {
          const token = event.payload.trim().replace(/['"]/g, "");
          if (token) {
            try {
              localStorage.setItem("dicty_jwt_token", token);
              const parts = token.split(".");
              if (parts.length >= 2) {
                try {
                  const base64Url = parts[1];
                  const base64 = base64Url.replace(/-/g, "+").replace(/_/g, "/");
                  const jsonStr = decodeURIComponent(
                    atob(base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "="))
                      .split("")
                      .map((c) => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2))
                      .join("")
                  );
                  const payload = JSON.parse(jsonStr);
                  const email = payload.email || (payload.sub && payload.sub.includes("@") ? payload.sub : null);
                  if (email) {
                    const authUser = {
                      id: payload.userId || payload.sub,
                      email,
                      is_pro: payload.isPro ?? payload.is_pro ?? false,
                      compute_balance: payload.computeBalance ?? payload.compute_balance ?? 0,
                      subscription_tier: payload.subscriptionTier ?? payload.subscription_tier ?? "free",
                    };
                    localStorage.setItem("dicty_auth_user", JSON.stringify(authUser));
                  }
                } catch {}
              }
              await engineApi.submitToken(token);
              window.dispatchEvent(new Event("storage"));
            } catch (err) {
              console.warn("Auto OAuth token submission error:", err);
            }
          }
        }
      }).then((un) => {
        unlisten = un;
      });
    });

    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  useEffect(() => {
    let isMounted = true;
    const updateCount = async () => {
      try {
        const res = await engineApi.getQueue();
        if (isMounted && res?.status === "success" && Array.isArray(res.items)) {
          const real = res.items.filter(
            (i: any) =>
              i.source !== "ci_test" &&
              i.text !== "Test thought for automated test" &&
              i.id !== "th_1" &&
              i.id !== "th_2" &&
              i.id !== "th_3"
          );
          setStagedThoughtsCount(real.length);
        }
      } catch {}

      try {
        const pRes = await engineFetch("/pending_updates");
        if (pRes.ok) {
          const pData = await pRes.json();
          if (isMounted && Array.isArray(pData.updates)) {
            const valid = pData.updates.filter(
              (u: any) => u && u.id && u.status !== "approved" && u.status !== "rejected"
            );
            setPendingUpdatesCount(valid.length);
          }
        }
      } catch {}
    };

    updateCount();
    const interval = setInterval(updateCount, 4000);
    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, []);

  const handleTabChange = (tab: ActiveTab) => {
    setActiveTab(tab);
    if (typeof window !== "undefined") {
      try {
        localStorage.setItem("dicty_active_tab", tab);
        const url = new URL(window.location.href);
        url.searchParams.set("tab", tab);
        window.history.replaceState({}, "", url.toString());
      } catch {
        // Ignore history / storage errors
      }
    }
  };

  // Help cards ("Set up") and other panels can ask the app to open a page.
  useEffect(() => {
    const onNavigate = (event: Event) => {
      const tab = (event as CustomEvent<{ tab?: ActiveTab }>).detail?.tab;
      if (tab && VALID_TABS.includes(tab)) handleTabChange(tab);
    };
    window.addEventListener("dicty:navigate", onNavigate as EventListener);
    return () => window.removeEventListener("dicty:navigate", onNavigate as EventListener);
  }, []);

  // Check if this window is running as the dedicated transparent floating overlay
  const isDedicatedOverlayWindow =
    currentWindowLabel === "overlay" ||
    (typeof window !== "undefined" &&
      (window.location.search.includes("window=overlay") ||
        window.location.search.includes("overlay") ||
        (window as any).__TAURI_METADATA__?.__currentWindow?.label === "overlay"));

  if (isDedicatedOverlayWindow) {
    return (
      <div className="w-screen h-screen bg-transparent flex items-center justify-center p-0 m-0 overflow-hidden">
        <RecordingOverlayHUD />
      </div>
    );
  }

  // Check if this window is running as the dedicated transparent floating mode switcher
  const isDedicatedModeSwitcherWindow =
    currentWindowLabel === "mode_switcher" ||
    (typeof window !== "undefined" &&
      (window.location.search.includes("window=mode_switcher") ||
        window.location.search.includes("mode_switcher") ||
        (window as any).__TAURI_METADATA__?.__currentWindow?.label === "mode_switcher"));

  if (isDedicatedModeSwitcherWindow) {
    return (
      <div className="w-screen h-screen bg-transparent flex items-center justify-center p-0 m-0 overflow-hidden">
        <ModeSwitcherHUDView />
      </div>
    );
  }

  // Check if this window is running as a dedicated standalone history window
  const isDedicatedHistoryWindow =
    currentWindowLabel === "history" ||
    (typeof window !== "undefined" &&
      (window.location.search.includes("window=history") ||
        (window as any).__TAURI_METADATA__?.__currentWindow?.label === "history"));

  if (isDedicatedHistoryWindow) {
    return (
      <div className="flex h-screen w-screen bg-[#121418] text-white overflow-hidden select-none font-sans relative">
        <div
          className="absolute w-[450px] h-[450px] rounded-full blur-[110px] pointer-events-none -top-32 -left-20"
          style={{ background: "rgba(93, 102, 88, 0.2)" }}
        />
        <div
          className="absolute w-[450px] h-[450px] rounded-full blur-[110px] pointer-events-none -bottom-32 -right-20"
          style={{ background: "rgba(56, 181, 115, 0.12)" }}
        />
        <main className="flex-1 flex flex-col min-w-0 overflow-hidden relative z-10">
          <HistoryView />
        </main>
      </div>
    );
  }

  return (
    <div className="flex h-screen w-screen bg-[#121418] text-white overflow-hidden select-none font-sans relative">
      {/* Dicty's Signature Animated Ambient Glow Blobs (from MainViews.swift) */}
      <div
        className="absolute w-[450px] h-[450px] rounded-full blur-[110px] pointer-events-none -top-32 -left-20"
        style={{ background: "rgba(93, 102, 88, 0.2)" }}
      />
      <div
        className="absolute w-[450px] h-[450px] rounded-full blur-[110px] pointer-events-none -bottom-32 -right-20"
        style={{ background: "rgba(56, 181, 115, 0.12)" }}
      />

      {/* Backend Offline Floating Banner */}
      {backendError && (
        <div className="absolute top-4 right-4 z-50 max-w-md bg-rose-950/90 border border-rose-500/40 text-rose-200 px-4 py-3 rounded-xl shadow-2xl backdrop-blur-md flex items-start gap-3 animate-in fade-in slide-in-from-top-2">
          <AlertCircle className="w-5 h-5 text-rose-400 shrink-0 mt-0.5" />
          <div className="text-xs">
            <p className="font-semibold text-rose-100">Dicty Engine Offline</p>
            <p className="text-rose-200/80 mt-0.5">{backendError}</p>
          </div>
          <button
            onClick={() => setBackendError(null)}
            className="text-rose-400 hover:text-rose-100 ml-auto text-xs"
          >
            ✕
          </button>
        </div>
      )}

      {/* Dicty Sidebar Navigation (1:1 with SwiftUI MainViews.swift) */}
      <Navigation
        activeTab={activeTab}
        onTabChange={handleTabChange}
        stagedThoughtsCount={stagedThoughtsCount}
        pendingUpdatesCount={pendingUpdatesCount}
        isGeneratingArchitecture={isGeneratingArchitecture}
      />

      {/* Main Content Pane */}
      <main className="flex-1 flex flex-col min-w-0 overflow-hidden relative z-10">
        {activeTab === "home" && <HomeView />}
        {activeTab === "modes" && <ModesView onNavigateTab={handleTabChange} />}
        {activeTab === "models" && <ModelsView />}
        {activeTab === "voice_queue" && <VoiceQueueView />}
        {activeTab === "projects" && <ProjectsView onNavigateTab={handleTabChange} />}
        {activeTab === "knowledge" && <KnowledgeBaseView />}
        {activeTab === "pending_updates" && <PendingUpdatesView />}
        {activeTab === "prompts" && <PromptsSettingsView />}
        {(activeTab === "words" || activeTab === "vocabulary") && <WordsView />}
        {activeTab === "account" && <AccountView />}
        {activeTab === "transcribe" && <TranscribeFileView />}
        {activeTab === "api_keys" && <APISettingsView />}
        {activeTab === "shortcuts" && <ShortcutsView />}
        {activeTab === "preferences" && <PreferencesView />}
        {activeTab === "sync_backup" && <SyncBackupView />}
        {activeTab === "history" && <HistoryView />}
        {activeTab === "updates" && <UpdatesView />}
      </main>

      {/* Dicty Windows Onboarding Flow (1:1 with SwiftUI OnboardingView) */}
      <OnboardingModal
        isOpen={showOnboarding}
        onClose={() => setShowOnboarding(false)}
      />
    </div>
  );
}
