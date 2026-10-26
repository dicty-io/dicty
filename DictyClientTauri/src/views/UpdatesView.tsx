import React, { useState, useEffect } from "react";
import {
  RefreshCw,
  CheckCircle2,
  AlertCircle,
  DownloadCloud,
  ExternalLink,
} from "lucide-react";
import { engineApi } from "../services/engineApi";
import { invoke } from "@tauri-apps/api/core";
import { openExternalUrl } from "../utils/browser";

interface UpdateInfo {
  has_update: boolean;
  latest_version: string;
  current_version: string;
  release_name?: string;
  release_notes?: string;
  download_url?: string | null;
  asset_name?: string | null;
  repo?: string;
  published_at?: string | null;
  html_url?: string | null;
  error?: string | null;
}

const parseVersion = (v: string): [number, number, number, number] => {
  if (!v) return [0, 0, 0, 0];
  const clean = v.trim().replace(/^[vV]/, "");
  let basePart = clean;
  let serial = 0;

  if (clean.includes("-")) {
    const [base, suffix] = clean.split("-", 2);
    basePart = base;
    const match = suffix.match(/^\d+/);
    if (match) {
      serial = parseInt(match[0], 10);
    }
  }

  const parts = basePart.split(".").map((p) => {
    const n = parseInt(p, 10);
    return isNaN(n) ? 0 : n;
  });

  while (parts.length < 3) {
    parts.push(0);
  }

  return [parts[0], parts[1], parts[2], serial];
};

const semverGt = (v1: string, v2: string): boolean => {
  const p1 = parseVersion(v1);
  const p2 = parseVersion(v2);

  for (let i = 0; i < 4; i++) {
    if (p1[i] > p2[i]) return true;
    if (p1[i] < p2[i]) return false;
  }
  return false;
};

export const UpdatesView: React.FC = () => {
  const [currentVersion, setCurrentVersion] = useState("1.0.0");
  const repo = "dicty-io/dicty";
  const [githubToken] = useState(() => localStorage.getItem("githubToken") || "");
  const [isChecking, setIsChecking] = useState(false);
  const [isApplying, setIsApplying] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [lastCheckedTime, setLastCheckedTime] = useState<string | null>(() => {
    return localStorage.getItem("dicty_last_update_check");
  });

  const handleCheckForUpdates = async (manualRepo?: string, manualToken?: string, activeVer?: string) => {
    if (isChecking) return;
    setIsChecking(true);
    setErrorMsg(null);

    const versionToCompare = activeVer ?? currentVersion;
    const targetRepo = manualRepo ?? repo;
    const targetToken = manualToken ?? githubToken;

    // Wake up local backend if running inside Tauri
    try {
      await invoke("ensure_engine").catch(() => {});
    } catch {
      // Ignored in browser preview
    }

    let checkSucceeded = false;

    // 1. Try querying local engine
    try {
      const res = await engineApi.checkForUpdates(versionToCompare, targetRepo, targetToken);
      if (res && res.latest_version) {
        const hasUpdate = Boolean(res.has_update || semverGt(res.latest_version, versionToCompare));
        setUpdateInfo({
          ...res,
          has_update: hasUpdate,
        });
        if (res.error && !res.latest_version) {
          setErrorMsg(res.error);
        } else {
          // If the engine reports has_update, but provided no download_url,
          // the engine may be an older build that only checked /releases/latest.
          // Don't treat check as resolved; let direct GitHub fetch find the OS-specific installer.
          if (!hasUpdate || res.download_url) {
            checkSucceeded = true;
          }
        }
      }
    } catch (engineErr) {
      console.warn("Local engine check failed, falling back to direct GitHub release fetch:", engineErr);
    }

    // 2. Fallback to direct GitHub API fetch if local engine was offline / starting / missing download_url
    if (!checkSucceeded) {
      const isWindows = navigator.userAgent.includes("Windows") || navigator.platform.includes("Win");
      const isMac = navigator.userAgent.includes("Mac") || navigator.platform.includes("Mac");

      const matchAsset = (assets: any[]) => {
        if (!assets || !Array.isArray(assets)) return null;
        if (isWindows) {
          // Priority 1: .exe or .msi with setup / installer in filename
          const setupExe = assets.find((a: any) => {
            const n = a.name?.toLowerCase() || "";
            return (n.endsWith(".exe") || n.endsWith(".msi")) && (n.includes("setup") || n.includes("installer"));
          });
          if (setupExe) return setupExe;
          // Priority 2: any .exe or .msi
          return assets.find((a: any) => {
            const n = a.name?.toLowerCase() || "";
            return n.endsWith(".exe") || n.endsWith(".msi");
          }) || null;
        }
        if (isMac) {
          return assets.find((a: any) => {
            const n = a.name?.toLowerCase() || "";
            return n.endsWith(".dmg") || n.endsWith(".pkg");
          }) || null;
        }
        // Linux
        return assets.find((a: any) => {
          const n = a.name?.toLowerCase() || "";
          return n.endsWith(".appimage") || n.endsWith(".tar.gz") || n.endsWith(".deb");
        }) || null;
      };

      const reposToTry = [
        `https://api.github.com/repos/${targetRepo}/releases?per_page=30`,
        `https://api.github.com/repos/dicty-io/dicty/releases?per_page=30`,
        `https://api.github.com/repos/vkazmin1/dicty/releases?per_page=30`,
      ];

      const ghHeaders: Record<string, string> = {
        Accept: "application/vnd.github.v3+json",
      };
      if (targetToken && targetToken.trim()) {
        ghHeaders.Authorization = `Bearer ${targetToken.trim()}`;
      }

      for (const url of reposToTry) {
        if (checkSucceeded) break;
        try {
          const ghRes = await fetch(url, { headers: ghHeaders });
          if (!ghRes.ok) continue;

          const data = await ghRes.json();
          const releasesList: any[] = Array.isArray(data) ? data : (data.tag_name ? [data] : []);
          if (releasesList.length === 0) continue;

          // Sort descending by semver
          releasesList.sort((a: any, b: any) => {
            const vA = (a.tag_name || "").replace(/^[vV]/, "");
            const vB = (b.tag_name || "").replace(/^[vV]/, "");
            return semverGt(vA, vB) ? -1 : semverGt(vB, vA) ? 1 : 0;
          });

          // Find the latest release that contains an installer for current OS
          let matchingRelease: any = null;
          let matchingAsset: any = null;
          for (const rel of releasesList) {
            if (rel.draft) continue;
            const asset = matchAsset(rel.assets);
            if (asset) {
              matchingRelease = rel;
              matchingAsset = asset;
              break;
            }
          }

          if (matchingRelease && matchingAsset) {
            const latestTag = matchingRelease.tag_name || "";
            const cleanVersion = latestTag.replace(/^[vV]/, "");
            const hasUpdate = semverGt(cleanVersion, versionToCompare);

            setUpdateInfo({
              has_update: hasUpdate,
              latest_version: cleanVersion || versionToCompare,
              current_version: versionToCompare,
              release_name: matchingRelease.name || latestTag,
              release_notes: matchingRelease.body || `Release ${latestTag} is available on GitHub.`,
              download_url: matchingAsset.browser_download_url || null,
              asset_name: matchingAsset.name || null,
              repo: targetRepo,
              published_at: matchingRelease.published_at,
              html_url: matchingRelease.html_url || `https://github.com/${targetRepo}/releases`,
              error: null,
            });
            setErrorMsg(null);
            checkSucceeded = true;
            break;
          } else {
            // Releases exist, but none contained an installer for current OS
            const topRel = releasesList[0];
            const latestTag = topRel.tag_name || "";
            const cleanVersion = latestTag.replace(/^[vV]/, "");
            const hasUpdate = semverGt(cleanVersion, versionToCompare);

            setUpdateInfo({
              has_update: hasUpdate,
              latest_version: cleanVersion || versionToCompare,
              current_version: versionToCompare,
              release_name: topRel.name || latestTag,
              release_notes: topRel.body || "Newer release found, but installer for your operating system is currently unavailable.",
              download_url: null,
              asset_name: null,
              repo: targetRepo,
              published_at: topRel.published_at,
              html_url: topRel.html_url || `https://github.com/${targetRepo}/releases`,
              error: null,
            });
            setErrorMsg(null);
            checkSucceeded = true;
            break;
          }
        } catch (directErr: any) {
          console.warn(`Direct GitHub release fetch from ${url} failed:`, directErr);
        }
      }
    }

    if (checkSucceeded) {
      const nowStr = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
      setLastCheckedTime(nowStr);
      localStorage.setItem("dicty_last_update_check", nowStr);
    } else {
      setErrorMsg("Unable to reach GitHub update servers. Please check your internet connection.");
    }

    setIsChecking(false);
  };

  useEffect(() => {
    invoke<string>("get_app_version")
      .then((ver) => {
        if (ver) {
          const clean = ver.replace(/^[vV]/, "");
          setCurrentVersion(clean);
          handleCheckForUpdates(undefined, undefined, clean);
        } else {
          handleCheckForUpdates();
        }
      })
      .catch(() => {
        handleCheckForUpdates();
      });
  }, []);

  const handleApplyUpdate = async () => {
    if (!updateInfo) return;
    setIsApplying(true);
    setDownloadProgress(0);

    try {
      if (updateInfo.download_url) {
        let backendApplied = false;
        try {
          const applyRes = await engineApi.applyUpdate(updateInfo.download_url, updateInfo.asset_name || undefined);
          if (applyRes?.status === "success" || applyRes?.success) {
            backendApplied = true;
            const interval = setInterval(async () => {
              try {
                const prog = await engineApi.getUpdateProgress();
                if (prog?.progress !== undefined) {
                  setDownloadProgress(prog.progress);
                  if (prog.progress >= 100) {
                    clearInterval(interval);
                  }
                }
              } catch {
                clearInterval(interval);
              }
            }, 800);
          }
        } catch (engineErr) {
          console.warn("Local engine could not apply update directly, falling back to browser download:", engineErr);
        }

        if (!backendApplied) {
          // If backend engine couldn't handle download, open installer URL in browser directly
          openExternalUrl(updateInfo.download_url);
          setIsApplying(false);
        }
      } else if (updateInfo.html_url) {
        openExternalUrl(updateInfo.html_url);
        setIsApplying(false);
      }
    } catch (err: any) {
      setErrorMsg(err?.message || "Failed to initiate update.");
      setIsApplying(false);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto px-10 py-8 max-w-2xl mx-auto space-y-6 select-none animate-in fade-in duration-200">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-white/10 pb-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-white">App Updates</h1>
          <p className="text-xs text-white/50">Keep Dicty synchronized with the latest releases.</p>
        </div>
        <button
          onClick={() => handleCheckForUpdates()}
          disabled={isChecking || isApplying}
          title="Check for updates"
          className="p-2 rounded-xl bg-white/[0.05] hover:bg-white/10 text-white/70 hover:text-white transition-all border border-white/10 disabled:opacity-40"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isChecking ? "animate-spin text-[#87B996]" : ""}`} />
        </button>
      </div>

      {/* Minimalist Status Card */}
      <div className="rounded-2xl bg-white/[0.03] border border-white/10 p-8 flex flex-col items-center text-center space-y-4 shadow-xl">
        {/* State Icon */}
        <div className="w-12 h-12 rounded-full bg-[#5D6658]/20 border border-[#5D6658]/30 flex items-center justify-center text-[#87B996]">
          {isChecking ? (
            <RefreshCw className="w-5 h-5 animate-spin" />
          ) : errorMsg ? (
            <AlertCircle className="w-5 h-5 text-red-400" />
          ) : updateInfo?.has_update ? (
            <DownloadCloud className="w-5 h-5 text-[#87B996]" />
          ) : (
            <CheckCircle2 className="w-5 h-5 text-[#87B996]" />
          )}
        </div>

        {/* State Content */}
        {isChecking ? (
          <div className="space-y-1">
            <h3 className="text-base font-semibold text-white">Checking for updates…</h3>
            <p className="text-xs text-white/40">Looking for new releases</p>
          </div>
        ) : errorMsg ? (
          <div className="space-y-2 max-w-sm">
            <h3 className="text-base font-semibold text-white">Unable to check for updates</h3>
            <p className="text-xs text-red-400/80">{errorMsg}</p>
            <button
              onClick={() => handleCheckForUpdates()}
              className="text-xs text-white/60 hover:text-white underline underline-offset-4 pt-1"
            >
              Try again
            </button>
          </div>
        ) : updateInfo?.has_update ? (
          <div className="space-y-4 max-w-md w-full">
            <div className="space-y-1">
              <h3 className="text-lg font-bold text-white tracking-tight">
                Dicty v{updateInfo.latest_version} is available
              </h3>
              <p className="text-xs text-white/50">
                You have version <span className="font-mono text-white/70">v{currentVersion}</span>
              </p>
            </div>

            {isApplying ? (
              <div className="space-y-2 pt-1 max-w-xs mx-auto w-full">
                <div className="w-full bg-white/10 rounded-full h-1.5 overflow-hidden">
                  <div
                    className="bg-[#87B996] h-full transition-all duration-300 rounded-full"
                    style={{ width: `${downloadProgress}%` }}
                  />
                </div>
                <div className="flex items-center justify-between text-[11px] text-white/50 font-mono">
                  <span>{downloadProgress >= 100 ? "Installing & relaunching…" : "Downloading update…"}</span>
                  <span>{Math.round(downloadProgress)}%</span>
                </div>
              </div>
            ) : updateInfo.download_url ? (
              <div className="flex items-center justify-center gap-3 pt-1">
                <button
                  onClick={handleApplyUpdate}
                  className="px-5 py-2.5 rounded-xl bg-[#5D6658] hover:bg-[#6e7968] text-white text-xs font-semibold shadow-md shadow-[#5D6658]/25 transition-all flex items-center gap-2"
                >
                  <DownloadCloud className="w-4 h-4" />
                  <span>Update & Relaunch</span>
                </button>
                {updateInfo.html_url && (
                  <a
                    href={updateInfo.html_url}
                    target="_blank"
                    rel="noreferrer"
                    className="px-3.5 py-2.5 rounded-xl text-white/50 hover:text-white text-xs font-medium transition-colors flex items-center gap-1.5"
                  >
                    <span>View on GitHub</span>
                    <ExternalLink className="w-3 h-3 text-white/40" />
                  </a>
                )}
              </div>
            ) : (
              <div className="flex flex-col items-center gap-2.5 pt-1">
                <p className="text-xs text-amber-300/90 font-medium">
                  Installer for your operating system is currently building or unavailable for this release.
                </p>
                {updateInfo.html_url && (
                  <a
                    href={updateInfo.html_url}
                    target="_blank"
                    rel="noreferrer"
                    className="px-4 py-2 rounded-xl bg-white/[0.05] hover:bg-white/10 text-white/80 hover:text-white text-xs font-medium border border-white/10 transition-all flex items-center gap-1.5"
                  >
                    <span>View Release on GitHub</span>
                    <ExternalLink className="w-3.5 h-3.5 text-white/50" />
                  </a>
                )}
              </div>
            )}
          </div>
        ) : (
          <div className="space-y-3">
            <div className="space-y-1">
              <h3 className="text-base font-semibold text-white">Dicty is up to date</h3>
              <p className="text-xs text-white/40">
                Version <span className="font-mono text-white/60">v{currentVersion}</span> is the newest version.
              </p>
            </div>
            <div>
              <button
                onClick={() => handleCheckForUpdates()}
                disabled={isChecking}
                className="px-4 py-2 rounded-xl bg-white/[0.05] hover:bg-white/10 text-white/70 hover:text-white text-xs font-medium border border-white/10 transition-all"
              >
                Check for Updates
              </button>
            </div>
          </div>
        )}

        {lastCheckedTime && (
          <span className="text-[10px] text-white/30 pt-2 block">
            Last checked {lastCheckedTime}
          </span>
        )}
      </div>

      {/* Release Notes (Clean, non-distracting) */}
      {updateInfo?.has_update && updateInfo?.release_notes && (
        <div className="rounded-2xl bg-white/[0.02] border border-white/10 p-5 space-y-3">
          <div className="flex items-center justify-between border-b border-white/5 pb-2.5">
            <span className="text-xs font-semibold text-white/70">What's New in v{updateInfo.latest_version}</span>
            {updateInfo.html_url && (
              <a
                href={updateInfo.html_url}
                target="_blank"
                rel="noreferrer"
                className="text-[11px] text-white/40 hover:text-white flex items-center gap-1 transition-colors"
              >
                <span>Changelog</span>
                <ExternalLink className="w-3 h-3 text-white/30" />
              </a>
            )}
          </div>
          <div className="text-xs text-white/65 leading-relaxed max-h-48 overflow-y-auto whitespace-pre-wrap font-sans select-text">
            {updateInfo.release_notes}
          </div>
        </div>
      )}
    </div>
  );
};
