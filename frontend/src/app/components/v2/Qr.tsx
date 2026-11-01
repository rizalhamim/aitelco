/* QR code drawn as one SVG path, level M with no logo hole, like the Redesign v2 mockups. */
import { useMemo } from "react";
import qrcode from "qrcode-generator";

/** Public site for links that must open on any phone (the QR and the share link). */
export const PUBLIC_ORIGIN = "https://agent.bizplan-java.com";

export function Qr({ text, className, label = "Kode QR halaman unduh aplikasi Android" }: { text: string; className?: string; label?: string }) {
  const { n, cells } = useMemo(() => {
    const q = qrcode(0, "M");
    q.addData(text);
    q.make();
    const size = q.getModuleCount();
    const out: string[] = [];
    for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (q.isDark(r, c)) out.push(`M${c} ${r}h1v1h-1z`);
    return { n: size, cells: out.join("") };
  }, [text]);
  return (
    <svg className={className} viewBox={`0 0 ${n} ${n}`} shapeRendering="crispEdges" role="img" aria-label={label}>
      <path d={cells} fill="#0F1F1D" />
    </svg>
  );
}
