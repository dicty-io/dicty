import React, { useState, useEffect } from "react";
import {
  Settings,
  Keyboard,
  CircleUser,
  KeyRound,
  RefreshCw,
  ArrowUpCircle,
  type LucideIcon,
} from "lucide-react";
import { PreferencesView } from "./PreferencesView";
import { ShortcutsView } from "./ShortcutsView";
import { AccountView } from "./AccountView";
import { APISettingsView } from "./APISettingsView";
import { SyncBackupView } from "./SyncBackupView";
import { UpdatesView } from "./UpdatesView";
import { engineApi } from "../services/engineApi";

export type SettingsSubTab =
  | "general"
  | "shortcuts"
  | "account"
  | "api_keys"
  | "sync"
  | "updates";

interface SettingsTabItem {
  id: SettingsSubTab;
  label: string;
  icon: LucideIcon;
  badge?: boolean;
}

const SETTINGS_TABS: SettingsTabItem[] = [
  { id: "general", label: "General", icon: Settings },
  { id: "shortcuts", label: "Shortcuts", icon: Keyboard },
  { id: "account", label: "Account", icon: CircleUser },
  { id: "api_keys", label: "AI Providers", icon: KeyRound },
  { id: "sync", label: "Sync & Backup", icon: RefreshCw },
  { id: "updates", label: "Updates", icon: ArrowUpCircle },
];

const SETTINGS_SUBTAB_STORAGE_KEY = "dicty_settings_subtab";

interface SettingsHubViewProps {
  initialSubTab?: SettingsSubTab;
}

export const SettingsHubView: React.FC<SettingsHubViewProps> = ({ initialSubTab }) => {
  const [activeSubTab, setActiveSubTab] = useState<SettingsSubTab>(() => {
    if (initialSubTab) return initialSubTab;
    try {
      const saved = localStorage.getItem(SETTINGS_SUBTAB_STORAGE_KEY) as SettingsSubTab | null;
      if (saved && ["general", "shortcuts", "account", "api_keys", "sync", "updates"].includes(saved)) {
        return saved;
      }
    } catch {
      // Ignore storage restrictions
    }
    return "general";
  });

  const [hasUpdateBadge, setHasUpdateBadge] = useState<boolean>(false);

  // Check if an update is available to display badge on the Updates toolbar button
  useEffect(() => {
    let isMounted = true;
    engineApi
      .checkForUpdates()
      .then((res: any) => {
        if (isMounted && res?.has_update) {
          setHasUpdateBadge(true);
        }
      })
      .catch(() => {});
    return () => {
      isMounted = false;
    };
  }, []);

  // Synchronize when initialSubTab changes from parent
  useEffect(() => {
    if (initialSubTab) {
      setActiveSubTab(initialSubTab);
    }
  }, [initialSubTab]);

  // Listen to navigation events (e.g. from help guides or shortcut links)
  useEffect(() => {
    const handleNavigate = (event: Event) => {
      const tab = (event as CustomEvent<{ tab?: string; subTab?: string }>).detail;
      if (tab?.subTab && ["general", "shortcuts", "account", "api_keys", "sync", "updates"].includes(tab.subTab)) {
        handleSelectTab(tab.subTab as SettingsSubTab);
      } else if (tab?.tab) {
        if (tab.tab === "updates") handleSelectTab("updates");
        else if (tab.tab === "shortcuts") handleSelectTab("shortcuts");
        else if (tab.tab === "preferences") handleSelectTab("general");
        else if (tab.tab === "api_keys") handleSelectTab("api_keys");
        else if (tab.tab === "account") handleSelectTab("account");
        else if (tab.tab === "sync_backup") handleSelectTab("sync");
      }
    };
    window.addEventListener("dicty:navigate", handleNavigate as EventListener);
    return () => {
      window.removeEventListener("dicty:navigate", handleNavigate as EventListener);
    };
  }, []);

  const handleSelectTab = (tab: SettingsSubTab) => {
    setActiveSubTab(tab);
    try {
      localStorage.setItem(SETTINGS_SUBTAB_STORAGE_KEY, tab);
    } catch {
      // Ignore storage restrictions
    }
  };

  return (
    <div className="flex-1 flex flex-col min-h-0 min-w-0 select-none">
      {/* macOS toolbar-style segmented switcher */}
      <div className="px-8 pt-5 pb-3 border-b border-white/10 shrink-0 bg-black/20 backdrop-blur-md">
        <div className="flex items-center gap-2 overflow-x-auto py-1">
          {SETTINGS_TABS.map((item) => {
            const isSelected = activeSubTab === item.id;
            const Icon = item.icon;
            const showBadge = item.id === "updates" && hasUpdateBadge;

            return (
              <button
                key={item.id}
                onClick={() => handleSelectTab(item.id)}
                className={`relative flex flex-col items-center justify-center min-w-[70px] px-3.5 py-1.5 rounded-xl transition-all ${
                  isSelected
                    ? "bg-[#5D6658]/35 text-white border border-[#87B996]/30 shadow-sm"
                    : "text-white/60 hover:text-white hover:bg-white/[0.04] border border-transparent"
                }`}
              >
                <div className="relative">
                  <Icon
                    className={`w-4 h-4 mb-1 transition-colors ${
                      isSelected ? "text-[#87B996]" : "text-white/60"
                    }`}
                  />
                  {showBadge && (
                    <span className="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-emerald-400 ring-2 ring-black" />
                  )}
                </div>
                <span
                  className={`text-[11px] font-medium tracking-tight whitespace-nowrap ${
                    isSelected ? "text-white font-semibold" : "text-white/70"
                  }`}
                >
                  {item.label}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Embedded Sub-View Container */}
      <div className="flex-1 min-h-0 overflow-y-auto">
        {activeSubTab === "general" && <PreferencesView />}
        {activeSubTab === "shortcuts" && <ShortcutsView />}
        {activeSubTab === "account" && <AccountView />}
        {activeSubTab === "api_keys" && <APISettingsView />}
        {activeSubTab === "sync" && <SyncBackupView />}
        {activeSubTab === "updates" && <UpdatesView />}
      </div>
    </div>
  );
};
