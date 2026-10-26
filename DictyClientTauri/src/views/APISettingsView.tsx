import React, { useState } from "react";
import {
  Sparkles,
  Cloud,
  Check,
  Network,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { invoke } from "@tauri-apps/api/core";
import {
  OpenRouterIcon,
  OllamaIcon,
  OpenAIIcon,
  GitHubIcon,
  GitLabIcon,
  BitbucketIcon,
  ConfluenceIcon,
  LinearIcon,
  NotionIcon,
} from "../components/BrandIcons";

const sanitizeToken = (tok: string): string => {
  if (!tok) return "";
  let t = tok.trim().replace(/^["']|["']$/g, "").trim();
  if (t.toLowerCase().startsWith("bearer ")) {
    t = t.substring(7).trim();
  } else if (t.toLowerCase().startsWith("token ")) {
    t = t.substring(6).trim();
  }
  return t;
};

export const APISettingsView: React.FC = () => {
  const [llmProvider, setLlmProvider] = useState<"dicty_cloud" | "openrouter" | "local">(() => {
    return (localStorage.getItem("llmProvider") as any) || "openrouter";
  });
  const [llmApiKey, setLlmApiKey] = useState(() => {
    return localStorage.getItem("llmApiKey") || "";
  });
  const [llmModel, setLlmModel] = useState(() => {
    return localStorage.getItem("llmModel") || "qwen/qwen3.7-plus";
  });
  const [llmBaseUrl, setLlmBaseUrl] = useState(() => {
    return localStorage.getItem("llmBaseUrl") || "http://localhost:1234/v1";
  });

  // Integration tokens initialized from localStorage
  const [openaiKey, setOpenaiKey] = useState(() => {
    return localStorage.getItem("openaiApiKey") || "";
  });
  const [githubToken, setGithubToken] = useState(() => {
    return localStorage.getItem("githubToken") || "";
  });
  const [gitlabToken, setGitlabToken] = useState(() => {
    return localStorage.getItem("gitlabToken") || "";
  });
  const [bitbucketToken, setBitbucketToken] = useState(() => {
    return localStorage.getItem("bitbucketToken") || "";
  });
  const [confluenceToken, setConfluenceToken] = useState(() => {
    return localStorage.getItem("confluenceToken") || "";
  });
  const [linearToken, setLinearToken] = useState(() => {
    return localStorage.getItem("linearApiToken") || "";
  });
  const [notionToken, setNotionToken] = useState(() => {
    return localStorage.getItem("notionApiKey") || "";
  });

  // Saved feedback flags
  const [savedFlags, setSavedFlags] = useState<Record<string, boolean>>({});
  const [testingKeys, setTestingKeys] = useState<Record<string, boolean>>({});
  const [testResults, setTestResults] = useState<Record<string, string>>({});

  const syncLLMConfigToRust = () => {
    invoke("set_llm_config", {
      provider: localStorage.getItem("llmProvider") || "openrouter",
      model: localStorage.getItem("llmModel") || "qwen/qwen-3.5-flash",
      apiKey: localStorage.getItem("llmApiKey") || localStorage.getItem("openaiApiKey") || "",
      baseUrl: localStorage.getItem("llmBaseUrl") || "http://localhost:1234/v1",
    }).catch(() => {});
  };

  const handleSave = (key: string, storageKey: string, value: string) => {
    const isGit = ["github", "gitlab", "bitbucket"].includes(key);
    const cleanValue = isGit ? sanitizeToken(value) : value.trim();
    localStorage.setItem(storageKey, cleanValue);
    setSavedFlags((prev) => ({ ...prev, [key]: true }));
    if (["llmApiKey", "llmModel", "llmBaseUrl", "openaiApiKey"].includes(storageKey)) {
      syncLLMConfigToRust();
    }
    setTimeout(() => {
      setSavedFlags((prev) => ({ ...prev, [key]: false }));
    }, 2000);
  };

  const handleTestGit = async (provider: string, token: string, key: string) => {
    const clean = sanitizeToken(token);
    if (!clean) return;
    setTestingKeys((prev) => ({ ...prev, [key]: true }));
    setTestResults((prev) => ({ ...prev, [key]: "" }));
    try {
      const res = await invoke<string>("git_test_connection", {
        provider,
        token: clean,
      });
      setTestResults((prev) => ({ ...prev, [key]: res }));
    } catch (err: any) {
      setTestResults((prev) => ({
        ...prev,
        [key]: `Failed: ${typeof err === "string" ? err : err?.message || String(err)}`,
      }));
    } finally {
      setTestingKeys((prev) => ({ ...prev, [key]: false }));
    }
  };

  const handleSelectLLMProvider = (provider: "dicty_cloud" | "openrouter" | "local") => {
    setLlmProvider(provider);
    localStorage.setItem("llmProvider", provider);
    syncLLMConfigToRust();
  };

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-8 select-none font-sans">
      <SettingsPageHeader
        title="API Keys & Integrations"
        description="Manage your AI intelligence providers, cloud credentials, and developer integrations."
        helpTopic="api_keys"
      />

      {/* LLM Intelligence Provider Section */}
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-[#87B996]" />
          <h3 className="text-sm font-bold text-white tracking-tight">
            LLM Intelligence Provider
          </h3>
        </div>
        <p className="text-xs text-white/50 leading-relaxed max-w-2xl">
          Powers speech restructuring, markdown note styling, summarization, and audio re-processing. Choose how Dicty accesses large language models:
        </p>

        {/* Segmented Picker (1:1 with SwiftUI LLMProviderSegmentedPicker) */}
        <div className="inline-flex p-1 rounded-xl bg-white/[0.05] border border-white/10 gap-1">
          <button
            onClick={() => handleSelectLLMProvider("dicty_cloud")}
            className={`px-4 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
              llmProvider === "dicty_cloud"
                ? "bg-[#5D6658] text-white shadow"
                : "text-white/60 hover:text-white"
            }`}
          >
            <Cloud className="w-3.5 h-3.5 text-[#87B996]" />
            <span>Dicty Cloud</span>
          </button>
          <button
            onClick={() => handleSelectLLMProvider("openrouter")}
            className={`px-4 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
              llmProvider === "openrouter"
                ? "bg-[#5D6658] text-white shadow"
                : "text-white/60 hover:text-white"
            }`}
          >
            <OpenRouterIcon size={14} className="text-[#87B996]" />
            <span>OpenRouter (BYOK)</span>
          </button>
          <button
            onClick={() => handleSelectLLMProvider("local")}
            className={`px-4 py-2 rounded-lg text-xs font-semibold flex items-center gap-2 transition-all ${
              llmProvider === "local"
                ? "bg-[#5D6658] text-white shadow"
                : "text-white/60 hover:text-white"
            }`}
          >
            <OllamaIcon size={14} className="text-[#87B996]" />
            <span>Local (Ollama)</span>
          </button>
        </div>

        {/* Provider Specific Settings */}
        {llmProvider === "dicty_cloud" && (
          <div className="p-4 rounded-2xl bg-[#87B996]/10 border border-[#87B996]/20 text-xs text-emerald-200/90 space-y-2 shadow-lg">
            <div className="flex items-center gap-2 text-[#87B996] font-bold text-sm">
              <Cloud className="w-4 h-4" />
              <span>Managed Dicty Cloud</span>
            </div>
            <p className="leading-relaxed text-white/70">
              Zero setup required. Dicty securely orchestrates model inference, token rate-limits, and routing in the cloud. No personal API keys needed; usage is tied to your Dicty account balance.
            </p>
          </div>
        )}

        {llmProvider === "openrouter" && (
          <div className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-4 shadow-lg">
            <div className="p-4 rounded-xl bg-white/[0.025] border border-white/5 space-y-1.5">
              <div className="flex items-center gap-2">
                <OpenRouterIcon size={16} className="text-[#87B996]" />
                <span className="text-sm font-bold text-white">
                  Bring Your Own Key (OpenRouter)
                </span>
              </div>
              <p className="text-xs text-white/60 leading-relaxed">
                Connect your OpenRouter account to unlock 100+ state-of-the-art models (Qwen, Claude, GPT-4o, Gemini 2.0, DeepSeek). Requests are billed directly to your OpenRouter token balance at upstream cost.
              </p>
            </div>

            <div className="space-y-1">
              <span className="text-xs font-bold text-white block">
                OpenRouter API Key
              </span>
              <div className="flex items-center gap-2">
                <input
                  type="password"
                  value={llmApiKey}
                  onChange={(e) => setLlmApiKey(e.target.value)}
                  placeholder="sk-or-v1-..."
                  className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
                />
                <button
                  onClick={() => handleSave("openrouter", "llmApiKey", llmApiKey)}
                  className="px-4 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
                >
                  Save
                </button>
              </div>
              {savedFlags["openrouter"] && (
                <span className="text-[11px] text-[#87B996] font-medium flex items-center gap-1">
                  <Check className="w-3 h-3" /> Saved!
                </span>
              )}
            </div>

            <div className="space-y-1">
              <span className="text-xs font-bold text-white block">
                Default Model Identifier
              </span>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={llmModel}
                  onChange={(e) => setLlmModel(e.target.value)}
                  placeholder="qwen/qwen3.7-plus"
                  className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
                />
                <button
                  onClick={() => handleSave("llmModel", "llmModel", llmModel)}
                  className="px-4 py-2 rounded-xl bg-white/[0.06] hover:bg-white/10 text-white text-xs font-semibold transition-all border border-white/10"
                >
                  Save
                </button>
              </div>
              <span className="text-[10px] text-white/40 block">
                You can also browse and select models with 1-click in the Models Library tab.
              </span>
              {savedFlags["llmModel"] && (
                <span className="text-[11px] text-[#87B996] font-medium flex items-center gap-1">
                  <Check className="w-3 h-3" /> Saved!
                </span>
              )}
            </div>
          </div>
        )}

        {llmProvider === "local" && (
          <div className="p-5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-4 shadow-lg">
            <div className="p-4 rounded-xl bg-white/[0.025] border border-white/5 space-y-1.5">
              <div className="flex items-center gap-2">
                <OllamaIcon size={16} className="text-[#87B996]" />
                <span className="text-sm font-bold text-white">
                  Local Inference Server (Ollama / LM Studio)
                </span>
              </div>
              <p className="text-xs text-white/60 leading-relaxed">
                Format speech and generate summaries 100% offline with complete privacy. Runs entirely on your machine without sending data over the internet or requiring external API keys.
              </p>
            </div>

            <div className="space-y-1">
              <span className="text-xs font-bold text-white block">Base URL</span>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={llmBaseUrl}
                  onChange={(e) => setLlmBaseUrl(e.target.value)}
                  placeholder="http://localhost:1234/v1"
                  className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
                />
                <button
                  onClick={() => handleSave("llmBaseUrl", "llmBaseUrl", llmBaseUrl)}
                  className="px-4 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
                >
                  Save
                </button>
              </div>
              {savedFlags["llmBaseUrl"] && (
                <span className="text-[11px] text-[#87B996] font-medium flex items-center gap-1">
                  <Check className="w-3 h-3" /> Saved!
                </span>
              )}
            </div>

            <div className="space-y-1">
              <span className="text-xs font-bold text-white block">
                Model Identifier
              </span>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={llmModel}
                  onChange={(e) => setLlmModel(e.target.value)}
                  placeholder="local-model"
                  className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
                />
                <button
                  onClick={() => handleSave("llmModel", "llmModel", llmModel)}
                  className="px-4 py-2 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
                >
                  Save
                </button>
              </div>
              {savedFlags["llmModel"] && (
                <span className="text-[11px] text-[#87B996] font-medium flex items-center gap-1">
                  <Check className="w-3 h-3" /> Saved!
                </span>
              )}
            </div>
          </div>
        )}
      </div>

      <div className="border-t border-white/10" />

      {/* Workspace & Developer Services Header (1:1 with SettingsView.swift) */}
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <Network className="w-4 h-4 text-[#87B996]" />
          <h3 className="text-sm font-bold text-white tracking-tight">
            Workspace & Developer Services
          </h3>
        </div>
        <p className="text-xs text-white/50 leading-relaxed max-w-2xl">
          Connect third-party productivity and developer platforms to sync notes, export meeting minutes, and stage code tasks:
        </p>

        {/* Cloud Transcription (OpenAI) */}
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 text-xs font-bold text-white">
              <OpenAIIcon size={18} className="text-[#87B996]" />
              <span>Cloud Transcription (OpenAI)</span>
            </div>
            <span className="text-[10px] text-white/40 font-mono">Whisper API</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="password"
              value={openaiKey}
              onChange={(e) => setOpenaiKey(e.target.value)}
              placeholder="sk-proj-..."
              className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
            />
            <button
              onClick={() => handleSave("openai", "openaiApiKey", openaiKey)}
              className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
            >
              Save
            </button>
          </div>
          {savedFlags["openai"] && (
            <span className="text-[10px] text-[#87B996] font-medium flex items-center gap-1">
              <Check className="w-2.5 h-2.5" /> Saved!
            </span>
          )}
        </div>

        {/* GitHub */}
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 text-xs font-bold text-white">
              <GitHubIcon size={18} className="text-white" />
              <span>GitHub Integration</span>
            </div>
            <span className="text-[10px] text-white/40">PAT (Classic or Fine-Grained)</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="password"
              value={githubToken}
              onChange={(e) => setGithubToken(e.target.value)}
              placeholder="ghp_... or github_pat_..."
              className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
            />
            <button
              onClick={() => handleTestGit("github", githubToken, "github")}
              disabled={!githubToken.trim() || testingKeys["github"]}
              className="px-3 py-1.5 rounded-xl bg-white/[0.06] hover:bg-white/10 disabled:opacity-40 text-white text-xs font-semibold transition-all border border-white/10"
            >
              {testingKeys["github"] ? "Testing..." : "Test"}
            </button>
            <button
              onClick={() => handleSave("github", "githubToken", githubToken)}
              className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
            >
              Save
            </button>
          </div>
          {testResults["github"] && (
            <div className={`text-[11px] font-medium p-2 rounded-lg ${
              testResults["github"].startsWith("Connected")
                ? "bg-emerald-500/10 text-emerald-300 border border-emerald-500/20"
                : "bg-red-500/10 text-red-300 border border-red-500/20"
            }`}>
              {testResults["github"]}
            </div>
          )}
          {savedFlags["github"] && (
            <span className="text-[10px] text-[#87B996] font-medium flex items-center gap-1">
              <Check className="w-2.5 h-2.5" /> Saved!
            </span>
          )}
        </div>

        {/* GitLab */}
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 text-xs font-bold text-white">
              <GitLabIcon size={18} />
              <span>GitLab Integration</span>
            </div>
            <span className="text-[10px] text-white/40">Personal Access Token (PAT)</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="password"
              value={gitlabToken}
              onChange={(e) => setGitlabToken(e.target.value)}
              placeholder="glpat-..."
              className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
            />
            <button
              onClick={() => handleTestGit("gitlab", gitlabToken, "gitlab")}
              disabled={!gitlabToken.trim() || testingKeys["gitlab"]}
              className="px-3 py-1.5 rounded-xl bg-white/[0.06] hover:bg-white/10 disabled:opacity-40 text-white text-xs font-semibold transition-all border border-white/10"
            >
              {testingKeys["gitlab"] ? "Testing..." : "Test"}
            </button>
            <button
              onClick={() => handleSave("gitlab", "gitlabToken", gitlabToken)}
              className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
            >
              Save
            </button>
          </div>
          {testResults["gitlab"] && (
            <div className={`text-[11px] font-medium p-2 rounded-lg ${
              testResults["gitlab"].startsWith("Connected")
                ? "bg-emerald-500/10 text-emerald-300 border border-emerald-500/20"
                : "bg-red-500/10 text-red-300 border border-red-500/20"
            }`}>
              {testResults["gitlab"]}
            </div>
          )}
          {savedFlags["gitlab"] && (
            <span className="text-[10px] text-[#87B996] font-medium flex items-center gap-1">
              <Check className="w-2.5 h-2.5" /> Saved!
            </span>
          )}
        </div>

        {/* Bitbucket */}
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 text-xs font-bold text-white">
              <BitbucketIcon size={18} />
              <span>Bitbucket Integration</span>
            </div>
            <span className="text-[10px] text-white/40">Repository / Workspace Access Token</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="password"
              value={bitbucketToken}
              onChange={(e) => setBitbucketToken(e.target.value)}
              placeholder="Access Token or app password"
              className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
            />
            <button
              onClick={() => handleTestGit("bitbucket", bitbucketToken, "bitbucket")}
              disabled={!bitbucketToken.trim() || testingKeys["bitbucket"]}
              className="px-3 py-1.5 rounded-xl bg-white/[0.06] hover:bg-white/10 disabled:opacity-40 text-white text-xs font-semibold transition-all border border-white/10"
            >
              {testingKeys["bitbucket"] ? "Testing..." : "Test"}
            </button>
            <button
              onClick={() => handleSave("bitbucket", "bitbucketToken", bitbucketToken)}
              className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
            >
              Save
            </button>
          </div>
          {testResults["bitbucket"] && (
            <div className={`text-[11px] font-medium p-2 rounded-lg ${
              testResults["bitbucket"].startsWith("Connected")
                ? "bg-emerald-500/10 text-emerald-300 border border-emerald-500/20"
                : "bg-red-500/10 text-red-300 border border-red-500/20"
            }`}>
              {testResults["bitbucket"]}
            </div>
          )}
          {savedFlags["bitbucket"] && (
            <span className="text-[10px] text-[#87B996] font-medium flex items-center gap-1">
              <Check className="w-2.5 h-2.5" /> Saved!
            </span>
          )}
        </div>

        {/* Confluence */}
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 text-xs font-bold text-white">
              <ConfluenceIcon size={18} />
              <span>Confluence Integration</span>
            </div>
            <span className="text-[10px] text-white/40">Atlassian API Token</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="password"
              value={confluenceToken}
              onChange={(e) => setConfluenceToken(e.target.value)}
              placeholder="Atlassian API Token"
              className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
            />
            <button
              onClick={() => handleSave("confluence", "confluenceToken", confluenceToken)}
              className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
            >
              Save
            </button>
          </div>
          {savedFlags["confluence"] && (
            <span className="text-[10px] text-[#87B996] font-medium flex items-center gap-1">
              <Check className="w-2.5 h-2.5" /> Saved!
            </span>
          )}
        </div>

        {/* Linear */}
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 text-xs font-bold text-white">
              <LinearIcon size={18} className="text-white" />
              <span>Linear Integration</span>
            </div>
            <span className="text-[10px] text-white/40">Personal API Key</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="password"
              value={linearToken}
              onChange={(e) => setLinearToken(e.target.value)}
              placeholder="lin_api_..."
              className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
            />
            <button
              onClick={() => handleSave("linear", "linearApiToken", linearToken)}
              className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
            >
              Save
            </button>
          </div>
          {savedFlags["linear"] && (
            <span className="text-[10px] text-[#87B996] font-medium flex items-center gap-1">
              <Check className="w-2.5 h-2.5" /> Saved!
            </span>
          )}
        </div>

        {/* Notion */}
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 text-xs font-bold text-white">
              <NotionIcon size={18} className="text-white" />
              <span>Notion Integration</span>
            </div>
            <span className="text-[10px] text-white/40">Internal Integration Secret</span>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="password"
              value={notionToken}
              onChange={(e) => setNotionToken(e.target.value)}
              placeholder="secret_... or ntn_..."
              className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 font-mono focus:outline-none focus:border-[#5D6658]"
            />
            <button
              onClick={() => handleSave("notion", "notionApiKey", notionToken)}
              className="px-3.5 py-1.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold transition-all shadow"
            >
              Save
            </button>
          </div>
          {savedFlags["notion"] && (
            <span className="text-[10px] text-[#87B996] font-medium flex items-center gap-1">
              <Check className="w-2.5 h-2.5" /> Saved!
            </span>
          )}
        </div>
      </div>
    </div>
  );
};
