import React, { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { Check } from "lucide-react";
import { engineApi } from "../services/engineApi";
import { getStoredProfiles, getProfileIcon, type ProfileItem } from "../types/profiles";

const resolveItemIcon = (profile: ProfileItem) => {
  if (profile.icon && typeof profile.icon !== "string") {
    return profile.icon;
  }
  return getProfileIcon(profile.iconName, profile.id);
};

export const ModeSwitcherHUDView: React.FC = () => {
  const [profiles, setProfiles] = useState<ProfileItem[]>(() => {
    return getStoredProfiles();
  });
  const [activeProfileId, setActiveProfileId] = useState<string>(() => {
    return localStorage.getItem("dicty_active_profile") || "prof_1";
  });
  const [selectedIndex, setSelectedIndex] = useState<number>(0);

  const profilesRef = useRef(profiles);
  profilesRef.current = profiles;
  const selectedIndexRef = useRef(selectedIndex);
  selectedIndexRef.current = selectedIndex;

  // Initialize selectedIndex to active profile index
  useEffect(() => {
    const activeId = localStorage.getItem("dicty_active_profile") || "prof_1";
    setActiveProfileId(activeId);
    const idx = profiles.findIndex((p) => p.id === activeId);
    setSelectedIndex(idx >= 0 ? idx : 0);
  }, [profiles]);

  const handleSelectProfile = async (index: number) => {
    const list = profilesRef.current;
    if (index < 0 || index >= list.length) return;
    const target = list[index];

    try {
      // 1. Set active mode on Tauri Rust layer (switches active model on engine, plays sound, emits dicty:mode-changed)
      await invoke("set_active_mode", { profileId: target.id });

      // 2. Persist to localStorage & trigger local state sync
      localStorage.setItem("dicty_active_profile", target.id);
      if (target.whisperModel) {
        localStorage.setItem("dicty_active_model", target.whisperModel);
        engineApi.setActiveModel(target.whisperModel).catch(() => {});
      }
      window.dispatchEvent(new Event("storage"));
    } catch (err) {
      console.warn("Failed to set active mode from Mode Switcher:", err);
    } finally {
      // 3. Hide floating switcher window
      invoke("hide_mode_switcher").catch(() => {});
    }
  };

  const handleClose = () => {
    invoke("hide_mode_switcher").catch(() => {});
  };

  // Listen for native events from Tauri
  useEffect(() => {
    let unlistenOpen: (() => void) | null = null;
    let unlistenNext: (() => void) | null = null;
    let unlistenChanged: (() => void) | null = null;

    listen("dicty:mode-switcher-opened", () => {
      const stored = getStoredProfiles();
      setProfiles(stored);
      profilesRef.current = stored;

      const curId = localStorage.getItem("dicty_active_profile") || "prof_1";
      setActiveProfileId(curId);
      const idx = stored.findIndex((p) => p.id === curId);
      setSelectedIndex(idx >= 0 ? idx : 0);
    }).then((fn) => {
      unlistenOpen = fn;
    });

    listen("dicty:mode-switcher-next", () => {
      const count = profilesRef.current.length;
      if (count > 0) {
        setSelectedIndex((prev) => (prev + 1) % count);
      }
    }).then((fn) => {
      unlistenNext = fn;
    });

    listen<any>("dicty:mode-changed", (event) => {
      if (event.payload?.profile_id) {
        setActiveProfileId(event.payload.profile_id);
      }
    }).then((fn) => {
      unlistenChanged = fn;
    });

    // Auto-hide when window loses focus (click outside)
    const handleBlur = () => {
      handleClose();
    };
    window.addEventListener("blur", handleBlur);

    return () => {
      if (unlistenOpen) unlistenOpen();
      if (unlistenNext) unlistenNext();
      if (unlistenChanged) unlistenChanged();
      window.removeEventListener("blur", handleBlur);
    };
  }, []);

  // Keyboard Navigation: Arrow Up, Arrow Down, Enter, Space, Numbers 1-9, Escape
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const count = profilesRef.current.length;
      if (count === 0) return;

      switch (e.key) {
        case "ArrowUp":
        case "Up":
          e.preventDefault();
          e.stopPropagation();
          setSelectedIndex((prev) => (prev - 1 + count) % count);
          break;

        case "ArrowDown":
        case "Down":
          e.preventDefault();
          e.stopPropagation();
          setSelectedIndex((prev) => (prev + 1) % count);
          break;

        case "Enter":
        case " ":
          e.preventDefault();
          e.stopPropagation();
          handleSelectProfile(selectedIndexRef.current);
          break;

        case "Escape":
          e.preventDefault();
          e.stopPropagation();
          handleClose();
          break;

        case "1":
        case "2":
        case "3":
        case "4":
        case "5":
        case "6":
        case "7":
        case "8":
        case "9": {
          const num = parseInt(e.key, 10);
          if (num >= 1 && num <= count) {
            e.preventDefault();
            e.stopPropagation();
            handleSelectProfile(num - 1);
          }
          break;
        }

        default:
          break;
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, []);

  const visibleProfiles = profiles.slice(0, 9);

  return (
    <div className="w-full h-full flex items-center justify-center p-2 bg-transparent select-none animate-in fade-in zoom-in-95 duration-150">
      <div
        className="w-[320px] max-w-full rounded-2xl overflow-hidden bg-[#14171A]/95 backdrop-blur-2xl border border-white/15 shadow-2xl shadow-black/80 flex flex-col"
        data-tauri-drag-region
      >
        {/* Modes List */}
        <div className="p-2 space-y-1">
          {visibleProfiles.map((profile, idx) => {
            const isActive = profile.id === activeProfileId;
            const isSelected = idx === selectedIndex;
            const Icon = resolveItemIcon(profile);

            return (
              <div
                key={profile.id}
                onClick={() => handleSelectProfile(idx)}
                onMouseEnter={() => setSelectedIndex(idx)}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-xl cursor-pointer transition-all duration-100 ${
                  isSelected
                    ? "bg-white/10 text-white border border-white/15 shadow-sm"
                    : "text-white/70 hover:text-white hover:bg-white/[0.04] border border-transparent"
                }`}
              >
                {/* Mode Icon */}
                <div
                  className={`w-7 h-7 rounded-lg flex items-center justify-center shrink-0 transition-colors ${
                    isActive
                      ? "bg-blue-500/20 text-blue-400 border border-blue-500/30"
                      : isSelected
                      ? "bg-white/10 text-white"
                      : "bg-white/5 text-white/50"
                  }`}
                >
                  <Icon className="w-4 h-4" />
                </div>

                {/* Mode Name & Assigned Model Subtitle */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span
                      className={`text-xs font-semibold truncate ${
                        isSelected ? "text-white" : "text-white/90"
                      }`}
                    >
                      {profile.name}
                    </span>
                  </div>
                  <div className="text-[10px] text-white/40 truncate">
                    {profile.whisperModel
                      ? profile.whisperModel
                      : profile.badgeText || "Dictation"}
                  </div>
                </div>

                {/* Right: Blue Checkmark for Active or Number Shortcut Badge */}
                <div className="shrink-0 flex items-center">
                  {isActive ? (
                    <div className="w-5 h-5 rounded-full bg-blue-500/20 border border-blue-500/40 flex items-center justify-center">
                      <Check className="w-3 h-3 text-blue-400 font-bold" />
                    </div>
                  ) : (
                    <span className="text-[10px] font-mono font-semibold px-1.5 py-0.5 rounded bg-white/5 border border-white/10 text-white/40">
                      {idx + 1}
                    </span>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {/* Divider */}
        <div className="border-t border-white/10" />

        {/* Bottom Keyboard Legend Bar */}
        <div className="px-3.5 py-2.5 bg-white/[0.02] flex items-center justify-between text-[10px] text-white/50 font-sans">
          <span className="text-white/30 font-medium tracking-wide">
            {visibleProfiles.length} MODES
          </span>

          <div className="flex items-center gap-2.5">
            <div className="flex items-center gap-1 font-mono">
              <span className="px-1.5 py-0.5 rounded bg-white/10 text-white/80 font-bold">
                ↑
              </span>
              <span className="px-1.5 py-0.5 rounded bg-white/10 text-white/80 font-bold">
                ↓
              </span>
            </div>
            <div className="flex items-center gap-1">
              <span className="text-white/40">Select</span>
              <span className="px-1.5 py-0.5 rounded bg-white/10 text-white/80 font-mono font-bold">
                ↩
              </span>
            </div>
            <div className="flex items-center gap-1">
              <span className="text-white/40">Close</span>
              <span className="px-1.5 py-0.5 rounded bg-white/10 text-white/70 font-mono">
                esc
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
