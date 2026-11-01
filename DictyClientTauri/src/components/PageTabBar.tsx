import type { LucideIcon } from "lucide-react";
import { useAppAccent } from "../services/themeService";

export interface PageTabItem<T extends string = string> {
  id: T;
  label: string;
  icon?: LucideIcon;
  badge?: string | number;
  badgeVariant?: "indigo" | "emerald" | "rose" | "default";
}

interface PageTabBarProps<T extends string = string> {
  selection: T;
  onSelect: (id: T) => void;
  tabs: PageTabItem<T>[];
  className?: string;
}

export function PageTabBar<T extends string = string>({
  selection,
  onSelect,
  tabs,
  className = "",
}: PageTabBarProps<T>) {
  const { info: accentInfo } = useAppAccent();

  return (
    <div
      className={`inline-flex items-center p-1 rounded-xl bg-white/[0.04] border border-white/10 backdrop-blur-md select-none ${className}`}
      role="tablist"
    >
      {tabs.map((tab) => {
        const isSelected = selection === tab.id;
        const Icon = tab.icon;
        return (
          <button
            key={tab.id}
            role="tab"
            aria-selected={isSelected}
            onClick={() => onSelect(tab.id)}
            style={{
              backgroundColor: isSelected ? accentInfo.activeHex : undefined,
            }}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
              isSelected
                ? "text-white shadow-sm font-semibold"
                : "text-white/60 hover:text-white hover:bg-white/[0.04]"
            }`}
          >
            {Icon && (
              <Icon
                style={{
                  color: isSelected ? "#ffffff" : accentInfo.swatchDark,
                }}
                className="w-3.5 h-3.5 transition-colors"
              />
            )}
            <span>{tab.label}</span>
            {tab.badge !== undefined && tab.badge !== 0 && (
              <span
                className={`ml-1 px-1.5 py-0.2 rounded-full text-[10px] font-bold border ${
                  tab.badgeVariant === "emerald"
                    ? "bg-emerald-500/30 text-emerald-300 border-emerald-500/40"
                    : tab.badgeVariant === "rose"
                    ? "bg-rose-500/30 text-rose-300 border-rose-500/40"
                    : "bg-indigo-500/30 text-indigo-300 border-indigo-500/40"
                }`}
              >
                {tab.badge}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}
