// Engine-backed state for the Modes page: the modes the engine owns, per-mode
// capabilities (what is missing), the app rules, and the "pick by app" and
// "where AI runs" settings.
//
// The recording pipeline still reads the local profile, so this store is
// read-mostly. It never publishes unless a value actually changed.

import { useSyncExternalStore } from "react";
import { engineApi } from "./engineApi";
import type {
  AppRule,
  AppRules,
  Capabilities,
  EngineMode,
  ModeCapability,
} from "../types/engine";
import type { ProfileItem } from "../types/profiles";

export interface ModesState {
  engineModes: EngineMode[];
  capabilities: Capabilities | null;
  appRules: AppRules;
  automaticAppRules: boolean;
  isBusy: boolean;
  loaded: boolean;
  errorMessage: string | null;
}

const EMPTY_RULES: AppRules = { enabled: true, rules: [] };

let state: ModesState = {
  engineModes: [],
  capabilities: null,
  appRules: EMPTY_RULES,
  automaticAppRules: true,
  isBusy: false,
  loaded: false,
  errorMessage: null,
};

const listeners = new Set<() => void>();
let hasMigrated = false;

function sameValue(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  try {
    return JSON.stringify(a) === JSON.stringify(b);
  } catch {
    return false;
  }
}

function setState(patch: Partial<ModesState>) {
  let changed = false;
  for (const key of Object.keys(patch) as (keyof ModesState)[]) {
    if (!sameValue(state[key], patch[key])) {
      changed = true;
      break;
    }
  }
  if (!changed) return;
  state = { ...state, ...patch };
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot(): ModesState {
  return state;
}

function newId(): string {
  try {
    if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
      return crypto.randomUUID();
    }
  } catch {
    // Fall through to a timestamp based id.
  }
  return `rule_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
}

function normalizeAppRules(value: any): AppRules {
  if (value && Array.isArray(value.rules)) {
    return { enabled: value.enabled !== false, rules: value.rules as AppRule[] };
  }
  return EMPTY_RULES;
}

async function saveRules(rules: AppRule[]) {
  const previous = state.appRules;
  const next: AppRules = { enabled: state.appRules.enabled, rules };
  setState({ appRules: next });
  try {
    await engineApi.replaceModeAppRules(next);
  } catch {
    setState({ appRules: previous, errorMessage: "Could not save app rules." });
  }
}

export const modesStore = {
  subscribe,
  getSnapshot,

  // MARK: Loading

  async refresh() {
    if (state.isBusy) return;
    setState({ isBusy: true });
    try {
      const [document, capabilities, rules, settings] = await Promise.all([
        engineApi.getModes(),
        engineApi.getCapabilities(),
        engineApi.getModeAppRules(),
        engineApi.getModeSettings(),
      ]);
      setState({
        engineModes: Array.isArray(document?.modes) ? (document.modes as EngineMode[]) : [],
        capabilities: capabilities as Capabilities,
        appRules: normalizeAppRules(rules),
        automaticAppRules:
          typeof settings?.automatic_app_rules === "boolean"
            ? settings.automatic_app_rules
            : state.automaticAppRules,
        loaded: true,
        errorMessage: null,
      });
    } catch {
      setState({ errorMessage: "Could not reach the engine." });
    } finally {
      setState({ isBusy: false });
    }
  },

  /// The engine builds its modes from the client's profiles. This sends them
  /// once so mode ids line up with the profiles. Safe to call again.
  async migrateIfNeeded(profiles: ProfileItem[]) {
    if (hasMigrated || !profiles.length) return;
    hasMigrated = true;
    try {
      const payload = profiles.map((p) => ({
        id: p.id,
        name: p.name,
        modeType: p.modeType,
        dictationFormatStyle: p.formatStyle,
        whisperModel: p.whisperModel,
        customPrompt: p.customPrompt || "",
        tags: p.tags || [],
        isDefault: !!p.isDefault,
      }));
      await engineApi.migrateModes({ profiles: payload });
      await modesStore.refresh();
    } catch {
      // A migration miss only costs the capability line and app-rule mapping.
    }
  },

  // MARK: Settings

  async setAutomaticAppRules(on: boolean) {
    if (on === state.automaticAppRules) return;
    const previous = state.automaticAppRules;
    setState({ automaticAppRules: on });
    try {
      await engineApi.updateModeSettings({ automatic_app_rules: on });
    } catch {
      setState({ automaticAppRules: previous });
    }
  },

  /// "local" or "cloud_when_better". The Models page and onboarding set this.
  async setAILocation(location: string) {
    if (location === state.capabilities?.ai_location) return;
    const previous = state.capabilities?.ai_location;
    if (state.capabilities) {
      setState({ capabilities: { ...state.capabilities, ai_location: location } });
    }
    try {
      await engineApi.updateModeSettings({ ai_location: location });
    } catch {
      if (state.capabilities && previous) {
        setState({ capabilities: { ...state.capabilities, ai_location: previous } });
      }
      setState({ errorMessage: "Could not change where Dicty runs AI." });
    }
  },

  async setActiveMode(modeId: string) {
    try {
      await engineApi.updateModeSettings({ active_mode_id: modeId });
    } catch {
      setState({ errorMessage: "Could not switch mode." });
    }
  },

  /// Create a mode the engine owns. Ids are slugs so they match the client.
  async createMode(payload: Record<string, any>) {
    try {
      await engineApi.createMode(payload);
      await modesStore.refresh();
    } catch {
      setState({ errorMessage: "Could not create this mode." });
    }
  },

  async deleteMode(modeId: string) {
    const previous = state.engineModes;
    setState({ engineModes: state.engineModes.filter((mode) => mode.id !== modeId) });
    try {
      await engineApi.deleteMode(modeId);
    } catch {
      setState({ engineModes: previous, errorMessage: "Could not delete this mode." });
    }
  },

  /// Save one mode's settings. Only the current field names are written
  /// (`style`, `fix_corrections`, `translate_to`, `custom_instructions`).
  async updateModeFields(modeId: string, patch: Partial<EngineMode>) {
    const previous = state.engineModes;
    setState({
      engineModes: state.engineModes.map((mode) =>
        mode.id === modeId ? { ...mode, ...patch } : mode
      ),
    });
    try {
      const updated = await engineApi.updateMode(modeId, patch as Record<string, any>);
      if (updated && updated.id) {
        setState({
          engineModes: state.engineModes.map((mode) =>
            mode.id === modeId ? { ...mode, ...(updated as EngineMode) } : mode
          ),
          errorMessage: null,
        });
      }
    } catch {
      setState({ engineModes: previous, errorMessage: "Could not save this mode." });
    }
  },

  // MARK: App rules

  async addAppRule(bundleId: string, name: string, modeId: string) {
    if (!bundleId || !modeId) return;
    const rules = [...state.appRules.rules];
    const index = rules.findIndex((rule) => rule.match?.value === bundleId);
    if (index >= 0) {
      rules[index] = {
        ...rules[index],
        mode_id: modeId,
        enabled: true,
        display_name: rules[index].display_name || name,
      };
    } else {
      rules.push({
        id: newId(),
        match: { type: "app", value: bundleId },
        display_name: name,
        mode_id: modeId,
        enabled: true,
        source: "user",
      });
    }
    await saveRules(rules);
  },

  async setAppRuleMode(ruleId: string, modeId: string) {
    const rules = state.appRules.rules.map((rule) =>
      rule.id === ruleId ? { ...rule, mode_id: modeId } : rule
    );
    await saveRules(rules);
  },

  async setAppRuleEnabled(ruleId: string, enabled: boolean) {
    const rules = state.appRules.rules.map((rule) =>
      rule.id === ruleId ? { ...rule, enabled } : rule
    );
    await saveRules(rules);
  },

  /// Reset drops the app's assignment so it follows the automatic rules again.
  async resetAppRule(ruleId: string) {
    await saveRules(state.appRules.rules.filter((rule) => rule.id !== ruleId));
  },

  async removeAppRule(bundleId: string, modeId: string) {
    await saveRules(
      state.appRules.rules.filter(
        (rule) => !(rule.match?.value === bundleId && rule.mode_id === modeId)
      )
    );
  },

  // MARK: Capabilities

  /// Start the download a mode is waiting for. Returns the model size in MB.
  async fix(modeId: string): Promise<number | undefined> {
    try {
      const data = await engineApi.fixCapability(modeId);
      await modesStore.refresh();
      return typeof data?.size_mb === "number" ? data.size_mb : undefined;
    } catch {
      setState({ errorMessage: "Could not start the download." });
      return undefined;
    }
  },
};

// MARK: - Hooks & lookups

export function useModesStore(): ModesState {
  return useSyncExternalStore(modesStore.subscribe, modesStore.getSnapshot, modesStore.getSnapshot);
}

export function rulesForMode(state: ModesState, modeId: string | undefined | null): AppRule[] {
  if (!modeId) return [];
  return state.appRules.rules.filter((rule) => rule.mode_id === modeId);
}

export function capabilityForModeId(state: ModesState, modeId: string | undefined | null): ModeCapability | undefined {
  if (!modeId || !state.capabilities) return undefined;
  return state.capabilities.modes.find((entry) => entry.mode_id === modeId);
}

export function isMeetingProfile(profile: ProfileItem): boolean {
  return profile.modeType === "meeting" || profile.modeType === "focused_meeting";
}

export function engineStyleForLegacy(legacy: string): string {
  switch (legacy) {
    case "raw":
    case "raw_dialogue":
      return "exact";
    case "punctuation_fast":
      return "clean";
    case "book":
    case "dialogue_structured":
    case "dialogue_summary":
    case "meeting_summary":
      return "note";
    case "email":
      return "email";
    case "message":
      return "message";
    case "code":
      return "code";
    default:
      return "clean";
  }
}

/// The engine mode that owns a local profile. Matching goes from most to least
/// precise so a migrated profile always resolves to its own mode.
export function engineModeForProfile(state: ModesState, profile: ProfileItem): EngineMode | undefined {
  const id = (profile.id || "").toLowerCase();
  const byId = state.engineModes.find((mode) => mode.id.toLowerCase() === id);
  if (byId) return byId;

  const name = (profile.name || "").toLowerCase();
  const byName = state.engineModes.find((mode) => mode.name.toLowerCase() === name);
  if (byName) return byName;

  const kind = isMeetingProfile(profile) ? "meeting" : "dictation";
  const style = engineStyleForLegacy(profile.formatStyle);
  const byKindStyle = state.engineModes.find((mode) => mode.kind === kind && mode.style === style);
  if (byKindStyle) return byKindStyle;

  return state.engineModes.find((mode) => mode.kind === kind);
}

export function capabilityForProfile(state: ModesState, profile: ProfileItem): ModeCapability | undefined {
  const mode = engineModeForProfile(state, profile);
  return capabilityForModeId(state, mode?.id);
}

export function modeName(state: ModesState, modeId: string): string {
  const mode = state.engineModes.find((entry) => entry.id === modeId);
  if (mode) return mode.name;
  switch (modeId) {
    case "dictation":
      return "General";
    case "meeting":
      return "Meeting";
    case "focused_meeting":
      return "Focused meeting";
    case "librarian":
      return "Librarian";
    case "raw":
      return "General";
    default:
      return modeId
        .split("_")
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join(" ");
  }
}
