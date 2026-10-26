import React, { useState } from "react";
import { VocabularyView } from "./VocabularyView";
import { SnippetsView } from "./SnippetsView";

const WORDS_TAB_KEY = "dicty_words_tab";

/// Words (Vocabulary + Snippets). One sidebar entry for both dictionaries.
/// Each tab is the existing page: it already has its own header and scroller,
/// so this page just adds a tab switcher above it.
export const WordsView: React.FC = () => {
  const [tab, setTab] = useState<"vocabulary" | "snippets">(() => {
    try {
      return localStorage.getItem(WORDS_TAB_KEY) === "snippets" ? "snippets" : "vocabulary";
    } catch {
      return "vocabulary";
    }
  });

  const selectTab = (next: "vocabulary" | "snippets") => {
    setTab(next);
    try {
      localStorage.setItem(WORDS_TAB_KEY, next);
    } catch {
      // Ignore storage restrictions.
    }
  };

  return (
    <div className="flex-1 flex flex-col min-h-0 min-w-0">
      <div className="px-8 pt-6 pb-3 shrink-0">
        <div className="inline-flex items-center p-1 rounded-xl bg-white/[0.04] border border-white/10">
          {(["vocabulary", "snippets"] as const).map((value) => (
            <button
              key={value}
              onClick={() => selectTab(value)}
              className={`px-4 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                tab === value
                  ? "bg-[#5D6658] text-white shadow-sm"
                  : "text-white/60 hover:text-white"
              }`}
            >
              {value === "vocabulary" ? "Vocabulary" : "Snippets"}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 min-h-0 flex flex-col">
        {tab === "snippets" ? <SnippetsView /> : <VocabularyView />}
      </div>
    </div>
  );
};
