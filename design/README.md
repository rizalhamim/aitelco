# Bizplan Java Agent design system

One set of design tokens drives both the web app (`frontend/`) and the Android app (`mobile/`).

```
design/tokens.json  ──python3 design/build_tokens.py──▶  frontend/src/app/design-tokens.css
                                                     └▶  mobile/lib/src/design_tokens.dart
```

Edit `tokens.json`, run the script, commit all three files. Never hand-edit the generated files.

## Principles

- **Teal is primary** (buttons, links, active, focus). Red is only for errors and destructive actions.
- **Poppins** for headings, KPIs and labels. **Prompt** for body text and data.
- **Fluid but calm motion.** Use the motion tokens (`fast` 120ms for hover/press, `base` 200ms for state changes, `slow` 320ms for panels, `page` 280ms for screen changes) with the `standard` easing. Web and Android both turn motion off when the OS asks for reduced motion.
- **Light and dark** are first-class. Use semantic tokens (`--ds-ink`, `--ds-surface`, `DSLight.ink`…) rather than raw hex so both modes work.
- **Charts** use the `chart` palette in order.

## Using the tokens

Web (CSS):

```css
.kpi-card {
  background: var(--ds-surface);
  border-radius: var(--ds-radius-lg);
  padding: var(--ds-space-6);
  transition: transform var(--ds-dur-fast) var(--ds-ease-standard);
}
```

The older `--ioh-*` variables in `ioh-tokens.css` are aliases kept for existing components; prefer `--ds-*` in new code.

Flutter:

```dart
import '../theme.dart'; // re-exports design_tokens.dart

Padding(padding: const EdgeInsets.all(DSSpace.s4), child: ...);
AnimatedContainer(duration: DSMotion.base, curve: DSMotion.standard, ...);
```

`AppTheme` already styles cards, buttons, inputs, chips, sheets, dialogs and page transitions from these tokens, so plain Material widgets pick up the look without per-screen styling.

## Other design references

- `docs/design-system-teal.md`: the long-form teal system this token set encodes.
- `design-rule.txt`: IOH **analyst deck** rules (red-primary, 1920×1080 slides). It applies only to exported PDF/slide reports, not to the app UI.
