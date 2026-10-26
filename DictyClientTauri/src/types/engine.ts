// Dicty Engine API type definitions (synchronized with the local FastAPI engine).

export type DictyMode = 'dictation' | 'librarian' | 'meeting' | 'focused_meeting' | 'formatting';

export type DictationFormatStyle =
  | 'raw'
  | 'book'
  | 'punctuation_fast'
  | 'email'
  | 'message'
  | 'note'
  | 'custom';

export interface AudioDevice {
  id: number;
  name: string;
  max_input_channels: number;
  default_samplerate: number;
}

export interface ModelInfo {
  id: string;
  name: string;
  size_mb?: number;
  downloaded: boolean;
  is_local: boolean;
  description?: string;
}

export interface RecordingStatus {
  is_recording: boolean;
  is_paused: boolean;
  mode: DictyMode;
  active_model: string;
  active_device_id: number;
}

export interface PartialTranscriptionEvent {
  status: 'partial' | 'final';
  text: string;
}

export interface HistoryItem {
  id: string;
  timestamp: number;
  text: string;
  audio_path?: string;
  duration_seconds?: number;
  mode: DictyMode;
  app_id?: string;
  target_app_name?: string;
  resolved_mode?: string;
  resolution_source?: string;
}

export interface VocabularyItem {
  id: string;
  word: string;
  replacement: string;
  created_at?: string;
}

export interface UserAccount {
  id?: number | string;
  email: string;
  is_pro: boolean;
  compute_balance: number;
  subscription_tier: string;
  plan_expires_at?: string;
  offline_mode?: boolean;
}

// --- App Rules Interfaces ---
export interface AppRuleItem {
  id: string;
  app_id: string;
  app_name: string;
  mode_id: string;
  source: 'default' | 'user' | 'learned';
  enabled: boolean;
  icon?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface AppRulesSettings {
  enabled: boolean;
  fallback_mode_id: string;
  override_scope: 'recording' | 'until_switched_back';
  prompt_to_learn: boolean;
}

export interface AppRulesState {
  settings: AppRulesSettings;
  rules: AppRuleItem[];
  suppressed_app_ids: string[];
}

export interface AppRuleMatch {
  matched: boolean;
  rule: AppRuleItem | null;
  effective_mode_id: string;
  reason: string;
}

export interface AppRuleSuggestion {
  app_id: string;
  app_name: string;
  mode_id: string;
  count: number;
  threshold: number;
}


// --- Modes store (engine /modes*) ---
//
// These mirror the payloads of the local engine's mode endpoints:
// `GET /modes`, `GET /modes/settings`, `GET /modes/app_rules`, `GET /capabilities`.
// Only the current field names are used (`style`, `fix_corrections`,
// `translate_to`, `custom_instructions`); the deprecated aliases are ignored.

export type EngineModeKind = "dictation" | "meeting";

export interface EngineMode {
  id: string;
  name: string;
  kind: EngineModeKind | string;
  icon?: string | null;
  style?: string | null;
  fix_corrections?: boolean | null;
  translate_to?: string | null;
  custom_instructions?: string | null;
  tags?: string[] | null;
  description?: string | null;
  is_default?: boolean;
  speech_model?: string | null;
  language?: string | null;
  keep_model_in_memory?: boolean;
  meeting?: Record<string, any>;
}

export interface EngineModesDocument {
  modes: EngineMode[];
}

export interface ModeCapability {
  mode_id: string;
  missing?: string;
  fix?: string;
  size_mb?: number;
  correction?: string;
}

export interface Capabilities {
  ai_location: string;
  correction_location: string;
  local_text_models: string[];
  cloud_access: boolean;
  modes: ModeCapability[];
}

export interface ModeAppRuleMatch {
  type: string;
  value: string;
  aliases?: string[];
}

export interface AppRule {
  id: string;
  match: ModeAppRuleMatch;
  display_name?: string;
  mode_id: string;
  enabled?: boolean;
  source?: string;
}

export interface AppRules {
  enabled: boolean;
  rules: AppRule[];
}

export interface ModeSettingsPayload {
  ai_location?: string;
  automatic_app_rules?: boolean;
  active_mode_id?: string;
}

export interface DictySnippet {
  id: string;
  trigger: string;
  content: string;
  aliases?: string[];
  expand_anywhere?: boolean;
}
