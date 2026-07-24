# MANA LINE — Flutter Scaffold & Design System (Week 1)

## Design plan (stated up front, per design-review discipline)

**Grounding:** this is a field utility app for rural lending agents —
used outdoors, one-handed, under time pressure, by people managing cash
against a paper ledger. Not a marketing surface. Every choice below
optimizes for that, not for looking impressive in a portfolio.

- **Palette** — deep ledger-ink (`#1B2B4B`) primary, brass (`#C68A2E`)
  accent reserved for primary actions only. Deliberately avoids the
  generic AI-default warm-cream+terracotta combination. Status colors
  (`good`/`bad`/`warn`) are desaturated for direct-sunlight legibility
  and map 1:1 to the spec's own status vocabulary (Balanced/Short/
  Excess, Active/Penalty/Grace) — no invented statuses.
- **Type** — Manrope (headers, restrained use) + Inter (body/data, with
  tabular figures for money). No display serif — wrong register for a
  transactional tool.
- **Signature element** — the Green/Red Verification Ring (already
  locked at BR-191/GC-002) is elevated from "avatar decoration" to the
  app's one consistent shape language: `ManaRadius.ring` and the
  `ManaVerificationRing` component are meant to be the thing this app
  is visually remembered by, used with restraint elsewhere (cards use a
  quieter `ManaRadius.md`, not the ring radius, to keep the signature
  from being diluted).
- **Structural rule, not a convention:** `11_UI_Guidelines.md`'s locked
  Title Case standard is enforced in code via `ManaText`, not left to
  screen-by-screen developer memory. `ManaText.raw()` exists explicitly
  for the guideline's own carve-outs (free text, system IDs).

## What's built (Week 1 scope)

```
lib/
  design/
    tokens/        colors.dart, typography.dart, spacing.dart
    components/     mana_text.dart (ManaText, ManaStatusPill, ManaVerificationRing)
    theme.dart      assembled ThemeData
  shared/
    widgets/
      language_selector.dart   GC-001, 5-language V1 list
  app/
    router.dart              go_router skeleton, one route per locked screen ID
    design_showcase_screen.dart   temporary — visual proof of the token system
  main.dart
```

Every screen in the locked inventory (LR-001–013, OW-000–015,
AG-001–009, CW-001–006, IW-001–005) has a route stub in `router.dart`
so the navigation graph can be sanity-checked against each screen
file's own NAVIGATION section before real implementation starts —
catches a wrong `context.go('/...')` target at build time, not by
manual cross-reference later.

## What's intentionally NOT done yet

- **No real screens.** Every route renders `_Placeholder`. Week 2 per
  the Development Timeline is Auth/Onboarding (LR-001–013) — that's
  where real screen builds start.
- **No state management wiring to the offline-sync package** delivered
  earlier (`mana_line_offline_sync`) — the `pubspec.yaml` path
  dependency is commented out until that package sits alongside this
  one in a real repo.
- **Fonts are runtime-fetched** (`google_fonts`), not bundled. Flagged
  explicitly in `typography.dart` and `main.dart` — flip
  `GoogleFonts.config.allowRuntimeFetching = false` and add the actual
  font files under `assets/fonts/` before shipping, given the whole
  point of this app is working in poor connectivity; first paint
  shouldn't depend on a font CDN.
- **No dark theme** — not spec'd anywhere, not built. `ManaTheme.light()`
  only.
- **`design_showcase_screen.dart` is temporary** — it's the initial
  route right now so the design system is actually reviewable. Once
  you're happy with it, swap `initialLocation` back to `/lr-001` in
  `router.dart` and either delete the showcase or keep it behind a
  debug-only route.

## Next step

Week 2: build LR-001 → LR-013 for real against these tokens, wire
`persons.preferred_language` persistence into `ManaLanguageSelector`'s
`onChanged` callback (currently stateless/local-only in the showcase).
