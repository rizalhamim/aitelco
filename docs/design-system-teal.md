# Web App Design System -- Teal Primary

A clean, modern web-application design system. **Teal** is the primary brand color,
**red** is a tertiary accent used sparingly for alerts and emphasis. Typography pairs
**Poppins** (bold, for headings) with **Prompt** (for all body and UI text). The aesthetic
is calm, professional, and trustworthy -- generous whitespace, soft surfaces, restrained color.

---

## 1. Fonts

- **Poppins** -- headings & subheadings only. Weights 600 / 700. Tracking slightly tight.
- **Prompt** -- body, UI labels, buttons, captions, data. Weights 300-600.

**Rule:** Never use Poppins for body text. Never use Prompt for h1-h3.

---

## 2. Design tokens

```css
:root {
  /* ---------- Primary -- Teal ---------- */
  --teal-50:  #E6F7F5;
  --teal-100: #C0EDE8;
  --teal-200: #8FDFD7;
  --teal-300: #5BCEC3;
  --teal-400: #33BCAD;   /* hover */
  --teal-500: #15A697;   /* PRIMARY -- buttons, links, active states */
  --teal-600: #0E8579;   /* pressed */
  --teal-700: #0A6A5F;   /* deep accents */
  --teal-800: #074D45;   /* headings on light, dark teal surfaces */
  --teal-900: #04332E;

  /* ---------- Tertiary accent -- Red (use sparingly) ---------- */
  --red-50:  #FDECEC;
  --red-100: #FAD0D0;
  --red-400: #EF5350;
  --red-500: #E13838;   /* TERTIARY accent -- destructive, alerts, key emphasis */
  --red-600: #C42B2B;

  /* ---------- Secondary / supporting ---------- */
  --amber-500: #F5A623;  /* warnings */
  --green-500: #2FA84F;  /* success (distinct from teal) */
  --blue-500:  #2A74D4;  /* info links if needed */

  /* ---------- Neutrals ---------- */
  --ink-900: #0F1F1D;
  --ink-700: #2E3F3C;
  --ink-500: #5A6B68;
  --ink-400: #8A9996;
  --ink-300: #B6C2BF;

  --bg:        #FFFFFF;
  --bg-soft:   #F5F9F8;
  --bg-muted:  #ECF3F1;
  --border:    #E1E9E7;
  --border-strong: #CCD8D5;

  /* ---------- Radii ---------- */
  --radius-sm: 6px;  --radius-md: 10px; --radius-lg: 16px;
  --radius-xl: 24px; --radius-pill: 999px;

  /* ---------- Shadows (soft, teal-tinted) ---------- */
  --shadow-sm: 0 1px 2px rgba(15, 31, 29, 0.06);
  --shadow-md: 0 4px 14px rgba(15, 31, 29, 0.08);
  --shadow-lg: 0 12px 32px rgba(15, 31, 29, 0.12);
  --shadow-teal: 0 8px 24px rgba(21, 166, 151, 0.24);

  /* ---------- Type families ---------- */
  --font-head: "Poppins", system-ui, sans-serif;
  --font-body: "Prompt", system-ui, sans-serif;

  /* ---------- Motion ---------- */
  --ease: cubic-bezier(0.22, 0.61, 0.36, 1);
  --dur-fast: 140ms; --dur: 220ms;
}
```

---

## 3. Color usage rules

- **Teal-500** is the workhorse: primary buttons, active nav, links, selected states, focus rings, key icons.
- **Teal-700 / 800** for brand-tinted headings, and for dark teal surfaces (hero, sidebar).
- **Red-500** is tertiary -- reserve for: destructive actions, error states, critical badges, at most ONE emphasis moment per screen. Never use red for primary CTAs.
- Neutrals carry most of the UI. Color is the seasoning, not the meal.
- Page background is `--bg-soft` (subtle teal tint); cards sit on it in pure white.

---

## 4. Typography scale

| Token   | Element     | Font / Weight | Size / LH    |
|---------|-------------|---------------|--------------|
| display | Hero        | Poppins 700   | 56px / 1.1   |
| h1      | Page title  | Poppins 700   | 40px / 1.15  |
| h2      | Section     | Poppins 600   | 30px / 1.2   |
| h3      | Subsection  | Poppins 600   | 22px / 1.25  |
| h4      | Card title  | Poppins 600   | 18px / 1.3   |
| body    | Default     | Prompt 400    | 16px / 1.6   |
| label   | Form/UI     | Prompt 500    | 13px / 1.4   |
| button  | Button      | Prompt 600    | 15px / 1     |

---

## 5. Component cues

- **Buttons:** pill radius, primary = teal-500 fill + soft teal shadow; hover teal-400 + lift; secondary = white + teal-200 border; danger = red-500 (delete only).
- **Cards:** white on `--bg-soft`, 1px border, radius-lg, soft shadow; feature card has 4px teal top border.
- **Inputs:** 1.5px border, focus = teal-500 border + 3px teal-50 halo; error = red-500.
- **Badges:** teal/success/warning/danger/neutral tints.
- **Nav active:** teal-600 text + underline / left border.
- **Alerts:** left 4px border, info=teal, success=green, warning=amber, danger=red.

---

## 6. Do / Don't

**Do:** let teal lead (buttons, links, active, focus); keep red rare; Poppins headings only, Prompt everywhere else; soft teal-tinted shadows; generous whitespace.

**Don't:** red for primary CTAs / large fills; mix Poppins into body or Prompt into headings; pure black (#000); >2 accent colors per component; heavy hard shadows.

---

## One-line summary

> Calm, modern web app. **Teal-500 (#15A697) is primary** (buttons, links, active states).
> **Red-500 (#E13838) is tertiary** (alerts / destructive only, used sparingly).
> **Poppins 600/700 for all headings, Prompt 300-600 for everything else.**
> Soft teal-tinted shadows, white cards on a #F5F9F8 background, pill buttons, 10-16px radii, generous whitespace.
