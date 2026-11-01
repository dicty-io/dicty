export type AccentPreset =
  | "olive"
  | "black"
  | "slate"
  | "lavender"
  | "terracotta"
  | "ocean";

export interface AccentInfo {
  id: AccentPreset;
  displayName: string;
  swatchDark: string;
  swatchLight: string;
  activeHex: string;
  glowRgb: string;
}

export const ACCENT_PRESETS: AccentInfo[] = [
  {
    id: "olive",
    displayName: "Olive",
    swatchDark: "#87B996",
    swatchLight: "#415F4B",
    activeHex: "#5D6658",
    glowRgb: "93, 102, 88",
  },
  {
    id: "black",
    displayName: "Obsidian",
    swatchDark: "#F4F4F5",
    swatchLight: "#18181B",
    activeHex: "#3F3F46",
    glowRgb: "113, 113, 122",
  },
  {
    id: "slate",
    displayName: "Slate",
    swatchDark: "#94A3B8",
    swatchLight: "#475569",
    activeHex: "#475569",
    glowRgb: "100, 116, 139",
  },
  {
    id: "lavender",
    displayName: "Lavender",
    swatchDark: "#B8A1D9",
    swatchLight: "#7C5BA6",
    activeHex: "#6D4C8C",
    glowRgb: "147, 112, 219",
  },
  {
    id: "terracotta",
    displayName: "Terracotta",
    swatchDark: "#E29578",
    swatchLight: "#B66236",
    activeHex: "#8D4925",
    glowRgb: "226, 149, 120",
  },
  {
    id: "ocean",
    displayName: "Ocean",
    swatchDark: "#7FB1C4",
    swatchLight: "#3D7387",
    activeHex: "#2E5B6B",
    glowRgb: "127, 177, 196",
  },
];

const ACCENT_STORAGE_KEY = "appAccentColor";

export function getActiveAccent(): AccentPreset {
  if (typeof window === "undefined") return "olive";
  try {
    const saved = localStorage.getItem(ACCENT_STORAGE_KEY) as AccentPreset;
    if (saved && ACCENT_PRESETS.some((p) => p.id === saved)) {
      return saved;
    }
  } catch {}
  return "olive";
}

export function applyAccentColor(preset: AccentPreset) {
  if (typeof window === "undefined") return;
  const info = ACCENT_PRESETS.find((p) => p.id === preset) || ACCENT_PRESETS[0];
  const root = document.documentElement;

  root.style.setProperty("--app-accent", info.swatchDark);
  root.style.setProperty("--app-accent-active", info.activeHex);
  root.style.setProperty("--app-accent-glow", info.glowRgb);

  try {
    localStorage.setItem(ACCENT_STORAGE_KEY, preset);
  } catch {}

  window.dispatchEvent(
    new CustomEvent("dicty:accent-color-changed", { detail: { preset, info } })
  );
}

// Auto-initialize on module load in browser
if (typeof window !== "undefined") {
  applyAccentColor(getActiveAccent());
}
