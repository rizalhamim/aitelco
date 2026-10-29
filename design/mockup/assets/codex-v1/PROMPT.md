You are generating hand-authored SVG visual elements for a UI design (an AI business-analyst app for a telecom region, "Bizplan Java Agent"). Write each file into the current directory. Do NOT write any text, letters, numbers, logos, brand marks, people or flags inside the SVGs. Pure abstract / data-viz motifs only.

Palette (use only these, opacity allowed): teal 50 #E6F7F5, 100 #C0EDE8, 200 #8FDFD7, 300 #5BCEC3, 400 #33BCAD, 500 #15A697, 600 #0E8579, 700 #0A6A5F, 800 #074D45, 900 #04332E; white #FFFFFF; amber #F5A623 (sparingly, max 1-2 accents).
Technical rules (the SVGs are imported into a design tool with a limited SVG parser):
- Only <svg>, <g>, <path>, <circle>, <ellipse>, <rect>, <line>, <polyline>, <polygon>, <defs>, <linearGradient>, <radialGradient>, <stop>. No filters, no masks, no clipPath, no <use>, no <style>/CSS classes, no <text>, no patterns, no transforms other than translate/rotate/scale on <g>.
- Attributes inline (fill, stroke, stroke-width, opacity, fill-opacity, stroke-opacity, stroke-linecap, stroke-dasharray).
- Absolute viewBox exactly as specified, width/height equal to viewBox size. Keep each file under 60 KB and under ~250 elements.
- Style: modern, calm, premium, precise geometry, thin strokes (1-1.5px), soft radial glows made with radialGradient (teal, low opacity). No noisy textures.

Files:
1. hero_ai_orb.svg (480x320): an "AI analyst core": a glowing teal orb (radial gradient) at about (340,160) with 3 concentric thin orbit rings (ellipses, slightly rotated), small node dots on the rings, and thin connector arcs flowing left toward faint mini chart fragments (a small rising polyline, a few bars, a donut arc) that fade out to the left. Transparent background. Designed to sit on the right side of a dark #04332E banner, so use light teals (100-400) and white at low opacity.
2. dataviz_waves.svg (1200x240): background motif for a light hero header: 3-4 smooth layered area waves (very low opacity teal 100/200 fills, 0.25-0.6) along the bottom, a faint dotted grid (small circles every 24px, teal-200 at 0.35 opacity) in the upper-right area only, and one crisp teal-600 1.5px line chart with 6 data-point dots and one highlighted point with a soft glow ring. Transparent background.
3. empty_reports.svg (240x180): empty-state illustration for "no reports yet": stacked document cards (rounded rects, white with teal-200 stroke) slightly fanned, top card shows abstract chart lines and bars, a small sparkle star shape in teal-500, soft teal-50 circle blob behind. Transparent background.
4. map_glow.svg (600x200): subtle decorative contour/topographic lines (6-8 smooth wavy closed or open paths, teal-300 at 0.25-0.4 opacity, 1px) plus 5 small "signal" markers (a dot with 2 concentric rings) — for behind a map header. Transparent background.
5. login_overlay_pattern.svg (1440x1024): a decorative overlay for a dark-teal login hero: very faint large concentric arcs emanating from the bottom-left corner (teal-300, 0.08-0.18 opacity, 1px), a scattering of 30-40 tiny dots (white, 0.15-0.4 opacity) like a network, and 6-8 thin connector lines between some dots. Transparent background.
6. ai_spark_badge.svg (64x64): a small app-style badge glyph: rounded square (rx 18) filled with a linear gradient teal-500 -> teal-700, with a white 4-point sparkle (and a tiny second sparkle) centered. (This is a UI glyph for "AI", not a logo.)

After writing the files, validate each one parses as XML (e.g. with python xml.etree) and print the list of files with byte sizes. Do not create any other files.
