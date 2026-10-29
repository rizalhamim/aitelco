"use client";
import { useEffect, useRef } from "react";
import type { ECharts, EChartsOption } from "echarts";
import { useThemeKey } from "./SmartChart";

/** Theme colours read from the design tokens at draw time, so canvases follow light/dark. */
export type ChartTheme = {
  dark: boolean; ink: string; mute: string; rule: string; surface: string; muted: string;
  teal300: string; teal600: string; teal800: string; grey: string; amber: string; danger: string;
};

function readTheme(): ChartTheme {
  const cs = getComputedStyle(document.documentElement);
  const v = (n: string, f: string) => cs.getPropertyValue(n).trim() || f;
  const surface = v("--ds-surface", "#FFFFFF");
  return {
    dark: /^#(0|1|2)/i.test(surface),
    ink: v("--ds-ink", "#0F1F1D"), mute: v("--ds-text-mute", "#5A6B68"), rule: v("--ds-rule", "#E1E9E7"),
    surface, muted: v("--ds-surface-muted", "#ECF3F1"),
    teal300: v("--ds-teal300", "#5BCEC3"), teal600: v("--ds-teal600", "#0E8579"), teal800: v("--ds-teal800", "#074D45"),
    grey: v("--ds-chart-grey", "#B9C6C3"), amber: v("--ds-warning", "#F5A623"), danger: v("--ds-danger-solid", "#E04848"),
  };
}

export const TOOLTIP = {
  backgroundColor: "rgba(15,31,29,0.94)", borderWidth: 0, padding: [10, 12],
  textStyle: { color: "#fff", fontSize: 12, fontFamily: "Poppins, system-ui, sans-serif" },
  extraCssText: "border-radius:12px;box-shadow:0 16px 40px -4px rgba(15,31,29,.18);",
};

export const tipRow = (color: string, label: string, value: string) =>
  `<div style="display:flex;align-items:center;gap:6px;margin-top:6px;min-width:140px">` +
  `<span style="width:8px;height:8px;border-radius:99px;background:${color}"></span>` +
  `<span style="color:#C9D6D3;flex:1">${label}</span><b style="font-weight:600;margin-left:12px">${value}</b></div>`;

type Props = {
  /** Builds the option from the current theme. Keep it stable (useCallback) so the chart only redraws on change. */
  build: (t: ChartTheme) => EChartsOption;
  height: number;
  className?: string;
  label: string;
};

/** Thin ECharts wrapper for one-off charts that SmartChart's spec format doesn't cover. */
export default function EChart({ build, height, className, label }: Props) {
  const el = useRef<HTMLDivElement>(null);
  const chart = useRef<ECharts | null>(null);
  const themeKey = useThemeKey();

  useEffect(() => {
    let disposed = false;
    let ro: ResizeObserver | null = null;
    import("echarts").then((echarts) => {
      if (disposed || !el.current) return;
      const c = echarts.getInstanceByDom(el.current) ?? echarts.init(el.current, undefined, { renderer: "canvas" });
      chart.current = c;
      c.setOption({
        textStyle: { fontFamily: "Poppins, system-ui, sans-serif" },
        animationDuration: 500, animationEasing: "cubicOut",
        ...build(readTheme()),
      }, true);
      ro = new ResizeObserver(() => c.resize());
      ro.observe(el.current);
    });
    return () => { disposed = true; ro?.disconnect(); };
  }, [build, themeKey]);

  useEffect(() => () => { chart.current?.dispose(); chart.current = null; }, []);

  return <div ref={el} className={className} style={{ height }} role="img" aria-label={label} />;
}
