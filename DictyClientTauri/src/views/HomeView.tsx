import React, { useState, useEffect } from "react";
import {
  Type,
  Activity,
  Zap,
  Clock,
  BookOpen,
  Mic,
  TrendingUp,
  Keyboard,
  Calendar,
} from "lucide-react";
import { engineApi } from "../services/engineApi";

interface MetricCardProps {
  title: string;
  value: string;
  subtitle?: string;
  icon: any;
  valueColor?: string;
}

const MetricCard: React.FC<MetricCardProps> = ({
  title,
  value,
  subtitle,
  icon: Icon,
  valueColor = "text-white",
}) => {
  return (
    <div className="dicty-card p-4 sm:p-5 rounded-2xl flex flex-col justify-between space-y-3 min-w-0 transition-all hover:border-white/15">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-white/50 truncate">{title}</span>
        <div className="w-8 h-8 rounded-xl bg-white/[0.04] border border-white/10 flex items-center justify-center text-white/70 flex-shrink-0">
          <Icon className="w-4 h-4 text-[#87B996]" />
        </div>
      </div>
      <div>
        <div className={`text-xl sm:text-2xl font-bold tracking-tight ${valueColor} truncate`}>
          {value}
        </div>
        {subtitle && (
          <div className="text-[11px] text-white/40 mt-1 truncate">
            {subtitle}
          </div>
        )}
      </div>
    </div>
  );
};

export const HomeView: React.FC = () => {
  const [statsPeriod, setStatsPeriod] = useState(() => {
    try {
      return localStorage.getItem("dicty_stats_period") || "day";
    } catch {
      return "day";
    }
  });
  const [stats, setStats] = useState<{
    total_words: number;
    avg_speaking_wpm: number;
    avg_engine_wpm: number;
    total_recordings: number;
    librarian_updates: number;
  }>({
    total_words: 0,
    avg_speaking_wpm: 0,
    avg_engine_wpm: 0,
    total_recordings: 0,
    librarian_updates: 0,
  });

  const [activeModelName, setActiveModelName] = useState<string>(() => {
    return localStorage.getItem("dicty_active_model") || "base.en";
  });
  const [recentHistory, setRecentHistory] = useState<any[]>([]);

  // User configured shortcuts
  const [toggleKey, setToggleKey] = useState(() => localStorage.getItem("dicty_shortcut_toggle") || "Ctrl + Space");
  const [pauseKey, setPauseKey] = useState(() => localStorage.getItem("dicty_shortcut_pause") || "Ctrl + Shift + P");
  const [modeKey, setModeKey] = useState(() => localStorage.getItem("dicty_shortcut_mode") || "Alt + Shift + M");

  useEffect(() => {
    const updateKeys = () => {
      try {
        const t = localStorage.getItem("dicty_shortcut_toggle");
        const p = localStorage.getItem("dicty_shortcut_pause");
        const m = localStorage.getItem("dicty_shortcut_mode");
        if (t) setToggleKey(t);
        if (p) setPauseKey(p);
        if (m) setModeKey(m);
      } catch {}
    };
    updateKeys();

    const handleStorage = (e: StorageEvent) => {
      if (e.key === "dicty_shortcut_toggle" && e.newValue) setToggleKey(e.newValue);
      if (e.key === "dicty_shortcut_pause" && e.newValue) setPauseKey(e.newValue);
      if (e.key === "dicty_shortcut_mode" && e.newValue) setModeKey(e.newValue);
    };
    window.addEventListener("storage", handleStorage);
    return () => window.removeEventListener("storage", handleStorage);
  }, []);

  // Fetch real statistics from engine
  const fetchStats = async () => {
    try {
      const data = await engineApi.getStats(statsPeriod);
      if (data) {
        setStats({
          total_words: typeof data.total_words === "number" ? data.total_words : 0,
          avg_speaking_wpm: typeof data.avg_speaking_wpm === "number" ? data.avg_speaking_wpm : 0,
          avg_engine_wpm: typeof data.avg_engine_wpm === "number" ? data.avg_engine_wpm : 0,
          total_recordings: typeof data.total_recordings === "number" ? data.total_recordings : 0,
          librarian_updates: typeof data.librarian_updates === "number" ? data.librarian_updates : 0,
        });
      }
    } catch {
      // Backend offline or starting up
    }
  };

  // Fetch recent history records
  const fetchHistory = async () => {
    try {
      const res = await engineApi.getHistory();
      const list = Array.isArray(res) ? res : res?.history || [];
      setRecentHistory(list.slice(0, 4));
    } catch {
      // Ignore
    }
  };

  useEffect(() => {
    fetchStats();
    fetchHistory();
  }, [statsPeriod]);

  // Periodic refresh and active model sync
  useEffect(() => {
    const syncModel = () => {
      engineApi
        .getActiveModel()
        .then((mRes) => {
          if (mRes?.active_model) {
            setActiveModelName(mRes.active_model);
            localStorage.setItem("dicty_active_model", mRes.active_model);
          }
        })
        .catch(() => {});
    };

    syncModel();
    const interval = setInterval(() => {
      fetchStats();
      syncModel();
    }, 4000);
    return () => clearInterval(interval);
  }, [statsPeriod]);

  // Listen for native OS hotkey / tray state changes from Tauri Rust layer
  useEffect(() => {
    let unlistenRec: (() => void) | null = null;
    let unlistenMode: (() => void) | null = null;

    import("@tauri-apps/api/event")
      .then(({ listen }) => {
        listen("dicty:recording-state-changed", (event: any) => {
          const payload = event.payload;
          if (payload && !payload.is_recording && (payload.text || payload.status === "completed")) {
            // New transcription finished: immediately refresh stats and history
            fetchStats();
            fetchHistory();
          }
        }).then((fn) => {
          unlistenRec = fn;
        });

        listen("dicty:mode-changed", (event: any) => {
          if (event.payload?.whisper_model) {
            setActiveModelName(event.payload.whisper_model);
            localStorage.setItem("dicty_active_model", event.payload.whisper_model);
          }
        }).then((fn) => {
          unlistenMode = fn;
        });
      })
      .catch(() => {});

    const onStorage = () => {
      const stored = localStorage.getItem("dicty_active_model");
      if (stored) setActiveModelName(stored);
    };
    window.addEventListener("storage", onStorage);

    return () => {
      if (unlistenRec) unlistenRec();
      if (unlistenMode) unlistenMode();
      window.removeEventListener("storage", onStorage);
    };
  }, [statsPeriod]);

  // Time saved calculations based on 40 WPM average typing speed
  const minutesSaved = Math.round((stats.total_words || 0) / 40);
  const hoursSaved = ((stats.total_words || 0) / 40 / 60).toFixed(1);
  const timeSavedDisplay =
    stats.total_words === 0
      ? "0 min"
      : minutesSaved < 60
      ? `${minutesSaved} mins`
      : `${hoursSaved} hrs`;

  // Typing speed comparison multiplier
  const speedMultiplier =
    stats.avg_speaking_wpm > 0 ? (stats.avg_speaking_wpm / 40).toFixed(1) : "3.8";

  // Keystrokes saved
  const keystrokesSaved = (stats.total_words * 5).toLocaleString();

  return (
    <div className="w-full flex-1 overflow-y-auto overflow-x-hidden p-5 sm:p-8 max-w-4xl mx-auto space-y-6 select-none animate-in fade-in duration-200">
      {/* Header: Title and Time Range Filter */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 min-w-0">
        <div className="space-y-1 min-w-0 flex-1">
          <h1 className="text-xl sm:text-2xl font-bold tracking-tight text-white font-sans truncate">
            Overview & Statistics
          </h1>
          <p className="text-xs sm:text-sm text-white/55 leading-relaxed break-words">
            Real-time vocal productivity analytics, speech metrics, and engine performance.
          </p>
        </div>

        {/* Period Selector */}
        <div className="flex items-center gap-2 self-start sm:self-auto flex-shrink-0">
          <Calendar className="w-3.5 h-3.5 text-white/40" />
          <select
            value={statsPeriod}
            onChange={(e) => {
              const val = e.target.value;
              setStatsPeriod(val);
              try {
                localStorage.setItem("dicty_stats_period", val);
              } catch {}
            }}
            className="bg-white/5 border border-white/10 rounded-xl px-3 py-1.5 text-xs text-white focus:outline-none focus:border-[#5D6658] transition-colors cursor-pointer"
          >
            <option value="day" className="bg-[#181B20] text-white">Today</option>
            <option value="week" className="bg-[#181B20] text-white">This Week</option>
            <option value="month" className="bg-[#181B20] text-white">This Month</option>
            <option value="all" className="bg-[#181B20] text-white">All Time</option>
          </select>
        </div>
      </div>

      {/* Primary Performance Metrics Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5 sm:gap-4">
        <MetricCard
          title="Words Spoken"
          value={stats.total_words > 0 ? stats.total_words.toLocaleString() : "0"}
          subtitle="Total transcribed words"
          icon={Type}
        />
        <MetricCard
          title="Speaking Speed"
          value={`${stats.avg_speaking_wpm || 0} WPM`}
          subtitle="Natural dictation rate"
          icon={Activity}
        />
        <MetricCard
          title="Engine Speed"
          value={`${stats.avg_engine_wpm || 0} WPM`}
          subtitle="Local Whisper acceleration"
          icon={Zap}
          valueColor="text-[#87B996]"
        />
        <MetricCard
          title="Total Recordings"
          value={stats.total_recordings > 0 ? stats.total_recordings.toLocaleString() : "0"}
          subtitle="Voice dictation sessions"
          icon={Mic}
        />
        <MetricCard
          title="Typing Time Saved"
          value={timeSavedDisplay}
          subtitle="vs. 40 WPM typing speed"
          icon={Clock}
          valueColor="text-[#87B996]"
        />
        <MetricCard
          title="Librarian Updates"
          value={`${stats.librarian_updates} Updates`}
          subtitle="Knowledge base updates"
          icon={BookOpen}
          valueColor="text-indigo-400"
        />
      </div>

      {/* Productivity & Hardware Efficiency Card */}
      <div className="dicty-card p-5 sm:p-6 rounded-2xl space-y-4 border border-white/10">
        <div className="flex items-center justify-between min-w-0">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400 flex-shrink-0">
              <TrendingUp className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-white">Productivity Multiplier</h2>
              <p className="text-xs text-white/50">Voice dictation vs traditional manual keyboard input</p>
            </div>
          </div>

          <span className="hidden sm:inline-flex px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-500/15 text-emerald-300 border border-emerald-500/30">
            ⚡ {speedMultiplier}x Faster
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-1">
          <div className="p-3.5 rounded-xl bg-black/30 border border-white/5">
            <div className="text-[11px] text-white/50">Dictation Pace</div>
            <div className="text-base font-semibold text-white mt-0.5">
              {stats.avg_speaking_wpm || 150} WPM
            </div>
          </div>
          <div className="p-3.5 rounded-xl bg-black/30 border border-white/5">
            <div className="text-[11px] text-white/50">Average Typing</div>
            <div className="text-base font-semibold text-white/70 mt-0.5">
              40 WPM
            </div>
          </div>
          <div className="p-3.5 rounded-xl bg-black/30 border border-white/5">
            <div className="text-[11px] text-white/50">Keystrokes Spared</div>
            <div className="text-base font-semibold text-[#87B996] mt-0.5">
              ~{keystrokesSaved} keys
            </div>
          </div>
        </div>
      </div>

      {/* Recent Transcriptions Section */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-white/50">
            Recent Transcriptions
          </h2>
          <span className="text-[11px] text-white/40">
            {recentHistory.length} latest recordings
          </span>
        </div>

        {recentHistory.length > 0 ? (
          <div className="space-y-2">
            {recentHistory.map((rec) => {
              const dateStr = rec.timestamp
                ? new Date(rec.timestamp).toLocaleDateString(undefined, {
                    month: "short",
                    day: "numeric",
                    hour: "2-digit",
                    minute: "2-digit",
                  })
                : "Recent";
              const wordCount = (rec.text || "").trim().split(/\s+/).filter(Boolean).length;

              return (
                <div
                  key={rec.id}
                  className="dicty-card p-3.5 sm:p-4 rounded-xl flex flex-col sm:flex-row sm:items-center justify-between gap-3 min-w-0"
                >
                  <div className="flex-1 min-w-0 space-y-1">
                    <p className="text-xs text-white/90 line-clamp-2 leading-relaxed break-words">
                      "{rec.text}"
                    </p>
                    <div className="flex items-center gap-2 text-[11px] text-white/40">
                      <span>{dateStr}</span>
                      <span>•</span>
                      <span>{wordCount} words</span>
                      {rec.speaking_wpm > 0 && (
                        <>
                          <span>•</span>
                          <span className="text-emerald-400 font-mono">{rec.speaking_wpm} WPM</span>
                        </>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center gap-2 flex-shrink-0 self-start sm:self-auto">
                    <span className="text-[10px] font-semibold uppercase px-2 py-0.5 rounded-md bg-white/5 border border-white/10 text-white/70">
                      {rec.mode || "dictation"}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="dicty-card p-8 rounded-xl text-center space-y-2 border border-white/5">
            <Mic className="w-6 h-6 text-white/30 mx-auto" />
            <p className="text-xs text-white/60">
              No recent transcriptions found for this time range.
            </p>
            <p className="text-[11px] text-white/40">
              Press <kbd className="px-1.5 py-0.5 bg-white/10 rounded text-white/80 font-mono">{toggleKey}</kbd> anywhere on your PC to dictate voice directly to any app.
            </p>
          </div>
        )}
      </div>

      {/* Global Shortcut Quick Reference Banner */}
      <div className="dicty-card p-4 sm:p-5 rounded-xl flex flex-col sm:flex-row sm:items-center justify-between gap-3 border border-white/10 bg-white/[0.02]">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/70 flex-shrink-0">
            <Keyboard className="w-4 h-4 text-[#87B996]" />
          </div>
          <div>
            <div className="text-xs font-semibold text-white">System Hotkeys</div>
            <div className="text-[11px] text-white/50">Active Model: <span className="text-white/80 font-mono">{activeModelName}</span></div>
          </div>
        </div>

        <div className="flex items-center gap-3 flex-wrap">
          <div className="flex items-center gap-1.5 text-xs text-white/70">
            <span className="text-white/40">Record:</span>
            <kbd className="px-2 py-0.5 rounded bg-white/10 border border-white/10 text-white font-mono text-[11px]">{toggleKey}</kbd>
          </div>
          <div className="flex items-center gap-1.5 text-xs text-white/70">
            <span className="text-white/40">Pause:</span>
            <kbd className="px-2 py-0.5 rounded bg-white/10 border border-white/10 text-white font-mono text-[11px]">{pauseKey}</kbd>
          </div>
          <div className="flex items-center gap-1.5 text-xs text-white/70">
            <span className="text-white/40">Mode:</span>
            <kbd className="px-2 py-0.5 rounded bg-white/10 border border-white/10 text-white font-mono text-[11px]">{modeKey}</kbd>
          </div>
        </div>
      </div>
    </div>
  );
};
