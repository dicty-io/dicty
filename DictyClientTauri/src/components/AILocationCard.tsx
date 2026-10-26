import React, { useState } from "react";
import { Check, Cloud, HardDrive, Download } from "lucide-react";
import { modesStore, useModesStore } from "../services/modesStore";

/// "Where should Dicty run AI?" — the first card on the Models page.
/// It sets the engine's `ai_location`. For "On this PC" it also lists the
/// text models Dicty is set to use and whether each one is downloaded.
export const AILocationCard: React.FC = () => {
  const state = useModesStore();
  const [busy, setBusy] = useState(false);

  const value = state.capabilities?.ai_location || "local";
  const cloudAccess = state.capabilities?.cloud_access ?? false;
  const localModels = state.capabilities?.local_text_models || [];

  const choose = async (location: string) => {
    if (location === value || busy) return;
    setBusy(true);
    await modesStore.setAILocation(location);
    setBusy(false);
  };

  return (
    <div className="dicty-card p-4 space-y-3.5">
      <div className="space-y-0.5">
        <h3 className="text-sm font-bold text-white tracking-tight">
          Where should Dicty run AI?
        </h3>
        <p className="text-xs text-white/55">
          This decides what Dicty uses for cleanup, modes, and translations.
        </p>
      </div>

      <div className="grid sm:grid-cols-2 gap-2">
        <LocationOption
          icon={HardDrive}
          title="On this PC"
          subtitle="Private. Runs on your computer, works offline."
          selected={value === "local"}
          onSelect={() => choose("local")}
        />
        <LocationOption
          icon={Cloud}
          title="Cloud when better"
          subtitle="Faster or better on hard tasks. Needs sign-in or an API key."
          selected={value === "cloud_when_better"}
          disabled={!cloudAccess}
          onSelect={() => choose("cloud_when_better")}
        />
      </div>

      {value === "local" && (
        <div className="rounded-xl bg-white/[0.03] border border-white/[0.06] p-3 space-y-2">
          {localModels.length === 0 ? (
            <div className="flex items-center gap-2 text-xs text-white/55">
              <Download className="w-3.5 h-3.5 text-white/45" />
              <span>
                Dicty downloads a small text model the first time a mode needs one.
              </span>
            </div>
          ) : (
            localModels.map((model) => (
              <div key={model} className="flex items-center gap-2 text-xs">
                <Check className="w-3.5 h-3.5 text-[#87B996]" />
                <span className="text-white/85 flex-1 truncate">{model}</span>
                <span className="text-[11px] text-white/45">Downloaded</span>
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
};

const LocationOption: React.FC<{
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  subtitle: string;
  selected: boolean;
  disabled?: boolean;
  onSelect: () => void;
}> = ({ icon: Icon, title, subtitle, selected, disabled = false, onSelect }) => (
  <button
    type="button"
    onClick={onSelect}
    disabled={disabled}
    className={`text-left p-3 rounded-xl border transition-colors ${
      selected
        ? "bg-[#5D6658]/20 border-[#5D6658]/45"
        : "bg-white/[0.02] border-white/[0.06] hover:bg-white/[0.05]"
    } ${disabled ? "opacity-45 cursor-not-allowed" : ""}`}
  >
    <div className="flex items-center gap-2">
      <Icon className={`w-4 h-4 ${selected ? "text-[#87B996]" : "text-white/45"}`} />
      <span className="text-xs font-semibold text-white flex-1">{title}</span>
      {selected && <Check className="w-3.5 h-3.5 text-[#87B996]" />}
    </div>
    <p className="text-[11px] text-white/50 mt-1 leading-snug">{subtitle}</p>
  </button>
);
