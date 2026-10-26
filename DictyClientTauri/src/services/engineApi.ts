// Dicty Engine REST client. All transport/auth details live in engineClient.ts.

import { engineFetch } from "./engineClient";

export const engineApi = {
  // --- Recording Control ---
  async getStatus() {
    const res = await engineFetch(`/recording/status`);
    return res.json();
  },

  async startRecording(params?: { mode?: string; device_id?: number; language?: string }) {
    const query = new URLSearchParams();
    if (params?.mode) query.set("mode", params.mode);
    if (params?.device_id && params.device_id !== -1) query.set("device_id", String(params.device_id));
    if (params?.language) query.set("language", params.language);

    const url = `/recording/start${query.toString() ? `?${query.toString()}` : ""}`;
    const res = await engineFetch(url, { method: "POST" });
    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData.detail || `Recording failed (HTTP ${res.status})`);
    }
    return res.json();
  },

  async stopRecording() {
    const res = await engineFetch(`/recording/stop`, { method: "POST" });
    return res.json();
  },

  async pauseRecording() {
    const res = await engineFetch(`/recording/pause`, { method: "POST" });
    return res.json();
  },

  async resumeRecording() {
    const res = await engineFetch(`/recording/resume`, { method: "POST" });
    return res.json();
  },

  async cancelRecording() {
    const res = await engineFetch(`/recording/cancel`, { method: "POST" });
    return res.json();
  },

  // --- Audio Devices ---
  async getDevices() {
    const res = await engineFetch(`/devices`);
    return res.json();
  },

  // --- Models Management ---
  async getModels() {
    const res = await engineFetch(`/models`);
    return res.json();
  },

  async getActiveModel() {
    const res = await engineFetch(`/models/active`);
    return res.json();
  },

  async setActiveModel(modelId: string) {
    const res = await engineFetch(`/models/active/${encodeURIComponent(modelId)}`, {
      method: "POST",
    });
    return res.json();
  },

  async downloadModel(modelId: string, quality: string = "q5_0") {
    const res = await engineFetch(`/models/download/${encodeURIComponent(modelId)}?quality=${encodeURIComponent(quality)}`, {
      method: "POST",
    });
    return res.json();
  },

  async openModelsFolder() {
    const res = await engineFetch(`/models/open`, { method: "POST" });
    return res.json();
  },

  async prewarmModel(modelId?: string) {
    const url = modelId
      ? `/models/prewarm?model_id=${encodeURIComponent(modelId)}`
      : `/models/prewarm`;
    const res = await engineFetch(url, { method: "POST" });
    return res.json();
  },

  async getDownloadProgress() {
    const res = await engineFetch(`/models/download/progress`);
    return res.json();
  },

  async cancelDownload() {
    const res = await engineFetch(`/models/download/cancel`, { method: "POST" });
    return res.json();
  },

  async deleteModel(modelId: string) {
    const res = await engineFetch(`/models/${encodeURIComponent(modelId)}`, {
      method: "DELETE",
    });
    return res.json();
  },

  async getOpenRouterModels(force: boolean = false) {
    const res = await engineFetch(`/models/openrouter?force=${force}`);
    return res.json();
  },


  // --- History Management ---
  async getHistory() {
    const res = await engineFetch(`/history`);
    return res.json();
  },

  async updateHistoryRecord(recordId: string, updates: { title?: string | null; tags?: string[]; notes?: string | null }) {
    const res = await engineFetch(`/history/${encodeURIComponent(recordId)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(updates),
    });
    return res.json();
  },

  async summarizeHistory(
    recordId: string,
    options?: {
      llm_provider?: string;
      llm_base_url?: string;
      llm_model?: string;
      llm_api_key?: string;
      openai_api_key?: string;
      notes?: string | null;
    }
  ) {
    const formData = new FormData();
    if (options?.llm_provider) formData.append("llm_provider", options.llm_provider);
    if (options?.llm_base_url) formData.append("llm_base_url", options.llm_base_url);
    if (options?.llm_model) formData.append("llm_model", options.llm_model);
    if (options?.llm_api_key) formData.append("llm_api_key", options.llm_api_key);
    if (options?.openai_api_key) formData.append("openai_api_key", options.openai_api_key);
    if (options?.notes !== undefined && options?.notes !== null) {
      formData.append("notes", options.notes);
    }

    const res = await engineFetch(`/history/summarize/${encodeURIComponent(recordId)}`, {
      method: "POST",
      body: formData,
    });
    return res.json();
  },

  async deleteHistoryItem(recordId: string) {
    const res = await engineFetch(`/history/${encodeURIComponent(recordId)}`, {
      method: "DELETE",
    });
    return res.json();
  },

  async getUpdatesHistory() {
    const res = await engineFetch(`/updates/history`);
    return res.json();
  },

  async deleteUpdateHistoryItem(historyId: string) {
    const res = await engineFetch(`/updates/history/${encodeURIComponent(historyId)}`, {
      method: "DELETE",
    });
    return res.json();
  },

  async clearUpdatesHistory() {
    const res = await engineFetch(`/updates/history`, {
      method: "DELETE",
    });
    return res.json();
  },

  async getStats(period: string = "all") {
    const res = await engineFetch(`/stats?period=${encodeURIComponent(period)}`);
    return res.json();
  },

  async reuploadUpdate(historyId: string, data?: any) {
    const res = await engineFetch(`/updates/history/${encodeURIComponent(historyId)}/reupload`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data || {}),
    });
    return res.json();
  },

  async reprocessHistoryItem(
    recordId: string,
    options?: {
      mode?: string;
      format_style?: string;
      custom_prompt?: string;
      retranscribe_audio?: boolean;
      language?: string;
      llm_provider?: string;
      llm_base_url?: string;
      llm_model?: string;
      llm_api_key?: string;
      openai_api_key?: string;
    }
  ) {
    const res = await engineFetch(`/history/reprocess/${encodeURIComponent(recordId)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(options || {}),
    });
    return res.json();
  },

  async clearHistory() {
    const res = await engineFetch(`/history/clear`, { method: "DELETE" });
    return res.json();
  },

  async triggerHistoryCleanup(scrubPastAudio: boolean = false) {
    const res = await engineFetch(`/history/cleanup?scrub_past_audio=${scrubPastAudio}`, {
      method: "POST",
    });
    return res.json();
  },

  async updateRetentionSettings(retentionPeriod: string, scrubAudioImmediately: boolean) {
    const res = await engineFetch(`/history/settings/retention`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        retention_period: retentionPeriod,
        scrub_audio_immediately: scrubAudioImmediately,
      }),
    });
    return res.json();
  },

  async exportDiagnostics(): Promise<{ blob: Blob; filename: string }> {
    const res = await engineFetch(`/diagnostics/export`);
    if (!res.ok) {
      throw new Error(`Diagnostics export failed with HTTP ${res.status}`);
    }
    const blob = await res.blob();
    const disposition = res.headers.get("Content-Disposition");
    let filename = `Dicty_Diagnostics_${new Date().toISOString().replace(/[:.]/g, "-")}.zip`;
    if (disposition) {
      const match = disposition.match(/filename=["']?([^"';]+)["']?/);
      if (match && match[1]) {
        filename = match[1];
      }
    }
    return { blob, filename };
  },

  // --- System Prompts ---
  async getPrompts() {
    const res = await engineFetch(`/prompts`);
    return res.json();
  },

  async updatePrompt(key: string, value: string) {
    const res = await engineFetch(`/prompts`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key, value }),
    });
    return res.json();
  },

  async resetPrompt(key: string) {
    const res = await engineFetch(`/prompts/${encodeURIComponent(key)}`, {
      method: "DELETE",
    });
    return res.json();
  },

  // --- Librarian Staging Queue ---
  async getQueue() {
    const res = await engineFetch(`/librarian/queue`);
    return res.json();
  },

  async addQueueItem(text: string, source: string = "manual") {
    const res = await engineFetch(`/librarian/queue`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text, source }),
    });
    return res.json();
  },

  async updateQueueItem(itemId: string, text: string) {
    const res = await engineFetch(`/librarian/queue/${encodeURIComponent(itemId)}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
    return res.json();
  },

  async deleteQueueItem(itemId: string) {
    const res = await engineFetch(`/librarian/queue/${encodeURIComponent(itemId)}`, {
      method: "DELETE",
    });
    return res.json();
  },

  async clearQueue() {
    const res = await engineFetch(`/librarian/queue`, {
      method: "DELETE",
    });
    return res.json();
  },

  async synthesizeQueue(payload: Record<string, any>) {
    const res = await engineFetch(`/librarian/synthesize`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    return res.json();
  },

  async reconcileArchitecture(payload: Record<string, any>) {
    const res = await engineFetch(`/reconcile/architecture`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    return res.json();
  },

  // --- Vocabulary ---
  async getVocabulary() {
    const res = await engineFetch(`/vocabulary?t=${Date.now()}`);
    return res.json();
  },

  async addVocabulary(word: string, replacement: string) {
    const res = await engineFetch(`/vocabulary`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ word, replacement }),
    });
    return res.json();
  },

  async deleteVocabulary(itemId: string) {
    const res = await engineFetch(`/vocabulary/${encodeURIComponent(itemId)}`, {
      method: "DELETE",
    });
    return res.json();
  },

  async loadDefaultVocabulary(replace: boolean = false) {
    const res = await engineFetch(`/vocabulary/defaults`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ replace }),
    });
    return res.json();
  },

  // --- Modes store (engine-owned) ---
  async getModes() {
    const res = await engineFetch(`/modes?t=${Date.now()}`);
    if (!res.ok) throw new Error(`Could not load modes (HTTP ${res.status})`);
    return await res.json();
  },

  async getMode(modeId: string) {
    const res = await engineFetch(`/modes/${encodeURIComponent(modeId)}`);
    if (!res.ok) throw new Error(`Could not load mode (HTTP ${res.status})`);
    return await res.json();
  },

  async updateMode(modeId: string, patch: Record<string, any>) {
    const res = await engineFetch(`/modes/${encodeURIComponent(modeId)}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    if (!res.ok) throw new Error(`Could not save mode (HTTP ${res.status})`);
    return await res.json();
  },

  async createMode(payload: Record<string, any>) {
    const res = await engineFetch(`/modes`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.detail || `Could not create mode (HTTP ${res.status})`);
    return data;
  },

  async deleteMode(modeId: string) {
    const res = await engineFetch(`/modes/${encodeURIComponent(modeId)}`, {
      method: "DELETE",
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.detail || `Could not delete mode (HTTP ${res.status})`);
    return data;
  },

  async getCapabilities() {
    const res = await engineFetch(`/capabilities?t=${Date.now()}`);
    if (!res.ok) throw new Error(`Could not load capabilities (HTTP ${res.status})`);
    return await res.json();
  },

  async getModeSettings() {
    const res = await engineFetch(`/modes/settings?t=${Date.now()}`);
    if (!res.ok) throw new Error(`Could not load mode settings (HTTP ${res.status})`);
    return await res.json();
  },

  async updateModeSettings(patch: { ai_location?: string; automatic_app_rules?: boolean; active_mode_id?: string }) {
    const res = await engineFetch(`/modes/settings`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    if (!res.ok) throw new Error(`Could not save mode settings (HTTP ${res.status})`);
    return await res.json();
  },

  async getModeAppRules() {
    const res = await engineFetch(`/modes/app_rules?t=${Date.now()}`);
    if (!res.ok) throw new Error(`Could not load app rules (HTTP ${res.status})`);
    return await res.json();
  },

  async replaceModeAppRules(appRules: { enabled: boolean; rules: any[] }) {
    const res = await engineFetch(`/modes/app_rules`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ rules: appRules }),
    });
    if (!res.ok) throw new Error(`Could not save app rules (HTTP ${res.status})`);
    return await res.json();
  },

  async fixCapability(modeId: string) {
    const res = await engineFetch(`/capabilities/fix`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode_id: modeId }),
    });
    if (!res.ok) throw new Error(`Could not start the download (HTTP ${res.status})`);
    return await res.json();
  },

  async migrateModes(config: any) {
    const res = await engineFetch(`/modes/migrate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(config),
    });
    if (!res.ok) throw new Error(`Could not migrate modes (HTTP ${res.status})`);
    return await res.json();
  },

  // --- Snippets ---
  async getSnippets() {
    const res = await engineFetch(`/snippets?t=${Date.now()}`);
    if (!res.ok) throw new Error(`Could not load snippets (HTTP ${res.status})`);
    return await res.json();
  },

  async addSnippet(trigger: string, content: string, aliases: string[] = [], expandAnywhere: boolean = false) {
    const res = await engineFetch(`/snippets`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ trigger, content, aliases, expand_anywhere: expandAnywhere }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.detail || `Could not save snippet (HTTP ${res.status})`);
    return data;
  },

  async updateSnippet(id: string, trigger: string, content: string, aliases: string[] = [], expandAnywhere: boolean = false) {
    const res = await engineFetch(`/snippets/${encodeURIComponent(id)}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ trigger, content, aliases, expand_anywhere: expandAnywhere }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.detail || `Could not save snippet (HTTP ${res.status})`);
    return data;
  },

  async deleteSnippet(id: string) {
    const res = await engineFetch(`/snippets/${encodeURIComponent(id)}`, {
      method: "DELETE",
    });
    return res.json();
  },

  // --- Auth & Account ---
  async getAuthStatus() {
    try {
      const res = await engineFetch(`/auth/status?t=${Date.now()}`);
      if (res.ok) return await res.json();
    } catch (e) {
      console.warn("Local engine /auth/status failed:", e);
    }
    return null;
  },

  async login(email: string, password: string) {
    const res = await engineFetch(`/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    return await res.json();
  },

  async register(email: string, password: string) {
    const res = await engineFetch(`/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    return await res.json();
  },

  async mockGoogleLogin(email: string) {
    const res = await engineFetch(`/auth/google/mock`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
    return await res.json();
  },

  async logout() {
    try {
      await engineFetch(`/auth/logout`, { method: "POST" });
    } catch (e) {
      console.warn("Local engine /auth/logout failed:", e);
    }
  },

  async submitToken(token: string) {
    try {
      const res = await engineFetch(`/auth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token }),
      });
      if (res.ok) return await res.json();
    } catch (e) {
      console.warn("Local engine /auth/token failed:", e);
    }
    return null;
  },

  async getCloudMe(token: string) {
    const cloudUrl = "https://dicty-backend.dicty-backend.workers.dev/auth/me";
    const res = await fetch(cloudUrl, {
      headers: { Authorization: `Bearer ${token}` },
    });
    return await res.json();
  },

  // --- Cloud Synchronization ---
  async uploadSettingsToCloud(token: string, payload: {
    customPrompts?: any[];
    librarianConfig?: any;
    vocabulary?: any[];
  }) {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 8000);
      const res = await fetch("https://dicty-backend.dicty-backend.workers.dev/sync/settings", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      return res.ok;
    } catch {
      return false;
    }
  },

  async downloadSettingsFromCloud(token: string) {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 8000);
      const res = await fetch("https://dicty-backend.dicty-backend.workers.dev/sync/settings", {
        headers: {
          Authorization: `Bearer ${token}`,
        },
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      if (res.ok) return await res.json();
    } catch {
      // Offline / network failure - gracefully return null
    }
    return null;
  },

  // --- App Updates & GitHub Version Synchronization ---
  async checkForUpdates(currentVersion: string = "1.0.0", repo?: string, token?: string) {
    const query = new URLSearchParams({ current_version: currentVersion });
    if (repo) query.set("repo", repo);
    if (token) query.set("token", token);
    const res = await engineFetch(`/update/check?${query.toString()}`);
    return await res.json();
  },

  async getUpdateProgress() {
    const res = await engineFetch(`/update/progress`);
    return await res.json();
  },

  async applyUpdate(downloadUrl?: string, assetName?: string) {
    const res = await engineFetch(`/update/apply`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ download_url: downloadUrl, asset_name: assetName }),
    });
    return await res.json();
  },

  // --- Per-App Mode Rules API ---
  async getAppRules() {
    const res = await engineFetch(`/app-rules`);
    return await res.json();
  },

  async updateAppRulesSettings(settings: {
    enabled?: boolean;
    fallback_mode_id?: string;
    override_scope?: 'recording' | 'until_switched_back';
    prompt_to_learn?: boolean;
  }) {
    const res = await engineFetch(`/app-rules/settings`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(settings),
    });
    return await res.json();
  },

  async createAppRule(rule: {
    app_id: string;
    app_name: string;
    mode_id: string;
    enabled?: boolean;
    icon?: string;
  }) {
    const res = await engineFetch(`/app-rules`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(rule),
    });
    return await res.json();
  },

  async updateAppRule(
    ruleId: string,
    rule: {
      app_name?: string;
      mode_id?: string;
      enabled?: boolean;
      icon?: string;
    }
  ) {
    const res = await engineFetch(`/app-rules/${encodeURIComponent(ruleId)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(rule),
    });
    return await res.json();
  },

  async deleteAppRule(ruleId: string) {
    const res = await engineFetch(`/app-rules/${encodeURIComponent(ruleId)}`, {
      method: "DELETE",
    });
    return await res.json();
  },

  async resetAppRules() {
    const res = await engineFetch(`/app-rules/reset`, {
      method: "POST",
    });
    return await res.json();
  },

  async resolveAppRule(params: {
    app_id?: string;
    target_app_name?: string;
    mode_override?: string;
    manual_override_active?: boolean;
  }) {
    const query = new URLSearchParams();
    if (params.app_id) query.set("app_id", params.app_id);
    if (params.target_app_name) query.set("target_app_name", params.target_app_name);
    if (params.mode_override) query.set("mode_override", params.mode_override);
    if (typeof params.manual_override_active === "boolean") {
      query.set("manual_override_active", String(params.manual_override_active));
    }
    const res = await engineFetch(`/app-rules/resolve?${query.toString()}`);
    return await res.json();
  },

  async acceptAppRuleSuggestion(appId: string, modeId: string, appName?: string) {
    const res = await engineFetch(`/app-rules/accept-suggestion`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ app_id: appId, mode_id: modeId, app_name: appName }),
    });
    return await res.json();
  },

  async suppressAppRuleSuggestion(appId: string) {
    const res = await engineFetch(`/app-rules/suppress-suggestion`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ app_id: appId }),
    });
    return await res.json();
  },

  async getAppRulesStats() {
    const res = await engineFetch(`/stats/app-rules`);
    return await res.json();
  },
};


