import React, { useState, useEffect } from "react";
import {
  House,
  SlidersHorizontal,
  LayoutGrid,
  Mic,
  Settings,
  Clock,
  FolderGit2,
  RefreshCw,
  BookA,
  BarChart3,
  Volume2,
  CircleHelp,
  type LucideIcon,
} from "lucide-react";
import { DictyLogo } from "./DictyLogo";
import { engineApi } from "../services/engineApi";
import { useAppAccent } from "../services/themeService";

export type ActiveTab =
  | "home"
  | "modes"
  | "words"
  | "history"
  | "insights"
  | "transcribe"
  | "tts"
  | "projects"
  | "models"
  | "settings"
  | "help"
  // Legacy / deep-link alias tabs
  | "voice_queue"
  | "knowledge"
  | "pending_updates"
  | "prompts"
  | "vocabulary"
  | "account"
  | "api_keys"
  | "shortcuts"
  | "preferences"
  | "sync_backup"
  | "updates";

interface NavItem {
  id: ActiveTab;
  label: string;
  icon: LucideIcon;
  badge?: string;
  badgeVariant?: "indigo" | "emerald";
  isLoading?: boolean;
}

interface NavSection {
  title?: string;
  items: NavItem[];
}

interface NavigationProps {
  activeTab: ActiveTab;
  onTabChange: (tab: ActiveTab) => void;
  stagedThoughtsCount?: number;
  pendingUpdatesCount?: number;
  isGeneratingArchitecture?: boolean;
}

export const Navigation: React.FC<NavigationProps> = ({
  activeTab,
  onTabChange,
  stagedThoughtsCount = 0,
  pendingUpdatesCount = 0,
  isGeneratingArchitecture = false,
}) => {
  const { info: accentInfo } = useAppAccent();
  const [hasUpdateBadge, setHasUpdateBadge] = useState<boolean>(false);

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

  const totalProjectBadges = stagedThoughtsCount + pendingUpdatesCount;

  // Streamlined 2-tier navigation structure (1:1 with MainViews.swift)
  const sections: NavSection[] = [
    {
      items: [
        { id: "home", label: "Home", icon: House },
        { id: "modes", label: "Modes", icon: SlidersHorizontal },
        { id: "words", label: "Words", icon: BookA },
        { id: "history", label: "History", icon: Clock },
        { id: "insights", label: "Insights", icon: BarChart3 },
      ],
    },
    {
      title: "Tools",
      items: [
        { id: "transcribe", label: "Transcribe file", icon: Mic },
        { id: "tts", label: "Text to Voice", icon: Volume2 },
        {
          id: "projects",
          label: "Projects",
          icon: FolderGit2,
          isLoading: isGeneratingArchitecture,
          badge: totalProjectBadges > 0 ? String(totalProjectBadges) : undefined,
          badgeVariant: pendingUpdatesCount > 0 ? "emerald" : "indigo",
        },
      ],
    },
    {
      title: "Library",
      items: [
        { id: "models", label: "Models", icon: LayoutGrid },
      ],
    },
  ];

  // Helper to determine active state including legacy aliases
  const isItemActive = (id: ActiveTab): boolean => {
    if (activeTab === id) return true;
    if (id === "words" && (activeTab === "vocabulary" || activeTab === "prompts")) return true;
    if (
      id === "projects" &&
      (activeTab === "voice_queue" || activeTab === "knowledge" || activeTab === "pending_updates")
    )
      return true;
    if (
      id === "settings" &&
      (activeTab === "preferences" ||
        activeTab === "shortcuts" ||
        activeTab === "account" ||
        activeTab === "api_keys" ||
        activeTab === "sync_backup" ||
        activeTab === "updates")
    )
      return true;
    return false;
  };

  const isSettingsActive = isItemActive("settings");
  const isHelpActive = activeTab === "help";

  return (
    <aside className="w-56 flex-shrink-0 bg-black/35 border-r border-white/10 flex flex-col justify-between py-4 select-none backdrop-blur-2xl">
      <div className="overflow-y-auto px-3 space-y-4">
        {/* Brand Header */}
        <div className="flex items-center gap-2.5 px-2 py-1 mb-1">
          <DictyLogo className="w-7 h-7 flex-shrink-0 shadow-md shadow-[#506658]/30 rounded-lg overflow-hidden" />
          <div>
            <span className="font-semibold text-sm tracking-tight text-white block leading-tight">
              Dicty
            </span>
            <span className="text-[10px] text-white/50 block font-medium">
              Configuration
            </span>
          </div>
        </div>

        {/* Sidebar Sections (1:1 with MainViews.swift) */}
        {sections.map((section, idx) => (
          <div key={idx} className="space-y-1">
            {section.title && (
              <div className="text-[11px] font-semibold text-white/40 uppercase tracking-wider px-2 py-1">
                {section.title}
              </div>
            )}

            <div className="space-y-0.5">
              {section.items.map((item) => {
                const Icon = item.icon;
                const active = isItemActive(item.id);
                return (
                  <button
                    key={item.id}
                    onClick={() => onTabChange(item.id)}
                    style={{
                      backgroundColor: active ? accentInfo.activeHex : undefined,
                    }}
                    className={`w-full flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                      active
                        ? "text-white shadow-sm"
                        : "text-white/70 hover:text-white hover:bg-white/5"
                    }`}
                  >
                    <Icon
                      style={{
                        color: active ? "#ffffff" : accentInfo.swatchDark,
                      }}
                      className="w-3.5 h-3.5 transition-colors"
                    />
                    <span className="truncate">{item.label}</span>

                    {item.isLoading && (
                      <RefreshCw className="ml-auto w-3.5 h-3.5 text-indigo-400 animate-spin flex-shrink-0" />
                    )}

                    {item.badge && !item.isLoading && (
                      <span
                        className={`ml-auto px-1.5 py-0.2 rounded-full text-[10px] font-bold border ${
                          item.badgeVariant === "emerald"
                            ? "bg-emerald-500/30 text-emerald-300 border-emerald-500/40"
                            : "bg-indigo-500/30 text-indigo-300 border-indigo-500/40"
                        }`}
                      >
                        {item.badge}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {/* Pinned Bottom Footer (1:1 with MainViews.swift: Settings + Help) */}
      <div className="px-3 pt-3 border-t border-white/10 space-y-0.5">
        <button
          onClick={() => onTabChange("settings")}
          style={{
            backgroundColor: isSettingsActive ? accentInfo.activeHex : undefined,
          }}
          className={`w-full flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg text-xs font-medium transition-all relative ${
            isSettingsActive
              ? "text-white shadow-sm"
              : "text-white/70 hover:text-white hover:bg-white/5"
          }`}
        >
          <Settings
            style={{
              color: isSettingsActive ? "#ffffff" : accentInfo.swatchDark,
            }}
            className="w-3.5 h-3.5 transition-colors"
          />
          <span className="truncate">Settings</span>

          {hasUpdateBadge && (
            <span
              className="ml-auto w-2 h-2 rounded-full bg-emerald-400 ring-2 ring-[#121418]"
              title="An update is available"
            />
          )}
        </button>

        <button
          onClick={() => {
            window.dispatchEvent(new CustomEvent("dicty:open-onboarding"));
          }}
          style={{
            backgroundColor: isHelpActive ? accentInfo.activeHex : undefined,
          }}
          className={`w-full flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
            isHelpActive
              ? "text-white shadow-sm"
              : "text-white/70 hover:text-white hover:bg-white/5"
          }`}
        >
          <CircleHelp
            style={{
              color: isHelpActive ? "#ffffff" : accentInfo.swatchDark,
            }}
            className="w-3.5 h-3.5 transition-colors"
          />
          <span className="truncate">Help</span>
        </button>
      </div>
    </aside>
  );
};
