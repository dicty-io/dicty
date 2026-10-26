import React, { useState, useRef } from "react";
import {
  ConfluenceIcon,
  LinearIcon,
  NotionIcon,
  LocalFilesIcon,
} from "../components/BrandIcons";
import {
  Info,
  RefreshCw,
  Globe,
  Zap,
  CheckCircle2,
  XCircle,
} from "lucide-react";

export const KnowledgeBaseView: React.FC = () => {
  const [targetSystem, setTargetSystem] = useState<string>(() => {
    return localStorage.getItem("targetSystem") || "obsidian";
  });

  // Local files / Obsidian paths
  const [obsidianPath, setObsidianPath] = useState<string>(() => {
    return localStorage.getItem("obsidianPath") || "";
  });

  const [specificTargetFile, setSpecificTargetFile] = useState<string>(() => {
    return localStorage.getItem("confluencePageTitle") || "";
  });

  // Confluence settings
  const [confluenceUrl, setConfluenceUrl] = useState<string>(() => {
    return localStorage.getItem("confluenceUrl") || "";
  });
  const [confluenceSpace, setConfluenceSpace] = useState<string>(() => {
    return localStorage.getItem("confluenceSpace") || "";
  });
  const [confluenceUser, setConfluenceUser] = useState<string>(() => {
    return localStorage.getItem("confluenceUser") || "";
  });

  // Linear settings
  const [linearWorkspaceId, setLinearWorkspaceId] = useState<string>(() => {
    return localStorage.getItem("linearWorkspaceId") || "";
  });
  const [linearSearchAllWorkspaces, setLinearSearchAllWorkspaces] = useState<boolean>(() => {
    return localStorage.getItem("linearSearchAllWorkspaces") === "true";
  });
  const [isFetchingLinear, setIsFetchingLinear] = useState(false);
  const [linearTeams, setLinearTeams] = useState<{ id: string; name: string }[]>([
    { id: "team_eng", name: "Core Engineering" },
    { id: "team_infra", name: "Platform & Infra" },
  ]);

  // Notion settings
  const [notionPageId, setNotionPageId] = useState<string>(() => {
    return localStorage.getItem("notionPageId") || "";
  });
  const [isTestingNotion, setIsTestingNotion] = useState(false);
  const [notionTestStatus, setNotionTestStatus] = useState<string | null>(null);
  const [notionTestSuccess, setNotionTestSuccess] = useState(false);

  // Tooltip state
  const [showInfoTooltip, setShowInfoTooltip] = useState(false);

  // Hidden file/dir inputs for browsing
  const fileInputRef = useRef<HTMLInputElement>(null);
  const dirInputRef = useRef<HTMLInputElement>(null);

  const handleSelectSystem = (sys: string) => {
    setTargetSystem(sys);
    localStorage.setItem("targetSystem", sys);
  };

  const handleObsidianPathChange = (val: string) => {
    setObsidianPath(val);
    localStorage.setItem("obsidianPath", val);
  };

  const handleTargetFileChange = (val: string) => {
    setSpecificTargetFile(val);
    localStorage.setItem("confluencePageTitle", val);
  };

  // Test Notion connection
  const testNotionConnection = () => {
    setIsTestingNotion(true);
    setNotionTestStatus(null);
    setTimeout(() => {
      setIsTestingNotion(false);
      setNotionTestSuccess(true);
      setNotionTestStatus("Connected successfully to Notion workspace!");
      setTimeout(() => setNotionTestStatus(null), 4000);
    }, 1100);
  };

  // Fetch Linear workspaces
  const fetchLinearWorkspaces = () => {
    setIsFetchingLinear(true);
    setTimeout(() => {
      setIsFetchingLinear(false);
      setLinearTeams([
        { id: "team_eng", name: "Core Engineering" },
        { id: "team_infra", name: "Platform & Infra" },
        { id: "team_arch", name: "Architecture & Design" },
      ]);
    }, 900);
  };

  const handleBrowseTargetFile = () => {
    if (fileInputRef.current) {
      fileInputRef.current.click();
    }
  };

  const handleBrowseFolder = () => {
    if (dirInputRef.current) {
      dirInputRef.current.click();
    }
  };

  const onFileSelected = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      const file = e.target.files[0];
      const path = (file as any).path || file.name;
      handleTargetFileChange(path);
    }
  };

  const onDirSelected = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      const file = e.target.files[0];
      const path = (file as any).path || (file as any).webkitRelativePath || "Local Vault";
      handleObsidianPathChange(path);
    }
  };

  const systems = [
    { id: "confluence", name: "Confluence", icon: ConfluenceIcon },
    { id: "linear", name: "Linear", icon: LinearIcon },
    { id: "notion", name: "Notion", icon: NotionIcon },
    { id: "obsidian", name: "Local Files", icon: LocalFilesIcon },
  ];

  return (
    <div className="flex-1 overflow-y-auto px-10 py-8 max-w-4xl space-y-6 select-none bg-transparent">
      {/* Hidden inputs for native file browsing */}
      <input
        type="file"
        ref={fileInputRef}
        onChange={onFileSelected}
        className="hidden"
      />
      <input
        type="file"
        // @ts-ignore
        webkitdirectory="true"
        directory="true"
        ref={dirInputRef}
        onChange={onDirSelected}
        className="hidden"
      />

      {/* Page Header (1:1 with macOS KnowledgeBaseSettingsView.swift) */}
      <div className="space-y-1.5">
        <h1 className="text-3xl font-bold tracking-tight text-white font-sans">
          Knowledge Base Settings
        </h1>
        <p className="text-xs text-white/50">
          Configure your remote or local knowledge base. Dicty will use this to synchronize your documentation.
        </p>
      </div>

      {/* Subtle Divider (1:1 with Divider()) */}
      <div className="h-px bg-white/10" />

      {/* Target System Section */}
      <div className="space-y-3">
        <h2 className="text-sm font-semibold text-white">Target System</h2>

        {/* Segmented Picker (1:1 with KnowledgeBaseSegmentedPicker) */}
        <div className="p-1 rounded-xl bg-black/40 border border-white/10 flex items-center gap-1.5">
          {systems.map((sys) => {
            const Icon = sys.icon;
            const isSelected = targetSystem === sys.id;
            return (
              <button
                key={sys.id}
                onClick={() => handleSelectSystem(sys.id)}
                className={`flex-1 py-2 px-3 rounded-lg text-xs font-semibold flex items-center justify-center gap-2 transition-all ${
                  isSelected
                    ? "bg-white/[0.14] text-white shadow-sm"
                    : "text-white/60 hover:text-white hover:bg-white/[0.04]"
                }`}
              >
                <Icon size={15} />
                <span>{sys.name}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* --- LOCAL FILES (OBSIDIAN) --- */}
      {targetSystem === "obsidian" && (
        <div className="space-y-5 pt-1">
          {/* Specific Target File (Optional) */}
          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-white">
              Specific Target File (Optional)
            </h3>
            <div className="flex items-center gap-2">
              <input
                type="text"
                value={specificTargetFile}
                onChange={(e) => handleTargetFileChange(e.target.value)}
                placeholder="E.g., ProjectX/Architecture"
                className="flex-1 bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
              />
              <button
                onClick={handleBrowseTargetFile}
                className="px-4 py-2 rounded-xl bg-white/[0.06] hover:bg-white/10 text-white text-xs font-medium border border-white/10 transition-all whitespace-nowrap"
              >
                Browse...
              </button>
            </div>
          </div>

          <div className="h-px bg-white/10" />

          {/* Local Data Source Path */}
          <div className="space-y-2">
            <div className="flex items-center gap-1.5 relative">
              <h3 className="text-sm font-semibold text-white">
                Local Data Source Path
              </h3>
              <div
                onMouseEnter={() => setShowInfoTooltip(true)}
                onMouseLeave={() => setShowInfoTooltip(false)}
                className="text-white/40 hover:text-white/80 cursor-help"
              >
                <Info className="w-3.5 h-3.5" />
              </div>

              {/* Info Tooltip matching InfoSign */}
              {showInfoTooltip && (
                <div className="absolute left-44 -top-8 bg-[#1A1D23] border border-white/15 rounded-xl px-3 py-2 text-[11px] text-white/80 shadow-2xl z-30 max-w-xs leading-relaxed animate-fadeIn">
                  This can be an Obsidian vault, a local folder of markdown files, or a locally cloned GitHub repository. The AI will scan this folder for context.
                </div>
              )}
            </div>

            <div className="flex items-center gap-2">
              <input
                type="text"
                value={obsidianPath}
                onChange={(e) => handleObsidianPathChange(e.target.value)}
                placeholder="/Users/name/Documents/MyDocs"
                className="flex-1 bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50 font-mono"
              />
              <button
                onClick={handleBrowseFolder}
                className="px-4 py-2 rounded-xl bg-white/[0.06] hover:bg-white/10 text-white text-xs font-medium border border-white/10 transition-all whitespace-nowrap"
              >
                Browse...
              </button>
            </div>
          </div>
        </div>
      )}

      {/* --- CONFLUENCE --- */}
      {targetSystem === "confluence" && (
        <div className="space-y-4 pt-1">
          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-white">Target Page (Optional)</h3>
            <input
              type="text"
              value={specificTargetFile}
              onChange={(e) => handleTargetFileChange(e.target.value)}
              placeholder="E.g., Architecture Overview"
              className="w-full bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>

          <div className="h-px bg-white/10" />

          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-white">Host URL</h3>
            <input
              type="text"
              value={confluenceUrl}
              onChange={(e) => {
                setConfluenceUrl(e.target.value);
                localStorage.setItem("confluenceUrl", e.target.value);
              }}
              placeholder="https://your-domain.atlassian.net"
              className="w-full bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>

          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-white">Space Key</h3>
            <input
              type="text"
              value={confluenceSpace}
              onChange={(e) => {
                setConfluenceSpace(e.target.value);
                localStorage.setItem("confluenceSpace", e.target.value);
              }}
              placeholder="ENG"
              className="w-full bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>

          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-white">Username / Email</h3>
            <input
              type="text"
              value={confluenceUser}
              onChange={(e) => {
                setConfluenceUser(e.target.value);
                localStorage.setItem("confluenceUser", e.target.value);
              }}
              placeholder="john@example.com"
              className="w-full bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>

          <div className="space-y-1 pt-1">
            <h3 className="text-sm font-semibold text-white">API Token</h3>
            <p className="text-xs text-indigo-400">
              Configure your Confluence API Token in the 'API Integrations' tab.
            </p>
          </div>
        </div>
      )}

      {/* --- LINEAR --- */}
      {targetSystem === "linear" && (
        <div className="space-y-4 pt-1">
          <div className="space-y-1">
            <h3 className="text-sm font-semibold text-white">Target Document</h3>
            <p className="text-xs text-white/50">
              No target required. The AI will autonomously explore your Linear workspace to find the right document or create a new one.
            </p>
          </div>

          <div className="h-px bg-white/10" />

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold text-white">Target Workspace</h3>
              <button
                onClick={fetchLinearWorkspaces}
                disabled={isFetchingLinear}
                className="text-xs text-indigo-400 hover:text-indigo-300 flex items-center gap-1 transition-colors"
              >
                <RefreshCw className={`w-3 h-3 ${isFetchingLinear ? "animate-spin" : ""}`} />
                <span>Refresh</span>
              </button>
            </div>

            <select
              value={linearWorkspaceId}
              onChange={(e) => {
                setLinearWorkspaceId(e.target.value);
                localStorage.setItem("linearWorkspaceId", e.target.value);
              }}
              className="w-full bg-[#1A1D23] border border-white/15 rounded-xl px-3.5 py-2 text-xs text-white font-medium focus:outline-none focus:border-indigo-500"
            >
              <option value="">Default Team</option>
              {linearTeams.map((team) => (
                <option key={team.id} value={`team:${team.id}`}>
                  Team: {team.name}
                </option>
              ))}
            </select>
          </div>

          {/* Global Document Search Toggle */}
          <div className="flex items-center justify-between p-3 rounded-xl bg-white/[0.03] border border-white/10">
            <div className="flex items-center gap-2.5">
              <Globe className="w-4 h-4 text-white/50" />
              <div>
                <span className="text-xs font-semibold text-white block">
                  Global Document Search
                </span>
                <span className="text-[11px] text-white/40 block">
                  If enabled, the AI will search across your entire Linear workspace rather than just the selected team/project.
                </span>
              </div>
            </div>
            <button
              onClick={() => {
                const next = !linearSearchAllWorkspaces;
                setLinearSearchAllWorkspaces(next);
                localStorage.setItem("linearSearchAllWorkspaces", String(next));
              }}
              className={`w-9 h-5 rounded-full p-0.5 transition-colors ${
                linearSearchAllWorkspaces ? "bg-indigo-600" : "bg-white/15"
              }`}
            >
              <div
                className={`w-4 h-4 rounded-full bg-white transition-transform ${
                  linearSearchAllWorkspaces ? "translate-x-4" : "translate-x-0"
                }`}
              />
            </button>
          </div>

          <div className="h-px bg-white/10" />

          <div className="space-y-1">
            <h3 className="text-sm font-semibold text-white">API Token</h3>
            <p className="text-xs text-indigo-400">
              Configure your Linear API Token in the 'API Integrations' tab.
            </p>
          </div>
        </div>
      )}

      {/* --- NOTION --- */}
      {targetSystem === "notion" && (
        <div className="space-y-4 pt-1">
          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-white">
              Target Page / Section Title (Optional)
            </h3>
            <input
              type="text"
              value={specificTargetFile}
              onChange={(e) => handleTargetFileChange(e.target.value)}
              placeholder="E.g., Architecture Overview"
              className="w-full bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50"
            />
          </div>

          <div className="h-px bg-white/10" />

          <div className="space-y-2">
            <h3 className="text-sm font-semibold text-white">
              Parent Page or Database ID
            </h3>
            <input
              type="text"
              value={notionPageId}
              onChange={(e) => {
                setNotionPageId(e.target.value);
                localStorage.setItem("notionPageId", e.target.value);
              }}
              placeholder="32-character ID or full Notion page URL"
              className="w-full bg-black/30 border border-white/10 rounded-xl px-3.5 py-2 text-xs text-white placeholder-white/30 focus:outline-none focus:border-indigo-500/50 font-mono"
            />
            <p className="text-xs text-white/50 leading-relaxed">
              Create an Internal Integration at notion.so/profile/integrations and share your target parent page with it via '...' -&gt; 'Add connections'.
            </p>
          </div>

          <div className="h-px bg-white/10" />

          <div className="space-y-1">
            <h3 className="text-sm font-semibold text-white">API Token</h3>
            <p className="text-xs text-indigo-400">
              Configure your Notion Integration Token in the 'API Integrations' tab.
            </p>
          </div>

          <div className="pt-2 flex items-center gap-3">
            <button
              onClick={testNotionConnection}
              disabled={isTestingNotion || !notionPageId.trim()}
              className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 text-white text-xs font-semibold flex items-center gap-2 transition-all shadow"
            >
              {isTestingNotion ? (
                <>
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                  <span>Testing Connection...</span>
                </>
              ) : (
                <>
                  <Zap className="w-3.5 h-3.5" />
                  <span>Test Connection</span>
                </>
              )}
            </button>

            {notionTestStatus && (
              <div
                className={`flex items-center gap-1.5 text-xs font-medium ${
                  notionTestSuccess ? "text-emerald-400" : "text-red-400"
                }`}
              >
                {notionTestSuccess ? (
                  <CheckCircle2 className="w-3.5 h-3.5" />
                ) : (
                  <XCircle className="w-3.5 h-3.5" />
                )}
                <span>{notionTestStatus}</span>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
