---
name: webapp-test-run
description: Execute an existing test plan (`dogfood-output/test-plan.md`) against a running web app using `agent-browser`, producing a dated report with per-step screenshots. Handles dual-actor sessions (customer + admin), common React/Radix automation pitfalls, and auto-commits results to a `test/dogfood-YYYY-MM-DD` branch. Use when asked to "run the test plan", "execute dogfood tests", "automate QA from plan", "go through test-plan.md".
---

# Webapp Test Plan Runner

Execute a plan from `webapp-test-plan` (or any similarly structured plan) against a running webapp, producing:
- Step-by-step screenshots in `dogfood-output/screenshots/`
- A dated report `dogfood-output/report-YYYY-MM-DD.md`
- A dated git branch `test/dogfood-YYYY-MM-DD` with plan + screenshots + report

## Prerequisites

- `agent-browser` on PATH (check with `which agent-browser`). If missing, install: `brew install agent-browser`
- Test plan at `dogfood-output/test-plan.md` (or user-specified path)
- Target app URL (default `http://localhost:3000`; ask if unknown)
- **Credentials** for each actor role (customer + admin). If not provided in the invocation, ask once upfront. Never invent them.

## Workflow

```
1. Initialize     Output dirs, copy report template, record date
2. Authenticate   Open session per actor, sign in, verify landing URL
3. Execute        Walk each test, step by step, with screenshots
4. Document       Update report incrementally; flag any app bugs as ISSUEs
5. Wrap           Close sessions, commit + push to test/dogfood-YYYY-MM-DD
```

## 1. Initialize

### 1.1 Pre-flight checks

Verify before doing anything else. Skipping these wastes the first 10–20 tool calls flailing inside §2.

1. **`agent-browser` is installed and runnable**
   ```bash
   agent-browser --version
   ```
   - If "command not found": `brew install agent-browser`, then re-check.

2. **Target app is reachable**
   ```bash
   curl -sf -o /dev/null -w "%{http_code}\n" "{APP_URL}"
   ```
   - Expect a 2xx or 3xx code.
   - `000` / connection refused → dev server isn't running. Start it (`pnpm dev`, `npm run dev`, etc.) and re-check.
   - Unexpected 4xx → confirm URL and port are correct (default 3000 may be taken; the actual port shows in the dev-server output).

Don't proceed to §1.2 until both checks pass.

### 1.2 Set up the report

```bash
mkdir -p dogfood-output/screenshots dogfood-output/videos
cp {SKILL_DIR}/templates/report-template.md dogfood-output/report-$(date +%Y-%m-%d).md
```

Fill in the report header fields: date, app URL, accounts, fixtures.

Then pre-populate `## テスト実行状況` with every step from `test-plan.md`, each as a `- [ ]` task-list item with 操作者 / 操作 / 確認ポイント filled in verbatim and 結果 left blank. This makes the report show the full intended scope upfront — execution then just flips boxes and fills in 結果.

## 2. Authenticate each actor

Standard pattern:

```bash
agent-browser --session {role}-session open {APP_URL}{SIGN_IN_PATH}
agent-browser --session {role}-session wait --load networkidle
agent-browser --session {role}-session snapshot -i | grep -iE "textbox|button"
# Locale-agnostic: pulls every form field and button. Pick the submit button
# from the results (sign in / ログイン / 登录 / etc. — depends on the app).
# Pipe into fill + click
agent-browser --session {role}-session fill @eN "{email}"
agent-browser --session {role}-session fill @eM "{password}"
agent-browser --session {role}-session click @eK
agent-browser --session {role}-session wait --load networkidle
agent-browser --session {role}-session eval "window.location.href"  # verify landing
```

Use separate sessions per actor. Typical names: `{app}-customer`, `{app}-admin`.

## 3. Execute each test

For every step in the plan:

1. **Snapshot first** — `snapshot -i` gives fresh refs. Refs change after state changes; do not reuse old refs.
2. **Perform the action** — `click @eN` / `fill @eN "..."` / `upload @eN path1 path2` / `scroll down N`.
3. **Wait** — after destructive or state-changing actions, `wait 1500` to 2500ms. After navigation, `wait --load networkidle`.
4. **Verify** — `snapshot -i | grep <expected-label>` or `eval "window.location.href"`. Never assume.
5. **Screenshot** — `screenshot dogfood-output/screenshots/test-<N>-<M>.png` using the plan's name. Use `--annotate` only when you need labels in the image.

**Batch independent commands with `&&`** to save tool calls:

```bash
agent-browser --session s fill @e5 "..." 2>&1 | tail -2 && \
agent-browser --session s click @e7 2>&1 | tail -2 && \
agent-browser --session s wait --load networkidle 2>&1 | tail -2 && \
agent-browser --session s screenshot ".dialog-content" dogfood-output/screenshots/test-1-2.png 2>&1 | tail -2
```

**Read screenshots** with `Read` only when you need to verify visually. Not every step needs it.

### 3.1 Scope snapshots and screenshots — default to the smallest relevant area

The default for both `snapshot` and `screenshot` should be **scoped to the area the step affects**, not the full page. Full-page captures only when the test explicitly verifies layout, navigation, or whole-page state (404 page, sidebar collapse, list pagination, etc.).

**Snapshot scoping** — `snapshot -s "<css-selector>"` returns the accessibility tree for one subtree only. This:
- shrinks token usage dramatically (a 300-line full snapshot becomes 10–30 lines)
- avoids ref renumbering noise from unrelated DOM elsewhere on the page
- makes `grep` against the output far more reliable

```bash
# Dialog only — refs are stable while dialog stays open
agent-browser --session s snapshot -i -s "[role=dialog]"

# Single table row by data attribute or aria
agent-browser --session s snapshot -i -s "tr:has-text('バンド')"

# Header / sidebar / main only
agent-browser --session s snapshot -i -s "header"
agent-browser --session s snapshot -i -s "main"
```

If you can't predict a stable selector, snapshot once unscoped to find one (`[role=dialog]`, `[data-testid=...]`, or a unique aria-label), then scope subsequent reads.

**Screenshot scoping** — `agent-browser screenshot [selector] [path]` accepts an optional selector as the first arg. Use it for verification screenshots:

```bash
# Capture only the dialog that opened
agent-browser --session s screenshot "[role=dialog]" dogfood-output/screenshots/test-1-5.png

# Capture only the row that changed
agent-browser --session s screenshot "tr:has-text('バンド')" dogfood-output/screenshots/test-3-4.png

# Capture a single card
agent-browser --session s screenshot "[data-testid=check-count-card]" dogfood-output/screenshots/test-2-8.png
```

**When to use full-page** (no selector, optionally `--full`):
- The test explicitly checks page-level state: 404, redirect landing, full layout, navigation.
- A toast/notification you want to capture is anchored outside the affected component.
- You are documenting an issue and want surrounding context (URL bar, sidebar, header) for the bug report.
- The first step of a test where you want to establish "where we are."

**When to scope** (default):
- Verifying a dialog opened, a row changed, a button toggled state, a counter incremented.
- Confirming a single field's validation message.
- Showing the result of an action whose effect is local (modal, dropdown, sheet, drawer).

When scoping, the screenshot still represents the step's verification point — keep one screenshot per step, just smaller.

### 3.2 Check console/errors at test boundaries

After finishing each test (not each step), inspect every open session for silent failures:

```bash
agent-browser --session {role}-session errors
agent-browser --session {role}-session console 2>&1 | grep -iE "error|warn|failed|4[0-9]{2}|5[0-9]{2}" | head -20
```

A visibly passing test can still hide bugs: failed fetches, uncaught promise rejections, React key warnings, 4xx/5xx responses. If new entries appear since the previous boundary, file them as an ISSUE-NNN with category `console` even when the UI checkpoint passed — silent failures are the ones users hit later.

**Ignore dev-only noise** (add to your filter as you find them): React DevTools nags, Fast Refresh / HMR logs, Next.js telemetry, source-map fetch warnings, hydration mismatch warnings that disappear on reload.

**Why per-test, not per-step**: per-step is too noisy and burns tool calls; end-of-run is too coarse to localize which test introduced the error. Per-test gives you a usable bisection.

## Automation gotchas (consult during §3 Execute)

This is reference material, not a sequential phase — open it when a step doesn't behave as expected. See `references/agent-browser-gotchas.md` for the full list. Top items:

### `<div onClick>` doesn't respond to `click @eN`

Symptom: snapshot shows `generic "..." [ref=eN] clickable [cursor:pointer, onclick]` (note: `generic`, not `button`). Clicking does nothing; state doesn't change.

**Workarounds** (in order of preference):
1. **Fix in app code**: convert to `<button type="button">`. A11y win + automation fix. Only do this if you have permission to modify the app.
2. **`click @eN --force`**: sometimes works after scroll-into-view.
3. **`eval` escape hatch**:
   ```bash
   agent-browser --session s eval "(() => { const c = Array.from(document.querySelectorAll('div')).filter(el => el.textContent.includes('LABEL') && el.onclick); c[0].click(); return 'clicked'; })()"
   ```

### Radix dialog triggers need a wait

A button with `aria-haspopup="dialog"` and `aria-expanded="false"` opens an AlertDialog. After clicking, wait ≥1500 ms before snapshotting, or the dialog content won't be in the tree yet.

### Refs renumber after any state change

Do **not** chain long action sequences using old refs. Re-snapshot after each state change. `@e27` before a navigation is a different element than `@e27` after.

### Date pickers need scroll-into-view first

Calendar popovers position relative to the trigger. If the trigger is off-screen, the popover may render below the fold. `scroll down N` until the trigger is visible, *then* click.

### Submit button inconsistency

Some forms have duplicate submit buttons (mobile header + desktop footer). They can map to different form instances. If the first one doesn't submit, try the other. Verify via `eval "window.location.href"` whether navigation happened.

### File upload

Use `upload @eInputRef path1 [path2 ...]`. Multiple files in one call creates N separate entities (not N attached to one). Useful for multi-item flows.

## 4. Document issues as you find them

Every bug is an `### ISSUE-NNN` block in the report with:
- Severity (critical / high / medium / low)
- Category (visual / functional / ux / content / performance / console / a11y)
- URL
- Description (what vs expected)
- Numbered repro steps, each with its screenshot

Static issues (typos, layout) need one annotated screenshot. Interactive issues need a step-by-step set or a video (`record start` / `record stop`).

**Do NOT batch** issue writing for later. Append immediately on discovery so the report survives a mid-session stop.

## 5. Wrap up: report + git

After all tests (or at a natural stopping point):

1. Update the report's `## テスト実行状況` section. For **every** step, copy the test item from the plan (操作者 / 操作 / 確認ポイント) verbatim and add the result (✅ / ⏸ / ❌ + what actually happened) plus the screenshot. Each step is a GitHub task-list item — `- [x]` for executed steps (regardless of pass/fail), `- [ ]` for not-yet-run steps. The report must be self-contained — never collapse a step to just a status line.
2. Close sessions: `agent-browser --session X close` for each.
3. Commit to a dated branch. If a branch with the same date already exists (e.g. you re-ran the suite the same day), append `-2`, `-3`, etc.:

```bash
# Pick a unique branch name: test/dogfood-YYYY-MM-DD, or -2/-3/... if it exists.
BASE="test/dogfood-$(date +%Y-%m-%d)"
BRANCH="$BASE"
N=2
while git show-ref --quiet "refs/heads/$BRANCH"; do
  BRANCH="${BASE}-${N}"
  N=$((N+1))
done

git checkout -b "$BRANCH"
git add dogfood-output/
# Add any app-code fixes that unblocked automation (if you made them)
git commit -m "$(cat <<EOF
test(dogfood): YYYY-MM-DD run — {summary}

{what-passed}
{what-blocked-and-why}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push -u origin "$BRANCH"
```

(The loop only checks local branches; if a remote branch with the same name exists from another machine, `git push` will reject — bump the suffix manually in that case.)

**Do not** include unrelated changes (e.g. `pnpm-lock.yaml` if you didn't touch deps). `git status` first.

## Formatting the report

Use `templates/report-template.md` as the skeleton. The `## テスト実行状況` section should use **inline sections per step with embedded screenshots**, not one big table.

**Each step MUST include the test item itself** (copied from the plan), not only the result. A reader should be able to understand what was tested without opening `test-plan.md`. Required per step:

- Checkbox prefix (`- [x]` = executed / `- [ ]` = not yet executed). At initialization, all steps are unchecked. Flip to checked as each step runs (regardless of pass/fail).
- 操作者 (actor — e.g. 顧客B / 管理者A)
- 操作 (action — copied verbatim from the plan's 操作 column)
- 確認ポイント (verification point — copied verbatim from the plan's 確認ポイント column)
- 結果 (✅/⏸/❌ + what actually happened; link ISSUE-NNN if a bug was found. For unchecked steps, write 未実行 + reason)

Status icon meaning: ✅ pass, ⏸ partially run / blocked mid-step, ❌ fail. "Not yet run at all" stays as `- [ ]` with no icon.

```markdown
### テスト1: {workflow name}

対象: {scope — 計画書から転記}
ステータス遷移: `{S0} -> {S1} -> ...`

- [x] **1-1** ✅
  - 操作者: 顧客B
  - 操作: ログインしてダッシュボードを開く
  - 確認ポイント: 「新規注文」ボタンが表示される
  - 結果: ボタン表示確認、URL `/dashboard` に遷移

  ![test-1-1](screenshots/test-1-1.png)

- [ ] **1-2**
  - 操作者: 顧客B
  - 操作: 新規注文フォームを送信
  - 確認ポイント: 注文一覧に表示される
  - 結果: 未実行（ブロッカー: ISSUE-001 で送信ボタンが反応しない）
```

Long wide tables are hard to read in rendered markdown. Task-list items with images interleaved work better, the checkbox makes executed/未実行 a glanceable signal, and the bulleted test-item block keeps each step self-describing.

### Initialization: pre-populate all steps as unchecked

At the start of the run (§1 Initialize), after copying the template, walk through `test-plan.md` and pre-populate the `## テスト実行状況` section with **every** step from the plan, all marked `- [ ]`. This way the report shows the complete coverage scope from the start, and execution simply flips boxes as you go. If you stop mid-run, the unchecked steps document exactly what's left.

## Guidance

- **Dual-actor pattern**: always open both sessions upfront; switch between them throughout. A round-trip bug (customer sends, admin receives) needs both open simultaneously.
- **Direct URL navigation beats clicking nav links** when you know the route. Saves tool calls and avoids brittle nav clicks.
- **Store entity IDs in memory** during the run — when you create an Order with ID `abc-123`, you'll need it for admin view, reports, and subsequent tests.
- **Verify each step via state, not via click success**. `✓ Done` from `click` means the click fired, not that the intended effect happened.
- **Screenshot at the verification point**, not before the action.
- **Scope snapshots and screenshots by default** — pass a selector (`snapshot -s "<sel>"`, `screenshot "<sel>" <path>`). Full-page only when the test is genuinely about the whole page (404, navigation, full layout). See §3.1.
- **Prefer `wait --load networkidle` for navigations**, fixed `wait NNN` for animations and state toggles.
- **When stuck, inspect DOM**: `agent-browser eval "(() => { const el = document.querySelector('...'); return {tag: el.tagName, attrs: [...el.attributes].map(a => a.name+'='+a.value)}; })()"`.
- **Never modify the app to make a test pass**. If you fix an app issue because automation needs it (e.g. `<div onclick>` → `<button>`), the fix must be independently justifiable (usually a11y win). Document the rationale in the commit.

## Stopping criteria

Stop and hand back to the user when:
- All tests in the plan have a result (✅ or ⏸ with reason)
- You hit an environmental blocker (missing account, missing fixture, broken local server)
- You find a **critical** or **high**-severity bug that changes subsequent steps

Don't stop just because a step is tricky — use the gotchas reference.
