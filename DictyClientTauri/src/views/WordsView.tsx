import React, { useState } from "react";
import { BookA, FileCode } from "lucide-react";
import { VocabularyView } from "./VocabularyView";
import { SnippetsView } from "./SnippetsView";
import { PageTabBar, type PageTabItem } from "../components/PageTabBar";

const WORDS_TAB_KEY = "dicty_words_tab";

type WordsTab = "vocabulary" | "snippets";

const WORDS_TABS: PageTabItem<WordsTab>[] = [
  { id: "vocabulary", label: "Vocabulary", icon: BookA },
  { id: "snippets", label: "Snippets", icon: FileCode },
];

/// Words (Vocabulary + Snippets). Consolidates both dictionary systems matching macOS WordsView.swift.
export const WordsView: React.FC = () => {
  const [tab, setTab] = useState<WordsTab>(() => {
    try {
      return localStorage.getItem(WORDS_TAB_KEY) === "snippets" ? "snippets" : "vocabulary";
    } catch {
      return "vocabulary";
    }
  });

  const selectTab = (next: WordsTab) => {
    setTab(next);
    try {
      localStorage.setItem(WORDS_TAB_KEY, next);
    } catch {
      // Ignore storage restrictions.
    }
  };

  return (
    <div className="flex-1 flex flex-col min-h-0 min-w-0 select-none">
      <div className="px-8 pt-5 pb-3 border-b border-white/10 shrink-0 bg-black/20 backdrop-blur-md">
        <PageTabBar
          selection={tab}
          onSelect={selectTab}
          tabs={WORDS_TABS}
        />
      </div>

      <div className="flex-1 min-h-0 flex flex-col">
        {tab === "snippets" ? <SnippetsView /> : <VocabularyView />}
      </div>
    </div>
  );
};
