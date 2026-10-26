import React, { useState, useEffect, useMemo, useCallback } from "react";
import {
  Sparkles,
  RotateCcw,
  Search,
  X,
  Check,
  Terminal,
  ChevronRight,
  Gift,
  CheckCircle2,
  AlertCircle,
} from "lucide-react";
import { getProviderIcon } from "./BrandIcons";
import { engineApi } from "../services/engineApi";

export interface OpenRouterModelItem {
  id: string;
  name: string;
  description?: string;
  context_length?: number;
  prompt_price_per_m?: number;
  completion_price_per_m?: number;
  is_free?: boolean;
}

const CACHE_KEY = "dicty_openrouter_catalog_cache";
const CACHE_DURATION_MS = 24 * 60 * 60 * 1000; // 24 hours (1 day)

// Curated starter list of frontier models (used solely before first network/cache resolution)
const STARTER_MODELS: OpenRouterModelItem[] = [
  {
    id: "anthropic/claude-3.7-sonnet",
    name: "Claude 3.7 Sonnet",
    description: "Hybrid reasoning and instant execution model with state-of-the-art coding and prose capabilities.",
    context_length: 200000,
    prompt_price_per_m: 3.0,
    completion_price_per_m: 15.0,
  },
  {
    id: "anthropic/claude-3.5-haiku",
    name: "Claude 3.5 Haiku",
    description: "Ultra-fast, low-latency model engineered for rapid text formatting and instant dictation cleaning.",
    context_length: 200000,
    prompt_price_per_m: 0.8,
    completion_price_per_m: 4.0,
  },
  {
    id: "openai/gpt-4o",
    name: "GPT-4o",
    description: "Omni-modal flagship model from OpenAI with fast output token generation and exceptional multi-lingual fluency.",
    context_length: 128000,
    prompt_price_per_m: 2.5,
    completion_price_per_m: 10.0,
  },
  {
    id: "openai/gpt-4o-mini",
    name: "GPT-4o Mini",
    description: "Cost-efficient, low-latency workhorse for near-instant transcription cleanup and punctuation.",
    context_length: 128000,
    prompt_price_per_m: 0.15,
    completion_price_per_m: 0.6,
  },
  {
    id: "google/gemini-2.5-flash",
    name: "Gemini 2.5 Flash",
    description: "Google's ultra-fast reasoning model with 1M+ context window and low latency.",
    context_length: 1000000,
    prompt_price_per_m: 0.15,
    completion_price_per_m: 0.6,
  },
  {
    id: "deepseek/deepseek-r1",
    name: "DeepSeek R1",
    description: "Open-weights reasoning frontier model with state-of-the-art math and code synthesis.",
    context_length: 64000,
    prompt_price_per_m: 0.55,
    completion_price_per_m: 2.19,
  },
  {
    id: "deepseek/deepseek-chat",
    name: "DeepSeek V3",
    description: "671B MoE frontier chat model with incredible speed and literary nuance at budget cost.",
    context_length: 64000,
    prompt_price_per_m: 0.14,
    completion_price_per_m: 0.28,
  },
  {
    id: "meta-llama/llama-3.3-70b-instruct",
    name: "Llama 3.3 70B Instruct",
    description: "Meta's flagship 70B open model matching 405B capabilities for writing, summarization, and translation.",
    context_length: 128000,
    prompt_price_per_m: 0.12,
    completion_price_per_m: 0.3,
  },
  {
    id: "meta-llama/llama-3.1-8b-instruct:free",
    name: "Llama 3.1 8B Instruct (Free)",
    description: "Free community tier of Meta's 8B lightweight instruction model.",
    context_length: 128000,
    prompt_price_per_m: 0.0,
    completion_price_per_m: 0.0,
    is_free: true,
  },
  {
    id: "mistralai/mistral-large-2407",
    name: "Mistral Large 2",
    description: "Flagship reasoning model with 128k context and native multilingual support.",
    context_length: 128000,
    prompt_price_per_m: 2.0,
    completion_price_per_m: 6.0,
  },
  {
    id: "qwen/qwen-2.5-72b-instruct",
    name: "Qwen 2.5 72B Instruct",
    description: "Alibaba's benchmark-dominating open weights model with broad language fluency.",
    context_length: 131072,
    prompt_price_per_m: 0.35,
    completion_price_per_m: 0.4,
  },
  {
    id: "x-ai/grok-2-1212",
    name: "Grok 2",
    description: "xAI's flagship reasoning model with bold comprehension, direct tone, and nuanced vocabulary.",
    context_length: 128000,
    prompt_price_per_m: 2.0,
    completion_price_per_m: 10.0,
  },
];

// Exact 1:1 match with SwiftUI ModelsLibraryView.swift line 1920
const PROVIDER_FILTERS = [
  "All",
  "Free",
  "Claude",
  "OpenAI",
  "Google",
  "DeepSeek",
  "xAI",
  "Nvidia",
  "Qwen",
  "Moonshot",
  "Zhipu",
  "MiniMax",
  "Meta",
  "Mistral",
];

interface Props {
  isOpen: boolean;
  onClose: () => void;
  onSelectModel: (modelId: string, modelName: string) => void;
  selectedModelId?: string;
}

export const OpenRouterExplorerModal: React.FC<Props> = ({
  isOpen,
  onClose,
  onSelectModel,
  selectedModelId,
}) => {
  const [models, setModels] = useState<OpenRouterModelItem[]>(() => {
    // Try restoring 24-hour cache synchronously on initial render
    try {
      const cached = localStorage.getItem(CACHE_KEY);
      if (cached) {
        const parsed = JSON.parse(cached);
        if (Array.isArray(parsed?.models) && parsed.models.length > 0) {
          return parsed.models;
        }
      }
    } catch {}
    return STARTER_MODELS;
  });

  const [loading, setLoading] = useState<boolean>(false);
  const [syncMessage, setSyncMessage] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [selectedProvider, setSelectedProvider] = useState<string>("All");
  const [customSlugInput, setCustomSlugInput] = useState<string>("");

  const formatRawOpenRouterModels = (rawList: any[]): OpenRouterModelItem[] => {
    return rawList
      .filter((m: any) => m && m.id && !m.id.includes(":floor") && !m.id.includes(":extended"))
      .map((m: any) => {
        const promptPrice = (parseFloat(m.pricing?.prompt) || 0) * 1_000_000;
        const compPrice = (parseFloat(m.pricing?.completion) || 0) * 1_000_000;
        const isFree =
          m.id.includes(":free") ||
          (promptPrice === 0 && compPrice === 0);

        return {
          id: m.id,
          name: m.name || m.id,
          description: m.description || "",
          context_length: m.context_length || 0,
          prompt_price_per_m: promptPrice,
          completion_price_per_m: compPrice,
          is_free: isFree,
        };
      });
  };

  const fetchCatalog = useCallback(async (force: boolean = false) => {
    // Check 24-hour cache unless force=true
    if (!force) {
      try {
        const cached = localStorage.getItem(CACHE_KEY);
        if (cached) {
          const parsed = JSON.parse(cached);
          const isFresh = Date.now() - (parsed?.timestamp || 0) < CACHE_DURATION_MS;
          if (isFresh && Array.isArray(parsed?.models) && parsed.models.length > 50) {
            setModels(parsed.models);
            return;
          }
        }
      } catch {}
    }

    setLoading(true);
    let resolvedModels: OpenRouterModelItem[] = [];

    // Strategy 1: Local Engine API (with a 24-hour backend cache)
    try {
      const res = await engineApi.getOpenRouterModels(force);
      if (res?.models && Array.isArray(res.models) && res.models.length > 50) {
        resolvedModels = res.models;
      }
    } catch {
      // Backend not running, connection refused, or CORS fallback
    }

    // Strategy 2: Direct OpenRouter Live API (client-side fallback with open CORS)
    if (resolvedModels.length === 0) {
      try {
        const resp = await fetch("https://openrouter.ai/api/v1/models", {
          headers: { "HTTP-Referer": "https://dicty.app", "X-Title": "Dicty" },
        });
        if (resp.ok) {
          const json = await resp.json();
          if (Array.isArray(json?.data)) {
            resolvedModels = formatRawOpenRouterModels(json.data);
          }
        }
      } catch (err) {
        console.warn("Direct OpenRouter fetch failed:", err);
      }
    }

    // If models were successfully fetched, persist to 24-hour localStorage cache
    if (resolvedModels.length > 0) {
      setModels(resolvedModels);
      try {
        localStorage.setItem(
          CACHE_KEY,
          JSON.stringify({
            timestamp: Date.now(),
            models: resolvedModels,
          })
        );
      } catch {}

      setSyncMessage(`✓ Synchronized ${resolvedModels.length} models with OpenRouter`);
      setTimeout(() => setSyncMessage(null), 3500);
    }

    setLoading(false);
  }, []);

  useEffect(() => {
    if (isOpen) {
      fetchCatalog(false);
    }
  }, [isOpen, fetchCatalog]);

  const handleUseCustomSlug = () => {
    const slug = customSlugInput.trim();
    if (slug) {
      onSelectModel(slug, slug);
      onClose();
    }
  };

  // Provider filtering exactly matching SwiftUI ModelsLibraryView.swift line 1925-1959
  const filteredModels = useMemo(() => {
    return models.filter((m) => {
      // 1. Search filter
      const q = searchQuery.trim().toLowerCase();
      if (q) {
        const matchesSearch =
          m.name.toLowerCase().includes(q) ||
          m.id.toLowerCase().includes(q) ||
          (m.description && m.description.toLowerCase().includes(q));
        if (!matchesSearch) return false;
      }

      // 2. Provider filter
      if (selectedProvider === "All") return true;

      const p = selectedProvider.toLowerCase();
      const mid = m.id.toLowerCase();

      switch (p) {
        case "free":
          return (
            m.is_free ||
            mid.includes(":free") ||
            ((m.prompt_price_per_m ?? 1.0) === 0.0 && (m.completion_price_per_m ?? 1.0) === 0.0)
          );
        case "claude":
          return mid.includes("anthropic/") || mid.includes("claude");
        case "openai":
          return mid.includes("openai/");
        case "google":
          return mid.includes("google/");
        case "deepseek":
          return mid.includes("deepseek/");
        case "xai":
          return mid.includes("x-ai/") || mid.includes("grok");
        case "nvidia":
          return mid.includes("nvidia/");
        case "qwen":
          return mid.includes("qwen/") || mid.includes("alibaba/");
        case "moonshot":
          return mid.includes("moonshot");
        case "zhipu":
          return mid.includes("z-ai/") || mid.includes("zhipu/") || mid.includes("thudm/");
        case "minimax":
          return mid.includes("minimax/");
        case "meta":
          return mid.includes("meta-llama/") || mid.includes("meta/");
        case "mistral":
          return mid.includes("mistralai/") || mid.includes("mistral/");
        default:
          return mid.includes(p) || (m.name && m.name.toLowerCase().includes(p));
      }
    });
  }, [models, searchQuery, selectedProvider]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black/80 backdrop-blur-md z-50 flex items-center justify-center p-4">
      <div className="w-full max-w-3xl h-[85vh] max-h-[740px] bg-[#16181D] border border-white/15 rounded-2xl shadow-2xl flex flex-col overflow-hidden select-none animate-fadeIn">
        {/* Header */}
        <div className="p-5 border-b border-white/10 bg-white/[0.02] flex items-start justify-between">
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-amber-400" />
              <h3 className="text-base font-bold text-white tracking-tight">
                OpenRouter Model Explorer
              </h3>
              <span className="px-2 py-0.5 rounded-full bg-amber-500/15 border border-amber-500/30 text-[10px] font-bold text-amber-300">
                {models.length > 50 ? `${models.length}+ Models` : "400+ Models"}
              </span>
            </div>
            <p className="text-xs text-white/60">
              Explore {models.length > 0 ? `${models.length}+` : "400+"} frontier and open-source models for transcription refinement & translation.
            </p>
            <p className="text-[11px] text-amber-300/80 font-medium">
              Tip: Use &apos;⚡ Fast&apos; models for instant voice translation. Avoid &apos;🧠 Reasoning&apos; models as they add extra latency.
            </p>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => fetchCatalog(true)}
              disabled={loading}
              className="px-2.5 py-1.5 rounded-lg bg-white/[0.06] hover:bg-white/10 text-white/70 hover:text-white transition-colors flex items-center gap-1.5 text-xs font-medium"
              title="Synchronize live catalog with OpenRouter (bypasses 24h cache)"
            >
              <RotateCcw className={`w-3.5 h-3.5 ${loading ? "animate-spin text-amber-400" : ""}`} />
              <span className="hidden sm:inline">{loading ? "Syncing..." : "Sync"}</span>
            </button>
            <button
              onClick={onClose}
              className="px-3.5 py-1.5 rounded-lg bg-[#278C40] hover:bg-[#2F9E49] text-white text-xs font-semibold shadow-md transition-colors"
            >
              Done
            </button>
          </div>
        </div>

        {/* Sync Status Banner */}
        {syncMessage && (
          <div className="px-5 py-1.5 bg-emerald-500/10 border-b border-emerald-500/20 flex items-center gap-2 text-xs text-emerald-300 font-medium animate-fadeIn">
            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 flex-shrink-0" />
            <span>{syncMessage} (cached for 24 hours)</span>
          </div>
        )}

        {/* Custom Slug Direct Entry Bar */}
        <div className="px-5 py-2.5 bg-amber-500/[0.04] border-b border-white/10 flex items-center gap-2.5">
          <Terminal className="w-3.5 h-3.5 text-white/40 flex-shrink-0" />
          <span className="text-xs font-semibold text-white/70 flex-shrink-0">
            Custom ID:
          </span>
          <input
            type="text"
            value={customSlugInput}
            onChange={(e) => setCustomSlugInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleUseCustomSlug()}
            placeholder="e.g. anthropic/claude-3.7-sonnet or custom fine-tune"
            className="flex-1 min-w-0 bg-black/40 border border-white/10 rounded-lg px-2.5 py-1 text-xs text-white placeholder:text-white/30 font-mono focus:outline-none focus:border-[#87B996]"
          />
          <button
            onClick={handleUseCustomSlug}
            disabled={!customSlugInput.trim()}
            className="px-3 py-1 rounded-lg bg-white/10 hover:bg-white/20 disabled:opacity-40 text-white text-xs font-semibold transition-all"
          >
            Use Model
          </button>
        </div>

        {/* Search & Provider Filter Chips */}
        <div className="p-4 border-b border-white/10 space-y-3 bg-white/[0.01]">
          {/* Search Input */}
          <div className="relative">
            <Search className="w-3.5 h-3.5 text-white/40 absolute left-3 top-2.5" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={`Search ${models.length} models by name, provider, or ID (e.g. llama-3, flash, qwen)...`}
              className="w-full bg-black/30 border border-white/10 rounded-xl pl-9 pr-8 py-1.5 text-xs text-white placeholder:text-white/35 focus:outline-none focus:border-[#87B996]"
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery("")}
                className="absolute right-2.5 top-2 text-white/40 hover:text-white"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            )}
          </div>

          {/* Provider Chips */}
          <div className="flex items-center gap-1.5 overflow-x-auto pb-1 scrollbar-none">
            {PROVIDER_FILTERS.map((p) => {
              const isSelected = selectedProvider === p;
              const isFree = p === "Free";
              return (
                <button
                  key={p}
                  onClick={() => setSelectedProvider(p)}
                  className={`px-3 py-1 rounded-full text-xs font-semibold whitespace-nowrap transition-all flex items-center gap-1 ${
                    isSelected
                      ? isFree
                        ? "bg-emerald-500 text-black shadow-md font-bold"
                        : "bg-gradient-to-r from-[#5D6658] to-[#278C40] text-white shadow-md shadow-[#278C40]/20"
                      : isFree
                      ? "bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20"
                      : "bg-white/[0.05] text-white/70 hover:bg-white/10 hover:text-white"
                  }`}
                >
                  {isFree && <Gift className="w-3 h-3" />}
                  <span>{p}</span>
                </button>
              );
            })}
          </div>

          {/* Counter info */}
          <div className="flex items-center justify-between text-[11px] text-white/40 px-1 pt-0.5">
            <span>
              Showing <strong className="text-white/80">{filteredModels.length}</strong> of{" "}
              <strong className="text-white/80">{models.length}</strong> models
            </span>
            {selectedProvider !== "All" && (
              <span className="text-amber-400/80">Filtered by: {selectedProvider}</span>
            )}
          </div>
        </div>

        {/* Models List */}
        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {loading && models.length === 0 ? (
            <div className="h-48 flex flex-col items-center justify-center gap-2 text-white/50 text-xs">
              <RotateCcw className="w-6 h-6 animate-spin text-[#87B996]" />
              <span>Fetching live catalog of 400+ models from OpenRouter...</span>
            </div>
          ) : filteredModels.length === 0 ? (
            <div className="h-48 flex flex-col items-center justify-center gap-1 text-white/40 text-xs">
              <AlertCircle className="w-6 h-6 opacity-40 mb-1 text-amber-400" />
              <span className="font-semibold text-white/60">No matching models found</span>
              <span>Try adjusting your search query or choosing another provider filter.</span>
            </div>
          ) : (
            filteredModels.map((model) => {
              const isCurrent = selectedModelId === model.id;
              const promptPrice =
                model.prompt_price_per_m !== undefined
                  ? model.prompt_price_per_m.toFixed(2)
                  : "0.00";
              const compPrice =
                model.completion_price_per_m !== undefined
                  ? model.completion_price_per_m.toFixed(2)
                  : "0.00";
              const isFree =
                model.is_free ||
                (model.prompt_price_per_m === 0 && model.completion_price_per_m === 0);

              return (
                <div
                  key={model.id}
                  onClick={() => {
                    onSelectModel(model.id, model.name);
                    onClose();
                  }}
                  className={`group p-3 rounded-xl border transition-all cursor-pointer flex items-center justify-between gap-4 ${
                    isCurrent
                      ? "bg-[#278C40]/15 border-[#278C40]/40 text-white"
                      : "bg-black/20 border-white/[0.07] hover:bg-white/[0.04] text-white/80"
                  }`}
                >
                  {/* Left: Provider Icon + Info */}
                  <div className="flex items-start gap-3 min-w-0 flex-1">
                    <div className="mt-0.5 w-6 h-6 rounded-lg bg-white/[0.05] border border-white/10 flex items-center justify-center flex-shrink-0">
                      {getProviderIcon(model.id, 14)}
                    </div>

                    <div className="min-w-0 space-y-0.5">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold text-xs text-white truncate">
                          {model.name}
                        </span>
                        {model.context_length && model.context_length > 0 ? (
                          <span className="px-1.5 py-0.2 rounded bg-white/[0.08] text-[9px] font-mono text-white/60">
                            {model.context_length >= 1000000
                              ? `${(model.context_length / 1000000).toFixed(1)}M ctx`
                              : `${Math.round(model.context_length / 1000)}K ctx`}
                          </span>
                        ) : null}
                        {isFree && (
                          <span className="px-1.5 py-0.2 rounded bg-emerald-500/20 text-emerald-300 text-[9px] font-bold">
                            FREE
                          </span>
                        )}
                      </div>

                      <div className="font-mono text-[10px] text-white/40 truncate">
                        {model.id}
                      </div>

                      {model.description && (
                        <p className="text-[11px] text-white/50 line-clamp-1 leading-snug">
                          {model.description}
                        </p>
                      )}
                    </div>
                  </div>

                  {/* Right: Pricing & Select Action */}
                  <div className="flex items-center gap-3 flex-shrink-0">
                    <div className="text-right">
                      {isFree ? (
                        <span className="text-[10.5px] font-bold text-emerald-400">
                          $0.00 / M
                        </span>
                      ) : (
                        <div className="text-[10px] font-mono text-white/60">
                          <div>
                            ${promptPrice} <span className="text-white/30">/M in</span>
                          </div>
                          <div>
                            ${compPrice} <span className="text-white/30">/M out</span>
                          </div>
                        </div>
                      )}
                    </div>

                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        onSelectModel(model.id, model.name);
                        onClose();
                      }}
                      className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all flex items-center gap-1 ${
                        isCurrent
                          ? "bg-emerald-500 text-black shadow-sm"
                          : "bg-white/[0.08] group-hover:bg-[#5D6658] text-white group-hover:shadow-md"
                      }`}
                    >
                      {isCurrent ? (
                        <>
                          <Check className="w-3 h-3" />
                          <span>Selected</span>
                        </>
                      ) : (
                        <>
                          <span>Select</span>
                          <ChevronRight className="w-3 h-3" />
                        </>
                      )}
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
};
