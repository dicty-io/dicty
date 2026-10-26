import React, { useState, useEffect } from "react";
import { RotateCcw, Check, RefreshCw } from "lucide-react";
import { engineApi } from "../services/engineApi";

export interface DictyPromptInfo {
  key: string;
  description: string;
  default_value: string;
  active_value: string;
  is_custom: boolean;
}

// Fallback list of all 12 system prompts matching prompts.py & macOS client
const FALLBACK_PROMPTS: DictyPromptInfo[] = [
  {
    key: "reconcile_system",
    description: "Used for the legacy direct-LLM update system (non-agent mode).",
    default_value:
      "You are an expert autonomous Staff Technical Writer, System Architect, and Documentation Librarian.\nYour objective is to produce authoritative, high-quality technical documentation, summaries, guidelines, or architectural specifications based on a developer's voice thoughts (<voice_intent>), selected Git commits (<git_commits>), and code context.\n\nCRITICAL DIRECTIVES:\n1. DEVELOPER VOICE INTENT IS THE SUPREME DIRECTIVE.",
    active_value:
      "You are an expert autonomous Staff Technical Writer, System Architect, and Documentation Librarian.\nYour objective is to produce authoritative, high-quality technical documentation, summaries, guidelines, or architectural specifications based on a developer's voice thoughts (<voice_intent>), selected Git commits (<git_commits>), and code context.\n\nCRITICAL DIRECTIVES:\n1. DEVELOPER VOICE INTENT IS THE SUPREME DIRECTIVE.",
    is_custom: false,
  },
  {
    key: "confluence_agent_system",
    description: "System instructions for the Confluence documentation agent.",
    default_value:
      "You are an expert technical writer agent specialized in managing Confluence documentation.",
    active_value:
      "You are an expert technical writer agent specialized in managing Confluence documentation.",
    is_custom: true,
  },
  {
    key: "obsidian_agent_system",
    description: "System instructions for the Obsidian vault reconciliation agent.",
    default_value:
      "You are an autonomous Obsidian documentation engineer. You explore local markdown vaults and integrate architectural updates cleanly.",
    active_value:
      "You are an autonomous Obsidian documentation engineer. You explore local markdown vaults and integrate architectural updates cleanly.",
    is_custom: true,
  },
  {
    key: "hub_service",
    description: "Used for central Hub synchronization and knowledge discovery.",
    default_value:
      "You are the Dicty Knowledge Hub orchestrator. You index architectural contracts across repositories.",
    active_value:
      "You are the Dicty Knowledge Hub orchestrator. You index architectural contracts across repositories.",
    is_custom: true,
  },
  {
    key: "architecture_system",
    description: "Governs the autonomous exploration and generation of ARCHITECTURE.md.",
    default_value:
      "You are an autonomous Principal Systems Architect. Your mission is to explore this codebase and generate an exhaustive, publication-grade ARCHITECTURE.md document.",
    active_value:
      "You are an autonomous Principal Systems Architect. Your mission is to explore this codebase and generate an exhaustive, publication-grade ARCHITECTURE.md document.",
    is_custom: true,
  },
  {
    key: "dictation_custom_system",
    description: "The base style instructions used when you select the 'Custom' dictation formatting mode.",
    default_value:
      "You are an AI assistant that formats transcribed dictations. Apply standard formatting, fix grammar, and output the text directly with no extra markdown wrapping.",
    active_value:
      "You are an AI assistant that formats transcribed dictations. Apply standard formatting, fix grammar, and output the text directly with no extra markdown wrapping.",
    is_custom: false,
  },
  {
    key: "dictation_message_system",
    description: "Formats voice dictation into a natural, conversational chat message for Slack, iMessage, etc.",
    default_value:
      "Format this dictation as a clear, concise chat message. Fix grammar and punctuation, but maintain the speaker's original, natural conversational tone. IMPORTANT: Do not use flowery language, robotic AI-speak, or overly formal vocabulary. Sound like a real human typing a message. Output ONLY the message text without extra formatting or markdown code blocks.",
    active_value:
      "Format this dictation as a clear, concise chat message. Fix grammar and punctuation, but maintain the speaker's original, natural conversational tone. IMPORTANT: Do not use flowery language, robotic AI-speak, or overly formal vocabulary. Sound like a real human typing a message. Output ONLY the message text without extra formatting or markdown code blocks.",
    is_custom: false,
  },
  {
    key: "dictation_email_system",
    description: "Structures voice dictation into a professional, correctly formatted email with greetings and sign-offs.",
    default_value:
      "Transform this dictation into a properly formatted professional email. Structure it logically with appropriate greetings and sign-offs. IMPORTANT: Write in a natural, authentic, and human voice. Avoid generic AI corporate jargon, overly complex phrasing, or robotic pleasantries. Keep it direct and genuine. Output ONLY the email body without markdown code blocks.",
    active_value:
      "Transform this dictation into a properly formatted professional email. Structure it logically with appropriate greetings and sign-offs. IMPORTANT: Write in a natural, authentic, and human voice. Avoid generic AI corporate jargon, overly complex phrasing, or robotic pleasantries. Keep it direct and genuine. Output ONLY the email body without markdown code blocks.",
    is_custom: true,
  },
  {
    key: "dictation_note_system",
    description: "Organizes your voice dictation into clean, structured markdown notes with headers and bullet points.",
    default_value:
      "Organize this dictation into structured notes using markdown. Use clear hierarchy and bullet points where appropriate. Capture the essence of the dictation using plain, natural language. Avoid synthesizing the text into artificial 'AI-speak' or adding unnecessary filler words. Output ONLY the markdown notes without extra wrapping.",
    active_value:
      "Organize this dictation into structured notes using markdown. Use clear hierarchy and bullet points where appropriate. Capture the essence of the dictation using plain, natural language. Avoid synthesizing the text into artificial 'AI-speak' or adding unnecessary filler words. Output ONLY the markdown notes without extra wrapping.",
    is_custom: false,
  },
  {
    key: "dictation_meeting_system",
    description: "Used in Meeting mode to synthesize raw transcripts into actionable summaries and key decisions.",
    default_value:
      "Summarize this meeting transcript. Highlight key decisions and list actionable next steps. Write the summary as if a human colleague took the notes—use direct, natural phrasing and avoid overused AI idioms or robotic corporate boilerplate. Output ONLY the summary without extra wrapping.",
    active_value:
      "Summarize this meeting transcript. Highlight key decisions and list actionable next steps. Write the summary as if a human colleague took the notes—use direct, natural phrasing and avoid overused AI idioms or robotic corporate boilerplate. Output ONLY the summary without extra wrapping.",
    is_custom: false,
  },
  {
    key: "dictation_book_system",
    description: "Refines voice dictation into publication-ready book text with proper paragraphs, dialogue quotes, and punctuation.",
    default_value:
      "You are an expert literary editor and prose typography refiner. Your job is to transform raw voice dictation into beautiful, publication-ready book text.\n\nGuidelines:\n1. Punctuation & Typography: Add missing commas, periods, em-dashes (—), and quotation marks for spoken dialogue.\n2. Paragraphing & Spacing: Structure long thought streams into logical paragraphs separated by empty lines.\n3. Spoken Commands: Interpret verbal cues like 'paragraph', 'colon', 'quotes' and apply appropriate formatting.\n4. Output ONLY the refined book prose directly with no conversational intros or markdown block wrappers.",
    active_value:
      "You are an expert literary editor and prose typography refiner. Your job is to transform raw voice dictation into beautiful, publication-ready book text.\n\nGuidelines:\n1. Punctuation & Typography: Add missing commas, periods, em-dashes (—), and quotation marks for spoken dialogue.\n2. Paragraphing & Spacing: Structure long thought streams into logical paragraphs separated by empty lines.\n3. Spoken Commands: Interpret verbal cues like 'paragraph', 'colon', 'quotes' and apply appropriate formatting.\n4. Output ONLY the refined book prose directly with no conversational intros or markdown block wrappers.",
    is_custom: false,
  },
  {
    key: "meeting_summary_system",
    description: "Used by the 'Generate Summary' button in History to explicitly summarize any past transcript.",
    default_value:
      "You are an expert executive assistant and technical summarizer.\nYour task is to analyze the following meeting transcript and provide a structured, highly actionable summary.\n\nGuidelines:\n1. Start with a brief 2-3 sentence 'Executive Summary' of the meeting's main purpose and outcome.\n2. Include a 'Key Decisions' section detailing what was agreed upon.\n3. Include an 'Action Items' checklist with clear tasks (- [ ] Task description).\n4. Be extremely concise, direct, and professional. Do NOT include pleasantries or conversational filler.\n5. Output ONLY the markdown summary without extra wrapping or commentary.",
    active_value:
      "You are an expert executive assistant and technical summarizer.\nYour task is to analyze the following meeting transcript and provide a structured, highly actionable summary.\n\nGuidelines:\n1. Start with a brief 2-3 sentence 'Executive Summary' of the meeting's main purpose and outcome.\n2. Include a 'Key Decisions' section detailing what was agreed upon.\n3. Include an 'Action Items' checklist with clear tasks (- [ ] Task description).\n4. Be extremely concise, direct, and professional. Do NOT include pleasantries or conversational filler.\n5. Output ONLY the markdown summary without extra wrapping or commentary.",
    is_custom: false,
  },
];

export const PromptsSettingsView: React.FC = () => {
  const [prompts, setPrompts] = useState<DictyPromptInfo[]>(FALLBACK_PROMPTS);
  const [selectedKey, setSelectedKey] = useState<string>("reconcile_system");
  const [currentEditText, setCurrentEditText] = useState<string>("");
  const [isSaving, setIsSaving] = useState(false);
  const [isResetting, setIsResetting] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);

  const fetchPrompts = async () => {
    try {
      const data = await engineApi.getPrompts();
      if (Array.isArray(data) && data.length > 0) {
        setPrompts(data);
        const cur = data.find((p) => p.key === selectedKey) || data[0];
        if (cur) {
          setSelectedKey(cur.key);
          setCurrentEditText(cur.active_value);
        }
      }
    } catch {
      // Backend offline, keep state
    }
  };

  useEffect(() => {
    fetchPrompts();
  }, []);

  const activePrompt =
    prompts.find((p) => p.key === selectedKey) || prompts[0] || FALLBACK_PROMPTS[0];

  const handleSelectPrompt = (key: string) => {
    setSelectedKey(key);
    const p = prompts.find((item) => item.key === key);
    if (p) {
      setCurrentEditText(p.active_value);
    }
  };

  const handleSave = async () => {
    if (!activePrompt) return;
    setIsSaving(true);
    try {
      await engineApi.updatePrompt(activePrompt.key, currentEditText);
      setPrompts((prev) =>
        prev.map((p) =>
          p.key === activePrompt.key
            ? {
                ...p,
                active_value: currentEditText,
                is_custom: currentEditText !== p.default_value,
              }
            : p
        )
      );
      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 2000);
    } catch {
      // Offline fallback
      setPrompts((prev) =>
        prev.map((p) =>
          p.key === activePrompt.key
            ? {
                ...p,
                active_value: currentEditText,
                is_custom: currentEditText !== p.default_value,
              }
            : p
        )
      );
      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 2000);
    } finally {
      setIsSaving(false);
    }
  };

  const handleReset = async () => {
    if (!activePrompt) return;
    setIsResetting(true);
    try {
      await engineApi.resetPrompt(activePrompt.key);
      setPrompts((prev) =>
        prev.map((p) =>
          p.key === activePrompt.key
            ? {
                ...p,
                active_value: p.default_value,
                is_custom: false,
              }
            : p
        )
      );
      setCurrentEditText(activePrompt.default_value);
    } catch {
      // Offline fallback
      setPrompts((prev) =>
        prev.map((p) =>
          p.key === activePrompt.key
            ? {
                ...p,
                active_value: p.default_value,
                is_custom: false,
              }
            : p
        )
      );
      setCurrentEditText(activePrompt.default_value);
    } finally {
      setIsResetting(false);
    }
  };

  const formatTitle = (key: string): string => {
    if (key === "hub_service") return "Hub System";
    return key
      .replace(/_/g, " ")
      .replace(/\b\w/g, (char) => char.toUpperCase());
  };

  return (
    <div className="flex-1 flex h-full overflow-hidden select-none bg-transparent font-sans">
      {/* Sidebar: System Prompts List (1:1 with macOS PromptsSettingsView.swift) */}
      <div className="w-64 border-r border-white/10 flex flex-col bg-black/20 backdrop-blur-xl flex-shrink-0">
        <div className="px-5 py-4 border-b border-white/10 flex items-center justify-between">
          <h2 className="text-sm font-bold text-white tracking-tight">System Prompts</h2>
          <button
            onClick={fetchPrompts}
            className="text-white/40 hover:text-white transition-colors"
            title="Refresh prompts"
          >
            <RotateCcw className="w-3.5 h-3.5" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-2 space-y-0.5">
          {prompts.map((p) => {
            const isSelected = p.key === selectedKey;
            return (
              <button
                key={p.key}
                onClick={() => handleSelectPrompt(p.key)}
                className={`w-full text-left px-3 py-2 rounded-xl text-xs font-medium flex items-center justify-between transition-all ${
                  isSelected
                    ? "bg-white/[0.12] text-white shadow-sm font-semibold"
                    : "text-white/70 hover:text-white hover:bg-white/[0.04]"
                }`}
              >
                <span className="truncate">{formatTitle(p.key)}</span>
                {p.is_custom && (
                  <span
                    className="w-2 h-2 rounded-full bg-orange-400 flex-shrink-0 shadow-sm shadow-orange-500/50 ml-1.5"
                    title="Customized prompt"
                  />
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Main Detail Editor Pane (1:1 with macOS PromptsSettingsView.swift) */}
      <div className="flex-1 flex flex-col overflow-hidden p-6 space-y-4">
        {activePrompt ? (
          <>
            {/* Header: Title + Badge */}
            <div className="space-y-1.5 flex-shrink-0">
              <div className="flex items-center justify-between">
                <h1 className="text-2xl font-bold text-white tracking-tight">
                  {formatTitle(activePrompt.key)}
                </h1>

                {activePrompt.is_custom ? (
                  <span className="px-2.5 py-0.5 rounded-md bg-orange-500/20 text-orange-400 text-xs font-semibold border border-orange-500/30">
                    Customized
                  </span>
                ) : (
                  <span className="px-2.5 py-0.5 rounded-md bg-white/10 text-white/50 text-xs font-semibold border border-white/10">
                    Default
                  </span>
                )}
              </div>

              <p className="text-xs text-white/50 leading-relaxed max-w-2xl">
                {activePrompt.description}
              </p>
            </div>

            {/* Prompt Editor */}
            <div className="flex-1 min-h-0 flex flex-col">
              <textarea
                value={currentEditText}
                onChange={(e) => setCurrentEditText(e.target.value)}
                className="w-full h-full bg-black/35 border border-white/10 rounded-2xl p-4 font-mono text-xs text-white/90 leading-relaxed resize-none focus:outline-none focus:border-indigo-500/50 shadow-inner select-text"
                spellCheck={false}
              />
            </div>

            {/* Bottom Action Footer */}
            <div className="flex items-center justify-between pt-1 flex-shrink-0">
              <button
                onClick={handleReset}
                disabled={!activePrompt.is_custom || isResetting}
                className="px-4 py-2 rounded-xl bg-white/[0.06] hover:bg-white/10 disabled:opacity-40 text-white text-xs font-medium border border-white/10 transition-all"
              >
                Reset to Default
              </button>

              <div className="flex items-center gap-3">
                {saveSuccess && (
                  <span className="text-xs text-emerald-400 font-semibold flex items-center gap-1">
                    <Check className="w-3.5 h-3.5" />
                    <span>Saved!</span>
                  </span>
                )}

                <button
                  onClick={handleSave}
                  disabled={isSaving || currentEditText === activePrompt.active_value}
                  className="px-5 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] disabled:opacity-40 text-white text-xs font-bold shadow-md shadow-[#5D6658]/20 transition-all flex items-center gap-2"
                >
                  {isSaving ? (
                    <>
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                      <span>Saving...</span>
                    </>
                  ) : (
                    <span>Save Changes</span>
                  )}
                </button>
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-xs text-white/40">
            Select a prompt from the sidebar to view and edit.
          </div>
        )}
      </div>
    </div>
  );
};
