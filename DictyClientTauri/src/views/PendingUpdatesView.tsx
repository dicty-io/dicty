import React, { useState, useEffect } from "react";
import {
  RotateCcw,
  CheckCircle2,
  FileText,
  AlignLeft,
  Check,
  Clock,
} from "lucide-react";
import { RichMarkdownDocumentView } from "../components/RichMarkdownDocumentView";
import { engineFetch } from "../services/engineClient";

export interface PendingUpdate {
  id: string;
  title: string;
  timestamp: string;
  target_type: string;
  original_content: string;
  proposed_content: string;
}

export function unpackDocumentContent(raw: string): string {
  if (!raw) return "";
  const trimmed = raw.trim();

  const codeFenceMatch = trimmed.match(/^```(?:json)?\s*(\{[\s\S]*?\})\s*```$/);
  const candidate = codeFenceMatch ? codeFenceMatch[1].trim() : trimmed;

  if (candidate.startsWith("{") && candidate.endsWith("}")) {
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object") {
        const fromFunc =
          parsed?.function?.parameters?.content ||
          parsed?.function?.parameters?.proposed_content ||
          parsed?.function?.parameters?.markdown;
        if (typeof fromFunc === "string" && fromFunc.trim()) return fromFunc.trim();

        const fromParams =
          parsed?.parameters?.content ||
          parsed?.parameters?.proposed_content ||
          parsed?.parameters?.markdown;
        if (typeof fromParams === "string" && fromParams.trim()) return fromParams.trim();

        const direct = parsed?.content || parsed?.proposed_content || parsed?.markdown;
        if (typeof direct === "string" && direct.trim()) return direct.trim();
      }
    } catch {}
  }
  return raw;
}

export const PendingUpdatesView: React.FC = () => {
  const [updates, setUpdates] = useState<PendingUpdate[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [renderMarkdown, setRenderMarkdown] = useState<Record<string, boolean>>({});
  const [approvingId, setApprovingId] = useState<string | null>(null);

  const fetchPending = async (silent: boolean = false) => {
    if (!silent) setLoading(true);
    try {
      const res = await engineFetch("/pending_updates");
      if (res.ok) {
        const data = await res.json();
        const list = Array.isArray(data.updates) ? data.updates : [];
        setUpdates(list);
        setRenderMarkdown((prev) => {
          const next = { ...prev };
          list.forEach((u: PendingUpdate) => {
            if (next[u.id] === undefined) next[u.id] = true;
          });
          return next;
        });
      }
    } catch {
      // Offline fallback
    } finally {
      if (!silent) setLoading(false);
    }
  };

  useEffect(() => {
    fetchPending();
    const interval = setInterval(() => fetchPending(true), 3500);
    return () => clearInterval(interval);
  }, []);

  const handleApprove = async (id: string, proposedContent?: string) => {
    setApprovingId(id);
    try {
      await engineFetch(`/pending_updates/${id}/approve`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          proposed_content: proposedContent ? unpackDocumentContent(proposedContent) : undefined,
        }),
      });
    } catch {}
    setUpdates((prev) => prev.filter((u) => u.id !== id));
    setApprovingId(null);
  };

  const handleReject = async (id: string) => {
    try {
      await engineFetch(`/pending_updates/${id}/reject`, {
        method: "POST",
      });
    } catch {}
    try {
      await engineFetch(`/pending_updates/${id}`, {
        method: "DELETE",
      });
    } catch {}
    setUpdates((prev) => prev.filter((u) => u.id !== id));
  };

  // Helper to render line-by-line raw diff
  const renderRawDiffLines = (content: string, type: "original" | "proposed") => {
    const unpacked = unpackDocumentContent(content);
    const lines = unpacked.replace(/\r\n/g, "\n").split("\n");
    const isNewFile = unpacked.trim() === "New File: This file does not exist yet." || !unpacked.trim();

    if (type === "original" && isNewFile) {
      return (
        <div className="p-4 text-xs font-mono text-red-400/70 italic">
          New File: This file does not exist yet.
        </div>
      );
    }

    return (
      <div className="divide-y divide-white/5 font-mono text-[11px] select-text">
        {lines.map((line, idx) => (
          <div
            key={idx}
            className={`flex items-start py-0.5 px-2.5 transition-colors ${
              type === "proposed"
                ? "hover:bg-emerald-500/10 text-emerald-300/90"
                : "hover:bg-red-500/10 text-red-300/80"
            }`}
          >
            <span className="w-8 text-white/30 text-right pr-3 select-none flex-shrink-0 font-mono text-[10px]">
              {idx + 1}
            </span>
            <span className="w-4 text-center select-none flex-shrink-0 text-white/40">
              {type === "proposed" ? "+" : "-"}
            </span>
            <span className="whitespace-pre-wrap break-all flex-1">{line || " "}</span>
          </div>
        ))}
      </div>
    );
  };

  return (
    <div className="flex-1 overflow-y-auto px-10 py-8 max-w-4xl space-y-6 select-none bg-transparent">
      {/* Header (1:1 with macOS PendingUpdatesView.swift) */}
      <div className="flex items-center justify-between border-b border-white/10 pb-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-white">Pending Updates</h1>
          <p className="text-xs text-white/50">
            Review proposed architecture document changes before committing them to your knowledge base.
          </p>
        </div>
        <button
          onClick={() => fetchPending(false)}
          disabled={loading}
          className="p-2 rounded-xl bg-white/[0.05] hover:bg-white/10 text-white/70 hover:text-white transition-all border border-white/10"
        >
          <RotateCcw className={`w-3.5 h-3.5 ${loading ? "animate-spin" : ""}`} />
        </button>
      </div>

      {loading && updates.length === 0 ? (
        <div className="py-24 text-center space-y-3">
          <div className="w-16 h-16 rounded-full bg-[#5D6658]/20 border border-[#5D6658]/30 flex items-center justify-center mx-auto text-[#87B996]">
            <RotateCcw className="w-8 h-8 animate-spin" />
          </div>
          <h3 className="text-base font-bold text-white">Checking for updates...</h3>
          <p className="text-xs text-white/40 max-w-xs mx-auto">
            Retrieving pending knowledge base modifications...
          </p>
        </div>
      ) : updates.length === 0 ? (
        <div className="py-24 text-center space-y-3">
          <div className="w-16 h-16 rounded-full bg-[#5D6658]/20 border border-[#5D6658]/30 flex items-center justify-center mx-auto text-[#87B996]">
            <CheckCircle2 className="w-8 h-8" />
          </div>
          <h3 className="text-base font-bold text-white">You're all caught up!</h3>
          <p className="text-xs text-white/40 max-w-xs mx-auto">
            No pending knowledge base modifications waiting for review.
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          {updates.map((update) => {
            const isMd = renderMarkdown[update.id] ?? true;
            const cleanOriginal = unpackDocumentContent(update.original_content);
            const cleanProposed = unpackDocumentContent(update.proposed_content);
            const isOriginalNew =
              cleanOriginal.trim() === "New File: This file does not exist yet." ||
              !cleanOriginal.trim();

            return (
              <div
                key={update.id}
                className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-4 shadow-xl"
              >
                {/* Card Header: Title, Timestamp, View Switcher, Target */}
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <h3 className="text-base font-bold text-white tracking-tight">
                      {update.title}
                    </h3>
                    <span className="text-[11px] text-white/40 flex items-center gap-1 mt-0.5 font-medium">
                      <Clock className="w-3 h-3" />
                      {new Date(update.timestamp).toLocaleTimeString([], {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </span>
                  </div>

                  <div className="flex items-center gap-2.5">
                    {/* Segmented Mode Switcher (Raw Diff vs Markdown Preview) */}
                    <div className="inline-flex p-0.5 rounded-xl bg-black/50 border border-white/10 shadow-inner">
                      <button
                        onClick={() =>
                          setRenderMarkdown((prev) => ({
                            ...prev,
                            [update.id]: false,
                          }))
                        }
                        className={`px-3 py-1 rounded-lg text-xs font-medium flex items-center gap-1.5 transition-all ${
                          !isMd
                            ? "bg-white/[0.15] text-white shadow-sm font-semibold"
                            : "text-white/50 hover:text-white"
                        }`}
                      >
                        <AlignLeft className="w-3 h-3" />
                        <span>Raw Diff</span>
                      </button>

                      <button
                        onClick={() =>
                          setRenderMarkdown((prev) => ({
                            ...prev,
                            [update.id]: true,
                          }))
                        }
                        className={`px-3 py-1 rounded-lg text-xs font-medium flex items-center gap-1.5 transition-all ${
                          isMd
                            ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/30 font-semibold"
                            : "text-white/50 hover:text-white"
                        }`}
                      >
                        <FileText className="w-3 h-3" />
                        <span>Markdown</span>
                      </button>
                    </div>

                    <span className="px-2.5 py-1 rounded-lg bg-[#5D6658]/20 text-[#87B996] text-[11px] font-semibold border border-[#5D6658]/30">
                      Target: {update.target_type === "obsidian" ? "Local Data" : update.target_type}
                    </span>
                  </div>
                </div>

                {/* Diff Comparison Pane */}
                <div className="grid grid-cols-2 gap-3 min-h-[220px]">
                  {/* Original Side */}
                  <div className="rounded-xl bg-black/40 border border-white/10 overflow-hidden flex flex-col">
                    <div className="px-3.5 py-2 border-b border-white/10 bg-white/[0.02] flex items-center justify-between">
                      <span className="text-xs font-semibold text-white/50">Original</span>
                      {isOriginalNew && (
                        <span className="text-[10px] text-red-400 font-mono">Not on disk</span>
                      )}
                    </div>
                    <div className="p-3.5 flex-1 overflow-y-auto max-h-[480px]">
                      {isMd ? (
                        isOriginalNew ? (
                          <div className="p-4 text-xs font-mono text-red-400/80 italic">
                            New File: This file does not exist yet.
                          </div>
                        ) : (
                          <RichMarkdownDocumentView content={cleanOriginal} />
                        )
                      ) : (
                        renderRawDiffLines(cleanOriginal, "original")
                      )}
                    </div>
                  </div>

                  {/* Proposed Side */}
                  <div className="rounded-xl bg-black/40 border border-emerald-500/20 overflow-hidden flex flex-col">
                    <div className="px-3.5 py-2 border-b border-white/10 bg-emerald-500/[0.04] flex items-center justify-between">
                      <span className="text-xs font-semibold text-emerald-400">Proposed</span>
                      <span className="text-[10px] text-emerald-400/70 font-mono">
                        {isMd ? "Rich Rendered Preview" : "Line Diff"}
                      </span>
                    </div>
                    <div className="p-3.5 flex-1 overflow-y-auto max-h-[480px]">
                      {isMd ? (
                        <RichMarkdownDocumentView content={cleanProposed} />
                      ) : (
                        renderRawDiffLines(cleanProposed, "proposed")
                      )}
                    </div>
                  </div>
                </div>

                {/* Actions: Reject / Approve */}
                <div className="flex items-center justify-between pt-2 border-t border-white/5">
                  <button
                    onClick={() => handleReject(update.id)}
                    className="text-xs font-semibold text-red-400 hover:text-red-300 transition-colors px-2 py-1"
                  >
                    Reject
                  </button>

                  <button
                    onClick={() => handleApprove(update.id, cleanProposed)}
                    disabled={approvingId === update.id}
                    className="px-5 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-bold shadow-md shadow-[#5D6658]/20 transition-all flex items-center gap-2"
                  >
                    {approvingId === update.id ? (
                      <span>Publishing...</span>
                    ) : (
                      <>
                        <Check className="w-3.5 h-3.5" />
                        <span>Approve & Publish</span>
                      </>
                    )}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
