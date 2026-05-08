# Webapp Testing Skills

Two Claude Code skills that together let you go from an unfamiliar webapp codebase to an executed, screenshotted, git-tracked dogfood run — while staying within one or two sessions.

- **`webapp-test-plan`** — generates `dogfood-output/test-plan.md` by reading the codebase
- **`webapp-test-run`** — executes the plan with `agent-browser`, producing `dogfood-output/report-YYYY-MM-DD.md` and a dated git branch

These are designed to be used independently or as a pipeline. They were distilled from a real 2-session dogfood run of a Next.js manufacturing quote/order platform (staging, ~76 test steps, 9 workflows).

## Installation

The skills are already installed at `~/.claude/skills/webapp-test-plan/` and `~/.claude/skills/webapp-test-run/`. To share with a teammate, copy both directories into their `~/.claude/skills/`.

Requirements:
- `agent-browser` on PATH (install: `brew install agent-browser`)
- Claude Code with the Skill tool
- Git (for the branch-push step)

## When to use which

| You want to… | Use |
|---|---|
| Understand an unfamiliar app's testable surface | `webapp-test-plan` |
| Turn a plan into a runnable automation script-of-a-kind | `webapp-test-run` |
| Run the full pipeline | Both, plan first, then run |
| Just find bugs without a plan | The existing `dogfood` skill |

## Pipeline at a glance

```
            ┌──────────────────────┐       ┌──────────────────────┐
codebase ─▶│   webapp-test-plan   │──────▶│   webapp-test-run    │──▶ dated branch
            │                      │       │                      │    + report
            │ • routes             │       │ • 2-actor sessions   │    + screenshots
            │ • enums              │       │ • per-step screenshots│
            │ • workflows          │       │ • issue tracking     │
            │ • fixtures           │       │ • gotcha references  │
            └──────────────────────┘       └──────────────────────┘
                      │                              │
                      ▼                              ▼
            dogfood-output/test-plan.md     dogfood-output/report-YYYY-MM-DD.md
            (inputs: screenshot name column)  (renders those screenshots inline)
```

## `webapp-test-plan`

### What it does

Walks the codebase and drafts a full manual test plan organized by workflow. The plan has enough detail that either a human or `webapp-test-run` can execute it.

### Output shape

`dogfood-output/test-plan.md` with:

1. **前提** — URLs, actors, rationale
2. **実装分析サマリ** — 4-8 bullet findings
3. **アップロード準備** — fixtures (needed / to-create / reuse)
4. **スクショ撮影ルール** — naming convention (`test-<N>-<M>.png`)
5. **テスト 1..N** — per-workflow tables: `# | 操作者 | 操作 | 確認ポイント | スクショ`
6. **実行順序** — numbered execution plan
7. **ステータス一覧（参考）** — enum → label mappings

### What it discovers

- Framework & auth separation (`app/` vs `pages/`, `/admin/*`)
- Primary domain entity + status enum (`prisma/schema.prisma`, `lib/domain/*/logic.ts`)
- Admin-only statuses hidden from customer view
- Derived group statuses (PARTIALLY_X, ALL_X)
- Role-based routes and UI surfaces (tabs, filters, docs, chat)
- Existing fixture files in `public/` / `docs/`

### Invocation

```
/webapp-test-plan
```

The skill will ask for missing info (app URL, output dir) rather than guess.

## `webapp-test-run`

### What it does

Runs a plan through `agent-browser`, taking screenshots per step, writing the report as it goes, and committing results to a dated branch.

### Output shape

1. `dogfood-output/screenshots/test-<N>-<M>.png` — one per plan step
2. `dogfood-output/report-YYYY-MM-DD.md` — report with:
   - Header (date, URL, accounts, fixtures)
   - Severity summary table
   - 実行サマリ (run overview)
   - Issues (critical/high/medium/low, appended as found)
   - テスト実行状況 (inline sections per step with embedded screenshots — **no large tables**)
3. `test/dogfood-YYYY-MM-DD` git branch with all of the above committed

### What it handles

- Dual-actor sessions (customer + admin open simultaneously)
- Direct-URL navigation when link clicks are brittle
- Entity ID tracking across role switches
- Dialog triggers that need post-click wait (`aria-haspopup="dialog"`)
- Stale refs after state changes
- Date-picker scroll-into-view
- Incremental report writes (survives mid-session interruption)

### Invocation

```
/webapp-test-run
```

Asks for credentials if not provided. Never invents them.

### When the automation hits a wall

See `~/.claude/skills/webapp-test-run/references/agent-browser-gotchas.md` for the full troubleshooting reference. The top issue and its fixes:

**`<div onClick>` doesn't respond to `click @eN`**

Snapshot shows `generic [ref=eN] clickable` (not `button`). Options:

1. Fix the app — convert to `<button type="button">`. A11y + automation win. Independently justifiable.
2. `click @eN --force` after scroll-into-view.
3. `eval` escape hatch:
   ```bash
   agent-browser --session s eval "(() => { const c = Array.from(document.querySelectorAll('div')).filter(el => el.textContent.includes('LABEL') && el.onclick); c[0].click(); return 'clicked'; })()"
   ```

In practice, option 1 (app fix) was the right call — one small change unblocked automation for the entire plan.

## Session lessons encoded

The skills bake in lessons from the source run:

| Lesson | Where it's encoded |
|---|---|
| Plan by workflow, not by page | `webapp-test-plan` SKILL.md §3 |
| Screenshot naming must be set at plan time | Both SKILL.md files (aligned) |
| Always use two browser sessions for role-based apps | `webapp-test-run` SKILL.md §2 |
| Refs renumber on any state change | gotchas.md "Ref stability" |
| Radix dialogs need 1500-2500ms post-click wait | gotchas.md "Clickability" |
| Don't narrate clicks — verify via `eval window.location.href` | `webapp-test-run` SKILL.md "Verifying navigation" |
| Inline report sections beat wide tables | `webapp-test-run` SKILL.md §"Formatting the report" |
| Commit to a dated branch, not a generic feature branch | `webapp-test-run` SKILL.md §6 |
| Don't include unrelated file changes in the commit | `webapp-test-run` SKILL.md §6 |
| Don't burn 30 tool calls on one step — mark as `⏸ blocked` | gotchas.md "When to give up" |
| Fix app code only when the fix is independently justifiable | `webapp-test-run` SKILL.md "Guidance" |

## Known limitations

- **Plan generator is heuristic**. It makes a good first draft but will miss app-specific flows. Review the plan before running.
- **Run skill assumes `agent-browser`** (not Playwright directly, not puppeteer). If you want a different runner, fork the skill.
- **Credentials are a prompt**. There's no managed credential storage — you paste them in the session.
- **No parallel test execution**. Steps run sequentially. Good enough for <100-step plans; would need rework for bigger suites.
- **Screenshot review is manual**. The skill captures screenshots but doesn't compare them across runs; there's no visual-regression layer.

## Real-world example

From the 2026-04-14/15 dogfood run that produced these skills:

- Plan generation: `dogfood-output/test-plan.md` — 9 tests, ~76 steps
- One code fix triggered by automation: `manufacturing-settings.tsx` `<div onClick>` → `<button>`
- Runtime result: 56+ steps ✅ passed, 0 app bugs, 1 automation issue (resolved by the fix), test 3 skipped due to missing fixture account
- Branch: `test/dogfood-2026-04-14`

## File layout

```
~/.claude/skills/
├── webapp-testing-README.md          ← this file
├── webapp-test-plan/
│   ├── SKILL.md                      ← main instructions
│   └── templates/
│       └── test-plan-template.md     ← plan scaffold
└── webapp-test-run/
    ├── SKILL.md                      ← main instructions
    ├── references/
    │   └── agent-browser-gotchas.md  ← troubleshooting reference
    └── templates/
        └── report-template.md        ← report scaffold
```
