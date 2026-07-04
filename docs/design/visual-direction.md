# Todori visual direction

> Status: design source for later UI tasks
> Last updated: 2026-07-04

This document is the public design source for Todori's Phase 1 UI work after
task-22. Image mocks are direction references, not pixel-perfect acceptance
criteria. Later Flutter tasks should preserve the product judgment here while
adapting layouts to real data, i18n, accessibility, and platform constraints.

## Concept

Todori should feel like a quiet everyday object: soft, friendly, and elegant
without becoming childish or decorative.

- The interface should reduce pressure. It helps the user decide what to do,
  then gets out of the way.
- Completion should feel like something has settled or been put away, not like
  winning a game.
- Focus/timer UI should feel declarative: "I am doing this now." It is a
  calm commitment surface, not a productivity scoreboard.
- E2EE and local protection are product truths, but the main task UI should not
  constantly display lock/encryption marks. Security belongs in settings,
  onboarding, docs, and carefully worded helper surfaces.
- The mascot should be rare and quiet. It can appear in empty states,
  onboarding, and occasional completion/focus acknowledgement, but not as a
  persistent character, assistant, badge, or header decoration.

## Image References

Primary task-22 mocks:

- [List overview](../../assets/brand/generated/todori-design-direction-lists.webp)
- [Task list](../../assets/brand/generated/todori-design-direction-tasks.webp)
- [Task detail](../../assets/brand/generated/todori-design-direction-task-detail.webp)
- [Trash and restore](../../assets/brand/generated/todori-design-direction-trash-restore.webp)
- [Empty state and dialog](../../assets/brand/generated/todori-design-direction-empty-dialog.webp)
- [Mobile focus task list](../../assets/brand/generated/todori-design-direction-mobile-focus-tasks.webp)
- [Focus timer](../../assets/brand/generated/todori-design-direction-focus-timer.webp)
- [Completion state](../../assets/brand/generated/todori-design-direction-completion-state.webp)

Earlier reference inputs:

- [Mobile product mood](../../assets/brand/generated/todori-mobile-product.png)
- [Desktop product mood](../../assets/brand/generated/todori-desktop-product.png)
- [Mascot refined kit](../../assets/brand/generated/todori-mascot-kit-refined-no-border.png)
- [Mascot kit](../../assets/brand/generated/todori-mascot-kit-no-sticker-border.png)

## Layout Principles

### Mobile Task List

The mobile task list can use a generous "Today" area as an entry experience.
It gives the screen a composed, intentional feeling. The rule is progressive
density: spacious when the user is arriving, compact when the user is working.

- On first arrival or at the top of the list, allow a slightly generous Today
  header with date, remaining count/progress, and a small focus entry.
- After scrolling, or when task density matters, collapse toward a compact
  header such as "Today" plus remaining count and primary action.
- The generous header should create mood, not become a permanent hero section.
- Use a focus affordance near the Today area or active task, but keep it
  secondary to the task list.
- Maintain a stable row rhythm: task title first, metadata second, action
  affordances predictable.
- Long task names and localized text must wrap gracefully. Do not depend on a
  fixed one-line row height.

### Desktop

Desktop should feel calm and work-focused, with enough density for repeated use.

- Use a clear sidebar/main/detail structure when width allows.
- Avoid marketing-style hero panels inside the app.
- Keep cards for real repeated objects or dialogs. Do not nest cards inside
  cards.
- Let white surfaces and thin borders provide structure instead of heavy
  shadows.

### Focus Timer

Timer is a future feature direction, not part of task-22 implementation.

- The timer screen centers the selected task and the user's current commitment.
- Supported conceptual modes: normal timer, Pomodoro, and open-ended focus.
- Primary controls: start/pause, finish, add time, exit. Keep them large enough
  for mobile use.
- The task title should be more important than decorative progress art.
- Avoid streaks, rankings, forests, trophies, or guilt-based language.

## Completion Behavior

Completion should be quiet and reversible.

- Completed rows use a filled or clear check state, muted title color, and soft
  strikethrough when useful.
- A completed section can appear when it helps scanning, but it should not
  dominate the screen.
- Use a short undo snackbar for recent completion/deletion once Undo is
  implemented.
- A small settling tint or brief micro-motion is acceptable in later UI work.
- Do not use confetti, trophies, fireworks, loud celebratory copy, or mascot-led
  celebration.

## Mascot Use

The mascot is a brand texture, not an always-on UI actor.

Use it in:

- First-run onboarding or welcome.
- Empty task/list states where it reduces blankness.
- Focus/timer entry or completion acknowledgement, sparingly.
- Public brand assets and release materials.

Avoid it in:

- Normal task list headers.
- Every card, every row, or every dialog.
- Security indicators, lock badges, or encryption claims.
- Error states where it could trivialize the problem.
- Dense screens where it competes with tasks.

When present in the app, the mascot should be small, soft-edged, and secondary
to the user's data.

## Security Signal

Do not keep a persistent lock/encryption mark in the main task UI.

Security can appear in:

- Onboarding: what local encrypted storage means.
- Settings/about/security surfaces.
- Documentation links.
- One-time or contextual helper text when the user asks why local data is safe.

Avoid:

- Lock icons in the primary header by default.
- Language implying unimplemented Keychain, app lock, sync E2EE, audit status,
  account security, or recovery guarantees.
- Security-dashboard visuals inside ordinary task workflows.

## Design Tokens

These tokens describe direction. Existing Flutter constants should stay small
and pragmatic.

### Color

Use this palette as the starting point for Flutter tokens. Values may be
adjusted for contrast, dark mode, or platform rendering, but do not sample new
colors from generated images unless a later design task updates this table.

| Token | Hex | Use |
|---|---:|---|
| `backgroundSage` | `#F2F7EF` | App background and large quiet areas |
| `surfaceWarm` | `#FFFCF7` | Main cards, rows, dialogs, and warm surfaces |
| `primaryGreen` | `#2F6F4E` | Brand primary, primary actions, checks, focus |
| `primaryContainerSage` | `#DDEBDD` | Soft selected/active surfaces |
| `borderSage` | `#D9E3D6` | Thin borders, dividers, hierarchy lines |
| `leafGreen` | `#6FA17B` | Mascot body, illustration, soft secondary accents |
| `softSage` | `#A8BEA8` | Botanical illustration accents and low-emphasis marks |
| `cream` | `#F6E7B7` | Mascot belly, empty-state illustration warmth |
| `charcoal` | `#343938` | Text, icon outlines, and illustration linework |
| `coral` | `#E8755A` | Destructive actions, high priority, small alerts |
| `peach` | `#F3B996` | Softer illustration warmth, gentle warning accents |
| `amber` | `#EDB73E` | Timer detail, medium priority, small highlights |

- Muted text should use Material `onSurfaceVariant` or a contrast-checked
  equivalent derived from `charcoal`.
- Success should usually reuse `primaryGreen`.
- Warning should use `amber` sparingly.
- Danger should use `coral`, limited to destructive actions and high priority.
- `leafGreen` is not a second primary color. Keep it mostly for the mascot,
  illustration, and very soft secondary accents.
- `cream`, `peach`, `amber`, and `coral` are tiny accent colors, not large
  surface colors.

Avoid one-note green-only screens. White, neutral text, and small coral/yellow
accents should keep the palette alive. Green remains the main brand color,
sage and warm white carry large surfaces, and warm colors should stay small.

### Spacing

- Base spacing: 8px rhythm.
- Screen horizontal padding: 16px on mobile, 24px or more on wide layouts.
- Row internal padding: 12-16px vertical, 16px horizontal.
- Section gap: 16-24px depending on density.
- Metadata gap: 4-8px with wrapping enabled.
- Empty state padding: generous, but not so large that the primary action falls
  below the fold on mobile.

### Radius

- Task/list rows: 14-16px in current app, with future tightening allowed if the
  interface becomes too bubbly.
- Chips/pills: fully rounded.
- Dialogs and panels: 18-24px maximum.
- Do not use oversized rounded containers for everything. Shape should clarify
  hierarchy, not become the brand by itself.

### Typography

- Screen title: calm, medium-large, semibold/bold.
- Compact app header/list title: smaller than marketing hero type.
- Task title: medium weight, readable at list density.
- Metadata: label-sized, never the visual center.
- Empty state: friendly but concise.
- Timer numerals: large and clear, but the selected task remains visible.

Do not scale text with viewport width. Let platform text scaling and wrapping
drive accessibility.

### Surface And Borders

- Prefer flat white/warm surfaces with thin borders.
- Use shadow rarely and softly. Borders should carry most separation.
- Do not layer a card inside another card.
- Destructive or restore areas can use subtle tinted surfaces, not warning-heavy
  panels.

## Component Rules

### Task Row

- Primary order: completion control, priority signal if any, title, metadata,
  navigation/action affordance.
- Priority dot is small and supplemental. Always keep text/semantics for
  priority when priority matters.
- Done rows should become quieter, not disappear immediately.
- Metadata should wrap and remain readable on small screens.
- Subtask hierarchy lines are useful, but should be thin and low contrast.

### Metadata Chip

- Use chips for due date, status, priority, and subtask progress.
- Keep chip copy short and localized.
- Chips should be information, not buttons, unless the screen explicitly makes
  them interactive.
- Avoid chip overload. If a row has too much metadata, move secondary data to
  detail.

### Empty State

- Empty states may use the mascot or a simple icon.
- The message should say what is empty and offer the next useful action.
- Avoid onboarding-style paragraphs in normal empty lists.
- Empty task list is the best place for the mascot in the regular app.

### Dialog

- Dialogs should be plain, readable, and task-specific.
- Destructive confirmation copy should be calm and exact.
- Primary action uses filled button only when it is truly the main action.
- Destructive action should not use cheerful colors or mascot art.

### Trash And Restore

- Trash is an operational screen, not a danger zone.
- Deleted rows should look recoverable: muted title, deletion metadata, restore
  action clearly available.
- Permanent delete, if added later, must be visually secondary and explicitly
  confirmed.
- Restore should feel ordinary and reversible, not celebratory.

### Icon-Only Controls

- Use familiar symbols for compact actions.
- Every icon-only control needs tooltip/semantics.
- Do not replace familiar icons with text pills when a standard icon is clearer.

## Adopted Expressions

- Deep green, pale sage, warm white surfaces.
- Priority dots plus text metadata.
- Pill metadata that wraps.
- A generous Today header as the arrival state, with a compact collapsed state
  while working.
- Thin hierarchy lines for subtasks.
- Calm completion state with undo.
- Timer as a focus declaration.
- Mascot in onboarding and empty states only by default.

## Expressions To Avoid

- Persistent encryption/lock mark in the main task header.
- Mascot-led UI or a constant assistant/avatar presence.
- Cute sticker-heavy screens.
- SaaS dashboard hardness with dense charts and status panels.
- Material default surfaces without Todori's color/spacing refinement.
- Heavy gradients, heavy shadows, nested cards, decorative blobs.
- Confetti, trophies, streaks, productivity pressure language.
- Bottom navigation as a default requirement before the information
  architecture calls for it.
- A permanently oversized Today header that keeps tasks below the fold during
  normal work.
- AI panels, account/sync screens, billing, legal, audit, or roadmap details in
  Phase 1 app mocks.

## Follow-Up Implementation Notes

### `app/lib/src/ui/theme.dart`

- Keep the current deep green / sage / warm white direction.
- Consider slightly tightening large radii if future screens feel too bubbly.
- Add explicit danger/warning accent helpers only when repeated use appears.
- Keep tokens small; do not introduce a large design system package.

### `app/lib/src/ui/task_components.dart`

- Preserve priority dot + text metadata.
- Ensure row density stays practical on mobile.
- Add future focus affordance as a compact row-level action or selected-task
  surface, not a permanent large panel.
- Keep subtask hierarchy lines subtle.

### `app/lib/src/ui/states.dart`

- Empty state is the main in-app home for the mascot.
- Add mascot support as optional content, not the default for every state.
- Keep error states plain and respectful.

### `app/lib/src/ui/dialogs.dart`

- Keep dialogs quiet and text-led.
- Restore/destructive flows should use exact confirmation language.
- Do not add mascot art to destructive dialogs.

### Future Timer Task

- Treat timer as its own feature task because it changes workflow, not just
  presentation.
- Model timer state explicitly before UI implementation.
- Support normal timer and Pomodoro as user-facing modes if the feature is
  accepted.
- Keep focus copy declarative and reversible.

### Future Completion/Undo Task

- Add undo snackbar for complete/delete/restore operations when the domain and
  UI flow support it.
- Keep completion visible long enough to reassure the user.
- Avoid celebration mechanics.

## Public/Private Boundary

This document is safe for the public repository. It does not include private
business, legal, audit, revenue, or unpublished roadmap details. Security
language is limited to public product positioning and does not claim features
that Phase 1 has not implemented.
