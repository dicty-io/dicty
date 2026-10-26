import React, { useState } from "react";
import {
  RefreshCw,
  Download,
  Upload,
  Cloud,
  CheckCircle2,
  AlertCircle,
  FileJson,
  ShieldCheck,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { engineApi } from "../services/engineApi";

export const SyncBackupView: React.FC = () => {
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [isCloudSyncing, setIsCloudSyncing] = useState(false);
  const [statusMessage, setStatusMessage] = useState<{
    type: "success" | "error";
    text: string;
  } | null>(null);

  const handleCloudSync = async () => {
    setIsCloudSyncing(true);
    setStatusMessage(null);
    try {
      const token = localStorage.getItem("dicty_jwt_token") || localStorage.getItem("auth_token");
      if (!token) {
        setStatusMessage({
          type: "error",
          text: "Please sign in to your Dicty account in the Account tab to enable cloud sync.",
        });
        return;
      }

      const vocabRes = await engineApi.getVocabulary().catch(() => null);
      const promptsRes = await engineApi.getPrompts().catch(() => null);
      const rawPrompts = Array.isArray(promptsRes) ? promptsRes : (promptsRes?.prompts || []);

      // 1. Upload local settings & vocabulary to cloud
      await engineApi.uploadSettingsToCloud(token, {
        customPrompts: rawPrompts,
        vocabulary: vocabRes?.vocabulary || [],
      });

      // 2. Download and merge cloud data
      const cloudRes = await engineApi.downloadSettingsFromCloud(token);
      if (cloudRes) {
        if (cloudRes.vocabulary && Array.isArray(cloudRes.vocabulary)) {
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

      setStatusMessage({
        type: "success",
        text: "Cloud sync complete! Custom prompts and vocabulary are fully synchronized across devices.",
      });
    } catch (err: any) {
      setStatusMessage({
        type: "error",
        text: `Cloud sync failed (offline or server unreachable): ${err.message || "Unknown error"}`,
      });
    } finally {
      setIsCloudSyncing(false);
    }
  };

  const handleExport = async () => {
    setIsExporting(true);
    setStatusMessage(null);
    try {
      // Gather local prompts, vocabulary, and preferences
      const vocabRes = await engineApi.getVocabulary();
      const promptsRes = await engineApi.getPrompts();
      const rawPrompts = Array.isArray(promptsRes) ? promptsRes : (promptsRes?.prompts || []);

      const activeProfileId = localStorage.getItem("dicty_active_profile") || "";
      const favoriteModels = localStorage.getItem("favorite_models") || "";
      const dictationLLMModel = localStorage.getItem("dictation_llm_model") || "";

      // Harmonized cross-platform schema (compatible with macOS and Windows)
      const backupData = {
        app: "Dicty",
        version: "1.0.0",
        exported_at: new Date().toISOString(),
        vocabulary: vocabRes?.vocabulary || [],
        prompts: rawPrompts.map((p: any) => ({
          key: p.key,
          active_value: p.active_value || p.value || "",
          value: p.active_value || p.value || "",
          default_value: p.default_value || "",
          description: p.description || "",
          is_custom: p.is_custom ?? true,
        })),
        // Modes are owned by the engine now. The backup only carries the active
        // mode id and model favorites so a restore puts you back where you were.
        dictationLLMModel: dictationLLMModel,
        dictation_llm_model: dictationLLMModel,
        favoriteModelsString: favoriteModels,
        favorite_models: favoriteModels,
        localStorageBackup: {
          favorite_models: favoriteModels,
          dicty_active_profile: activeProfileId || null,
        },
      };

      const blob = new Blob([JSON.stringify(backupData, null, 2)], {
        type: "application/json",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `dicty-backup-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);

      setStatusMessage({
        type: "success",
        text: "Configuration successfully exported to cross-platform JSON file.",
      });
    } catch (err: any) {
      setStatusMessage({
        type: "error",
        text: `Export failed: ${err.message || "Unknown error"}`,
      });
    } finally {
      setIsExporting(false);
    }
  };

  const handleImport = () => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".json";
    input.onchange = async (e: any) => {
      const file = e.target.files?.[0];
      if (!file) return;

      setIsImporting(true);
      setStatusMessage(null);

      const reader = new FileReader();
      reader.onload = async (event) => {
        try {
          const content = event.target?.result as string;
          const parsed = JSON.parse(content);

          // 1. Vocabulary
          if (parsed.vocabulary && Array.isArray(parsed.vocabulary)) {
            for (const v of parsed.vocabulary) {
              if (v.word && v.replacement) {
                await engineApi.addVocabulary(v.word, v.replacement);
              }
            }
          }

          // 2. Prompts (supports macOS active_value and Windows value)
          if (parsed.prompts && Array.isArray(parsed.prompts)) {
            for (const p of parsed.prompts) {
              const key = p.key;
              const val = p.active_value || p.value || p.system_prompt;
              if (key && val) {
                await engineApi.updatePrompt(key, val);
              }
            }
          }

          // 3. Preferences (supports top-level & localStorageBackup keys)
          const activeProfileId = parsed.dicty_active_profile || parsed.localStorageBackup?.dicty_active_profile;
          if (activeProfileId) {
            localStorage.setItem("dicty_active_profile", activeProfileId);
          }
          const favoriteModels = parsed.favoriteModelsString || parsed.favorite_models || parsed.localStorageBackup?.favorite_models;
          if (favoriteModels) {
            localStorage.setItem("favorite_models", favoriteModels);
          }

          setStatusMessage({
            type: "success",
            text: "Configuration restored successfully! Vocabulary and prompts synchronized.",
          });
        } catch (err: any) {
          setStatusMessage({
            type: "error",
            text: `Import failed: ${err.message || "Invalid JSON format."}`,
          });
        } finally {
          setIsImporting(false);
        }
      };
      reader.readAsText(file);
    };
    input.click();
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-6 select-none font-sans">
      <SettingsPageHeader
        title="Sync & Backup"
        description="Backup your custom vocabulary, tailored prompts, and sync configurations across devices."
        helpTopic="sync_backup"
      />

      {statusMessage && (
        <div
          className={`p-4 rounded-2xl flex items-center gap-2.5 text-xs font-medium ${
            statusMessage.type === "success"
              ? "bg-[#87B996]/15 border border-[#87B996]/30 text-[#87B996]"
              : "bg-red-500/10 border border-red-500/20 text-red-400"
          }`}
        >
          {statusMessage.type === "success" ? (
            <CheckCircle2 className="w-4 h-4 flex-shrink-0" />
          ) : (
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
          )}
          <span>{statusMessage.text}</span>
        </div>
      )}

      {/* Cloud Sync Status Card */}
      <div className="p-5 rounded-2xl bg-white/[0.04] border border-white/10 shadow-lg space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-[#5D6658]/20 border border-[#87B996]/30 flex items-center justify-center text-[#87B996]">
              <Cloud className="w-4 h-4" />
            </div>
            <div>
              <span className="text-xs font-bold text-white block">
                Dicty Cloud Synchronization
              </span>
              <span className="text-[11px] text-white/50 block">
                Encrypted sync for custom prompts & vocabulary across all your devices
              </span>
            </div>
          </div>

          <button
            onClick={handleCloudSync}
            disabled={isCloudSyncing}
            className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold shadow transition-all flex items-center gap-2 disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isCloudSyncing ? "animate-spin" : ""}`} />
            <span>{isCloudSyncing ? "Syncing..." : "Sync with Cloud Now"}</span>
          </button>
        </div>
      </div>

      {/* Export / Import Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Export Card */}
        <div className="p-5 rounded-2xl bg-white/[0.04] border border-white/10 shadow-lg space-y-4 flex flex-col justify-between">
          <div className="space-y-2">
            <div className="w-8 h-8 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/80">
              <Download className="w-4 h-4 text-[#87B996]" />
            </div>
            <h3 className="text-xs font-bold text-white">
              Export Configuration
            </h3>
            <p className="text-[11px] text-white/50 leading-relaxed">
              Export your custom vocabulary rules, prompts, hotkey assignments, and
              formatting presets into an encrypted portable JSON file.
            </p>
          </div>

          <button
            onClick={handleExport}
            disabled={isExporting}
            className="w-full py-2 px-4 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold shadow transition-all flex items-center justify-center gap-2 disabled:opacity-50"
          >
            {isExporting ? (
              <RefreshCw className="w-3.5 h-3.5 animate-spin" />
            ) : (
              <FileJson className="w-3.5 h-3.5" />
            )}
            <span>Export to File</span>
          </button>
        </div>

        {/* Import Card */}
        <div className="p-5 rounded-2xl bg-white/[0.04] border border-white/10 shadow-lg space-y-4 flex flex-col justify-between">
          <div className="space-y-2">
            <div className="w-8 h-8 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/80">
              <Upload className="w-4 h-4 text-[#87B996]" />
            </div>
            <h3 className="text-xs font-bold text-white">
              Restore Configuration
            </h3>
            <p className="text-[11px] text-white/50 leading-relaxed">
              Restore your vocabulary and preferences from an existing Dicty backup
              file created on macOS or Windows.
            </p>
          </div>

          <button
            onClick={handleImport}
            disabled={isImporting}
            className="w-full py-2 px-4 rounded-xl bg-white/[0.06] hover:bg-white/10 border border-white/10 text-white text-xs font-semibold shadow transition-all flex items-center justify-center gap-2 disabled:opacity-50"
          >
            {isImporting ? (
              <RefreshCw className="w-3.5 h-3.5 animate-spin" />
            ) : (
              <Upload className="w-3.5 h-3.5 text-[#87B996]" />
            )}
            <span>Import from File</span>
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 text-[11px] text-white/40 pt-2">
        <ShieldCheck className="w-3.5 h-3.5 text-[#87B996]" />
        <span>Your API keys and personal tokens are never included in unencrypted exports.</span>
      </div>
    </div>
  );
};
