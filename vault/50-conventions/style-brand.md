---
title: Style + IOH brand
type: convention
updated: 2026-07-26
---

# Style + IOH brand

## Hard style rule

**Never use em-dashes anywhere** — code, comments, labels, copy, commits. Workspace-wide.

## Two design systems (do not mix)

The project has two distinct systems for two surfaces:

### Web app — Teal primary (`docs/design-system-teal.md`)

- Primary: **Teal-500 `#15A697`** (buttons, links, active, focus). Hover teal-400, pressed teal-600.
- Tertiary: **Red-500 `#E13838`** — alerts / destructive only, sparingly. Never a primary CTA.
- Fonts: **Poppins** 600/700 headings ONLY, **Prompt** 300-600 for body/UI. Never swap them.
- White cards on `#F5F9F8`, soft teal-tinted shadows, pill buttons, 10-16px radii, whitespace.

### Analyst decks — IOH brand (`design-rule.txt`)

- Primary: **IOH red `#ED1C24`**. Order: red → pink `#EC008C` → yellow `#FFCB05` → teal
  `#32BCAD` → magenta `#C6168D`. Max 4-5 colors per chart.
- Never raw black — use `--ioh-ink #1A1A1B`. Positive delta = teal, negative = red.
- Font "Indosat"/"Inter". 1920x1080 slides. Signature "Circle System" (overlapping translucent
  circles, cover + dividers only).

## Brand model

IOH = IM3 + 3ID. Reports show an IOH/IM3/3ID brand bar globally except on the FTTH tab ([[reports]]).

## Which to use

Web/mobile product UI → teal system. Exported analyst slide decks/PDF → IOH deck system.
Full tokens in the two source files via [[big-docs]].

## Related

- [[frontend]] · [[reports]] · [[deploy-restart]]
