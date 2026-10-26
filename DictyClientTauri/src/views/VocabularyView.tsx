import React, { useState, useEffect } from "react";
import {
  BookOpen,
  Plus,
  Trash2,
  Search,
  Upload,
  ArrowRight,
  RefreshCw,
  Loader2,
  Sparkles,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { engineApi } from "../services/engineApi";
import { VocabularyItem } from "../types/engine";

const VOCAB_STORAGE_KEY = "dicty_vocabulary_cache";

export const VocabularyView: React.FC = () => {
  const [rules, setRules] = useState<VocabularyItem[]>(() => {
    try {
      const cached = localStorage.getItem(VOCAB_STORAGE_KEY);
      if (cached) {
        const parsed = JSON.parse(cached);
        if (Array.isArray(parsed) && parsed.length > 0) {
          return parsed;
        }
      }
    } catch (e) {
      console.warn("Failed to parse cached vocabulary:", e);
    }
    return [];
  });

  const [newWord, setNewWord] = useState("");
  const [newReplacement, setNewReplacement] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const fetchVocabulary = async () => {
    setIsLoading(true);
    try {
      const res = await engineApi.getVocabulary();
      if (res && Array.isArray(res.vocabulary)) {
        setRules(res.vocabulary);
        localStorage.setItem(VOCAB_STORAGE_KEY, JSON.stringify(res.vocabulary));
      }
    } catch (err) {
      console.error("Failed to fetch vocabulary from engine:", err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchVocabulary();
  }, []);

  const filteredRules = rules.filter(
    (r) =>
      r.word.toLowerCase().includes(searchQuery.toLowerCase()) ||
      r.replacement.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleAddRule = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanWord = newWord.trim();
    const cleanReplacement = newReplacement.trim();
    if (!cleanWord || isSubmitting) return;

    const replacementVal = cleanReplacement || cleanWord;
    const tempId = `temp_${Date.now()}`;
    const optimisticRule: VocabularyItem = {
      id: tempId,
      word: cleanWord,
      replacement: replacementVal,
    };

    // Optimistic UI update + local cache
    const updated = [optimisticRule, ...rules];
    setRules(updated);
    localStorage.setItem(VOCAB_STORAGE_KEY, JSON.stringify(updated));
    setNewWord("");
    setNewReplacement("");

    setIsSubmitting(true);
    try {
      const res = await engineApi.addVocabulary(cleanWord, replacementVal);
      if (res && res.status === "success" && res.item) {
        setRules((prev) => {
          const next = prev.map((r) => (r.id === tempId ? res.item : r));
          localStorage.setItem(VOCAB_STORAGE_KEY, JSON.stringify(next));
          return next;
        });
      } else {
        await fetchVocabulary();
      }
    } catch (err) {
      console.error("Failed to persist vocabulary rule to engine:", err);
      await fetchVocabulary();
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDelete = async (id: string) => {
    // Optimistic UI update + local cache
    const updated = rules.filter((r) => r.id !== id);
    setRules(updated);
    localStorage.setItem(VOCAB_STORAGE_KEY, JSON.stringify(updated));

    try {
      await engineApi.deleteVocabulary(id);
    } catch (err) {
      console.error("Failed to delete vocabulary rule from engine:", err);
      await fetchVocabulary();
    }
  };

  const handleImportCSV = () => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".csv,.txt";
    input.onchange = async (e: any) => {
      const file = e.target.files?.[0];
      if (file) {
        const reader = new FileReader();
        reader.onload = async (event) => {
          const content = event.target?.result as string;
          const lines = content.split(/\r?\n/);
          setIsLoading(true);
          try {
            for (const line of lines) {
              const parts = line.split(",");
              if (parts.length >= 1) {
                const word = parts[0].trim();
                const replacement = parts.length >= 2 ? parts[1].trim() : word;
                if (word && word.toLowerCase() !== "word") {
                  await engineApi.addVocabulary(word, replacement || word);
                }
              }
            }
            await fetchVocabulary();
          } catch (err) {
            console.error("Failed to import CSV rules to engine:", err);
            await fetchVocabulary();
          } finally {
            setIsLoading(false);
          }
        };
        reader.readAsText(file);
      }
    };
    input.click();
  };

  const handleLoadStarterPack = async () => {
    setIsLoading(true);
    try {
      const res = await engineApi.loadDefaultVocabulary(false);
      if (res && Array.isArray(res.vocabulary)) {
        setRules(res.vocabulary);
        localStorage.setItem(VOCAB_STORAGE_KEY, JSON.stringify(res.vocabulary));
      } else {
        await fetchVocabulary();
      }
    } catch (err) {
      console.error("Failed to load starter vocabulary:", err);
      await fetchVocabulary();
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-6 select-none">
      <div className="flex items-center justify-between">
        <SettingsPageHeader
          title="Custom Vocabulary"
          description="Force Whisper to spell technical terms, company names, and internal acronyms correctly."
          helpTopic="vocabulary"
        />
        <div className="flex items-center gap-2">
          <button
            onClick={fetchVocabulary}
            disabled={isLoading}
            className="p-2 rounded-xl bg-white/[0.05] hover:bg-white/10 text-white/60 hover:text-white border border-white/10 transition-all disabled:opacity-50"
            title="Refresh vocabulary"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? "animate-spin text-[#87B996]" : ""}`} />
          </button>
          <button
            onClick={handleLoadStarterPack}
            disabled={isLoading}
            className="px-3 py-1.5 rounded-xl bg-white/[0.05] hover:bg-white/10 text-white text-xs font-medium border border-white/10 flex items-center gap-1.5 transition-all disabled:opacity-50"
            title="Load 10 curated developer vocabulary rules"
          >
            <Sparkles className="w-3.5 h-3.5 text-[#87B996]" />
            <span>Starter Pack (10)</span>
          </button>
          <button
            onClick={handleImportCSV}
            disabled={isLoading}
            className="px-3 py-1.5 rounded-xl bg-white/[0.05] hover:bg-white/10 text-white text-xs font-medium border border-white/10 flex items-center gap-1.5 transition-all disabled:opacity-50"
          >
            <Upload className="w-3.5 h-3.5 text-[#87B996]" />
            <span>Import CSV</span>
          </button>
        </div>
      </div>

      {/* Informative Tip Banner */}
      <div className="flex items-center gap-2.5 p-2.5 rounded-xl bg-white/[0.03] border border-white/10 text-xs text-white/70">
        <Sparkles className="w-4 h-4 text-[#87B996] flex-shrink-0" />
        <div className="text-[11px] sm:text-xs">
          <span className="font-semibold text-white/90">Vocabulary Tip: </span>
          <span>
            Whisper uses the top 25 terms to acoustically bias speech recognition, while all rules are applied via exact text normalization.
          </span>
        </div>
      </div>

      {/* Add New Rule Card (1:1 with submitNewRule in HistoryView.swift:1261) */}
      <form
        onSubmit={handleAddRule}
        className="p-4 rounded-2xl bg-white/[0.04] border border-white/10 space-y-3 shadow-lg"
      >
        <span className="text-xs font-bold text-white tracking-tight block">
          Add Replacement Rule
        </span>
        <div className="flex items-center gap-3">
          <div className="flex-1">
            <input
              type="text"
              placeholder="When I say... (e.g. fast api)"
              value={newWord}
              onChange={(e) => setNewWord(e.target.value)}
              className="w-full bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658]"
            />
          </div>
          <ArrowRight className="w-4 h-4 text-white/40 flex-shrink-0" />
          <div className="flex-1">
            <input
              type="text"
              placeholder="Replace with... (e.g. FastAPI)"
              value={newReplacement}
              onChange={(e) => setNewReplacement(e.target.value)}
              className="w-full bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-[#5D6658]"
            />
          </div>
          <button
            type="submit"
            disabled={!newWord.trim() || isSubmitting}
            className="px-5 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] disabled:opacity-40 text-white text-xs font-semibold transition-all shadow flex items-center gap-1.5"
          >
            {isSubmitting ? (
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
            ) : (
              <Plus className="w-3.5 h-3.5" />
            )}
            <span>Add Rule</span>
          </button>
        </div>
      </form>

      {/* Search & Counter */}
      <div className="flex items-center justify-between gap-3">
        <div className="relative flex-1">
          <Search className="w-3.5 h-3.5 text-white/40 absolute left-3.5 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search custom vocabulary rules..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-white/[0.04] border border-white/10 rounded-xl pl-9 pr-3 py-1.5 text-xs text-white placeholder-white/40 focus:outline-none focus:border-[#5D6658]"
          />
        </div>
        <span className="text-xs text-white/40 font-mono">
          {rules.length} active rules
        </span>
      </div>

      {/* Column Headers for Alignment */}
      {filteredRules.length > 0 && (
        <div className="flex items-center px-4 text-[10px] font-bold uppercase tracking-wider text-white/35 pb-1">
          <span className="w-[140px] sm:w-[200px] flex-shrink-0">When I say</span>
          <span className="w-8 flex-shrink-0 text-center" />
          <span className="flex-1 min-w-0 pl-1">Replaced with</span>
          <span className="w-8 flex-shrink-0 text-right">Action</span>
        </div>
      )}

      {/* Rules List */}
      {filteredRules.length === 0 ? (
        <div className="py-16 text-center space-y-3">
          <BookOpen className="w-8 h-8 text-white/20 mx-auto" />
          <div className="text-xs text-white/40 max-w-sm mx-auto">
            {isLoading
              ? "Loading custom vocabulary rules..."
              : searchQuery
              ? "No matching vocabulary rules found."
              : "No custom vocabulary rules yet. Load our curated 10-word starter pack to help Whisper with terms like FastAPI, Kubernetes, and GitHub."}
          </div>
          {!searchQuery && !isLoading && (
            <button
              onClick={handleLoadStarterPack}
              className="px-3.5 py-1.5 rounded-xl bg-white/[0.05] hover:bg-white/10 text-emerald-300 border border-emerald-500/20 text-xs font-semibold shadow transition-all inline-flex items-center gap-1.5"
            >
              <Sparkles className="w-3.5 h-3.5 text-emerald-400" />
              <span>Load 10 Tech Starter Words</span>
            </button>
          )}
        </div>
      ) : (
        <div className="space-y-2">
          {filteredRules.map((rule) => (
            <div
              key={rule.id}
              onMouseEnter={() => setHoveredId(rule.id)}
              onMouseLeave={() => setHoveredId(null)}
              className="p-2.5 px-4 rounded-xl bg-white/[0.025] hover:bg-white/[0.05] border border-white/10 transition-all flex items-center text-xs"
            >
              {/* Spoken Word (Fixed-width column so arrow is vertically aligned) */}
              <div className="w-[140px] sm:w-[200px] flex-shrink-0 flex items-center pr-2">
                <span
                  className="px-2.5 py-1 rounded-md bg-white/[0.06] text-white/80 font-mono font-medium text-[11px] truncate max-w-full"
                  title={`When you say: "${rule.word}"`}
                >
                  "{rule.word}"
                </span>
              </div>

              {/* Arrow Indicator (Fixed Center Alignment across all rows) */}
              <div className="w-8 flex-shrink-0 flex items-center justify-center">
                <ArrowRight className="w-3.5 h-3.5 text-white/30" />
              </div>

              {/* Replacement (Left-aligned column with subtle grey & light-blue styling) */}
              <div className="flex-1 min-w-0 flex items-center pl-1 pr-2">
                <span
                  className="px-2.5 py-1 rounded-md bg-white/[0.04] border border-white/10 text-[#8ec3e6] font-bold font-mono text-[11px] truncate max-w-full"
                  title={`Replaces with: ${rule.replacement}`}
                >
                  {rule.replacement}
                </span>
              </div>

              {/* Delete Action Button */}
              <div className="w-8 flex-shrink-0 flex items-center justify-end">
                <button
                  onClick={() => handleDelete(rule.id)}
                  className={`p-1.5 rounded-lg text-red-400/70 hover:text-red-400 hover:bg-red-500/10 transition-all ${
                    hoveredId === rule.id ? "opacity-100" : "opacity-0"
                  }`}
                  title="Delete rule"
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
