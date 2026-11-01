import React, { useState, useEffect, useMemo } from "react";
import {
  Clock,
  Sparkles,
  RefreshCw,
  Gauge,
  BarChart2,
  CheckCircle2,
  Keyboard,
  Cpu,
} from "lucide-react";
import { SettingsPageHeader } from "../components/SettingsPageHeader";
import { engineFetch } from "../services/engineClient";

interface LatencyMetric {
  id: string;
  timestamp: string;
  mode?: string;
  model_id?: string;
  model_name?: string;
  provider?: string;
  audio_duration_s?: number;
  word_count?: number;
  engine_ms?: number;
  end_to_end_ms?: number;
  whisper_ms?: number;
  whisper_latency_ms?: number;
  llm_latency_ms?: number;
  correction_latency_ms?: number;
  format_style?: string;
  reformat_model?: string;
  target_app_name?: string;
}

interface PerformanceStats {
  total_transcriptions?: number;
  avg_latency_ms?: number;
  avg_whisper_ms?: number;
  avg_llm_ms?: number;
  avg_wpm?: number;
  period?: string;
}

export const InsightsView: React.FC = () => {
  const [metrics, setMetrics] = useState<LatencyMetric[]>([]);
  const [stats, setStats] = useState<PerformanceStats | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [period, setPeriod] = useState<"day" | "week" | "month" | "all">("week");

  const fetchData = async () => {
    setIsLoading(true);
    try {
      const [metricsRes, statsRes] = await Promise.all([
        engineFetch("/metrics/recent?limit=25"),
        engineFetch(`/stats?period=${period}`),
      ]);

      if (metricsRes.ok) {
        const data = await metricsRes.json();
        const list = Array.isArray(data) ? data : data?.metrics || [];
        setMetrics(list);
      }

      if (statsRes.ok) {
        const data = await statsRes.json();
        setStats(data);
      }
    } catch (err) {
      console.warn("Failed to fetch performance metrics:", err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 8000);
    return () => clearInterval(interval);
  }, [period]);

  // Derived calculations from recent metrics
  const computed = useMemo(() => {
    if (!metrics.length) {
      return {
        avgTotal: 0,
        avgWhisper: 0,
        avgLlm: 0,
        avgPaste: 0,
        fastest: 0,
      };
    }

    let sumTotal = 0;
    let sumWhisper = 0;
    let sumLlm = 0;
    let sumPaste = 0;
    let fastest = Infinity;

    for (const m of metrics) {
      const total = m.end_to_end_ms || m.engine_ms || 0;
      const whisper = m.whisper_latency_ms || m.whisper_ms || Math.max(0, total * 0.75);
      const llm = (m.llm_latency_ms || 0) + (m.correction_latency_ms || 0);
      const paste = Math.max(0, total - whisper - llm);

      sumTotal += total;
      sumWhisper += whisper;
      sumLlm += llm;
      sumPaste += paste;

      if (total > 0 && total < fastest) {
        fastest = total;
      }
    }

    const n = metrics.length;
    return {
      avgTotal: Math.round(sumTotal / n),
      avgWhisper: Math.round(sumWhisper / n),
      avgLlm: Math.round(sumLlm / n),
      avgPaste: Math.round(sumPaste / n),
      fastest: fastest === Infinity ? 0 : Math.round(fastest),
    };
  }, [metrics]);

  return (
    <div className="flex-1 overflow-y-auto p-8 max-w-5xl mx-auto space-y-7 select-none">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <SettingsPageHeader
            title="Insights & Performance"
            description="Real-time end-to-end latency breakdowns across speech inference, LLM rewriting, and system typing."
          />
          {stats?.total_transcriptions !== undefined && (
            <div className="text-xs text-white/50 mt-1">
              Recorded <span className="text-white font-semibold">{stats.total_transcriptions}</span> transcriptions in the current period.
            </div>
          )}
        </div>
        <div className="flex items-center gap-2">
          <div className="inline-flex p-1 rounded-xl bg-white/[0.04] border border-white/10 text-xs">
            {(["day", "week", "month", "all"] as const).map((p) => (
              <button
                key={p}
                onClick={() => setPeriod(p)}
                className={`px-3 py-1 rounded-lg capitalize transition-all ${
                  period === p
                    ? "bg-[#5D6658] text-white font-semibold shadow-sm"
                    : "text-white/60 hover:text-white"
                }`}
              >
                {p}
              </button>
            ))}
          </div>
          <button
            onClick={fetchData}
            disabled={isLoading}
            className="p-2 rounded-xl bg-white/[0.04] hover:bg-white/10 text-white/70 hover:text-white border border-white/10 transition-all"
            title="Refresh metrics"
          >
            <RefreshCw className={`w-4 h-4 ${isLoading ? "animate-spin" : ""}`} />
          </button>
        </div>
      </div>

      {/* KPI Highlight Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3.5">
        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-1 relative overflow-hidden">
          <div className="flex items-center justify-between text-xs text-white/60">
            <span>End-to-End Latency</span>
            <Gauge className="w-4 h-4 text-emerald-400" />
          </div>
          <div className="text-2xl font-bold tracking-tight text-white flex items-baseline gap-1.5">
            <span>{computed.avgTotal || "--"}</span>
            <span className="text-xs font-normal text-white/50">ms avg</span>
          </div>
          <div className="text-[11px] text-emerald-400 flex items-center gap-1 font-medium">
            <CheckCircle2 className="w-3 h-3" />
            <span>Fastest: {computed.fastest || "--"} ms</span>
          </div>
        </div>

        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-1">
          <div className="flex items-center justify-between text-xs text-white/60">
            <span>STT Inference</span>
            <Cpu className="w-4 h-4 text-indigo-400" />
          </div>
          <div className="text-2xl font-bold tracking-tight text-white flex items-baseline gap-1.5">
            <span>{computed.avgWhisper || "--"}</span>
            <span className="text-xs font-normal text-white/50">ms</span>
          </div>
          <div className="text-[11px] text-white/45">Whisper / Speech Engine</div>
        </div>

        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-1">
          <div className="flex items-center justify-between text-xs text-white/60">
            <span>LLM Rewriting</span>
            <Sparkles className="w-4 h-4 text-amber-400" />
          </div>
          <div className="text-2xl font-bold tracking-tight text-white flex items-baseline gap-1.5">
            <span>{computed.avgLlm || "0"}</span>
            <span className="text-xs font-normal text-white/50">ms</span>
          </div>
          <div className="text-[11px] text-white/45">Formatting & Cleanup</div>
        </div>

        <div className="p-4 rounded-2xl bg-white/[0.025] border border-white/10 space-y-1">
          <div className="flex items-center justify-between text-xs text-white/60">
            <span>Paste / Typing</span>
            <Keyboard className="w-4 h-4 text-rose-400" />
          </div>
          <div className="text-2xl font-bold tracking-tight text-white flex items-baseline gap-1.5">
            <span>{computed.avgPaste || "--"}</span>
            <span className="text-xs font-normal text-white/50">ms</span>
          </div>
          <div className="text-[11px] text-white/45">Direct Win32 paste</div>
        </div>
      </div>

      {/* Pipeline Stage Breakdown Visualizer */}
      <div className="p-5 rounded-2xl bg-white/[0.025] border border-white/10 space-y-4">
        <div className="flex items-center justify-between">
          <div className="space-y-0.5">
            <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
              <BarChart2 className="w-4 h-4 text-[#87B996]" />
              <span>Pipeline Stage Breakdown</span>
            </h3>
            <p className="text-[11px] text-white/50">
              Proportion of total time spent in audio processing vs. AI refinement vs. UI insertion.
            </p>
          </div>
          <div className="flex items-center gap-3 text-[11px]">
            <div className="flex items-center gap-1.5 text-indigo-300">
              <span className="w-2.5 h-2.5 rounded-full bg-indigo-500" />
              <span>STT Engine</span>
            </div>
            <div className="flex items-center gap-1.5 text-amber-300">
              <span className="w-2.5 h-2.5 rounded-full bg-amber-500" />
              <span>LLM Pass</span>
            </div>
            <div className="flex items-center gap-1.5 text-rose-300">
              <span className="w-2.5 h-2.5 rounded-full bg-rose-500" />
              <span>Paste Overhead</span>
            </div>
          </div>
        </div>

        {computed.avgTotal > 0 ? (
          <div className="w-full h-4 rounded-full overflow-hidden bg-white/[0.05] flex">
            <div
              style={{
                width: `${Math.max(
                  5,
                  Math.round((computed.avgWhisper / (computed.avgTotal || 1)) * 100)
                )}%`,
              }}
              className="bg-indigo-500 h-full transition-all duration-500"
              title={`STT: ${computed.avgWhisper}ms`}
            />
            {computed.avgLlm > 0 && (
              <div
                style={{
                  width: `${Math.max(
                    5,
                    Math.round((computed.avgLlm / (computed.avgTotal || 1)) * 100)
                  )}%`,
                }}
                className="bg-amber-500 h-full transition-all duration-500"
                title={`LLM: ${computed.avgLlm}ms`}
              />
            )}
            <div
              style={{
                width: `${Math.max(
                  5,
                  Math.round((computed.avgPaste / (computed.avgTotal || 1)) * 100)
                )}%`,
              }}
              className="bg-rose-500 h-full transition-all duration-500"
              title={`Paste: ${computed.avgPaste}ms`}
            />
          </div>
        ) : (
          <div className="py-6 text-center text-xs text-white/40">
            Record a dictation with Dicty to view the real-time latency pipeline.
          </div>
        )}
      </div>

      {/* Recent Transcriptions Latency Table */}
      <div className="p-5 rounded-2xl bg-white/[0.025] border border-white/10 space-y-3">
        <h3 className="text-xs font-semibold text-white/90 flex items-center gap-2">
          <Clock className="w-4 h-4 text-[#87B996]" />
          <span>Recent Transcriptions Activity</span>
        </h3>

        {metrics.length === 0 ? (
          <div className="py-10 text-center text-xs text-white/40">
            No dictations logged yet. Press your global shortcut to test latency.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead>
                <tr className="border-b border-white/10 text-white/50 text-[11px] font-semibold">
                  <th className="pb-2">Time</th>
                  <th className="pb-2">Target App / Mode</th>
                  <th className="pb-2">Words</th>
                  <th className="pb-2">STT Model</th>
                  <th className="pb-2">STT Time</th>
                  <th className="pb-2">LLM</th>
                  <th className="pb-2 text-right">Total Latency</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/[0.06]">
                {metrics.map((m, idx) => {
                  const total = m.end_to_end_ms || m.engine_ms || 0;
                  const whisper = m.whisper_latency_ms || m.whisper_ms || total;
                  const llm = (m.llm_latency_ms || 0) + (m.correction_latency_ms || 0);

                  return (
                    <tr key={m.id || idx} className="hover:bg-white/[0.02] transition-colors">
                      <td className="py-2.5 text-white/70 font-mono text-[11px]">
                        {m.timestamp ? m.timestamp.split("T")?.[1]?.slice(0, 8) || m.timestamp : "Just now"}
                      </td>
                      <td className="py-2.5">
                        <span className="font-medium text-white">
                          {m.target_app_name || m.mode || "Default"}
                        </span>
                      </td>
                      <td className="py-2.5 text-white/70">{m.word_count ?? "--"}</td>
                      <td className="py-2.5 text-white/50 truncate max-w-[140px]">
                        {m.model_name || m.model_id || "Whisper"}
                      </td>
                      <td className="py-2.5 text-indigo-300 font-mono">
                        {whisper ? `${Math.round(whisper)} ms` : "--"}
                      </td>
                      <td className="py-2.5 text-amber-300 font-mono">
                        {llm > 0 ? `${Math.round(llm)} ms` : "-"}
                      </td>
                      <td className="py-2.5 text-right font-mono font-bold">
                        <span
                          className={`px-2 py-0.5 rounded-md ${
                            total < 150
                              ? "bg-emerald-500/15 text-emerald-300 border border-emerald-500/30"
                              : total < 400
                              ? "bg-amber-500/15 text-amber-300 border border-amber-500/30"
                              : "bg-white/[0.06] text-white"
                          }`}
                        >
                          {total ? `${Math.round(total)} ms` : "--"}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};
