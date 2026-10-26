import React, { useState, useEffect, useMemo, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import {
  Plus,
  Search,
  RotateCcw,
  Trash2,
  AlertTriangle,
  FolderOpen,
  Check,
  X,
  Sparkles,
  RefreshCw,
  Sliders,
} from "lucide-react";
import { ToggleSwitch } from "../components/ToggleSwitch";
import { engineApi } from "../services/engineApi";
import type { AppRuleItem, AppRulesSettings } from "../types/engine";
import {
  type ProfileItem,
  getStoredProfiles,
} from "../types/profiles";

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
  "cursor.exe": "Cursor",
  "windowsterminal.exe": "Windows Terminal",
  "notepad.exe": "Notepad",
  "devenv.exe": "Visual Studio",
  "obs64.exe": "OBS Studio",
  "steam.exe": "Steam",
  "steamwebhelper.exe": "Steam",
};

function getAppDisplayName(processName: string, windowTitle?: string): string {
  const norm = processName.toLowerCase().trim();
  const known = KNOWN_APP_NAMES[norm];
  if (known) return known;
  if (windowTitle && windowTitle.trim() && windowTitle.toLowerCase() !== norm) {
    return windowTitle.trim();
  }
  const base = norm.replace(/\.exe$/i, "");
  return base.charAt(0).toUpperCase() + base.slice(1);
}

export const AppRulesSettingsView: React.FC = () => {
  const [settings, setSettings] = useState<AppRulesSettings>({
    enabled: true,
    fallback_mode_id: "prof_1",
    override_scope: "recording",
    prompt_to_learn: true,
  });
  const [rules, setRules] = useState<AppRuleItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [profiles, setProfiles] = useState<ProfileItem[]>(() => getStoredProfiles());

  // Modal states
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [showResetConfirm, setShowResetConfirm] = useState(false);

  // Add App Form state
  const [runningApps, setRunningApps] = useState<RunningAppItem[]>([]);
  const [isScanningApps, setIsScanningApps] = useState(false);
  const [selectedRunningApp, setSelectedRunningApp] = useState<RunningAppItem | null>(null);
  const [manualExeInput, setManualExeInput] = useState("");
  const [manualNameInput, setManualNameInput] = useState("");
  const [selectedModeId, setSelectedModeId] = useState("prof_1");
  const [addModalSearch, setAddModalSearch] = useState("");
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Available dictation & non-meeting profiles for mode picking
  const selectableProfiles = useMemo(() => {
    return profiles.filter(
      (p) => p.modeType !== "meeting" && p.modeType !== "focused_meeting"
    );
  }, [profiles]);

  // Load app rules from engine
  const fetchRules = useCallback(async () => {
    setIsLoading(true);
    try {
      const data = await engineApi.getAppRules();
      if (data?.settings) {
        setSettings(data.settings);
        try {
          await invoke("set_override_scope", { scope: data.settings.override_scope });
        } catch {}
      }
      if (Array.isArray(data?.rules)) {
        setRules(data.rules);
      }
    } catch (err) {
      console.warn("Failed to load app rules:", err);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchRules();
    setProfiles(getStoredProfiles());
  }, [fetchRules]);

  // Fetch running applications from Windows
  const fetchRunningApps = async () => {
    setIsScanningApps(true);
    try {
      const apps = await invoke<RunningAppItem[]>("get_running_applications");
      if (Array.isArray(apps)) {
        setRunningApps(apps);
      }
    } catch (err) {
      console.warn("Failed to get running applications:", err);
    } finally {
      setIsScanningApps(false);
    }
  };

  const handleOpenAddModal = () => {
    setIsAddModalOpen(true);
    setSelectedRunningApp(null);
    setManualExeInput("");
    setManualNameInput("");
    setAddModalSearch("");
    setErrorMsg(null);
    if (selectableProfiles.length > 0) {
      setSelectedModeId(selectableProfiles[0].id);
    }
    fetchRunningApps();
  };

  // Pick executable from disk via Windows OpenFileDialog
  const handleBrowseExecutable = async () => {
    try {
      const selectedPath = await invoke<string | null>("pick_app_executable");
      if (selectedPath) {
        const parts = selectedPath.replace(/\\/g, "/").split("/");
        const fileName = parts[parts.length - 1];
        if (fileName) {
          const exe = fileName.toLowerCase();
          const name = getAppDisplayName(exe);
          setManualExeInput(exe);
          setManualNameInput(name);
          setSelectedRunningApp(null);
        }
      }
    } catch (err) {
      console.warn("Error picking executable:", err);
    }
  };

  // Master switch toggle
  const handleToggleMaster = async (enabled: boolean) => {
    setSettings((prev) => ({ ...prev, enabled }));
    try {
      await engineApi.updateAppRulesSettings({ enabled });
    } catch (err) {
      console.error("Failed to update master switch:", err);
      setSettings((prev) => ({ ...prev, enabled: !enabled }));
    }
  };

  // Override scope toggle
  const handleScopeChange = async (override_scope: "recording" | "until_switched_back") => {
    setSettings((prev) => ({ ...prev, override_scope }));
    try {
      await engineApi.updateAppRulesSettings({ override_scope });
      await invoke("set_override_scope", { scope: override_scope });
    } catch (err) {
      console.error("Failed to update override scope:", err);
    }
  };

  // Prompt to learn toggle
  const handleToggleLearn = async (prompt_to_learn: boolean) => {
    setSettings((prev) => ({ ...prev, prompt_to_learn }));
    try {
      await engineApi.updateAppRulesSettings({ prompt_to_learn });
    } catch (err) {
      console.error("Failed to update prompt_to_learn:", err);
      setSettings((prev) => ({ ...prev, prompt_to_learn: !prompt_to_learn }));
    }
  };

  // Toggle single rule enabled
  const handleToggleRuleEnabled = async (rule: AppRuleItem) => {
    const nextEnabled = !rule.enabled;
    setRules((prev) =>
      prev.map((r) => (r.id === rule.id ? { ...r, enabled: nextEnabled } : r))
    );
    try {
      await engineApi.updateAppRule(rule.id, { enabled: nextEnabled });
    } catch (err) {
      console.error("Failed to toggle rule enabled:", err);
      setRules((prev) =>
        prev.map((r) => (r.id === rule.id ? { ...r, enabled: rule.enabled } : r))
      );
    }
  };

  // Change mode for a rule
  const handleRuleModeChange = async (rule: AppRuleItem, mode_id: string) => {
    setRules((prev) =>
      prev.map((r) => (r.id === rule.id ? { ...r, mode_id } : r))
    );
    try {
      await engineApi.updateAppRule(rule.id, { mode_id });
    } catch (err) {
      console.error("Failed to update rule mode:", err);
      fetchRules();
    }
  };

  // Delete a rule
  const handleDeleteRule = async (rule: AppRuleItem) => {
    try {
      await engineApi.deleteAppRule(rule.id);
      setRules((prev) => prev.filter((r) => r.id !== rule.id));
    } catch (err) {
      console.error("Failed to delete rule:", err);
    }
  };

  // Reset a rule to default mode
  const handleResetRuleToDefault = async (rule: AppRuleItem) => {
    try {
      // Re-fetch default rules to know its default mode, or trigger reset for this rule
      await engineApi.updateAppRule(rule.id, { mode_id: "prof_1" });
      fetchRules();
    } catch (err) {
      console.error("Failed to reset rule:", err);
    }
  };

  // Reset all rules to factory defaults
  const handleResetAll = async () => {
    try {
      const res = await engineApi.resetAppRules();
      if (res?.rules) {
        setRules(res.rules);
      }
      if (res?.settings) {
        setSettings(res.settings);
      }
      setShowResetConfirm(false);
    } catch (err) {
      console.error("Failed to reset app rules:", err);
    }
  };

  // Add rule submit
  const handleAddRuleSubmit = async () => {
    let finalExe = "";
    let finalName = "";

    if (selectedRunningApp) {
      finalExe = selectedRunningApp.process_name.toLowerCase().trim();
      finalName = getAppDisplayName(finalExe, selectedRunningApp.window_title);
    } else {
      finalExe = manualExeInput.toLowerCase().trim();
      if (!finalExe.endsWith(".exe") && !finalExe.includes(".")) {
        finalExe = `${finalExe}.exe`;
      }
      finalName = manualNameInput.trim() || getAppDisplayName(finalExe);
    }

    if (!finalExe) {
      setErrorMsg("Please select a running application or enter an executable name.");
      return;
    }

    try {
      const newRule = await engineApi.createAppRule({
        app_id: finalExe,
        app_name: finalName,
        mode_id: selectedModeId,
        enabled: true,
      });
      if (newRule?.id) {
        setRules((prev) => {
          const filtered = prev.filter((r) => r.app_id !== newRule.app_id);
          return [newRule, ...filtered];
        });
      }
      setIsAddModalOpen(false);
    } catch (err: any) {
      setErrorMsg(err?.message || "Failed to add application rule.");
    }
  };

  // Filtered running apps inside add modal
  const filteredRunningModalApps = useMemo(() => {
    if (!addModalSearch.trim()) return runningApps;
    const q = addModalSearch.toLowerCase();
    return runningApps.filter((a) => {
      const name = getAppDisplayName(a.process_name, a.window_title).toLowerCase();
      return (
        name.includes(q) ||
        a.process_name.toLowerCase().includes(q) ||
        (a.window_title && a.window_title.toLowerCase().includes(q))
      );
    });
  }, [runningApps, addModalSearch]);

  // Filtered rules in main list
  const filteredRules = useMemo(() => {
    if (!searchQuery.trim()) return rules;
    const q = searchQuery.toLowerCase();
    return rules.filter(
      (r) =>
        r.app_name.toLowerCase().includes(q) ||
        r.app_id.toLowerCase().includes(q) ||
        r.mode_id.toLowerCase().includes(q)
    );
  }, [rules, searchQuery]);

  return (
    <div className="space-y-6 animate-in fade-in duration-200">
      {/* Master Feature Card */}
      <div className="dicty-card p-5 sm:p-6 bg-gradient-to-br from-white/[0.04] to-transparent border border-white/10 rounded-2xl shadow-xl">
        <div className="flex items-start justify-between gap-4">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <Sliders className="w-5 h-5 text-emerald-400" />
              <h3 className="font-semibold text-base text-white">
                Automatic Mode Selection
              </h3>
            </div>
            <p className="text-xs sm:text-sm text-white/60 max-w-xl leading-relaxed">
              When you start dictating, Dicty automatically selects the appropriate mode based on the application currently in the foreground.
            </p>
          </div>
          <ToggleSwitch
            checked={settings.enabled}
            onChange={handleToggleMaster}
          />
        </div>

        {/* Sub-settings (only active when enabled) */}
        {settings.enabled && (
          <div className="mt-6 pt-5 border-t border-white/10 space-y-5 animate-in fade-in duration-200">
            {/* Override Scope */}
            <div>
              <label className="text-xs font-semibold text-white/80 uppercase tracking-wider block mb-2">
                When I switch modes by hand
              </label>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 max-w-xl">
                <button
                  type="button"
                  onClick={() => handleScopeChange("recording")}
                  className={`flex flex-col p-3 rounded-xl border text-left transition-all ${
                    settings.override_scope === "recording"
                      ? "bg-emerald-500/15 border-emerald-500/40 text-emerald-200 shadow-sm"
                      : "bg-white/5 border-white/10 text-white/70 hover:bg-white/10"
                  }`}
                >
                  <span className="font-medium text-xs sm:text-sm">
                    For this recording only
                  </span>
                  <span className="text-[11px] text-white/50 mt-0.5">
                    Dicty returns to the app's default mode on the next recording.
                  </span>
                </button>

                <button
                  type="button"
                  onClick={() => handleScopeChange("until_switched_back")}
                  className={`flex flex-col p-3 rounded-xl border text-left transition-all ${
                    settings.override_scope === "until_switched_back"
                      ? "bg-emerald-500/15 border-emerald-500/40 text-emerald-200 shadow-sm"
                      : "bg-white/5 border-white/10 text-white/70 hover:bg-white/10"
                  }`}
                >
                  <span className="font-medium text-xs sm:text-sm">
                    Until I turn Automatic back on
                  </span>
                  <span className="text-[11px] text-white/50 mt-0.5">
                    Keeps the selected mode until you resume automatic switching.
                  </span>
                </button>
              </div>
            </div>

            {/* Smart Learning Suggestions Toggle */}
            <div className="flex items-center justify-between pt-2">
              <div className="space-y-0.5">
                <div className="flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5 text-amber-400" />
                  <span className="text-xs font-medium text-white/90">
                    Smart Rule Suggestions
                  </span>
                </div>
                <p className="text-[11px] text-white/50">
                  Dicty will offer to remember your preferred mode when you repeatedly choose it in an app.
                </p>
              </div>
              <ToggleSwitch
                checked={settings.prompt_to_learn}
                onChange={handleToggleLearn}
              />
            </div>
          </div>
        )}
      </div>

      {/* Rules Section Header & Actions */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pt-2">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-white/40" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search rules by app name or process..."
            className="w-full pl-9 pr-3 py-1.5 bg-white/5 border border-white/10 rounded-xl text-xs text-white placeholder-white/40 focus:outline-none focus:border-white/30 transition-colors"
          />
        </div>

        <div className="flex items-center gap-2 self-start sm:self-auto">
          <button
            type="button"
            onClick={() => setShowResetConfirm(true)}
            className="px-3 py-1.5 rounded-xl bg-white/5 hover:bg-white/10 text-white/60 hover:text-white text-xs font-medium border border-white/10 transition-colors flex items-center gap-1.5"
            title="Reset all rules to defaults"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            <span>Reset to defaults</span>
          </button>

          <button
            type="button"
            onClick={handleOpenAddModal}
            className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6A7565] text-white text-xs font-semibold shadow-md transition-all flex items-center gap-1.5 cursor-pointer"
          >
            <Plus className="w-3.5 h-3.5" />
            <span>Add app rule</span>
          </button>
        </div>
      </div>

      {/* Rules Table / Card List */}
      <div className="space-y-2">
        {isLoading ? (
          <div className="dicty-card p-8 text-center text-white/50 text-xs">
            Loading app rules...
          </div>
        ) : filteredRules.length === 0 ? (
          <div className="dicty-card p-8 text-center space-y-2">
            <p className="text-sm font-medium text-white/70">No app rules found</p>
            <p className="text-xs text-white/40">
              {searchQuery ? "Try a different search query." : "Click '+ Add app rule' to configure an app."}
            </p>
          </div>
        ) : (
          filteredRules.map((rule) => {
            const matchedProfile = profiles.find((p) => p.id === rule.mode_id);
            const isMissingMode = !matchedProfile;

            return (
              <div
                key={rule.id}
                className={`dicty-card p-3 sm:p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 transition-all ${
                  rule.enabled ? "border-white/10" : "opacity-60 border-white/5"
                }`}
              >
                {/* App Info */}
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-9 h-9 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white font-bold text-xs flex-shrink-0">
                    {rule.app_name.charAt(0).toUpperCase()}
                  </div>

                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-sm text-white truncate">
                        {rule.app_name}
                      </span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-white/10 text-white/60 font-mono">
                        {rule.app_id}
                      </span>
                      {rule.source === "default" && (
                        <span className="text-[9px] px-1.5 py-0.2 rounded bg-blue-500/15 text-blue-300 border border-blue-500/30 font-medium">
                          Default
                        </span>
                      )}
                      {rule.source === "learned" && (
                        <span className="text-[9px] px-1.5 py-0.2 rounded bg-amber-500/15 text-amber-300 border border-amber-500/30 font-medium flex items-center gap-0.5">
                          <Sparkles className="w-2.5 h-2.5" /> Learned
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-white/40 truncate">
                      {isMissingMode ? (
                        <span className="text-amber-400 font-medium flex items-center gap-1 mt-0.5">
                          <AlertTriangle className="w-3 h-3" /> Mode missing — pick another
                        </span>
                      ) : (
                        `Uses ${matchedProfile.name}`
                      )}
                    </p>
                  </div>
                </div>

                {/* Controls: Mode Picker, Toggle, Delete */}
                <div className="flex items-center gap-2.5 self-end sm:self-auto flex-shrink-0">
                  {/* Mode Picker dropdown */}
                  <div className="relative">
                    <select
                      value={rule.mode_id}
                      onChange={(e) => handleRuleModeChange(rule, e.target.value)}
                      disabled={!rule.enabled}
                      className={`text-xs rounded-xl px-2.5 py-1.5 bg-white/5 border text-white focus:outline-none transition-colors cursor-pointer ${
                        isMissingMode
                          ? "border-amber-500/60 bg-amber-500/10 text-amber-200"
                          : "border-white/10 hover:border-white/20"
                      }`}
                    >
                      {isMissingMode && (
                        <option value={rule.mode_id} disabled>
                          Mode missing ({rule.mode_id})
                        </option>
                      )}
                      {selectableProfiles.map((p) => (
                        <option key={p.id} value={p.id} className="bg-[#1e222b] text-white">
                          {p.name}
                        </option>
                      ))}
                    </select>
                  </div>

                  {/* Enable / Disable switch */}
                  <ToggleSwitch
                    checked={rule.enabled}
                    onChange={() => handleToggleRuleEnabled(rule)}
                  />

                  {/* Delete / Reset Action */}
                  {rule.source === "default" ? (
                    <button
                      type="button"
                      onClick={() => handleResetRuleToDefault(rule)}
                      title="Reset rule to default"
                      className="p-1.5 text-white/40 hover:text-white hover:bg-white/10 rounded-lg transition-colors"
                    >
                      <RotateCcw className="w-3.5 h-3.5" />
                    </button>
                  ) : (
                    <button
                      type="button"
                      onClick={() => handleDeleteRule(rule)}
                      title="Remove rule"
                      className="p-1.5 text-white/40 hover:text-rose-400 hover:bg-rose-500/10 rounded-lg transition-colors"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* Modal: Add App Rule */}
      {isAddModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#181B20] border border-white/15 rounded-2xl w-full max-w-lg shadow-2xl p-6 space-y-5 animate-in fade-in zoom-in-95 duration-150">
            <div className="flex items-center justify-between pb-3 border-b border-white/10">
              <h3 className="text-base font-semibold text-white flex items-center gap-2">
                <Plus className="w-4 h-4 text-emerald-400" />
                Add Application Rule
              </h3>
              <button
                type="button"
                onClick={() => setIsAddModalOpen(false)}
                className="text-white/50 hover:text-white p-1 rounded-lg hover:bg-white/10"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {errorMsg && (
              <div className="p-3 rounded-xl bg-rose-500/15 border border-rose-500/30 text-rose-200 text-xs">
                {errorMsg}
              </div>
            )}

            {/* Mode selection for the new rule */}
            <div>
              <label className="text-xs font-semibold text-white/80 block mb-1.5">
                Target Dictation Mode
              </label>
              <select
                value={selectedModeId}
                onChange={(e) => setSelectedModeId(e.target.value)}
                className="w-full text-xs rounded-xl px-3 py-2 bg-white/5 border border-white/15 text-white focus:outline-none"
              >
                {selectableProfiles.map((p) => (
                  <option key={p.id} value={p.id} className="bg-[#1e222b] text-white">
                    {p.name} ({p.badgeText})
                  </option>
                ))}
              </select>
            </div>

            {/* Tab: Pick running app or browse */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <label className="text-xs font-semibold text-white/80">
                  Select Running Application
                </label>
                <button
                  type="button"
                  onClick={fetchRunningApps}
                  className="text-[11px] text-emerald-400 hover:text-emerald-300 flex items-center gap-1"
                >
                  <RefreshCw className={`w-3 h-3 ${isScanningApps ? "animate-spin" : ""}`} />
                  Refresh
                </button>
              </div>

              <div className="relative">
                <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-white/40" />
                <input
                  type="text"
                  value={addModalSearch}
                  onChange={(e) => setAddModalSearch(e.target.value)}
                  placeholder="Filter running apps..."
                  className="w-full pl-8 pr-3 py-1.5 bg-white/5 border border-white/10 rounded-xl text-xs text-white placeholder-white/40 focus:outline-none"
                />
              </div>

              <div className="max-h-48 overflow-y-auto space-y-1 pr-1 border border-white/10 rounded-xl p-1 bg-black/20">
                {filteredRunningModalApps.length === 0 ? (
                  <p className="text-center py-4 text-xs text-white/40">
                    No matching running applications found.
                  </p>
                ) : (
                  filteredRunningModalApps.map((app) => {
                    const isSelected =
                      selectedRunningApp?.process_name.toLowerCase() ===
                      app.process_name.toLowerCase();
                    const displayName = getAppDisplayName(app.process_name, app.window_title);

                    return (
                      <div
                        key={`${app.process_name}-${app.pid}`}
                        onClick={() => {
                          setSelectedRunningApp(app);
                          setManualExeInput(app.process_name);
                          setManualNameInput(displayName);
                        }}
                        className={`p-2 rounded-lg text-xs flex items-center justify-between cursor-pointer transition-colors ${
                          isSelected
                            ? "bg-emerald-500/20 text-emerald-200 border border-emerald-500/40"
                            : "hover:bg-white/5 text-white/80"
                        }`}
                      >
                        <div className="truncate">
                          <span className="font-semibold">{displayName}</span>
                          <span className="text-[10px] text-white/50 ml-2 font-mono">
                            {app.process_name}
                          </span>
                        </div>
                        {isSelected && <Check className="w-3.5 h-3.5 text-emerald-400" />}
                      </div>
                    );
                  })
                )}
              </div>
            </div>

            {/* Or Browse for .exe */}
            <div className="pt-2 border-t border-white/10 space-y-2">
              <span className="text-xs font-semibold text-white/70 block">
                Or pick an executable manually
              </span>

              <div className="flex gap-2">
                <input
                  type="text"
                  value={manualExeInput}
                  onChange={(e) => {
                    setManualExeInput(e.target.value);
                    setSelectedRunningApp(null);
                  }}
                  placeholder="e.g. cursor.exe, slack.exe"
                  className="flex-1 px-3 py-1.5 bg-white/5 border border-white/10 rounded-xl text-xs text-white placeholder-white/40 focus:outline-none"
                />
                <button
                  type="button"
                  onClick={handleBrowseExecutable}
                  className="px-3 py-1.5 bg-white/10 hover:bg-white/15 text-white text-xs font-medium rounded-xl border border-white/10 flex items-center gap-1.5"
                  title="Browse for executable file"
                >
                  <FolderOpen className="w-3.5 h-3.5" />
                  <span>Browse…</span>
                </button>
              </div>
            </div>

            {/* Modal Actions */}
            <div className="flex items-center justify-end gap-2 pt-3 border-t border-white/10">
              <button
                type="button"
                onClick={() => setIsAddModalOpen(false)}
                className="px-4 py-2 rounded-xl text-xs text-white/60 hover:text-white hover:bg-white/10 transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleAddRuleSubmit}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-[#5D6658] hover:bg-[#6A7565] text-white shadow-md transition-colors"
              >
                Create rule
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal: Confirm Reset All */}
      {showResetConfirm && (
        <div className="fixed inset-0 z-50 bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#181B20] border border-white/15 rounded-2xl w-full max-w-md shadow-2xl p-6 space-y-4 animate-in fade-in zoom-in-95 duration-150">
            <div className="flex items-center gap-3 text-amber-400">
              <AlertTriangle className="w-6 h-6 flex-shrink-0" />
              <h3 className="text-base font-semibold text-white">
                Reset all rules to defaults?
              </h3>
            </div>

            <p className="text-xs text-white/70 leading-relaxed">
              This will restore Dicty's factory rules and remove any custom application rules you've added. This action cannot be undone.
            </p>

            <div className="flex items-center justify-end gap-2 pt-3 border-t border-white/10">
              <button
                type="button"
                onClick={() => setShowResetConfirm(false)}
                className="px-4 py-2 rounded-xl text-xs text-white/60 hover:text-white hover:bg-white/10 transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleResetAll}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-rose-600 hover:bg-rose-500 text-white shadow-md transition-colors"
              >
                Reset all rules
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
