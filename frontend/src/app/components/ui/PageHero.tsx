import type { ReactNode } from "react";

type Props = {
  /** Duotone illustration path (from /illustrations) or an icon element for the glass tile. */
  icon: string | ReactNode;
  eyebrow: string;
  title: string;
  sub?: ReactNode;
  /** Right-hand controls (glass chip, buttons, search). */
  actions?: ReactNode;
  /** Isometric illustration that bleeds off the top right. */
  art?: string;
  pattern?: boolean;
};

/** Dark teal page header used by Watchlist, Laporan, Peta and Statistik. */
export default function PageHero({ icon, eyebrow, title, sub, actions, art, pattern = true }: Props) {
  return (
    <section className="ph">
      {pattern && <span className="ph-pattern" aria-hidden="true" />}
      <span className="ph-glow" aria-hidden="true" />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {art && <img className="ph-art" src={art} alt="" />}
      <span className="ph-icon">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {typeof icon === "string" ? <img src={icon} alt="" /> : icon}
      </span>
      <div className="ph-text">
        <span className="ph-eyebrow">{eyebrow}</span>
        <h1 className="ph-title">{title}</h1>
        {sub && <p className="ph-sub">{sub}</p>}
      </div>
      {actions && <div className="ph-actions">{actions}</div>}
    </section>
  );
}
