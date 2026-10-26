import React, { useState, useEffect, useCallback } from "react";
import {
  FolderGit2,
  GitCommit,
  GitPullRequest,
  Sparkles,
  RefreshCw,
  Cpu,
  AlertCircle,
  ExternalLink,
  KeyRound,
  CheckCircle2,
  Check,
  Info,
  Mic,
  FileText,
  Layers,
  Trash2,
  ChevronDown,
  ChevronUp,
  ArrowRight,
  X,
} from "lucide-react";
import { OpenRouterExplorerModal } from "../components/OpenRouterExplorerModal";
import { engineApi } from "../services/engineApi";
import { GitHubIcon, GitLabIcon, BitbucketIcon } from "../components/BrandIcons";
import { invoke } from "@tauri-apps/api/core";
import { useArchitectureTask } from "../services/architectureTaskService";
import { type ActiveTab } from "../components/Navigation";
import { FeatureHelpButton } from "../components/FeatureHelpModal";

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

interface CommitInfo {
  id: string;
  message: string;
  author: string;
  date: string;
  url: string;
}

interface PRInfo {
  id: number;
  title: string;
  author: string;
  date: string;
  url: string;
}

const REASONING_MODELS = [
  { id: "qwen/qwen3.7-plus", name: "Qwen 3.7 Plus (Recommended)" },
  { id: "deepseek/deepseek-chat", name: "DeepSeek V3" },
  { id: "openai/gpt-4o-mini", name: "GPT-4o Mini" },
  { id: "qwen/qwen-2.5-coder-32b-instruct", name: "Qwen 2.5 Coder 32B" },
  { id: "custom", name: "Custom Model ID..." },
];

interface ProjectsViewProps {
  onNavigateTab?: (tab: ActiveTab) => void;
}

export const ProjectsView: React.FC<ProjectsViewProps> = ({ onNavigateTab }) => {
  // Provider state
  const [gitProvider, setGitProvider] = useState<"github" | "gitlab" | "bitbucket">(() => {
    return (localStorage.getItem("gitProvider") as any) || "github";
  });

  const [gitlabHost, setGitlabHost] = useState<string>(() => {
    return localStorage.getItem("gitlabHost") || "https://gitlab.com";
  });

  // Tokens
  const [githubToken, setGithubToken] = useState<string>(() => localStorage.getItem("githubToken") || "");
  const [gitlabToken, setGitlabToken] = useState<string>(() => localStorage.getItem("gitlabToken") || "");
  const [bitbucketToken, setBitbucketToken] = useState<string>(() => localStorage.getItem("bitbucketToken") || "");
  const [tokenInput, setTokenInput] = useState<string>("");
  const [showTokenInput, setShowTokenInput] = useState(false);

  // Selected repos and branches
  const [selectedRepo, setSelectedRepo] = useState<string>(() => {
    const provider = localStorage.getItem("gitProvider") || "github";
    if (provider === "gitlab") return localStorage.getItem("selectedGitLabRepo") || "";
    if (provider === "bitbucket") return localStorage.getItem("selectedBitbucketRepo") || "";
    return localStorage.getItem("selectedGitHubRepo") || "";
  });

  const [selectedBranch, setSelectedBranch] = useState<string>(() => {
    const provider = localStorage.getItem("gitProvider") || "github";
    if (provider === "gitlab") return localStorage.getItem("selectedGitLabBranch") || "";
    if (provider === "bitbucket") return localStorage.getItem("selectedBitbucketBranch") || "";
    return localStorage.getItem("selectedGitHubBranch") || "";
  });

  // Repos and branches lists
  const [availableRepos, setAvailableRepos] = useState<string[]>(() => {
    try {
      const provider = localStorage.getItem("gitProvider") || "github";
      const key = provider === "gitlab" ? "cachedGitLabRepos" : provider === "bitbucket" ? "cachedBitbucketRepos" : "cachedAvailableRepos";
      const cached = localStorage.getItem(key);
      if (cached) return cached.split(",").filter(Boolean);
    } catch {}
    return [];
  });

  const [availableBranches, setAvailableBranches] = useState<string[]>([]);
  const [isFetchingRepos, setIsFetchingRepos] = useState(false);
  const [isFetchingBranches, setIsFetchingBranches] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  // Active Context Selection (Commits & PRs)
  const [selectedContextTab, setSelectedContextTab] = useState<"commits" | "prs">("commits");
  const [commitsLimit, setCommitsLimit] = useState<number>(10);
  const [recentCommits, setRecentCommits] = useState<CommitInfo[]>([]);
  const [recentPRs, setRecentPRs] = useState<PRInfo[]>([]);
  const [isFetchingContext, setIsFetchingContext] = useState(false);
  const [contextFetchError, setContextFetchError] = useState<string | null>(null);

  const [selectedCommitsSet, setSelectedCommitsSet] = useState<Set<string>>(() => {
    try {
      const saved = localStorage.getItem("selectedGitHubCommits");
      if (saved) return new Set(saved.split(",").filter(Boolean));
    } catch {}
    return new Set();
  });

  const [selectedPRsSet, setSelectedPRsSet] = useState<Set<number>>(() => {
    try {
      const saved = localStorage.getItem("selectedGitHubPRs");
      if (saved) return new Set(saved.split(",").map(Number).filter(Boolean));
    } catch {}
    return new Set();
  });

  // Architecture doc generation & model selection
  const [llmModel, setLlmModel] = useState<string>(() => {
    return localStorage.getItem("llmModel") || "qwen/qwen3.7-plus";
  });
  const [customModelSlug, setCustomModelSlug] = useState<string>(() => {
    const cur = localStorage.getItem("llmModel") || "qwen/qwen3.7-plus";
    return REASONING_MODELS.some((m) => m.id === cur && m.id !== "custom") ? "" : cur;
  });
  const [showOpenRouterExplorer, setShowOpenRouterExplorer] = useState(false);
  const [targetSystem] = useState<string>(() => {
    return localStorage.getItem("targetSystem") || "obsidian";
  });
  const {
    isGenerating: isGeneratingArch,
    message: archGenMessage,
    status: archGenStatus,
    startGeneration,
    clearStatus,
  } = useArchitectureTask();
  const [localValidationError, setLocalValidationError] = useState<string | null>(null);
  const [queuedThoughts, setQueuedThoughts] = useState<any[]>([]);
  const [isFetchingQueue, setIsFetchingQueue] = useState(false);
  const [showQueuedThoughtsModal, setShowQueuedThoughtsModal] = useState(false);

  const fetchQueuedThoughts = useCallback(async () => {
    try {
      setIsFetchingQueue(true);
      const res = await engineApi.getQueue();
      if (res && Array.isArray(res.items)) {
        setQueuedThoughts(res.items);
      }
    } catch {
      // ignore
    } finally {
      setIsFetchingQueue(false);
    }
  }, []);

  const handleClearQueuedThoughts = async () => {
    try {
      await engineApi.clearQueue();
      setQueuedThoughts([]);
    } catch {
      // ignore
    }
  };

  // Provider test states
  const [testConnectionStatus, setTestConnectionStatus] = useState<string | null>(null);
  const [isTestingConnection, setIsTestingConnection] = useState(false);

  // Detected environment git tokens (.env)
  const [envTokens, setEnvTokens] = useState<{
    github_token?: string;
    gitlab_token?: string;
    bitbucket_token?: string;
  } | null>(null);

  // Get active provider token
  const getActiveToken = useCallback(() => {
    let tok = "";
    if (gitProvider === "gitlab") tok = gitlabToken;
    else if (gitProvider === "bitbucket") tok = bitbucketToken;
    else tok = githubToken;
    return sanitizeToken(tok);
  }, [gitProvider, githubToken, gitlabToken, bitbucketToken]);

  const saveToken = (tok: string) => {
    const trimmed = sanitizeToken(tok);
    if (gitProvider === "gitlab") {
      setGitlabToken(trimmed);
      localStorage.setItem("gitlabToken", trimmed);
    } else if (gitProvider === "bitbucket") {
      setBitbucketToken(trimmed);
      localStorage.setItem("bitbucketToken", trimmed);
    } else {
      setGithubToken(trimmed);
      localStorage.setItem("githubToken", trimmed);
    }
    setTokenInput("");
    setShowTokenInput(false);
  };

  // Switch git provider
  const handleSelectProvider = (prov: "github" | "gitlab" | "bitbucket") => {
    setGitProvider(prov);
    localStorage.setItem("gitProvider", prov);
    setFetchError(null);
    setContextFetchError(null);

    // Restore cached repo & branch for this provider
    let repo = "";
    let branch = "";
    let cachedList: string[] = [];

    if (prov === "gitlab") {
      repo = localStorage.getItem("selectedGitLabRepo") || "";
      branch = localStorage.getItem("selectedGitLabBranch") || "";
      const raw = localStorage.getItem("cachedGitLabRepos");
      if (raw) cachedList = raw.split(",").filter(Boolean);
    } else if (prov === "bitbucket") {
      repo = localStorage.getItem("selectedBitbucketRepo") || "";
      branch = localStorage.getItem("selectedBitbucketBranch") || "";
      const raw = localStorage.getItem("cachedBitbucketRepos");
      if (raw) cachedList = raw.split(",").filter(Boolean);
    } else {
      repo = localStorage.getItem("selectedGitHubRepo") || "";
      branch = localStorage.getItem("selectedGitHubBranch") || "";
      const raw = localStorage.getItem("cachedAvailableRepos");
      if (raw) cachedList = raw.split(",").filter(Boolean);
    }

    setSelectedRepo(repo);
    setSelectedBranch(branch);
    setAvailableRepos(cachedList);
  };

  const handleSelectRepo = (repo: string) => {
    setSelectedRepo(repo);
    if (gitProvider === "gitlab") localStorage.setItem("selectedGitLabRepo", repo);
    else if (gitProvider === "bitbucket") localStorage.setItem("selectedBitbucketRepo", repo);
    else localStorage.setItem("selectedGitHubRepo", repo);

    setSelectedBranch("");
    setSelectedCommitsSet(new Set());
    setSelectedPRsSet(new Set());
    localStorage.removeItem("selectedGitHubCommits");
    localStorage.removeItem("selectedGitHubPRs");

    if (repo) {
      fetchBranches(repo);
    }
  };

  const handleSelectBranch = (branch: string) => {
    setSelectedBranch(branch);
    if (gitProvider === "gitlab") localStorage.setItem("selectedGitLabBranch", branch);
    else if (gitProvider === "bitbucket") localStorage.setItem("selectedBitbucketBranch", branch);
    else localStorage.setItem("selectedGitHubBranch", branch);

    if (selectedRepo) {
      fetchContext(selectedRepo, branch);
    }
  };

  // Format relative date helper (matching Swift formatRelativeDate)
  const formatRelativeDate = (dateStr: string) => {
    try {
      const date = new Date(dateStr);
      const now = new Date();
      const diffSec = Math.floor((now.getTime() - date.getTime()) / 1000);
      if (diffSec < 60) return "just now";
      if (diffSec < 3600) return `${Math.floor(diffSec / 60)}m ago`;
      if (diffSec < 86400) return `${Math.floor(diffSec / 3600)}h ago`;
      if (diffSec < 604800) return `${Math.floor(diffSec / 86400)}d ago`;
      return date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
    } catch {
      return dateStr;
    }
  };

  // Fetch Repositories
  const fetchRepositories = async () => {
    const token = getActiveToken();
    if (!token) {
      setFetchError(`No ${gitProvider.toUpperCase()} token configured. Click below to add your token.`);
      setShowTokenInput(true);
      return;
    }

    setIsFetchingRepos(true);
    setFetchError(null);

    try {
      // 1. Try native Tauri command (bypasses rogue hosts mappings e.g. 8.8.4.4, CORS, browser header limits)
      try {
        const repos = await invoke<string[]>("git_fetch_repositories", {
          provider: gitProvider,
          token,
          host: gitProvider === "gitlab" ? gitlabHost : undefined,
        });
        if (Array.isArray(repos)) {
          setAvailableRepos(repos);
          const key =
            gitProvider === "gitlab"
              ? "cachedGitLabRepos"
              : gitProvider === "bitbucket"
              ? "cachedBitbucketRepos"
              : "cachedAvailableRepos";
          localStorage.setItem(key, repos.join(","));
          if (!selectedRepo && repos.length > 0) {
            handleSelectRepo(repos[0]);
          } else if (selectedRepo && availableBranches.length === 0) {
            fetchBranches(selectedRepo);
          }
          return;
        }
      } catch (nativeErr: any) {
        const errMsg = typeof nativeErr === "string" ? nativeErr : nativeErr?.message || String(nativeErr);
        if (errMsg && !errMsg.includes("not found") && !errMsg.includes("cannot find command")) {
          throw new Error(errMsg);
        }
      }

      // 2. Browser fallback (for pure web testing / development outside Tauri)
      if (gitProvider === "github") {
        const authHeader = token.startsWith("github_pat_") ? `Bearer ${token}` : `token ${token}`;
        const res = await fetch("https://api.github.com/user/repos?per_page=100&sort=updated", {
          headers: {
            Authorization: authHeader,
            Accept: "application/vnd.github.v3+json",
          },
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.message || `GitHub error (${res.status})`);
        }
        const data = await res.json();
        const repos = (data as any[]).map((r) => r.full_name);
        setAvailableRepos(repos);
        localStorage.setItem("cachedAvailableRepos", repos.join(","));
        if (!selectedRepo && repos.length > 0) {
          handleSelectRepo(repos[0]);
        }
      } else if (gitProvider === "gitlab") {
        const host = gitlabHost.replace(/\/+$/, "");
        const res = await fetch(`${host}/api/v4/projects?membership=true&per_page=100&order_by=updated_at`, {
          headers: {
            "PRIVATE-TOKEN": token,
          },
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.message || `GitLab error (${res.status})`);
        }
        const data = await res.json();
        const repos = (data as any[]).map((r) => r.path_with_namespace || r.name);
        setAvailableRepos(repos);
        localStorage.setItem("cachedGitLabRepos", repos.join(","));
        if (!selectedRepo && repos.length > 0) {
          handleSelectRepo(repos[0]);
        }
      } else if (gitProvider === "bitbucket") {
        const headers: Record<string, string> = { Accept: "application/json" };
        if (token.includes(":")) {
          headers["Authorization"] = `Basic ${btoa(token)}`;
        } else {
          headers["Authorization"] = `Bearer ${token}`;
        }
        const res = await fetch("https://api.bitbucket.org/2.0/user/permissions/repositories?pagelen=100", {
          headers,
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.error?.message || `Bitbucket error (${res.status})`);
        }
        const data = await res.json();
        const repos = (data.values || []).map((v: any) => v.repository?.full_name).filter(Boolean);
        setAvailableRepos(repos);
        localStorage.setItem("cachedBitbucketRepos", repos.join(","));
        if (!selectedRepo && repos.length > 0) {
          handleSelectRepo(repos[0]);
        }
      }
    } catch (err: any) {
      setFetchError(err.message || "Failed to fetch repositories");
    } finally {
      setIsFetchingRepos(false);
    }
  };

  // Fetch Branches
  const fetchBranches = async (repo: string) => {
    const token = getActiveToken();
    if (!token || !repo) return;

    setIsFetchingBranches(true);
    try {
      // 1. Try native Tauri command
      try {
        const branches = await invoke<string[]>("git_fetch_branches", {
          provider: gitProvider,
          token,
          repo,
          host: gitProvider === "gitlab" ? gitlabHost : undefined,
        });
        if (Array.isArray(branches)) {
          setAvailableBranches(branches);
          const defaultBranch = branches.includes("main") ? "main" : branches.includes("master") ? "master" : branches[0] || "";
          if (!selectedBranch && defaultBranch) {
            handleSelectBranch(defaultBranch);
          } else if (selectedBranch) {
            fetchContext(repo, selectedBranch);
          }
          return;
        }
      } catch (nativeErr: any) {
        const errMsg = typeof nativeErr === "string" ? nativeErr : nativeErr?.message || String(nativeErr);
        if (errMsg && !errMsg.includes("not found") && !errMsg.includes("cannot find command")) {
          throw new Error(errMsg);
        }
      }

      // 2. Browser fallback
      if (gitProvider === "github") {
        const authHeader = token.startsWith("github_pat_") ? `Bearer ${token}` : `token ${token}`;
        const res = await fetch(`https://api.github.com/repos/${repo}/branches?per_page=100`, {
          headers: {
            Authorization: authHeader,
            Accept: "application/vnd.github.v3+json",
          },
        });
        if (res.ok) {
          const data = await res.json();
          const branches = (data as any[]).map((b) => b.name);
          setAvailableBranches(branches);
          const defaultBranch = branches.includes("main") ? "main" : branches.includes("master") ? "master" : branches[0] || "";
          if (!selectedBranch && defaultBranch) {
            handleSelectBranch(defaultBranch);
          } else if (selectedBranch) {
            fetchContext(repo, selectedBranch);
          }
        }
      } else if (gitProvider === "gitlab") {
        const host = gitlabHost.replace(/\/+$/, "");
        const encoded = encodeURIComponent(repo);
        const res = await fetch(`${host}/api/v4/projects/${encoded}/repository/branches?per_page=100`, {
          headers: { "PRIVATE-TOKEN": token },
        });
        if (res.ok) {
          const data = await res.json();
          const branches = (data as any[]).map((b) => b.name);
          setAvailableBranches(branches);
          const defaultBranch = branches.includes("main") ? "main" : branches.includes("master") ? "master" : branches[0] || "";
          if (!selectedBranch && defaultBranch) {
            handleSelectBranch(defaultBranch);
          } else if (selectedBranch) {
            fetchContext(repo, selectedBranch);
          }
        }
      } else if (gitProvider === "bitbucket") {
        const headers: Record<string, string> = { Accept: "application/json" };
        if (token.includes(":")) headers["Authorization"] = `Basic ${btoa(token)}`;
        else headers["Authorization"] = `Bearer ${token}`;

        const res = await fetch(`https://api.bitbucket.org/2.0/repositories/${repo}/refs/branches?pagelen=100`, {
          headers,
        });
        if (res.ok) {
          const data = await res.json();
          const branches = (data.values || []).map((b: any) => b.name);
          setAvailableBranches(branches);
          const defaultBranch = branches.includes("main") ? "main" : branches.includes("master") ? "master" : branches[0] || "";
          if (!selectedBranch && defaultBranch) {
            handleSelectBranch(defaultBranch);
          } else if (selectedBranch) {
            fetchContext(repo, selectedBranch);
          }
        }
      }
    } catch {}
    finally {
      setIsFetchingBranches(false);
    }
  };

  // Fetch Commits & PRs (Context)
  const fetchContext = async (repo: string, branch?: string) => {
    const token = getActiveToken();
    if (!token || !repo) return;

    setIsFetchingContext(true);
    setContextFetchError(null);

    try {
      // 1. Try native Tauri command
      try {
        interface NativeGitContext {
          commits: CommitInfo[];
          prs: PRInfo[];
        }
        const res = await invoke<NativeGitContext>("git_fetch_context", {
          provider: gitProvider,
          token,
          repo,
          branch: branch || undefined,
          limit: commitsLimit,
          host: gitProvider === "gitlab" ? gitlabHost : undefined,
        });
        if (res) {
          if (Array.isArray(res.commits)) {
            setRecentCommits(
              res.commits.map((c) => ({
                ...c,
                date: formatRelativeDate(c.date),
              }))
            );
          }
          if (Array.isArray(res.prs)) {
            setRecentPRs(
              res.prs.map((p) => ({
                ...p,
                date: formatRelativeDate(p.date),
              }))
            );
          }
          return;
        }
      } catch (nativeErr: any) {
        const errMsg = typeof nativeErr === "string" ? nativeErr : nativeErr?.message || String(nativeErr);
        if (errMsg && !errMsg.includes("not found") && !errMsg.includes("cannot find command")) {
          throw new Error(errMsg);
        }
      }

      // 2. Browser fallback
      if (gitProvider === "github") {
        const authHeader = token.startsWith("github_pat_") ? `Bearer ${token}` : `token ${token}`;
        const branchParam = branch ? `&sha=${encodeURIComponent(branch)}` : "";
        const [commitsRes, prsRes] = await Promise.all([
          fetch(`https://api.github.com/repos/${repo}/commits?per_page=${commitsLimit}${branchParam}`, {
            headers: {
              Authorization: authHeader,
              Accept: "application/vnd.github.v3+json",
            },
          }),
          fetch(`https://api.github.com/repos/${repo}/pulls?state=open&per_page=15`, {
            headers: {
              Authorization: authHeader,
              Accept: "application/vnd.github.v3+json",
            },
          }),
        ]);

        if (commitsRes.ok) {
          const cData = await commitsRes.json();
          const parsedCommits: CommitInfo[] = (cData as any[]).map((c) => ({
            id: c.sha.substring(0, 7),
            message: c.commit.message.split("\n")[0],
            author: c.commit.author?.name || c.author?.login || "Unknown",
            date: formatRelativeDate(c.commit.author?.date || ""),
            url: c.html_url,
          }));
          setRecentCommits(parsedCommits);
        } else {
          const err = await commitsRes.json().catch(() => ({}));
          setContextFetchError(`GitHub Commits: ${err.message || commitsRes.statusText}`);
        }

        if (prsRes.ok) {
          const pData = await prsRes.json();
          const parsedPRs: PRInfo[] = (pData as any[]).map((p) => ({
            id: p.number,
            title: p.title,
            author: p.user?.login || "Unknown",
            date: formatRelativeDate(p.created_at || ""),
            url: p.html_url,
          }));
          setRecentPRs(parsedPRs);
        }
      } else if (gitProvider === "gitlab") {
        const host = gitlabHost.replace(/\/+$/, "");
        const encoded = encodeURIComponent(repo);
        const branchParam = branch ? `&ref_name=${encodeURIComponent(branch)}` : "";

        const [commitsRes, prsRes] = await Promise.all([
          fetch(`${host}/api/v4/projects/${encoded}/repository/commits?per_page=${commitsLimit}${branchParam}`, {
            headers: { "PRIVATE-TOKEN": token },
          }),
          fetch(`${host}/api/v4/projects/${encoded}/merge_requests?state=opened&per_page=15`, {
            headers: { "PRIVATE-TOKEN": token },
          }),
        ]);

        if (commitsRes.ok) {
          const cData = await commitsRes.json();
          const parsedCommits: CommitInfo[] = (cData as any[]).map((c) => ({
            id: c.short_id || c.id.substring(0, 7),
            message: c.message.split("\n")[0],
            author: c.author_name || "Unknown",
            date: formatRelativeDate(c.created_at || ""),
            url: c.web_url,
          }));
          setRecentCommits(parsedCommits);
        }

        if (prsRes.ok) {
          const pData = await prsRes.json();
          const parsedPRs: PRInfo[] = (pData as any[]).map((p) => ({
            id: p.iid,
            title: p.title,
            author: p.author?.username || "Unknown",
            date: formatRelativeDate(p.created_at || ""),
            url: p.web_url,
          }));
          setRecentPRs(parsedPRs);
        }
      } else if (gitProvider === "bitbucket") {
        const headers: Record<string, string> = { Accept: "application/json" };
        if (token.includes(":")) headers["Authorization"] = `Basic ${btoa(token)}`;
        else headers["Authorization"] = `Bearer ${token}`;

        const branchParam = branch ? `&include=${encodeURIComponent(branch)}` : "";
        const [commitsRes, prsRes] = await Promise.all([
          fetch(`https://api.bitbucket.org/2.0/repositories/${repo}/commits?pagelen=${commitsLimit}${branchParam}`, {
            headers,
          }),
          fetch(`https://api.bitbucket.org/2.0/repositories/${repo}/pullrequests?state=OPEN&pagelen=15`, {
            headers,
          }),
        ]);

        if (commitsRes.ok) {
          const cData = await commitsRes.json();
          const parsedCommits: CommitInfo[] = (cData.values || []).map((c: any) => ({
            id: (c.hash || "").substring(0, 7),
            message: (c.message || "").split("\n")[0],
            author: c.author?.raw || "Unknown",
            date: formatRelativeDate(c.date || ""),
            url: c.links?.html?.href || "",
          }));
          setRecentCommits(parsedCommits);
        }

        if (prsRes.ok) {
          const pData = await prsRes.json();
          const parsedPRs: PRInfo[] = (pData.values || []).map((p: any) => ({
            id: p.id,
            title: p.title,
            author: p.author?.display_name || "Unknown",
            date: formatRelativeDate(p.created_on || ""),
            url: p.links?.html?.href || "",
          }));
          setRecentPRs(parsedPRs);
        }
      }
    } catch (err: any) {
      setContextFetchError(err.message || "Failed to fetch Git context");
    } finally {
      setIsFetchingContext(false);
    }
  };

  const handleTestConnection = async () => {
    const tok = tokenInput.trim() || getActiveToken();
    if (!tok) return;
    setIsTestingConnection(true);
    setTestConnectionStatus(null);
    try {
      const res = await invoke<string>("git_test_connection", {
        provider: gitProvider,
        token: tok,
        host: gitProvider === "gitlab" ? gitlabHost : undefined,
      });
      setTestConnectionStatus(res);
    } catch (err: any) {
      const msg = typeof err === "string" ? err : err?.message || String(err);
      setTestConnectionStatus(`Failed: ${msg}`);
    } finally {
      setIsTestingConnection(false);
    }
  };

  useEffect(() => {
    invoke<{
      github_token?: string;
      gitlab_token?: string;
      bitbucket_token?: string;
    }>("get_env_git_tokens")
      .then((tokens) => {
        if (tokens) {
          setEnvTokens(tokens);
          const currentToken = getActiveToken();
          if (!currentToken) {
            if (gitProvider === "github" && tokens.github_token) {
              setGithubToken(tokens.github_token);
              localStorage.setItem("githubToken", tokens.github_token);
            } else if (gitProvider === "gitlab" && tokens.gitlab_token) {
              setGitlabToken(tokens.gitlab_token);
              localStorage.setItem("gitlabToken", tokens.gitlab_token);
            } else if (gitProvider === "bitbucket" && tokens.bitbucket_token) {
              setBitbucketToken(tokens.bitbucket_token);
              localStorage.setItem("bitbucketToken", tokens.bitbucket_token);
            }
          }
        }
      })
      .catch(() => {});
  }, [gitProvider, getActiveToken]);

  const handleRefreshAll = async () => {
    await fetchRepositories();
    if (selectedRepo) {
      await fetchBranches(selectedRepo);
      if (selectedBranch) {
        await fetchContext(selectedRepo, selectedBranch);
      }
    }
  };

  // Toggle commit selection
  const toggleCommit = (sha: string) => {
    setSelectedCommitsSet((prev) => {
      const next = new Set(prev);
      if (next.has(sha)) next.delete(sha);
      else next.add(sha);
      localStorage.setItem("selectedGitHubCommits", Array.from(next).join(","));
      return next;
    });
  };

  // Toggle PR selection
  const togglePR = (id: number) => {
    setSelectedPRsSet((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      localStorage.setItem("selectedGitHubPRs", Array.from(next).join(","));
      return next;
    });
  };

  // Trigger Architecture Generation
  const handleGenerateArchitecture = async () => {
    setLocalValidationError(null);
    const token = getActiveToken();
    if (!token) {
      setLocalValidationError("Error: No valid API token configured. Please enter one above.");
      return;
    }
    if (!selectedRepo) {
      setLocalValidationError("Error: Please select a target repository first.");
      return;
    }

    const activeModel = llmModel === "custom" ? customModelSlug || "qwen/qwen3.7-plus" : llmModel;

    // Retrieve Knowledge Base target settings
    const targetSys = localStorage.getItem("targetSystem") || "obsidian";
    const obsidianPath = localStorage.getItem("obsidianPath") || "";
    const targetPageTitle = localStorage.getItem("confluencePageTitle") || "ARCHITECTURE.md";
    const confluenceUrl = localStorage.getItem("confluenceUrl") || "";
    const linearWorkspaceId = localStorage.getItem("linearWorkspaceId") || "";
    const linearApiToken = localStorage.getItem("linearApiToken") || localStorage.getItem("linearApiKey") || "";
    const notionPageId = localStorage.getItem("notionPageId") || "";
    const notionApiKey = localStorage.getItem("notionApiKey") || "";

    // 1. Fetch latest queued voice thoughts from Code & Architecture mode
    let latestQueue = queuedThoughts;
    try {
      const queueRes = await engineApi.getQueue();
      if (queueRes?.items) {
        latestQueue = queueRes.items;
        setQueuedThoughts(queueRes.items);
      }
    } catch (e) {
      console.warn("Could not refresh queue:", e);
    }

    // 2. Collect selected Git commits and PRs
    const selectedCommitsList = recentCommits.filter((c) => selectedCommitsSet.has(c.id));
    const selectedPRsList = recentPRs.filter((p) => selectedPRsSet.has(p.id));

    // 3. Compose structured context for AI Agent
    const promptSections: string[] = [];

    if (latestQueue.length > 0) {
      const thoughtsFormatted = latestQueue
        .map((item, idx) => {
          const branchInfo = item.git_branch ? ` (Branch: ${item.git_branch}${item.git_commit ? ` @ ${item.git_commit}` : ""})` : "";
          return `• Thought #${idx + 1}${branchInfo}: "${item.text}"`;
        })
        .join("\n");
      promptSections.push(`### Recorded Voice Thoughts & Directives (Code & Architecture Mode):\n${thoughtsFormatted}`);
    } else {
      promptSections.push("### Developer Architecture Directives:\nPlease deeply analyze the repository structure and document the comprehensive technical architecture.");
    }

    if (selectedCommitsList.length > 0) {
      const commitsFormatted = selectedCommitsList
        .map((c) => `• [${c.id.substring(0, 7)}] ${c.message} (Author: ${c.author}, ${c.date})`)
        .join("\n");
      promptSections.push(`### Selected Git Commits to Incorporate into Architecture:\n${commitsFormatted}`);
    }

    if (selectedPRsList.length > 0) {
      const prsFormatted = selectedPRsList
        .map((p) => `• PR #${p.id}: ${p.title} (Author: ${p.author}, ${p.date})`)
        .join("\n");
      promptSections.push(`### Selected Pull Requests to Incorporate into Architecture:\n${prsFormatted}`);
    }

    const voiceText = promptSections.join("\n\n");

    const destinationUrl =
      targetSys === "obsidian" || targetSys === "local"
        ? obsidianPath
        : targetSys === "notion"
        ? notionPageId
        : targetSys === "linear"
        ? linearWorkspaceId
        : confluenceUrl;

    const destDesc =
      targetSys === "obsidian" || targetSys === "local"
        ? (obsidianPath ? `for ${obsidianPath}` : "for local vault")
        : `for ${targetSys.toUpperCase()}`;

    const payload: Record<string, any> = {
      github_token: token,
      github_repo: gitProvider === "github" ? selectedRepo : "",
      github_branch: gitProvider === "github" ? selectedBranch : "",
      git_provider: gitProvider,
      gitlab_host: gitlabHost,
      gitlab_token: gitProvider === "gitlab" ? token : "",
      gitlab_repo: gitProvider === "gitlab" ? selectedRepo : "",
      gitlab_branch: gitProvider === "gitlab" ? selectedBranch : "",
      bitbucket_token: gitProvider === "bitbucket" ? token : "",
      bitbucket_repo: gitProvider === "bitbucket" ? selectedRepo : "",
      bitbucket_branch: gitProvider === "bitbucket" ? selectedBranch : "",
      target_type: targetSys,
      target_file: targetPageTitle || "ARCHITECTURE.md",
      confluence_url: destinationUrl,
      linear_api_token: linearApiToken,
      linear_workspace_id: linearWorkspaceId,
      notion_api_key: notionApiKey,
      notion_page_id: notionPageId,
      voice_text: voiceText,
      llm_provider: localStorage.getItem("llmProvider") || "openrouter",
      llm_model: activeModel,
      llm_api_key: localStorage.getItem("llmApiKey") || "",
      llm_base_url: localStorage.getItem("llmBaseUrl") || "https://openrouter.ai/api/v1",
    };

    startGeneration(payload, {
      repo: selectedRepo,
      branch: selectedBranch,
      thoughtCount: latestQueue.length,
      commitCount: selectedCommitsList.length,
      destinationDesc: destDesc,
    });
  };

  // Initial load
  useEffect(() => {
    fetchQueuedThoughts();
    if (availableRepos.length === 0) {
      fetchRepositories();
    } else if (selectedRepo && availableBranches.length === 0) {
      fetchBranches(selectedRepo);
    }
  }, [fetchQueuedThoughts]);

  const isCustomModel = !REASONING_MODELS.slice(0, -1).some((m) => m.id === llmModel);

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-4xl mx-auto space-y-7 select-none">
      {/* Page Header (1:1 with ProjectSettingsView.swift) */}
      <div className="space-y-1.5 border-b border-white/10 pb-5">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-2xl bg-indigo-500/15 border border-indigo-500/30 flex items-center justify-center text-indigo-400 shadow-md shadow-indigo-500/10">
            <FolderGit2 className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-bold text-white tracking-tight">Projects</h1>
              <FeatureHelpButton topic="projects" label="Projects & Librarian Guide" />
            </div>
            <p className="text-xs text-white/50">
              Select the target repository you are currently working on. The Librarian will sync documentation with this project.
            </p>
          </div>
        </div>
      </div>

      {/* Git Provider Segmented Picker */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold text-white/60 uppercase tracking-wider">
            Git Provider
          </span>
          <button
            onClick={() => setShowTokenInput(!showTokenInput)}
            className="text-[11px] text-indigo-400 hover:text-indigo-300 flex items-center gap-1 font-medium transition-colors"
          >
            <KeyRound className="w-3 h-3" />
            <span>{getActiveToken() ? "Update Provider Token" : "Configure Token"}</span>
          </button>
        </div>

        <div className="grid grid-cols-3 gap-2 p-1 rounded-2xl bg-white/[0.04] border border-white/10 max-w-md">
          {(["github", "gitlab", "bitbucket"] as const).map((prov) => {
            const isSelected = gitProvider === prov;
            const provName = prov === "github" ? "GitHub" : prov === "gitlab" ? "GitLab" : "Bitbucket";
            return (
              <button
                key={prov}
                onClick={() => handleSelectProvider(prov)}
                className={`py-2 px-4 rounded-xl text-xs font-semibold transition-all flex items-center justify-center gap-2 ${
                  isSelected
                    ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/25"
                    : "text-white/60 hover:text-white hover:bg-white/[0.04]"
                }`}
              >
                {prov === "github" && <GitHubIcon size={14} className={isSelected ? "text-white" : "text-white/70"} />}
                {prov === "gitlab" && <GitLabIcon size={14} />}
                {prov === "bitbucket" && <BitbucketIcon size={14} />}
                <span>{provName}</span>
              </button>
            );
          })}
        </div>

        {/* Self-hosted GitLab Host URL */}
        {gitProvider === "gitlab" && (
          <div className="p-3.5 rounded-xl bg-white/[0.03] border border-white/10 max-w-md space-y-1.5">
            <label className="text-[11px] font-semibold text-white/70">GitLab Instance Host URL</label>
            <input
              type="text"
              value={gitlabHost}
              onChange={(e) => {
                setGitlabHost(e.target.value);
                localStorage.setItem("gitlabHost", e.target.value);
              }}
              placeholder="https://gitlab.com"
              className="w-full bg-black/40 border border-white/10 rounded-lg px-3 py-1.5 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>
        )}

        {/* Quick Token Configuration Drawer */}
        {showTokenInput && (
          <div className="p-4 rounded-2xl bg-white/[0.03] border border-indigo-500/30 max-w-md space-y-3 animate-fadeIn">
            <div className="flex items-center justify-between text-xs font-semibold text-white">
              <span>Enter {gitProvider.toUpperCase()} Personal Access Token</span>
              <button onClick={() => setShowTokenInput(false)} className="text-white/40 hover:text-white">
                ✕
              </button>
            </div>
            {/* Detected .env token banner if available */}
            {envTokens && (() => {
              const detected =
                gitProvider === "github"
                  ? envTokens.github_token
                  : gitProvider === "gitlab"
                  ? envTokens.gitlab_token
                  : envTokens.bitbucket_token;
              if (!detected) return null;
              const preview = detected.length > 20 ? `${detected.substring(0, 16)}...` : detected;
              return (
                <div className="p-2.5 rounded-xl bg-indigo-500/10 border border-indigo-500/25 flex items-center justify-between gap-2 text-[11px]">
                  <div className="flex items-center gap-1.5 text-white/80">
                    <Sparkles className="w-3.5 h-3.5 text-indigo-400 flex-shrink-0" />
                    <span>Found in <code className="text-indigo-200 font-mono bg-black/40 px-1 py-0.5 rounded">.env</code>: {preview}</span>
                  </div>
                  <button
                    onClick={() => {
                      saveToken(detected);
                      setFetchError(null);
                      setTimeout(() => fetchRepositories(), 50);
                    }}
                    className="px-2.5 py-1 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white font-semibold transition-colors flex-shrink-0 shadow"
                  >
                    Use .env Token
                  </button>
                </div>
              );
            })()}
            <div className="flex items-center gap-2">
              <input
                type="password"
                value={tokenInput}
                onChange={(e) => setTokenInput(e.target.value)}
                placeholder={gitProvider === "bitbucket" ? "username:app_password" : "ghp_... / glpat-..."}
                className="flex-1 bg-black/40 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500 font-mono"
              />
              <button
                onClick={handleTestConnection}
                disabled={!tokenInput.trim() || isTestingConnection}
                className="px-3.5 py-1.5 rounded-xl bg-white/[0.08] hover:bg-white/15 disabled:opacity-40 text-white text-xs font-semibold transition-all border border-white/10"
              >
                {isTestingConnection ? "Testing..." : "Test"}
              </button>
              <button
                onClick={() => saveToken(tokenInput)}
                disabled={!tokenInput.trim()}
                className="px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 text-white text-xs font-semibold shadow"
              >
                Save
              </button>
            </div>
            {testConnectionStatus && (
              <div className={`text-[11px] font-medium p-2.5 rounded-xl border animate-fadeIn ${
                testConnectionStatus.startsWith("Connected")
                  ? "bg-emerald-500/10 text-emerald-300 border-emerald-500/20"
                  : "bg-red-500/10 text-red-300 border-red-500/20"
              }`}>
                {testConnectionStatus}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Target Repository & Branch Selection */}
      <div className="space-y-3 pt-2">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-bold text-white">Target Repository</h2>
          <button
            onClick={handleRefreshAll}
            disabled={isFetchingRepos || isFetchingBranches || isFetchingContext}
            className="text-[11px] text-indigo-400 hover:text-indigo-300 flex items-center gap-1.5 font-medium transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`w-3 h-3 ${isFetchingRepos || isFetchingBranches || isFetchingContext ? "animate-spin" : ""}`} />
            <span>Refresh Repositories & Context</span>
          </button>
        </div>

        {fetchError && (
          <div className="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-xs text-red-300 flex flex-col sm:flex-row sm:items-center justify-between gap-2 animate-fadeIn">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 text-red-400 flex-shrink-0" />
              <span>{fetchError}</span>
            </div>
            <div className="flex items-center gap-2 flex-shrink-0">
              {envTokens && (() => {
                const detected =
                  gitProvider === "github"
                    ? envTokens.github_token
                    : gitProvider === "gitlab"
                    ? envTokens.gitlab_token
                    : envTokens.bitbucket_token;
                if (!detected) return null;
                return (
                  <button
                    onClick={() => {
                      saveToken(detected);
                      setFetchError(null);
                      setTimeout(() => fetchRepositories(), 50);
                    }}
                    className="px-2.5 py-1 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-[11px] font-semibold transition-all shadow"
                  >
                    Use Token from .env ({detected.substring(0, 14)}...)
                  </button>
                );
              })()}
              <button
                onClick={() => setFetchError(null)}
                className="text-red-400 hover:text-red-200 text-xs px-2 py-0.5 rounded hover:bg-red-500/20 transition-colors"
              >
                ✕
              </button>
            </div>
          </div>
        )}

        {isFetchingRepos ? (
          <div className="flex items-center gap-2 text-xs text-white/50 py-2">
            <RefreshCw className="w-3.5 h-3.5 animate-spin" />
            <span>Fetching repositories from {gitProvider}...</span>
          </div>
        ) : (
          <div className="flex flex-wrap items-center gap-3">
            {/* Repository Select */}
            <div className="flex-1 min-w-[220px] max-w-sm">
              <select
                value={selectedRepo}
                onChange={(e) => handleSelectRepo(e.target.value)}
                className="w-full bg-[#1A1D23] border border-white/15 rounded-xl px-3 py-2 text-xs text-white font-medium focus:outline-none focus:border-indigo-500"
              >
                <option value="" disabled>
                  {availableRepos.length > 0 ? "Select Repository..." : "No repositories loaded"}
                </option>
                {availableRepos.map((repo) => (
                  <option key={repo} value={repo}>
                    {repo}
                  </option>
                ))}
              </select>
            </div>

            {/* Branch Select */}
            {selectedRepo && (
              <div className="w-48">
                {isFetchingBranches ? (
                  <div className="flex items-center gap-2 text-xs text-white/50 py-2">
                    <RefreshCw className="w-3 h-3 animate-spin" />
                    <span>Loading branches...</span>
                  </div>
                ) : (
                  <select
                    value={selectedBranch}
                    onChange={(e) => handleSelectBranch(e.target.value)}
                    className="w-full bg-[#1A1D23] border border-white/15 rounded-xl px-3 py-2 text-xs text-white font-medium focus:outline-none focus:border-indigo-500"
                  >
                    <option value="" disabled>
                      {availableBranches.length > 0 ? "Select Branch..." : "No branches found"}
                    </option>
                    {availableBranches.map((br) => (
                      <option key={br} value={br}>
                        {br}
                      </option>
                    ))}
                  </select>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Active Context Selection Section (Commits & PRs) */}
      {selectedRepo && (
        <div className="space-y-3 pt-2 border-t border-white/10">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-sm font-bold text-white">Active Context Selection</h2>
              <p className="text-xs text-white/50">
                Select specific commits or Pull Requests to feed into the Librarian's short-term memory.
              </p>
            </div>
            {isFetchingContext && (
              <div className="flex items-center gap-1.5 text-xs text-white/40">
                <RefreshCw className="w-3 h-3 animate-spin" />
                <span>Syncing...</span>
              </div>
            )}
          </div>

          {contextFetchError && (
            <div className="p-2.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-xs text-amber-300 flex items-center gap-2">
              <Info className="w-3.5 h-3.5 flex-shrink-0" />
              <span>{contextFetchError}</span>
            </div>
          )}

          {/* Context Mode Tabs: Commits (X) / PRs (Y) */}
          <div className="inline-flex p-1 rounded-xl bg-white/[0.04] border border-white/10">
            <button
              onClick={() => setSelectedContextTab("commits")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all flex items-center gap-2 ${
                selectedContextTab === "commits"
                  ? "bg-indigo-600 text-white shadow-sm"
                  : "text-white/60 hover:text-white"
              }`}
            >
              <GitCommit className="w-3.5 h-3.5" />
              <span>Commits ({selectedCommitsSet.size})</span>
            </button>
            <button
              onClick={() => setSelectedContextTab("prs")}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all flex items-center gap-2 ${
                selectedContextTab === "prs"
                  ? "bg-indigo-600 text-white shadow-sm"
                  : "text-white/60 hover:text-white"
              }`}
            >
              <GitPullRequest className="w-3.5 h-3.5" />
              <span>
                {gitProvider === "gitlab" ? "Merge Requests" : "Pull Requests"} ({selectedPRsSet.size})
              </span>
            </button>
          </div>

          {/* Context List Container */}
          <div className="p-3.5 rounded-2xl bg-white/[0.03] border border-white/10 space-y-3">
            {selectedContextTab === "commits" ? (
              <>
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-white">Recent Commits</span>
                  <div className="flex items-center gap-1.5">
                    <span className="text-[11px] text-white/40">Limit:</span>
                    <div className="inline-flex p-0.5 rounded-lg bg-black/40 border border-white/10">
                      {[5, 10, 20, 50].map((lim) => (
                        <button
                          key={lim}
                          onClick={() => {
                            setCommitsLimit(lim);
                            if (selectedRepo) fetchContext(selectedRepo, selectedBranch);
                          }}
                          className={`px-2 py-0.5 rounded text-[10px] font-bold transition-all ${
                            commitsLimit === lim ? "bg-indigo-600 text-white" : "text-white/50 hover:text-white"
                          }`}
                        >
                          {lim}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>

                {recentCommits.length === 0 && !isFetchingContext ? (
                  <div className="py-8 text-center text-xs text-white/40">
                    No commits fetched. Ensure repository and branch are selected, then click Refresh.
                  </div>
                ) : (
                  <div className="max-h-52 overflow-y-auto space-y-1.5 pr-1">
                    {recentCommits.map((c) => {
                      const isSelected = selectedCommitsSet.has(c.id);
                      return (
                        <div
                          key={c.id}
                          onClick={() => toggleCommit(c.id)}
                          className={`p-2 rounded-xl border transition-all flex items-center justify-between gap-3 cursor-pointer ${
                            isSelected
                              ? "bg-indigo-600/15 border-indigo-500/40 text-white"
                              : "bg-black/20 border-white/5 hover:border-white/15 text-white/80"
                          }`}
                        >
                          <div className="flex items-center gap-2.5 min-w-0 flex-1">
                            <div
                              className={`w-4 h-4 rounded flex items-center justify-center border transition-all flex-shrink-0 ${
                                isSelected
                                  ? "bg-indigo-600 border-indigo-500 text-white shadow-sm"
                                  : "bg-white/5 border-white/20 hover:border-white/40 text-transparent"
                              }`}
                            >
                              <Check className="w-3 h-3 stroke-[3]" />
                            </div>
                            <span className="font-mono text-[11px] font-bold text-indigo-400 bg-indigo-500/10 px-1.5 py-0.5 rounded border border-indigo-500/20">
                              {c.id}
                            </span>
                            <span className="text-xs truncate font-medium">{c.message}</span>
                          </div>

                          <div className="flex items-center gap-2 text-[11px] text-white/40 flex-shrink-0">
                            <span>{c.author}</span>
                            <span>•</span>
                            <span>{c.date}</span>
                            {c.url && (
                              <a
                                href={c.url}
                                target="_blank"
                                rel="noreferrer"
                                onClick={(e) => e.stopPropagation()}
                                className="text-white/40 hover:text-white ml-1"
                              >
                                <ExternalLink className="w-3 h-3" />
                              </a>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </>
            ) : (
              <>
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-white">
                    {gitProvider === "gitlab" ? "Open Merge Requests" : "Open Pull Requests"}
                  </span>
                </div>

                {recentPRs.length === 0 && !isFetchingContext ? (
                  <div className="py-8 text-center text-xs text-white/40">
                    No open pull requests found in this repository.
                  </div>
                ) : (
                  <div className="max-h-52 overflow-y-auto space-y-1.5 pr-1">
                    {recentPRs.map((pr) => {
                      const isSelected = selectedPRsSet.has(pr.id);
                      return (
                        <div
                          key={pr.id}
                          onClick={() => togglePR(pr.id)}
                          className={`p-2 rounded-xl border transition-all flex items-center justify-between gap-3 cursor-pointer ${
                            isSelected
                              ? "bg-indigo-600/15 border-indigo-500/40 text-white"
                              : "bg-black/20 border-white/5 hover:border-white/15 text-white/80"
                          }`}
                        >
                          <div className="flex items-center gap-2.5 min-w-0 flex-1">
                            <div
                              className={`w-4 h-4 rounded flex items-center justify-center border transition-all flex-shrink-0 ${
                                isSelected
                                  ? "bg-indigo-600 border-indigo-500 text-white shadow-sm"
                                  : "bg-white/5 border-white/20 hover:border-white/40 text-transparent"
                              }`}
                            >
                              <Check className="w-3 h-3 stroke-[3]" />
                            </div>
                            <span className="font-mono text-[11px] font-bold text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded border border-emerald-500/20">
                              #{pr.id}
                            </span>
                            <span className="text-xs truncate font-medium">{pr.title}</span>
                          </div>

                          <div className="flex items-center gap-2 text-[11px] text-white/40 flex-shrink-0">
                            <span>{pr.author}</span>
                            <span>•</span>
                            <span>{pr.date}</span>
                            {pr.url && (
                              <a
                                href={pr.url}
                                target="_blank"
                                rel="noreferrer"
                                onClick={(e) => e.stopPropagation()}
                                className="text-white/40 hover:text-white ml-1"
                              >
                                <ExternalLink className="w-3 h-3" />
                              </a>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      )}

      {/* Architecture Analysis & Documentation Section (1:1 with ProjectSettingsView.swift) */}
      <div className="space-y-4 pt-2 border-t border-white/10">
        <div>
          <h2 className="text-sm font-bold text-white">Architecture Analysis & Documentation</h2>
          <p className="text-xs text-white/50">
            Let the Librarian agent autonomously explore this repository and generate a comprehensive ARCHITECTURE.md document.
          </p>
        </div>

        {/* AI Reasoning Model Card */}
        <div className="p-4 rounded-2xl bg-white/[0.03] border border-white/10 space-y-3.5">
          {/* Header Row: Label + Explore 400+ Models Button */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs font-semibold text-white">
              <Cpu className="w-3.5 h-3.5 text-indigo-400" />
              <span>AI Reasoning Model</span>
            </div>

            <button
              onClick={() => setShowOpenRouterExplorer(true)}
              className="px-2.5 py-1 rounded-lg bg-white/[0.06] hover:bg-white/10 text-white text-[11px] font-semibold flex items-center gap-1.5 border border-white/10 transition-all shadow-sm"
            >
              <Sparkles className="w-3 h-3 text-indigo-300" />
              <span>Explore 400+ Models</span>
            </button>
          </div>

          <div className="h-px bg-white/10" />

          {/* Model Selection Row */}
          <div className="flex items-center justify-between gap-4">
            <span className="text-xs text-white/50 font-medium">Active Model:</span>
            <select
              value={isCustomModel ? "custom" : llmModel}
              onChange={(e) => {
                const val = e.target.value;
                if (val !== "custom") {
                  setLlmModel(val);
                  localStorage.setItem("llmModel", val);
                } else {
                  setLlmModel("custom");
                }
              }}
              className="bg-[#1A1D23] border border-white/15 rounded-xl px-3 py-1.5 text-xs text-white font-medium focus:outline-none focus:border-indigo-500 max-w-xs text-right"
            >
              {REASONING_MODELS.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.name}
                </option>
              ))}
            </select>
          </div>

          {/* Custom Slug Input */}
          {(llmModel === "custom" || isCustomModel) && (
            <div className="flex items-center gap-2 pt-1">
              <span className="text-[11px] text-white/40 w-20">Model Slug:</span>
              <input
                type="text"
                value={customModelSlug}
                onChange={(e) => {
                  setCustomModelSlug(e.target.value);
                  setLlmModel(e.target.value);
                  localStorage.setItem("llmModel", e.target.value);
                }}
                placeholder="e.g. nvidia/nemotron-3.5-lightning:free"
                className="flex-1 bg-black/40 border border-white/10 rounded-lg px-3 py-1 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500"
              />
            </div>
          )}

        </div>

        {/* Synthesis Context & Knowledge Base Target Destination Card */}
        <div className="p-4 rounded-2xl bg-white/[0.03] border border-white/10 space-y-3.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs font-semibold text-white">
              <Layers className="w-3.5 h-3.5 text-indigo-400" />
              <span>Synthesis Context & Target Destination</span>
            </div>
            <button
              onClick={fetchQueuedThoughts}
              disabled={isFetchingQueue}
              className="text-[11px] text-indigo-400 hover:text-indigo-300 flex items-center gap-1 font-medium transition-colors disabled:opacity-50"
              title="Refresh queued thoughts"
            >
              <RefreshCw className={`w-3 h-3 ${isFetchingQueue ? "animate-spin" : ""}`} />
              <span>Refresh Thoughts</span>
            </button>
          </div>

          <div className="h-px bg-white/10" />

          {/* Context Sources Badges */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
            {/* 1. Voice Thoughts */}
            <div className="p-2.5 rounded-xl bg-black/30 border border-white/10 space-y-1">
              <div className="flex items-center justify-between text-[11px] text-white/50">
                <span className="flex items-center gap-1.5">
                  <Mic className="w-3 h-3 text-rose-400" />
                  <span>Voice Thoughts</span>
                </span>
                <span className="font-mono font-bold text-white text-xs">{queuedThoughts.length}</span>
              </div>
              <div className="text-[10px] text-white/40 truncate">
                {queuedThoughts.length > 0
                  ? "Recorded in Code & Arch mode"
                  : "0 queued thoughts"}
              </div>
              {queuedThoughts.length > 0 && (
                <div className="flex items-center justify-between pt-1">
                  <button
                    onClick={() => setShowQueuedThoughtsModal(!showQueuedThoughtsModal)}
                    className="text-[10px] text-indigo-400 hover:text-indigo-300 flex items-center gap-0.5 underline underline-offset-2"
                  >
                    <span>{showQueuedThoughtsModal ? "Hide details" : "View thoughts"}</span>
                    {showQueuedThoughtsModal ? <ChevronUp className="w-3 h-3" /> : <ChevronDown className="w-3 h-3" />}
                  </button>
                  <button
                    onClick={handleClearQueuedThoughts}
                    className="text-[10px] text-red-400/70 hover:text-red-300 flex items-center gap-1"
                    title="Clear queued thoughts"
                  >
                    <Trash2 className="w-3 h-3" />
                    <span>Clear</span>
                  </button>
                </div>
              )}
            </div>

            {/* 2. Selected Commits */}
            <div className="p-2.5 rounded-xl bg-black/30 border border-white/10 space-y-1">
              <div className="flex items-center justify-between text-[11px] text-white/50">
                <span className="flex items-center gap-1.5">
                  <GitCommit className="w-3 h-3 text-indigo-400" />
                  <span>Selected Commits</span>
                </span>
                <span className="font-mono font-bold text-white text-xs">{selectedCommitsSet.size}</span>
              </div>
              <div className="text-[10px] text-white/40 truncate">
                {selectedCommitsSet.size > 0
                  ? `${selectedCommitsSet.size} commit(s) checked`
                  : "Recent commits included"}
              </div>
            </div>

            {/* 3. Selected PRs */}
            <div className="p-2.5 rounded-xl bg-black/30 border border-white/10 space-y-1">
              <div className="flex items-center justify-between text-[11px] text-white/50">
                <span className="flex items-center gap-1.5">
                  <GitPullRequest className="w-3 h-3 text-emerald-400" />
                  <span>Selected PRs</span>
                </span>
                <span className="font-mono font-bold text-white text-xs">{selectedPRsSet.size}</span>
              </div>
              <div className="text-[10px] text-white/40 truncate">
                {selectedPRsSet.size > 0
                  ? `${selectedPRsSet.size} PR(s) checked`
                  : "Optional PR context"}
              </div>
            </div>
          </div>

          {/* Expanded Queued Thoughts Drawer */}
          {showQueuedThoughtsModal && queuedThoughts.length > 0 && (
            <div className="p-3 rounded-xl bg-black/50 border border-indigo-500/30 space-y-2 max-h-48 overflow-y-auto animate-fadeIn">
              <div className="flex items-center justify-between text-[11px] font-semibold text-white/80">
                <span>Staged Thoughts from Code & Architecture Mode:</span>
                <span className="text-[10px] text-white/40">{queuedThoughts.length} item(s)</span>
              </div>
              <div className="space-y-1.5">
                {queuedThoughts.map((item, idx) => (
                  <div key={item.id || idx} className="p-2 rounded-lg bg-white/[0.04] border border-white/5 text-[11px] text-white/90 space-y-0.5">
                    <div className="flex items-center justify-between text-[10px] text-white/40">
                      <span>Thought #{idx + 1} {item.git_branch ? `• ${item.git_branch}` : ""}</span>
                      <span>{item.source || "voice"}</span>
                    </div>
                    <div className="text-white/80 leading-relaxed font-sans">{item.text}</div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Target Destination Info */}
          <div className="flex items-center justify-between text-[11px] text-white/60 bg-black/20 p-2.5 rounded-xl border border-white/5">
            <div className="flex items-center gap-2">
              <FileText className="w-3.5 h-3.5 text-indigo-400" />
              <span>
                Target Destination:{" "}
                <strong className="text-white">
                  {targetSystem === "obsidian" ? "Local Files (Obsidian)" : targetSystem.toUpperCase()}
                </strong>
                {" • "}
                <code className="text-indigo-300 font-mono text-[10px] bg-black/40 px-1 py-0.5 rounded">
                  {localStorage.getItem("confluencePageTitle") || "ARCHITECTURE.md"}
                </code>
              </span>
            </div>
            <span className="text-[10px] text-white/40 truncate max-w-xs" title={localStorage.getItem("obsidianPath") || ""}>
              {targetSystem === "obsidian" ? (localStorage.getItem("obsidianPath") || "Default vault") : ""}
            </span>
          </div>
        </div>

        {/* Primary Action Button */}
        <div className="space-y-3">
          <button
            onClick={handleGenerateArchitecture}
            disabled={isGeneratingArch || !selectedRepo}
            className="px-5 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white text-xs font-semibold shadow-lg shadow-indigo-600/25 flex items-center gap-2 transition-all"
          >
            {isGeneratingArch ? (
              <>
                <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                <span>Analyzing & Generating...</span>
              </>
            ) : (
              <>
                <Cpu className="w-3.5 h-3.5" />
                <span>Generate Architecture Document</span>
              </>
            )}
          </button>

          {/* Status Message Banner */}
          {(localValidationError || archGenMessage) && (
            <div
              className={`p-3 rounded-xl border text-xs flex items-center justify-between gap-3 animate-fadeIn ${
                localValidationError || archGenStatus === "error" || archGenMessage?.includes("Error")
                  ? "bg-red-500/10 border-red-500/20 text-red-300"
                  : archGenStatus === "generating"
                  ? "bg-indigo-500/10 border-indigo-500/25 text-indigo-200"
                  : "bg-emerald-500/10 border-emerald-500/20 text-emerald-300"
              }`}
            >
              <div className="flex items-center gap-2.5 min-w-0">
                {localValidationError || archGenStatus === "error" || archGenMessage?.includes("Error") ? (
                  <AlertCircle className="w-4 h-4 text-red-400 flex-shrink-0" />
                ) : archGenStatus === "generating" ? (
                  <RefreshCw className="w-4 h-4 text-indigo-400 animate-spin flex-shrink-0" />
                ) : (
                  <CheckCircle2 className="w-4 h-4 text-emerald-400 flex-shrink-0" />
                )}
                <span className="leading-relaxed">{localValidationError || archGenMessage}</span>
              </div>

              <div className="flex items-center gap-2 flex-shrink-0">
                {archGenStatus === "completed" && onNavigateTab && (
                  <button
                    onClick={() => onNavigateTab("pending_updates")}
                    className="px-2.5 py-1 rounded-lg bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-200 text-[11px] font-semibold flex items-center gap-1 transition-colors border border-emerald-500/30"
                  >
                    <span>View in Pending Updates</span>
                    <ArrowRight className="w-3 h-3" />
                  </button>
                )}
                {archGenStatus !== "generating" && (
                  <button
                    onClick={() => {
                      setLocalValidationError(null);
                      clearStatus();
                    }}
                    className="p-1 rounded-md text-white/40 hover:text-white hover:bg-white/10 transition-colors"
                    title="Dismiss"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* OpenRouter 400+ Models Explorer Modal */}
      <OpenRouterExplorerModal
        isOpen={showOpenRouterExplorer}
        onClose={() => setShowOpenRouterExplorer(false)}
        selectedModelId={llmModel}
        onSelectModel={(modelId) => {
          setLlmModel(modelId);
          setCustomModelSlug(modelId);
          localStorage.setItem("llmModel", modelId);
        }}
      />
    </div>
  );
};
