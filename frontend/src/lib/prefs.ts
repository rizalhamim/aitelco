// Display preferences from the "Tampilan" page. Stored per browser and
// applied to <html> as data attributes so plain CSS can react to them.

export type ThemePref = "light" | "dark" | "system";
export type AccentPref = "teal" | "zamrud" | "laut" | "amber" | "grafit";
export type DensityPref = "lega" | "standar" | "ringkas";

export interface UiPrefs {
  theme: ThemePref;
  accent: AccentPref;
  density: DensityPref;
  textScale: number; // percent, 85–120
  animation: boolean;
  tooltip: boolean;
  targetLine: boolean;
}

export const DEFAULT_PREFS: UiPrefs = {
  theme: "light",
  accent: "teal",
  density: "standar",
  textScale: 100,
  animation: true,
  tooltip: true,
  targetLine: false,
};

const KEY = "ui_prefs";
export const PREFS_EVENT = "ui-prefs";

export function getPrefs(): UiPrefs {
  if (typeof window === "undefined") return DEFAULT_PREFS;
  try {
    const raw = localStorage.getItem(KEY);
    const legacyTheme = localStorage.getItem("theme");
    const base = { ...DEFAULT_PREFS, ...(legacyTheme === "dark" ? { theme: "dark" as const } : {}) };
    return raw ? { ...base, ...JSON.parse(raw) } : base;
  } catch {
    return DEFAULT_PREFS;
  }
}

export function isDark(p: UiPrefs = getPrefs()): boolean {
  if (p.theme === "system") {
    return typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }
  return p.theme === "dark";
}

export function applyPrefs(p: UiPrefs = getPrefs()) {
  const el = document.documentElement;
  const dark = isDark(p);
  if (p.theme === "system") el.removeAttribute("data-theme");
  else el.setAttribute("data-theme", p.theme);
  el.classList.toggle("dark", dark);
  el.classList.toggle("light", !dark && p.theme === "light");
  el.dataset.accent = p.accent;
  el.dataset.density = p.density;
  el.dataset.motion = p.animation ? "on" : "off";
  el.style.fontSize = `${p.textScale}%`;
}

export function setPrefs(patch: Partial<UiPrefs>): UiPrefs {
  const next = { ...getPrefs(), ...patch };
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
    localStorage.setItem("theme", isDark(next) ? "dark" : "light");
  } catch { /* storage unavailable */ }
  applyPrefs(next);
  window.dispatchEvent(new CustomEvent(PREFS_EVENT, { detail: next }));
  return next;
}
