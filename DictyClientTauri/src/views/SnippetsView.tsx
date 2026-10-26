import React, { useEffect, useState } from "react";
import {
  Mic,
  Pencil,
  Trash2,
  Search,
  Loader2,
  PlusCircle,
  ArrowRight,
  TextSelect,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { engineApi } from "../services/engineApi";
import type { DictySnippet } from "../types/engine";

/// Voice snippets: say a short trigger, Dicty types prepared text.
/// Matching is deterministic (no LLM, ~0 ms).
export const SnippetsView: React.FC = () => {
  const [snippets, setSnippets] = useState<DictySnippet[]>([]);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [trigger, setTrigger] = useState("");
  const [content, setContent] = useState("");
  const [expandAnywhere, setExpandAnywhere] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [searchText, setSearchText] = useState("");
  const [hoveredId, setHoveredId] = useState<string | null>(null);

  const fetchSnippets = async () => {
    setIsLoading(true);
    try {
      const res = await engineApi.getSnippets();
      if (res && Array.isArray(res.snippets)) {
        setSnippets(res.snippets);
      }
    } catch (err) {
      console.warn("Failed to load snippets from engine:", err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchSnippets();
  }, []);

  const query = searchText.trim().toLowerCase();
  const filtered = query
    ? snippets.filter(
        (s) =>
          s.trigger.toLowerCase().includes(query) ||
          s.content.toLowerCase().includes(query)
      )
    : snippets;

  const canSave =
    trigger.trim().length > 0 && content.trim().length > 0 && !isSaving;

  const resetEditor = () => {
    setEditingId(null);
    setTrigger("");
    setContent("");
    setExpandAnywhere(false);
    setErrorMessage(null);
  };

  const beginEditing = (s: DictySnippet) => {
    setEditingId(s.id);
    setTrigger(s.trigger);
    setContent(s.content);
    setExpandAnywhere(!!s.expand_anywhere);
    setErrorMessage(null);
  };

  const save = async () => {
    if (!canSave) return;
    setIsSaving(true);
    setErrorMessage(null);
    const cleanTrigger = trigger.trim();
    const cleanContent = content;
    try {
      if (editingId) {
        const res = await engineApi.updateSnippet(
          editingId,
          cleanTrigger,
          cleanContent,
          [],
          expandAnywhere
        );
        if (res?.item) {
          setSnippets((prev) => prev.map((s) => (s.id === editingId ? res.item : s)));
        }
      } else {
        const res = await engineApi.addSnippet(cleanTrigger, cleanContent, [], expandAnywhere);
        if (res?.item) {
          setSnippets((prev) => [res.item, ...prev]);
        }
      }
      resetEditor();
    } catch (err: any) {
      setErrorMessage(err?.message || "Could not save this snippet.");
    } finally {
      setIsSaving(false);
    }
  };

  const remove = async (id: string) => {
    const previous = snippets;
    setSnippets((prev) => prev.filter((s) => s.id !== id));
    if (editingId === id) resetEditor();
    try {
      await engineApi.deleteSnippet(id);
    } catch (err) {
      console.warn("Failed to delete snippet:", err);
      setSnippets(previous);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-5 select-none">
      <SettingsPageHeader
        title="Snippets"
        description="Save text you type a lot. Say a short phrase, and Dicty types the full text for you."
      />

      {/* How to use it */}
      <div className="p-4 rounded-2xl bg-[#5D6658]/10 border border-white/10 space-y-2">
        <span className="text-xs font-bold text-white tracking-tight block">
          How to use it
        </span>
        <ExampleRow say="my email" get="john@example.com" />
        <ExampleRow say="my LinkedIn" get="linkedin.com/in/john" />
        <ExampleRow say="Here's my profile, insert my LinkedIn" get="Here's my profile, linkedin.com/in/john" />
        <p className="text-[11px] text-white/50 pt-1">
          Say the phrase by itself. Inside a sentence, say &ldquo;insert&rdquo; first.
        </p>
      </div>

      {/* Editor */}
      <div className="p-4 rounded-2xl bg-white/[0.03] border border-white/10 space-y-3.5">
        <div className="flex items-center gap-2">
          {editingId ? (
            <Pencil className="w-3.5 h-3.5 text-[#87B996]" />
          ) : (
            <PlusCircle className="w-3.5 h-3.5 text-[#87B996]" />
          )}
          <span className="text-xs font-bold text-white tracking-tight">
            {editingId ? "Edit snippet" : "New snippet"}
          </span>
          <div className="flex-1" />
          {editingId && (
            <button
              onClick={resetEditor}
              className="text-[11px] font-medium text-white/50 hover:text-white transition-colors"
            >
              Cancel
            </button>
          )}
        </div>

        <div className="space-y-1">
          <label className="text-[11px] font-medium text-white/50">When you say</label>
          <input
            type="text"
            value={trigger}
            onChange={(e) => setTrigger(e.target.value)}
            placeholder="e.g. my LinkedIn"
            className="w-full bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658]"
          />
        </div>

        <div className="space-y-1">
          <label className="text-[11px] font-medium text-white/50">Dicty types</label>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="The full text Dicty should type"
            className="w-full min-h-[70px] max-h-[140px] bg-black/40 border border-white/10 rounded-xl px-3 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658] resize-y"
          />
        </div>

        <div className="flex items-center justify-between gap-3">
          <label className="flex items-center gap-2 text-[11.5px] text-white/60 cursor-pointer">
            <input
              type="checkbox"
              checked={expandAnywhere}
              onChange={(e) => setExpandAnywhere(e.target.checked)}
              className="accent-[#5D6658]"
              title="Use this only for phrases you never say by accident."
            />
            <span>Also work inside sentences, without saying &ldquo;insert&rdquo;</span>
          </label>

          <button
            onClick={save}
            disabled={!canSave}
            className="px-4 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] disabled:opacity-40 text-white text-xs font-semibold transition-all flex items-center gap-1.5"
          >
            {isSaving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
            <span>{editingId ? "Save" : "Add Snippet"}</span>
          </button>
        </div>

        {errorMessage && (
          <p className="text-[11px] text-rose-300">{errorMessage}</p>
        )}
      </div>

      {/* Search */}
      {snippets.length > 0 && (
        <div className="relative">
          <Search className="w-3.5 h-3.5 text-white/40 absolute left-3.5 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
            placeholder="Search snippets"
            className="w-full bg-white/[0.04] border border-white/10 rounded-xl pl-9 pr-3 py-2 text-xs text-white placeholder-white/40 focus:outline-none focus:border-[#5D6658]"
          />
        </div>
      )}

      {/* List */}
      {filtered.length === 0 ? (
        <div className="py-16 text-center space-y-2">
          <TextSelect className="w-8 h-8 text-white/20 mx-auto" />
          <div className="text-xs text-white/40 max-w-sm mx-auto">
            {isLoading
              ? "Loading snippets..."
              : snippets.length === 0
              ? 'No snippets yet. Try: "my email address" → your email. Then just say "my email address".'
              : "No matching snippets."}
          </div>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((s) => (
            <div
              key={s.id}
              onMouseEnter={() => setHoveredId(s.id)}
              onMouseLeave={() => setHoveredId(null)}
              className={`p-3 px-4 rounded-xl border transition-all flex items-start gap-3 ${
                editingId === s.id
                  ? "bg-[#5D6658]/15 border-[#5D6658]/40"
                  : "bg-white/[0.025] hover:bg-white/[0.05] border-white/10"
              }`}
            >
              <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#5D6658]/25 text-white text-[11px] font-semibold shrink-0 max-w-[180px]">
                <Mic className="w-2.5 h-2.5 shrink-0" />
                <span className="truncate">{s.trigger}</span>
              </span>

              <ArrowRight className="w-3.5 h-3.5 text-white/30 mt-1.5 shrink-0" />

              <div className="flex-1 min-w-0 space-y-1 pt-0.5">
                <p className="text-xs text-white/85 line-clamp-2 break-words">{s.content}</p>
                {s.expand_anywhere && (
                  <p className="text-[10px] text-white/40">Works inside sentences</p>
                )}
              </div>

              <div
                className={`flex items-center gap-1 shrink-0 transition-opacity ${
                  hoveredId === s.id || editingId === s.id ? "opacity-100" : "opacity-0"
                }`}
              >
                <button
                  onClick={() => beginEditing(s)}
                  className="p-1.5 rounded-lg text-white/50 hover:text-white hover:bg-white/10 transition-all"
                  title="Edit"
                >
                  <Pencil className="w-3.5 h-3.5" />
                </button>
                <button
                  onClick={() => remove(s.id)}
                  className="p-1.5 rounded-lg text-red-400/70 hover:text-red-400 hover:bg-red-500/10 transition-all"
                  title="Delete"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

const ExampleRow: React.FC<{ say: string; get: string }> = ({ say, get }) => (
  <div className="flex items-center gap-2 text-xs">
    <span className="flex items-center gap-1 text-white/85">
      <Mic className="w-2.5 h-2.5" />
      <span>&ldquo;{say}&rdquo;</span>
    </span>
    <ArrowRight className="w-3 h-3 text-white/40" />
    <span className="font-mono text-white/60 truncate">{get}</span>
  </div>
);
