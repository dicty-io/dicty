import React, { useState, useEffect, useMemo, useRef } from "react";
import {
  Search,
  Copy,
  Check,
  Trash2,
  Play,
  Square,
  RefreshCw,
  Sparkles,
  Tag,
  Filter,
  X,
  ChevronDown,
  ChevronUp,
  Pencil,
  Plus,
  Zap,
  Clock,
  RotateCcw,
  FileText,
  AlertTriangle,
  BookOpen,
  AlignLeft,
  FileEdit,
  StickyNote,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { RichMarkdownDocumentView } from "../components/RichMarkdownDocumentView";
import { engineApi } from "../services/engineApi";
import { engineFetch } from "../services/engineClient";

interface HistoryRecord {
  id: string;
  timestamp: string | number;
  text: string;
  title?: string | null;
  notes?: string | null;
  mode: "dictation" | "librarian" | "meeting" | "focused_meeting" | string;
  duration_seconds?: number;
  tags?: string[];
  summary?: string | null;
  credits_used?: number;
  reprocessed_at?: string;
  audio_file?: string;
  has_audio?: boolean;
  speaking_wpm?: number;
  engine_wpm?: number;
  app_id?: string;
  target_app_name?: string;
  resolved_mode?: string;
  resolution_source?: string;
}

interface HistoryUpdate {
  id: string;
  title: string;
  original_content?: string;
  proposed_content: string;
  target_type: string;
  status: string;
  timestamp: string;
  resolved_at?: string | null;
}

function formatRecordDate(ts: any): string {
  if (!ts) return "Just now";
  let date: Date;
  if (typeof ts === "number") {
    date = new Date(ts > 1e11 ? ts : ts * 1000);
  } else {
    date = new Date(ts);
  }
  if (isNaN(date.getTime())) return String(ts);

  const now = new Date();
  const isToday = date.toDateString() === now.toDateString();
  const timeStr = date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  if (isToday) {
    return `Today at ${timeStr}`;
  }
  return `${date.toLocaleDateString([], { month: "short", day: "numeric" })} at ${timeStr}`;
}

export const HistoryView: React.FC = () => {
  const [selectedTab, setSelectedTab] = useState<"transcription" | "librarian">("transcription");

  // Transcription History State
  const [records, setRecords] = useState<HistoryRecord[]>([]);
  const [isLoadingHistory, setIsLoadingHistory] = useState(true);
  const [searchText, setSearchText] = useState("");
  const [selectedTags, setSelectedTags] = useState<string[]>([]);
  const [selectedApp, setSelectedApp] = useState<string | null>(null);
  const [showFilterPopover, setShowFilterPopover] = useState(false);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [playingId, setPlayingId] = useState<string | null>(null);
  const [audioPlayer, setAudioPlayer] = useState<HTMLAudioElement | null>(null);

  // Librarian Updates State
  const [updates, setUpdates] = useState<HistoryUpdate[]>([]);
  const [isLoadingUpdates, setIsLoadingUpdates] = useState(false);
  const [expandedUpdateIds, setExpandedUpdateIds] = useState<Set<string>>(new Set());
  const [renderMarkdown, setRenderMarkdown] = useState<Record<string, boolean>>({});
  const [reuploadingId, setReuploadingId] = useState<string | null>(null);
  const [reuploadSuccessId, setReuploadSuccessId] = useState<string | null>(null);

  // Reprocess & Edit State
  const [reprocessRecord, setReprocessRecord] = useState<HistoryRecord | null>(null);
  const [reprocessMode, setReprocessMode] = useState<"dictation" | "meeting" | "focused_meeting">("dictation");
  const [formatStyle, setFormatStyle] = useState<"raw" | "note" | "email" | "message" | "book" | "custom">("raw");
  const [customPrompt, setCustomPrompt] = useState("");
  const [retranscribeAudio, setRetranscribeAudio] = useState(false);
  const [isReprocessing, setIsReprocessing] = useState(false);
  const [reprocessError, setReprocessError] = useState<string | null>(null);

  // Inline Title Editing
  const [editingTitleId, setEditingTitleId] = useState<string | null>(null);
  const [editingTitleText, setEditingTitleText] = useState("");

  // Notes Editing State
  const [editingNotesId, setEditingNotesId] = useState<string | null>(null);
  const [editingNotesText, setEditingNotesText] = useState("");
  const [isSavingNotesId, setIsSavingNotesId] = useState<string | null>(null);

  // Summarize History State
  const [summarizingIds, setSummarizingIds] = useState<Set<string>>(new Set());
  const [summarizationErrors, setSummarizationErrors] = useState<Record<string, string>>({});

  // Tag Adding State
  const [addingTagId, setAddingTagId] = useState<string | null>(null);
  const [newTagInput, setNewTagInput] = useState("");

  // Clear All Modal
  const [showClearModal, setShowClearModal] = useState(false);
  const [isClearing, setIsClearing] = useState(false);

  // Fetch real transcription history
  const fetchHistory = async () => {
    setIsLoadingHistory(true);
    try {
      const data = await engineApi.getHistory();
      if (Array.isArray(data)) {
        setRecords(data);
      } else if (Array.isArray(data.history)) {
        setRecords(data.history);
      } else {
        setRecords([]);
      }
    } catch (err) {
      console.warn("Failed to fetch local history from engine:", err);
    } finally {
      setIsLoadingHistory(false);
    }
  };

  // Fetch real librarian updates history
  const fetchUpdates = async () => {
    setIsLoadingUpdates(true);
    try {
      const data = await engineApi.getUpdatesHistory();
      const list = data.updates || data.history || (Array.isArray(data) ? data : []);
      setUpdates(list);
      // Default to rendered markdown for all updates
      const initialMd: Record<string, boolean> = {};
      list.forEach((u: HistoryUpdate) => {
        initialMd[u.id] = true;
      });
      setRenderMarkdown(initialMd);
    } catch (err) {
      console.warn("Failed to fetch librarian updates history:", err);
    } finally {
      setIsLoadingUpdates(false);
    }
  };

  useEffect(() => {
    fetchHistory();
    fetchUpdates();
  }, []);

  // Cleanup audio player on unmount
  useEffect(() => {
    return () => {
      if (audioPlayer) {
        audioPlayer.pause();
      }
    };
  }, [audioPlayer]);

  // Available tags computed from actual records
  const availableTags = useMemo(() => {
    const map = new Map<string, number>();
    records.forEach((r) => {
      r.tags?.forEach((t) => {
        const clean = t.replace(/^#/, "").trim().toLowerCase();
        if (clean) {
          map.set(clean, (map.get(clean) || 0) + 1);
        }
      });
    });
    return Array.from(map.entries()).sort((a, b) => b[1] - a[1]);
  }, [records]);

  // Available apps computed from actual records
  const availableApps = useMemo(() => {
    const map = new Map<string, number>();
    records.forEach((r) => {
      const app = r.target_app_name || r.app_id;
      if (app) {
        map.set(app, (map.get(app) || 0) + 1);
      }
    });
    return Array.from(map.entries()).sort((a, b) => b[1] - a[1]);
  }, [records]);

  const toggleTagFilter = (tag: string) => {
    setSelectedTags((prev) =>
      prev.includes(tag) ? prev.filter((t) => t !== tag) : [...prev, tag]
    );
  };

  const filteredRecords = useMemo(() => {
    return records.filter((r) => {
      if (selectedTags.length > 0) {
        const hasMatch = r.tags?.some((t) =>
          selectedTags.includes(t.replace(/^#/, "").trim().toLowerCase())
        );
        if (!hasMatch) return false;
      }
      if (selectedApp) {
        const app = r.target_app_name || r.app_id;
        if (app !== selectedApp) return false;
      }
      if (searchText.trim()) {
        const q = searchText.toLowerCase();
        const matchesText = r.text?.toLowerCase().includes(q);
        const matchesTitle = r.title?.toLowerCase().includes(q);
        const matchesMode = r.mode?.toLowerCase().includes(q);
        const matchesTag = r.tags?.some((t) => t.toLowerCase().includes(q));
        const matchesApp =
          r.target_app_name?.toLowerCase().includes(q) ||
          r.app_id?.toLowerCase().includes(q);
        if (!matchesText && !matchesTitle && !matchesMode && !matchesTag && !matchesApp) return false;
      }
      return true;
    });
  }, [records, selectedTags, selectedApp, searchText]);

  const toggleExpand = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleExpandUpdate = (id: string) => {
    setExpandedUpdateIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleCopy = (id: string, text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const audioUrlRef = useRef<string | null>(null);

  const releaseAudioUrl = () => {
    if (audioUrlRef.current) {
      URL.revokeObjectURL(audioUrlRef.current);
      audioUrlRef.current = null;
    }
  };

  const stopPlayback = () => {
    audioPlayer?.pause();
    releaseAudioUrl();
    setAudioPlayer(null);
    setPlayingId(null);
  };

  const togglePlayback = async (recordId: string) => {
    if (playingId === recordId) {
      stopPlayback();
      return;
    }
    if (audioPlayer) {
      audioPlayer.pause();
      releaseAudioUrl();
    }

    try {
      const res = await engineFetch(
        `/history/audio/${encodeURIComponent(recordId)}`
      );
      if (!res.ok) {
        throw new Error(`Audio playback failed (HTTP ${res.status})`);
      }

      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      audioUrlRef.current = url;
      const audio = new Audio(url);

      const clearPlayback = () => {
        setPlayingId(null);
        setAudioPlayer(null);
        releaseAudioUrl();
      };

      audio.onended = clearPlayback;
      audio.onerror = clearPlayback;

      try {
        await audio.play();
        setAudioPlayer(audio);
        setPlayingId(recordId);
      } catch {
        clearPlayback();
      }
    } catch {
      setPlayingId(null);
      setAudioPlayer(null);
      releaseAudioUrl();
    }
  };

  useEffect(() => {
    return () => {
      releaseAudioUrl();
    };
  }, []);

  const handleDelete = async (recordId: string) => {
    try {
      await engineApi.deleteHistoryItem(recordId);
      setRecords((prev) => prev.filter((r) => r.id !== recordId));
    } catch (e) {
      console.error("Failed to delete history record:", e);
    }
  };

  const handleClearAll = async () => {
    setIsClearing(true);
    try {
      await engineApi.clearHistory();
      setRecords([]);
      setShowClearModal(false);
    } catch (e) {
      console.error("Failed to clear history:", e);
    } finally {
      setIsClearing(false);
    }
  };

  const saveTitle = async (recordId: string) => {
    const trimmed = editingTitleText.trim();
    try {
      await engineApi.updateHistoryRecord(recordId, { title: trimmed || null });
      setRecords((prev) =>
        prev.map((r) => (r.id === recordId ? { ...r, title: trimmed || null } : r))
      );
    } catch (e) {
      console.error("Failed to update title:", e);
    } finally {
      setEditingTitleId(null);
    }
  };

  const addTagToRecord = async (recordId: string) => {
    const clean = newTagInput.trim().replace(/^#/, "");
    if (!clean) {
      setAddingTagId(null);
      return;
    }
    const targetRecord = records.find((r) => r.id === recordId);
    const existingTags = targetRecord?.tags || [];
    if (!existingTags.includes(clean)) {
      const updatedTags = [...existingTags, clean];
      try {
        await engineApi.updateHistoryRecord(recordId, { tags: updatedTags });
        setRecords((prev) =>
          prev.map((r) => (r.id === recordId ? { ...r, tags: updatedTags } : r))
        );
      } catch (e) {
        console.error("Failed to add tag:", e);
      }
    }
    setNewTagInput("");
    setAddingTagId(null);
  };

  const removeTagFromRecord = async (recordId: string, tagToRemove: string) => {
    const targetRecord = records.find((r) => r.id === recordId);
    const existingTags = targetRecord?.tags || [];
    const updatedTags = existingTags.filter((t) => t !== tagToRemove);
    try {
      await engineApi.updateHistoryRecord(recordId, { tags: updatedTags });
      setRecords((prev) =>
        prev.map((r) => (r.id === recordId ? { ...r, tags: updatedTags } : r))
      );
    } catch (e) {
      console.error("Failed to remove tag:", e);
    }
  };

  const handleSaveNotes = async (recordId: string, textToSave?: string) => {
    setIsSavingNotesId(recordId);
    const text = textToSave !== undefined ? textToSave : editingNotesText;
    const clean = text.trim();
    const finalNotes = clean.length > 0 ? clean : null;
    try {
      await engineApi.updateHistoryRecord(recordId, { notes: finalNotes });
      setRecords((prev) =>
        prev.map((r) => (r.id === recordId ? { ...r, notes: finalNotes } : r))
      );
    } catch (e) {
      console.error("Failed to save notes:", e);
    } finally {
      setIsSavingNotesId(null);
      setEditingNotesId(null);
    }
  };

  const handleDeleteNotes = async (recordId: string) => {
    try {
      await engineApi.updateHistoryRecord(recordId, { notes: null });
      setRecords((prev) =>
        prev.map((r) => (r.id === recordId ? { ...r, notes: null } : r))
      );
      if (editingNotesId === recordId) {
        setEditingNotesId(null);
        setEditingNotesText("");
      }
    } catch (e) {
      console.error("Failed to delete notes:", e);
    }
  };

  const handleTriggerSummarize = async (record: HistoryRecord) => {
    const recordId = record.id;
    let notesToSend: string | undefined = undefined;

    if (editingNotesId === recordId) {
      const clean = editingNotesText.trim();
      notesToSend = clean.length > 0 ? clean : "";
      await handleSaveNotes(recordId, clean);
    } else if (record.notes) {
      notesToSend = record.notes;
    }

    setSummarizingIds((prev) => new Set(prev).add(recordId));
    setSummarizationErrors((prev) => {
      const copy = { ...prev };
      delete copy[recordId];
      return copy;
    });

    try {
      const provider = localStorage.getItem("llmProvider") || "openrouter";
      const model = localStorage.getItem("llmModel") || "qwen/qwen3.7-plus";
      const baseUrl = localStorage.getItem("llmBaseUrl") || "http://localhost:1234/v1";
      const llmApiKey = localStorage.getItem("llmApiKey") || "";
      const openaiApiKey = localStorage.getItem("openaiApiKey") || "";

      const res = await engineApi.summarizeHistory(recordId, {
        llm_provider: provider,
        llm_model: model,
        llm_base_url: baseUrl,
        llm_api_key: llmApiKey,
        openai_api_key: openaiApiKey,
        notes: notesToSend,
      });

      if (res?.status === "error" || res?.detail) {
        const errorMsg = res?.message || res?.detail || "Failed to generate summary.";
        setSummarizationErrors((prev) => ({ ...prev, [recordId]: errorMsg }));
      } else if (res?.record) {
        setRecords((prev) =>
          prev.map((r) => (r.id === recordId ? { ...r, ...res.record } : r))
        );
      } else if (res?.summary) {
        setRecords((prev) =>
          prev.map((r) => (r.id === recordId ? { ...r, summary: res.summary } : r))
        );
      } else {
        await fetchHistory();
      }
    } catch (e: any) {
      console.error("Failed to summarize history:", e);
      setSummarizationErrors((prev) => ({
        ...prev,
        [recordId]: e?.message || "Network error while summarizing.",
      }));
    } finally {
      setSummarizingIds((prev) => {
        const copy = new Set(prev);
        copy.delete(recordId);
        return copy;
      });
    }
  };

  const openReprocessModal = (record: HistoryRecord) => {
    setReprocessRecord(record);
    const initialMode =
      record.mode === "meeting"
        ? "meeting"
        : record.mode === "focused_meeting"
        ? "focused_meeting"
        : "dictation";
    setReprocessMode(initialMode);
    setFormatStyle("raw");
    setCustomPrompt("");
    setRetranscribeAudio(false);
    setReprocessError(null);
  };

  const handleStartReprocess = async () => {
    if (!reprocessRecord) return;
    setIsReprocessing(true);
    setReprocessError(null);
    try {
      const res = await engineApi.reprocessHistoryItem(reprocessRecord.id, {
        mode: reprocessMode,
        format_style: reprocessMode === "dictation" ? formatStyle : (reprocessMode === "meeting" ? "meeting_summary" : "raw"),
        custom_prompt:
          reprocessMode === "dictation" && formatStyle === "custom" && customPrompt.trim()
            ? customPrompt.trim()
            : undefined,
        retranscribe_audio: retranscribeAudio,
      });
      if (res?.status === "error" || res?.detail) {
        setReprocessError(res?.message || res?.detail || "Failed to re-process recording.");
        return;
      }
      if (res?.record) {
        setRecords((prev) =>
          prev.map((r) => (r.id === reprocessRecord.id ? { ...r, ...res.record } : r))
        );
      } else {
        await fetchHistory();
      }
      setReprocessRecord(null);
      setCustomPrompt("");
    } catch (e: any) {
      console.error("Reprocess error:", e);
      setReprocessError(e?.message || "An unexpected error occurred during re-processing.");
    } finally {
      setIsReprocessing(false);
    }
  };

  const handleReuploadUpdate = async (updateId: string) => {
    setReuploadingId(updateId);
    setReuploadSuccessId(null);
    try {
      await engineApi.reuploadUpdate(updateId);
      setReuploadSuccessId(updateId);
      setTimeout(() => setReuploadSuccessId(null), 3000);
    } catch (e) {
      console.error("Reupload update error:", e);
    } finally {
      setReuploadingId(null);
    }
  };

  const handleDeleteUpdate = async (updateId: string) => {
    try {
      await engineApi.deleteUpdateHistoryItem(updateId);
      setUpdates((prev) => prev.filter((u) => u.id !== updateId));
    } catch (e) {
      console.error("Delete update error:", e);
    }
  };

  const handleClearUpdates = async () => {
    if (!window.confirm("Are you sure you want to clear all Librarian updates history?")) return;
    try {
      await engineApi.clearUpdatesHistory();
      setUpdates([]);
    } catch (e) {
      console.error("Clear updates error:", e);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-6 select-none">
      {/* Segmented Tab Switcher (1:1 with HistoryContainerView in HistoryView.swift:21-25) */}
      <div className="flex justify-center">
        <div className="inline-flex p-1 rounded-xl bg-white/[0.05] border border-white/10 shadow-sm">
          <button
            onClick={() => setSelectedTab("transcription")}
            className={`px-5 py-2 rounded-lg text-xs font-semibold transition-all ${
              selectedTab === "transcription"
                ? "bg-[#5D6658] text-white shadow-md shadow-[#5D6658]/20"
                : "text-white/60 hover:text-white"
            }`}
          >
            Transcription History
          </button>
          <button
            onClick={() => setSelectedTab("librarian")}
            className={`px-5 py-2 rounded-lg text-xs font-semibold transition-all ${
              selectedTab === "librarian"
                ? "bg-[#5D6658] text-white shadow-md shadow-[#5D6658]/20"
                : "text-white/60 hover:text-white"
            }`}
          >
            Librarian Updates
          </button>
        </div>
      </div>

      {/* Header */}
      <div className="flex items-center justify-between">
        <SettingsPageHeader
          title={selectedTab === "transcription" ? "Transcription History" : "Librarian Updates"}
          description={
            selectedTab === "transcription"
              ? "Browse, filter, listen to, and re-process your local speech-to-text dictation archive."
              : "Review resolved knowledge base documents and architectural updates published by Librarian."
          }
          helpTopic="history"
        />

        <div className="flex items-center gap-2">
          <button
            onClick={selectedTab === "transcription" ? fetchHistory : fetchUpdates}
            disabled={isLoadingHistory || isLoadingUpdates}
            className="p-2 rounded-xl bg-white/[0.04] hover:bg-white/10 text-white/70 hover:text-white border border-white/10 transition-all"
            title="Refresh"
          >
            <RefreshCw
              className={`w-4 h-4 ${
                (isLoadingHistory || isLoadingUpdates) && "animate-spin text-emerald-400"
              }`}
            />
          </button>

          {selectedTab === "transcription" && records.length > 0 && (
            <button
              onClick={() => setShowClearModal(true)}
              className="px-3 py-1.5 rounded-xl bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 text-xs font-medium transition-all flex items-center gap-1.5"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span>Clear History</span>
            </button>
          )}

          {selectedTab === "librarian" && updates.length > 0 && (
            <button
              onClick={handleClearUpdates}
              className="px-3 py-1.5 rounded-xl bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 text-xs font-medium transition-all flex items-center gap-1.5"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span>Clear Updates</span>
            </button>
          )}
        </div>
      </div>

      {/* ========================================================================= */}
      {/* 1. TRANSCRIPTION HISTORY TAB                                              */}
      {/* ========================================================================= */}
      {selectedTab === "transcription" && (
        <>
          {/* Search & Label Filters Bar */}
          <div className="flex items-center gap-3">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-white/40" />
              <input
                type="text"
                placeholder="Search dictation history or #tag..."
                value={searchText}
                onChange={(e) => setSearchText(e.target.value)}
                className="w-full bg-white/[0.04] border border-white/10 rounded-xl pl-9 pr-8 py-2 text-xs text-white placeholder-white/40 focus:outline-none focus:border-[#5D6658] transition-colors"
              />
              {searchText && (
                <button
                  onClick={() => setSearchText("")}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-white/40 hover:text-white"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              )}
            </div>

            {/* Filter by Labels Popover */}
            <div className="relative">
              <button
                onClick={() => setShowFilterPopover(!showFilterPopover)}
                className={`px-3 py-2 rounded-xl text-xs font-medium border flex items-center gap-2 transition-all ${
                  selectedTags.length > 0
                    ? "bg-[#5D6658]/30 border-[#5D6658] text-white shadow"
                    : "bg-white/[0.04] border-white/10 text-white/70 hover:bg-white/10"
                }`}
              >
                <Filter className="w-3.5 h-3.5" />
                <span>{selectedTags.length > 0 ? `Tags (${selectedTags.length})` : "Filter by Tags"}</span>
                <ChevronDown className="w-3 h-3 opacity-60" />
              </button>

              {showFilterPopover && (
                <div className="absolute right-0 mt-2 w-64 p-3 rounded-xl bg-[#1A1D23] border border-white/15 shadow-2xl z-30 space-y-2">
                  <div className="flex items-center justify-between pb-2 border-b border-white/10">
                    <div className="flex items-center gap-1.5 text-xs font-semibold text-white">
                      <Tag className="w-3 h-3 text-[#87B996]" />
                      <span>Filter by Labels</span>
                    </div>
                    {selectedTags.length > 0 && (
                      <button
                        onClick={() => setSelectedTags([])}
                        className="text-[10px] text-red-400 hover:underline font-semibold"
                      >
                        Reset
                      </button>
                    )}
                  </div>

                  {availableTags.length === 0 ? (
                    <div className="text-[11px] text-white/40 py-3 text-center">
                      No labels found in history.
                    </div>
                  ) : (
                    <div className="max-h-48 overflow-y-auto space-y-1 pr-1">
                      {availableTags.map(([tag, count]) => {
                        const isSelected = selectedTags.includes(tag);
                        return (
                          <button
                            key={tag}
                            onClick={() => toggleTagFilter(tag)}
                            className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-lg text-xs transition-all ${
                              isSelected
                                ? "bg-white/10 text-white font-medium"
                                : "text-white/70 hover:bg-white/5"
                            }`}
                          >
                            <div className="flex items-center gap-2">
                              <span
                                className={`w-3.5 h-3.5 rounded flex items-center justify-center border text-[9px] ${
                                  isSelected
                                    ? "bg-[#5D6658] border-[#5D6658] text-white"
                                    : "border-white/30"
                                }`}
                              >
                                {isSelected && "✓"}
                              </span>
                              <span>#{tag}</span>
                            </div>
                            <span className="text-[10px] px-1.5 py-0.5 rounded bg-white/5 text-white/40 font-mono">
                              {count}
                            </span>
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Filter by App Dropdown */}
            {availableApps.length > 0 && (
              <div className="relative">
                <select
                  value={selectedApp || ""}
                  onChange={(e) => setSelectedApp(e.target.value || null)}
                  className="px-3 py-2 rounded-xl text-xs font-medium bg-white/[0.04] border border-white/10 text-white/80 hover:bg-white/10 focus:outline-none transition-all cursor-pointer"
                >
                  <option value="" className="bg-[#1A1D23] text-white">All Apps</option>
                  {availableApps.map(([app, count]) => (
                    <option key={app} value={app} className="bg-[#1A1D23] text-white">
                      {app} ({count})
                    </option>
                  ))}
                </select>
              </div>
            )}

            {/* Reset Filters */}
            {(selectedTags.length > 0 || selectedApp) && (
              <button
                onClick={() => {
                  setSelectedTags([]);
                  setSelectedApp(null);
                }}
                className="px-3 py-2 rounded-xl text-xs font-medium border border-white/10 hover:bg-white/10 text-white/70 transition-all flex items-center gap-1.5"
              >
                <RotateCcw className="w-3.5 h-3.5" />
                <span>Reset</span>
              </button>
            )}
          </div>

          {/* Records List */}
          {isLoadingHistory ? (
            <div className="py-24 text-center space-y-3">
              <RefreshCw className="w-8 h-8 mx-auto animate-spin text-[#87B996]" />
              <div className="text-xs text-white/50">Loading transcription history...</div>
            </div>
          ) : filteredRecords.length === 0 ? (
            <div className="py-24 text-center space-y-3">
              <div className="w-14 h-14 rounded-2xl bg-white/[0.03] border border-white/10 flex items-center justify-center mx-auto text-white/30">
                <Clock className="w-7 h-7" />
              </div>
              <div className="text-sm font-semibold text-white/60">No History Found</div>
              <p className="text-xs text-white/40 max-w-xs mx-auto">
                {searchText || selectedTags.length > 0
                  ? "No transcripts match your current search or label filters."
                  : "Dictated speech from your hotkey will be permanently archived and cataloged here."}
              </p>
            </div>
          ) : (
            <div className="space-y-3.5">
              {filteredRecords.map((record) => {
                const isExpanded = expandedIds.has(record.id);
                const isPlaying = playingId === record.id;
                const hasAudio = Boolean(record.has_audio || record.audio_file);

                return (
                  <div
                    key={record.id}
                    onClick={() => toggleExpand(record.id)}
                    className={`p-5 rounded-2xl transition-all border cursor-pointer ${
                      isExpanded
                        ? "bg-white/[0.05] border-white/20 shadow-xl shadow-black/40"
                        : "bg-white/[0.025] border-white/10 hover:border-white/20 hover:bg-white/[0.04]"
                    }`}
                  >
                    {/* Header Row */}
                    <div
                      className="flex items-center justify-between"
                    >
                      <div className="flex items-center gap-2.5">
                        <span className="text-[11px] font-bold text-white/40 tracking-wide">
                          {formatRecordDate(record.timestamp)}
                        </span>
                        {record.credits_used ? (
                          <span className="flex items-center gap-1 text-[10px] font-bold text-amber-400 bg-amber-500/15 border border-amber-500/20 px-2 py-0.5 rounded-full">
                            <Zap className="w-2.5 h-2.5" />
                            {record.credits_used}
                          </span>
                        ) : null}
                        {record.duration_seconds ? (
                          <span className="text-[10px] text-white/40 font-mono">
                            {Math.round(record.duration_seconds)}s
                          </span>
                        ) : null}
                        {(record.target_app_name || record.app_id) && (
                          <span
                            className="inline-flex items-center gap-1 text-[10px] font-medium text-emerald-300 bg-emerald-500/10 border border-emerald-500/20 px-2 py-0.5 rounded-full"
                            title={record.app_id ? `Target process: ${record.app_id}` : undefined}
                          >
                            <span>{record.target_app_name || record.app_id}</span>
                            {record.resolution_source && record.resolution_source !== "manual_override" && (
                              <span className="text-[9px] text-emerald-400/60 font-normal">auto</span>
                            )}
                          </span>
                        )}
                      </div>

                      <div className="flex items-center gap-2">
                        <span
                          className={`text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-md border ${
                            record.mode === "dictation"
                              ? "bg-emerald-500/15 text-emerald-400 border-emerald-500/20"
                              : record.mode === "librarian"
                              ? "bg-indigo-500/15 text-indigo-300 border-indigo-500/20"
                              : "bg-amber-500/15 text-amber-400 border-amber-500/20"
                          }`}
                        >
                          {(record.mode || "dictation").replace("_", " ")}
                        </span>
                        <button className="text-white/40 hover:text-white p-0.5">
                          {isExpanded ? (
                            <ChevronUp className="w-4 h-4" />
                          ) : (
                            <ChevronDown className="w-4 h-4" />
                          )}
                        </button>
                      </div>
                    </div>

                    {/* Title View (Inline Editable) */}
                    <div className="mt-3" onClick={(e) => { if (editingTitleId === record.id) e.stopPropagation(); }}>
                      {editingTitleId === record.id ? (
                        <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
                          <input
                            type="text"
                            value={editingTitleText}
                            onChange={(e) => setEditingTitleText(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === "Enter") saveTitle(record.id);
                              if (e.key === "Escape") setEditingTitleId(null);
                            }}
                            autoFocus
                            placeholder="Card title..."
                            className="flex-1 bg-black/40 border border-white/20 rounded-lg px-2.5 py-1 text-xs text-white focus:outline-none focus:border-[#5D6658]"
                          />
                          <button
                            onClick={() => saveTitle(record.id)}
                            className="p-1 text-emerald-400 hover:text-emerald-300"
                          >
                            <Check className="w-3.5 h-3.5" />
                          </button>
                          <button
                            onClick={() => setEditingTitleId(null)}
                            className="p-1 text-white/40 hover:text-white"
                          >
                            <X className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      ) : (
                        <div className="flex items-center gap-2 group">
                          <h4
                            onClick={(e) => {
                              e.stopPropagation();
                              setEditingTitleId(record.id);
                              setEditingTitleText(record.title || "");
                            }}
                            className="text-sm font-semibold text-white tracking-tight cursor-pointer hover:text-indigo-300 transition-colors"
                          >
                            {record.title || "Untitled Recording"}
                          </h4>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              setEditingTitleId(record.id);
                              setEditingTitleText(record.title || "");
                            }}
                            className="opacity-0 group-hover:opacity-100 text-white/40 hover:text-white transition-opacity p-0.5"
                          >
                            <Pencil className="w-3 h-3" />
                          </button>

                          {/* Add Notes shortcut button if record has no notes and not editing */}
                          {(!record.notes || record.notes.trim() === "") && editingNotesId !== record.id && (
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                setEditingNotesId(record.id);
                                setEditingNotesText("");
                                if (!isExpanded) toggleExpand(record.id);
                              }}
                              className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-white/[0.04] hover:bg-white/10 text-[11px] text-white/50 hover:text-white transition-all ml-1 border border-white/5"
                              title="Add personal notes or context before summarizing"
                            >
                              <FileEdit className="w-3 h-3 text-[#87B996]" />
                              <span>Add Notes</span>
                            </button>
                          )}
                        </div>
                      )}
                    </div>

                    {/* Notes Section (Inline Editable & Display) */}
                    {editingNotesId === record.id ? (
                      <div
                        className="mt-3 p-3.5 rounded-xl bg-[#5D6658]/15 border border-[#5D6658]/30 space-y-2.5"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <div className="flex items-center justify-between text-[#87B996] font-bold text-[11px]">
                          <div className="flex items-center gap-1.5">
                            <StickyNote className="w-3.5 h-3.5 text-[#87B996]" />
                            <span>Notes</span>
                          </div>
                          <span className="text-[10px] text-white/40 font-normal">
                            Optional context for AI summary
                          </span>
                        </div>
                        <textarea
                          value={editingNotesText}
                          onChange={(e) => setEditingNotesText(e.target.value)}
                          placeholder="Add attendees, project context, key points, or acronyms for the LLM..."
                          rows={3}
                          className="w-full bg-black/40 border border-[#5D6658]/40 rounded-lg p-2.5 text-xs text-white placeholder-white/40 focus:outline-none focus:border-[#87B996] resize-y leading-relaxed"
                          autoFocus
                        />
                        <div className="flex items-center justify-end gap-2">
                          <button
                            onClick={() => {
                              setEditingNotesId(null);
                              setEditingNotesText("");
                            }}
                            className="px-2.5 py-1 rounded-md text-[11px] font-medium text-white/60 hover:text-white transition-colors"
                          >
                            Cancel
                          </button>
                          <button
                            onClick={() => handleSaveNotes(record.id)}
                            disabled={isSavingNotesId === record.id}
                            className="flex items-center gap-1.5 px-3 py-1 rounded-md bg-[#5D6658] hover:bg-[#6D7767] text-white text-[11px] font-semibold transition-all disabled:opacity-50"
                          >
                            {isSavingNotesId === record.id ? (
                              <RefreshCw className="w-3 h-3 animate-spin" />
                            ) : (
                              <Check className="w-3 h-3" />
                            )}
                            <span>Save Notes</span>
                          </button>
                        </div>
                      </div>
                    ) : record.notes && record.notes.trim() !== "" ? (
                      <div
                        className="mt-3 p-3.5 rounded-xl bg-[#5D6658]/10 border border-[#5D6658]/25 text-xs text-emerald-100/90 space-y-2 cursor-pointer hover:border-[#5D6658]/40 transition-colors"
                        onClick={(e) => {
                          e.stopPropagation();
                          setEditingNotesId(record.id);
                          setEditingNotesText(record.notes || "");
                        }}
                      >
                        <div className="flex items-center justify-between text-[#87B996] font-bold text-[11px]">
                          <div className="flex items-center gap-1.5">
                            <StickyNote className="w-3.5 h-3.5 text-[#87B996]" />
                            <span>Notes</span>
                          </div>
                          <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
                            <button
                              onClick={() => {
                                setEditingNotesId(record.id);
                                setEditingNotesText(record.notes || "");
                              }}
                              className="text-[#87B996] hover:text-white flex items-center gap-1 text-[11px] font-medium transition-colors"
                            >
                              <Pencil className="w-3 h-3" />
                              <span>Edit</span>
                            </button>
                            <button
                              onClick={() => handleDeleteNotes(record.id)}
                              className="text-white/40 hover:text-red-400 p-0.5 transition-colors"
                              title="Remove notes"
                            >
                              <X className="w-3 h-3" />
                            </button>
                          </div>
                        </div>
                        <div className={`leading-relaxed text-white/90 whitespace-pre-wrap ${!isExpanded && "line-clamp-2"}`}>
                          {record.notes}
                        </div>
                      </div>
                    ) : null}

                    {/* Tags Display */}
                    <div className="flex flex-wrap items-center gap-1.5 mt-2" onClick={(e) => e.stopPropagation()}>
                      {record.tags?.map((t) => (
                        <span
                          key={t}
                          className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-white/[0.06] border border-white/10 text-[10px] text-white/70"
                        >
                          <span>#{t.replace(/^#/, "")}</span>
                          {isExpanded && (
                            <button
                              onClick={() => removeTagFromRecord(record.id, t)}
                              className="text-white/40 hover:text-white"
                            >
                              <X className="w-2.5 h-2.5" />
                            </button>
                          )}
                        </span>
                      ))}

                      {isExpanded && (
                        <>
                          {addingTagId === record.id ? (
                            <div className="inline-flex items-center gap-1">
                              <input
                                type="text"
                                value={newTagInput}
                                onChange={(e) => setNewTagInput(e.target.value)}
                                onKeyDown={(e) => {
                                  if (e.key === "Enter") addTagToRecord(record.id);
                                  if (e.key === "Escape") setAddingTagId(null);
                                }}
                                autoFocus
                                placeholder="tag..."
                                className="w-20 bg-black/40 border border-white/20 rounded px-1.5 py-0.5 text-[11px] text-white focus:outline-none"
                              />
                              <button
                                onClick={() => addTagToRecord(record.id)}
                                className="text-emerald-400 hover:text-emerald-300"
                              >
                                <Plus className="w-3 h-3" />
                              </button>
                              <button
                                onClick={() => setAddingTagId(null)}
                                className="text-white/40 hover:text-white"
                              >
                                <X className="w-3 h-3" />
                              </button>
                            </div>
                          ) : (
                            <button
                              onClick={() => {
                                setAddingTagId(record.id);
                                setNewTagInput("");
                              }}
                              className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-white/[0.04] border border-white/10 text-[10px] text-white/50 hover:text-white hover:bg-white/10"
                            >
                              <Plus className="w-2.5 h-2.5" />
                              <span>Tag</span>
                            </button>
                          )}
                        </>
                      )}
                    </div>

                    {/* Summary Box (if present) */}
                    {record.summary && (() => {
                      const isSummaryMd = renderMarkdown[record.id + "_sum"] ?? true;
                      return (
                        <div className="mt-3 p-3.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-xs text-amber-200/90 space-y-2">
                          <div className="flex items-center justify-between text-amber-400 font-bold text-[10px] uppercase tracking-wider">
                            <span className="flex items-center gap-1.5">
                              <Sparkles className="w-3.5 h-3.5" />
                              Summary
                            </span>
                            <div className="flex items-center gap-3">
                              {/* Raw Text / Markdown Toggle Button */}
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setRenderMarkdown((prev) => ({
                                    ...prev,
                                    [record.id + "_sum"]: !isSummaryMd,
                                  }));
                                }}
                                className="text-amber-300/80 hover:text-amber-100 flex items-center gap-1 font-medium text-[11px] transition-colors normal-case"
                              >
                                <AlignLeft className="w-3 h-3" />
                                <span>{isSummaryMd ? "Raw Text" : "Markdown"}</span>
                              </button>

                              {/* Copy Summary Button */}
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleCopy(record.id + "_sum", record.summary!);
                                }}
                                className="text-amber-300/80 hover:text-amber-100 flex items-center gap-1 font-medium text-[11px] transition-colors normal-case"
                              >
                                {copiedId === record.id + "_sum" ? (
                                  <Check className="w-3 h-3 text-emerald-400" />
                                ) : (
                                  <Copy className="w-3 h-3" />
                                )}
                                <span>{copiedId === record.id + "_sum" ? "Copied" : "Copy"}</span>
                              </button>

                              {/* Re-summarize Button in Summary Box */}
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleTriggerSummarize(record);
                                }}
                                disabled={summarizingIds.has(record.id)}
                                className="text-amber-300/80 hover:text-amber-100 flex items-center gap-1 font-medium text-[11px] transition-colors normal-case disabled:opacity-50"
                              >
                                {summarizingIds.has(record.id) ? (
                                  <RefreshCw className="w-3 h-3 animate-spin" />
                                ) : (
                                  <RefreshCw className="w-3 h-3" />
                                )}
                                <span>{summarizingIds.has(record.id) ? "Summarizing..." : "Re-summarize"}</span>
                              </button>
                            </div>
                          </div>
                          <div className={`leading-relaxed ${!isExpanded && "line-clamp-2"}`}>
                            {isSummaryMd ? (
                              <RichMarkdownDocumentView content={record.summary} />
                            ) : (
                              <pre className="font-mono text-xs text-amber-100/90 whitespace-pre-wrap select-text bg-black/20 p-2.5 rounded-lg border border-amber-500/15 leading-relaxed">
                                {record.summary}
                              </pre>
                            )}
                          </div>
                        </div>
                      );
                    })()}

                    {/* Summarization Error Banner */}
                    {summarizationErrors[record.id] && (
                      <div className="mt-2.5 px-3 py-2 rounded-lg bg-red-500/10 border border-red-500/20 text-red-300 text-xs flex items-center gap-2">
                        <AlertTriangle className="w-3.5 h-3.5 shrink-0 text-red-400" />
                        <span>{summarizationErrors[record.id]}</span>
                      </div>
                    )}

                    {/* Transcript Text */}
                    <div className="mt-3">
                      <div
                        className={`text-xs text-white/80 leading-relaxed font-sans select-text whitespace-pre-wrap ${
                          !isExpanded && "line-clamp-3"
                        }`}
                      >
                        {record.text}
                      </div>
                    </div>

                    {/* Expanded Action Toolbar */}
                    {isExpanded && (
                      <div
                        onClick={(e) => e.stopPropagation()}
                        className="mt-4 pt-3 border-t border-white/10 flex items-center justify-between text-xs"
                      >
                        <div className="flex items-center gap-2.5">
                          {/* Play Audio Button */}
                          <button
                            onClick={() => togglePlayback(record.id)}
                            disabled={!hasAudio}
                            className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg transition-all ${
                              !hasAudio
                                ? "opacity-30 cursor-not-allowed text-white/40"
                                : isPlaying
                                ? "bg-red-500/20 text-red-300 border border-red-500/30"
                                : "bg-indigo-500/15 text-indigo-300 hover:bg-indigo-500/25 border border-indigo-500/20"
                            }`}
                          >
                            {isPlaying ? (
                              <>
                                <Square className="w-3 h-3" />
                                <span>Stop</span>
                              </>
                            ) : (
                              <>
                                <Play className="w-3 h-3" />
                                <span>{hasAudio ? "Play Audio" : "No Audio"}</span>
                              </>
                            )}
                          </button>

                          {/* Copy Text Button */}
                          <button
                            onClick={() => handleCopy(record.id, record.text)}
                            className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-white/[0.05] hover:bg-white/10 text-white/80 transition-all border border-white/10"
                          >
                            {copiedId === record.id ? (
                              <Check className="w-3 h-3 text-emerald-400" />
                            ) : (
                              <Copy className="w-3 h-3" />
                            )}
                            <span>{copiedId === record.id ? "Copied" : "Copy"}</span>
                          </button>

                          {/* Summarize / Re-summarize Button */}
                          <button
                            onClick={() => handleTriggerSummarize(record)}
                            disabled={summarizingIds.has(record.id)}
                            className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg transition-all border ${
                              summarizingIds.has(record.id)
                                ? "opacity-50 cursor-not-allowed bg-amber-500/10 text-amber-300 border-amber-500/20"
                                : "bg-amber-500/15 hover:bg-amber-500/25 text-amber-300 border-amber-500/30"
                            }`}
                            title="Generate AI summary of this meeting transcript and notes"
                          >
                            {summarizingIds.has(record.id) ? (
                              <RefreshCw className="w-3 h-3 animate-spin text-amber-400" />
                            ) : (
                              <Sparkles className="w-3 h-3 text-amber-400" />
                            )}
                            <span>
                              {summarizingIds.has(record.id)
                                ? "Summarizing..."
                                : record.summary
                                ? "Re-summarize"
                                : "Summarize"}
                            </span>
                          </button>

                          {/* Re-process Modal Trigger */}
                          <button
                            onClick={() => openReprocessModal(record)}
                            className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[#5D6658]/20 hover:bg-[#5D6658]/30 text-[#87B996] transition-all border border-[#5D6658]/40"
                          >
                            <RefreshCw className="w-3 h-3" />
                            <span>Re-process</span>
                          </button>
                        </div>

                        {/* Delete Card */}
                        <button
                          onClick={() => handleDelete(record.id)}
                          className="flex items-center gap-1 text-red-400/80 hover:text-red-400 px-2 py-1 rounded hover:bg-red-500/10 transition-all"
                        >
                          <Trash2 className="w-3 h-3" />
                          <span>Delete</span>
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}

      {/* ========================================================================= */}
      {/* 2. LIBRARIAN UPDATES TAB (1:1 with UpdatesHistoryView in KnowledgeBase)   */}
      {/* ========================================================================= */}
      {selectedTab === "librarian" && (
        <div className="space-y-4">
          {isLoadingUpdates ? (
            <div className="py-24 text-center space-y-3">
              <RefreshCw className="w-8 h-8 mx-auto animate-spin text-[#87B996]" />
              <div className="text-xs text-white/50">Loading Librarian updates...</div>
            </div>
          ) : updates.length === 0 ? (
            <div className="py-24 text-center space-y-3">
              <div className="w-14 h-14 rounded-2xl bg-white/[0.03] border border-white/10 flex items-center justify-center mx-auto text-white/30">
                <BookOpen className="w-7 h-7" />
              </div>
              <div className="text-sm font-semibold text-white/60">No Updates History Yet</div>
              <p className="text-xs text-white/40 max-w-sm mx-auto">
                Documents approved or merged through the Librarian voice pipeline will be documented here.
              </p>
            </div>
          ) : (
            <div className="space-y-4">
              {updates.map((update) => {
                const isExpanded = expandedUpdateIds.has(update.id);
                const isMd = renderMarkdown[update.id] ?? true;
                const isReuploading = reuploadingId === update.id;
                const isReuploadSuccess = reuploadSuccessId === update.id;

                return (
                  <div
                    key={update.id}
                    onClick={() => toggleExpandUpdate(update.id)}
                    className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 hover:border-white/15 hover:bg-white/[0.04] transition-all space-y-3.5 cursor-pointer"
                  >
                    {/* Header Row */}
                    <div className="flex items-start justify-between gap-4">
                      <div>
                        <h4 className="text-base font-bold text-white tracking-tight">
                          {update.title}
                        </h4>
                        <span className="text-[11px] text-white/40 block mt-0.5">
                          {formatRecordDate(update.resolved_at || update.timestamp)}
                        </span>
                      </div>

                      <div className="flex items-center gap-2 flex-shrink-0" onClick={(e) => e.stopPropagation()}>
                        {/* Markdown / Raw Toggle */}
                        <button
                          onClick={() =>
                            setRenderMarkdown((prev) => ({
                              ...prev,
                              [update.id]: !isMd,
                            }))
                          }
                          className="px-2.5 py-1 rounded-lg bg-white/[0.05] hover:bg-white/10 text-white/80 border border-white/10 text-xs font-medium transition-all flex items-center gap-1.5"
                        >
                          <FileText className="w-3 h-3 text-[#87B996]" />
                          <span>{isMd ? "Raw Text" : "Markdown"}</span>
                        </button>

                        {/* Target Type Badge */}
                        <span className="text-xs px-2.5 py-1 rounded-lg bg-[#5D6658]/20 text-[#87B996] border border-[#5D6658]/40 font-medium">
                          Target: {update.target_type === "obsidian" ? "Local Data" : update.target_type.toUpperCase()}
                        </span>

                        {/* Status Badge */}
                        <span
                          className={`text-xs px-2.5 py-1 rounded-lg font-bold capitalize border ${
                            update.status === "approved"
                              ? "bg-emerald-500/15 text-emerald-400 border-emerald-500/25"
                              : update.status === "rejected"
                              ? "bg-red-500/15 text-red-400 border-red-500/25"
                              : "bg-amber-500/15 text-amber-400 border-amber-500/25"
                          }`}
                        >
                          {update.status}
                        </span>

                        {/* Expand Button */}
                        <button
                          onClick={() => toggleExpandUpdate(update.id)}
                          className="p-1 text-white/40 hover:text-white"
                        >
                          {isExpanded ? (
                            <ChevronUp className="w-4 h-4" />
                          ) : (
                            <ChevronDown className="w-4 h-4" />
                          )}
                        </button>
                      </div>
                    </div>

                    {/* Proposed Content View */}
                    <div className="pt-2">
                      {isMd ? (
                        <div
                          className={`bg-black/30 border border-white/10 rounded-xl p-4 overflow-hidden transition-all ${
                            !isExpanded && "max-h-48 relative"
                          }`}
                        >
                          <RichMarkdownDocumentView content={update.proposed_content} />
                          {!isExpanded && (
                            <div className="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-[#16181D] to-transparent pointer-events-none" />
                          )}
                        </div>
                      ) : (
                        <pre
                          className={`text-xs font-mono whitespace-pre-wrap text-white/80 bg-black/40 border border-white/10 rounded-xl p-4 overflow-x-auto ${
                            !isExpanded && "max-h-40 overflow-hidden"
                          }`}
                        >
                          {update.proposed_content}
                        </pre>
                      )}
                    </div>

                    {/* Action Footer */}
                    <div className="pt-2 flex items-center justify-between text-xs" onClick={(e) => e.stopPropagation()}>
                      <div className="flex items-center gap-3">
                        <button
                          onClick={() => handleCopy(update.id + "_content", update.proposed_content)}
                          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-white/[0.04] hover:bg-white/10 text-white/80 border border-white/10 transition-all"
                        >
                          {copiedId === update.id + "_content" ? (
                            <Check className="w-3.5 h-3.5 text-emerald-400" />
                          ) : (
                            <Copy className="w-3.5 h-3.5" />
                          )}
                          <span>{copiedId === update.id + "_content" ? "Copied" : "Copy Document"}</span>
                        </button>

                        <button
                          onClick={() => handleReuploadUpdate(update.id)}
                          disabled={isReuploading}
                          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#5D6658]/20 hover:bg-[#5D6658]/30 text-[#87B996] border border-[#5D6658]/40 transition-all font-medium disabled:opacity-50"
                        >
                          <RefreshCw className={`w-3.5 h-3.5 ${isReuploading ? "animate-spin" : ""}`} />
                          <span>{isReuploading ? "Syncing..." : isReuploadSuccess ? "Synced!" : "Re-Upload / Sync"}</span>
                        </button>

                        <button
                          onClick={() => handleDeleteUpdate(update.id)}
                          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 transition-all font-medium"
                          title="Delete update"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                          <span>Delete</span>
                        </button>
                      </div>

                      <button
                        onClick={() => toggleExpandUpdate(update.id)}
                        className="text-xs text-white/50 hover:text-white underline underline-offset-2"
                      >
                        {isExpanded ? "Collapse View" : "Expand Full Document"}
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* Clear All History Confirmation Modal */}
      {showClearModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-md z-50 flex items-center justify-center p-4">
          <div className="w-full max-w-sm bg-[#1A1D23] border border-white/15 rounded-2xl p-6 shadow-2xl space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-red-500/10 border border-red-500/20 flex items-center justify-center text-red-400 flex-shrink-0">
                <AlertTriangle className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-base font-bold text-white">Clear All History?</h3>
                <span className="text-[11px] text-white/40">
                  Total records: {records.length}
                </span>
              </div>
            </div>

            <p className="text-xs text-white/70 leading-relaxed">
              Are you sure you want to permanently delete all transcription history? All records will be wiped from local storage and cannot be restored.
            </p>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                onClick={() => setShowClearModal(false)}
                className="px-4 py-1.5 rounded-xl text-xs font-medium text-white/60 hover:text-white"
              >
                Cancel
              </button>
              <button
                onClick={handleClearAll}
                disabled={isClearing}
                className="px-4 py-1.5 rounded-xl text-xs font-semibold bg-red-500 hover:bg-red-600 text-white shadow transition-all disabled:opacity-50"
              >
                {isClearing ? "Clearing..." : "Delete All"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reprocess Sheet Modal (1:1 with SwiftUI ReprocessModalSheet) */}
      {reprocessRecord && (
        <div className="fixed inset-0 bg-black/75 backdrop-blur-md z-50 flex items-center justify-center p-4">
          <div className="w-full max-w-[500px] bg-[#1a1d22] border border-white/15 rounded-2xl p-6 shadow-2xl space-y-4 select-none animate-in fade-in zoom-in-95 duration-150">
            {/* Modal Header */}
            <div className="flex items-start justify-between">
              <div className="space-y-1">
                <div className="flex items-center gap-2.5">
                  <RotateCcw className="w-5 h-5 text-[#87B996]" />
                  <h3 className="text-lg font-bold text-white tracking-tight">Re-process Recording</h3>
                </div>
                <p className="text-xs text-white/50">
                  Change category, formatting structure, or prompt without speaking again.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setReprocessRecord(null)}
                className="w-7 h-7 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center text-white/60 hover:text-white transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Current Transcript Box */}
            <div className="bg-black/35 border border-white/10 rounded-xl p-3.5 space-y-1">
              <span className="text-[10px] font-bold tracking-wider uppercase text-white/40 block">
                CURRENT TRANSCRIPT
              </span>
              <p className="text-xs text-white/90 leading-relaxed line-clamp-3 font-sans select-text">
                {reprocessRecord.text}
              </p>
            </div>

            {/* Target Mode Segmented Control */}
            <div className="space-y-2">
              <span className="text-[11px] font-bold tracking-wider uppercase text-white/50 block">
                TARGET MODE
              </span>
              <div className="grid grid-cols-3 gap-1.5 p-1 bg-black/40 border border-white/10 rounded-xl">
                {[
                  { id: "dictation", label: "Dictation" },
                  { id: "meeting", label: "Meeting" },
                  { id: "focused_meeting", label: "Focused Meeting" },
                ].map((tab) => {
                  const isActive = reprocessMode === tab.id;
                  return (
                    <button
                      key={tab.id}
                      type="button"
                      onClick={() => setReprocessMode(tab.id as any)}
                      className={`py-2 px-3 rounded-lg text-xs font-semibold text-center transition-all ${
                        isActive
                          ? "bg-[#87B996] text-black shadow-sm"
                          : "text-white/60 hover:text-white hover:bg-white/[0.04]"
                      }`}
                    >
                      {tab.label}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Formatting Style (when Dictation) */}
            {reprocessMode === "dictation" && (
              <div className="space-y-2">
                <span className="text-[11px] font-bold tracking-wider uppercase text-white/50 block">
                  FORMATTING STYLE
                </span>
                <div className="relative">
                  <select
                    value={formatStyle}
                    onChange={(e) => setFormatStyle(e.target.value as any)}
                    className="w-full bg-black/40 border border-white/10 rounded-xl px-3.5 py-2.5 text-xs text-white appearance-none cursor-pointer focus:outline-none focus:border-[#87B996]"
                  >
                    <option value="raw" className="bg-[#1a1d22] text-white">Raw / Verbatim</option>
                    <option value="note" className="bg-[#1a1d22] text-white">Structured Note</option>
                    <option value="email" className="bg-[#1a1d22] text-white">Professional Email</option>
                    <option value="message" className="bg-[#1a1d22] text-white">Chat Message</option>
                    <option value="book" className="bg-[#1a1d22] text-white">Book Prose</option>
                    <option value="custom" className="bg-[#1a1d22] text-white">Custom Prompt...</option>
                  </select>
                  <div className="absolute right-3.5 top-1/2 -translate-y-1/2 pointer-events-none text-white/40 flex flex-col items-center">
                    <ChevronUp className="w-2.5 h-2.5 -mb-0.5" />
                    <ChevronDown className="w-2.5 h-2.5 -mt-0.5" />
                  </div>
                </div>
              </div>
            )}

            {/* Custom Prompt Instructions (when Dictation + Custom) */}
            {reprocessMode === "dictation" && formatStyle === "custom" && (
              <div className="space-y-1.5">
                <span className="text-[11px] font-bold tracking-wider uppercase text-white/50 block">
                  CUSTOM PROMPT INSTRUCTIONS
                </span>
                <textarea
                  value={customPrompt}
                  onChange={(e) => setCustomPrompt(e.target.value)}
                  rows={3}
                  placeholder="Enter custom instructions (e.g., 'Summarize in 3 bullet points with Spanish translation')."
                  className="w-full bg-black/40 border border-white/10 rounded-xl p-3 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#87B996] resize-none"
                />
                <span className="text-[10px] text-white/40 block">
                  Enter custom instructions (e.g., 'Summarize in 3 bullet points with Spanish translation').
                </span>
              </div>
            )}

            {/* Processing Engine */}
            <div className="space-y-2">
              <span className="text-[11px] font-bold tracking-wider uppercase text-white/50 block">
                PROCESSING ENGINE
              </span>
              <div className="grid grid-cols-2 gap-1.5 p-1 bg-black/40 border border-white/10 rounded-xl">
                <button
                  type="button"
                  onClick={() => setRetranscribeAudio(false)}
                  className={`py-2 px-3 rounded-lg text-xs font-semibold text-center transition-all ${
                    !retranscribeAudio
                      ? "bg-[#87B996] text-black shadow-sm"
                      : "text-white/60 hover:text-white hover:bg-white/[0.04]"
                  }`}
                >
                  Fast Re-Format (LLM)
                </button>
                <button
                  type="button"
                  onClick={() => setRetranscribeAudio(true)}
                  className={`py-2 px-3 rounded-lg text-xs font-semibold text-center transition-all ${
                    retranscribeAudio
                      ? "bg-[#87B996] text-black shadow-sm"
                      : "text-white/60 hover:text-white hover:bg-white/[0.04]"
                  }`}
                >
                  {reprocessRecord.has_audio || reprocessRecord.audio_file
                    ? "Full Re-Transcribe (Audio)"
                    : "Full Re-Transcribe (No Audio)"}
                </button>
              </div>

              {!retranscribeAudio ? (
                <p className="text-[11px] text-white/40 leading-normal">
                  {reprocessRecord.has_audio || reprocessRecord.audio_file
                    ? "Restructures existing transcript with LLM. Fast & zero audio lag."
                    : "Restructures existing transcript with LLM (original audio was deleted or scrubbed)."}
                </p>
              ) : (
                <p className={`text-[11px] leading-normal ${
                  reprocessRecord.has_audio || reprocessRecord.audio_file
                    ? "text-white/40"
                    : "text-amber-400 font-medium"
                }`}>
                  {reprocessRecord.has_audio || reprocessRecord.audio_file
                    ? "Re-runs speech recognition from audio file. Useful if words were misheard or you changed models."
                    : "⚠️ Audio file is not available because it was scrubbed by retention policy."}
                </p>
              )}
            </div>

            {/* Error Banner */}
            {reprocessError && (
              <div className="p-3 bg-red-500/10 border border-red-500/25 rounded-xl flex items-center gap-2 text-xs text-red-300">
                <AlertTriangle className="w-4 h-4 text-red-400 flex-shrink-0" />
                <span>{reprocessError}</span>
              </div>
            )}

            {/* Modal Actions */}
            <div className="flex items-center justify-between pt-3 border-t border-white/10">
              <button
                type="button"
                onClick={() => setReprocessRecord(null)}
                className="px-4 py-2 rounded-xl text-xs font-medium text-white/60 hover:text-white hover:bg-white/5 transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleStartReprocess}
                disabled={isReprocessing}
                className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-xs font-semibold bg-[#52b788] hover:bg-[#40916c] text-black shadow-lg shadow-[#52b788]/20 transition-all disabled:opacity-50"
              >
                <RotateCcw className={`w-3.5 h-3.5 ${isReprocessing ? "animate-spin" : ""}`} />
                <span>{isReprocessing ? "Processing..." : "Re-process Transcript"}</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
