# agent-browser gotchas (from real dogfood runs)

Consult this reference when a step doesn't behave as expected.

## Clickability

### `<div onClick>` with no role

**Symptom**: `snapshot -i` shows the element as `generic "LABEL" [ref=eN] clickable [cursor:pointer, onclick]` — note `generic`, not `button`. Calling `click @eN` fires synthetic event but React state doesn't change.

**Why**: Playwright's synthetic click on non-button divs doesn't always bubble through React's event system the way users' native clicks do.

**Fixes** (in order of preference):
1. Convert to `<button type="button">` in the app (A11y improvement too).
2. `click @eN --force`.
3. `eval "(() => { const c = Array.from(document.querySelectorAll('div')).filter(el => el.textContent.includes('LABEL') && el.onclick); c[0].click(); return 'clicked'; })()"`.
4. If it's a Radix primitive rendered as div with `role="button"`, use `click @eN` but after `wait 500`.

### Radix dropdowns / dialog triggers

**Symptom**: button with `aria-haspopup="dialog"` or `aria-haspopup="menu"` and `aria-expanded="false"`. Click doesn't seem to open the popover in the snapshot.

**Why**: Radix portals content at the end of `<body>` after a small delay. A snapshot taken immediately after `click` may capture the pre-mount DOM.

**Fix**: `wait 1500-2500` after click before snapshotting. Then look for `heading "本当に..."` or `dialog` / `alertdialog` roles.

## Ref stability

Refs (`@e1`, `@e2`, ...) are assigned per-snapshot based on a DOM walk. **Any state change re-walks the DOM**. A ref captured before a click is generally invalid after. Rules:

- Re-snapshot before each action that needs a ref.
- After navigation (`wait --load networkidle`), refs always change.
- After form input state change (e.g., opening a datepicker), refs always change.
- Small actions like hover or scroll *usually* don't change refs, but verify.

## Date / time pickers

Most Radix/shadcn Calendar components render days as real `<button>` elements inside `gridcell`. They click fine, but:

- The popover is positioned near the trigger — scroll the trigger into view first.
- Disabled dates (past, weekends, before ETA) are `button [disabled]`. Don't try to click them.
- The calendar shows the current month by default; to find a future date, sometimes you need to click the month-nav `>` button first.
- Look for `gridcell "YYYY年M月D日曜日"` in the snapshot to find date buttons.

## Form inputs

### `fill` vs `type`

- `fill` sets the value atomically (fast, works for most inputs).
- `type` types character-by-character (slow, needed for inputs that react on each keystroke, e.g. autocomplete).
- For recording videos, use `type` to make the video watchable.

### Select / combobox

Shadcn Select is `button role="combobox"`. Pattern:

```bash
click @eComboboxRef
wait 500
# Re-snapshot to find option refs — they only exist after opening
snapshot -i | grep -E "option"
click @eOptionRef
```

Don't try to `fill` a combobox; it won't work.

### File upload

```bash
upload @eInputRef /abs/path/to/file.ext
# For multi-file:
upload @eInputRef /path1 /path2 /path3
```

The `@e` ref can point to the hidden `<input type=file>` (often labelled as "Choose Files" in the snapshot). Some apps have custom drop zones — uploading to the hidden input is the reliable path.

## Navigation & waits

### `wait --load networkidle` vs `wait NNN`

- `wait --load networkidle` — wait for no network activity for ~500ms. Good for page loads and server actions.
- `wait NNN` — fixed ms wait. Good for animations, Radix portals, toast dismissal.

Don't `wait 500` when you should `wait --load networkidle`; you'll flake when the server is slow.

### Verifying navigation

```bash
agent-browser --session s eval "window.location.href"
```

Reliable check that routing actually happened. `✓ Done` from `click` means the click fired, not that the page navigated.

## Visual verification

### When to use `--annotate`

`screenshot --annotate path.png` overlays numeric labels on interactive elements. Great for:
- Understanding page structure on first visit
- Verifying which element got ref `@eN`

Don't use `--annotate` for final report screenshots; they look cluttered. Use plain `screenshot`.

### Small screenshots

`agent-browser` screenshots default to viewport size. If the output looks tiny and unreadable, check:
- The browser window size (default is 1280×720 or similar)
- Zoom level (use `eval "document.body.style.zoom = '1'"` to reset)
- Whether you need `--full` for full-page screenshots

### Reading a screenshot

Use Claude's `Read` tool on a PNG to view it. Don't spam `Read` on every screenshot — only when verifying hard-to-inspect state (toasts, status badges, non-structural UI). Prefer `snapshot -i | grep` when possible.

## Session lifecycle

### Session cookies / auth

Sessions persist within the daemon until `close`. Refresh your browser with `open URL` — the cookies stay.

**But**: if your local dev server restarts (e.g., Fast Refresh broke the Prisma client), cookies tied to the old server may be invalid. If you get unexpected redirects to `/sign-in` mid-run, re-authenticate.

### Closing sessions

```bash
agent-browser --session NAME close
```

Always close sessions at the end of a run. Orphan sessions consume memory.

## Console & errors

- `agent-browser --session s errors` — page errors since session start.
- `agent-browser --session s console` — console logs.

Dev-only warnings (React DevTools, Fast Refresh) are noise. Look for:
- `Error` / `Uncaught`
- `Failed to fetch`
- 4xx / 5xx status codes in `console`

## Common failure modes and fixes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Click fires but nothing changes | `<div onclick>` | See "Clickability" |
| Dialog doesn't appear | Radix mount delay | `wait 1500` |
| `fill` seems to work but value doesn't persist | React controlled input re-render | Use `type` instead |
| `click @eN` errors "Unknown ref" | Refs renumbered | Re-snapshot |
| Submit button click does nothing | Wrong button (duplicate) | Try the other submit button |
| Date picker not visible | Trigger off-screen | Scroll trigger into view first |
| Navigation didn't happen | Form validation error | Scroll, look for error messages |
| Cart count didn't update | Optimistic state desync | `open URL` to force reload |

## When to give up on a step

If you've:
1. Re-snapshotted
2. Tried force click
3. Tried the eval escape hatch
4. Verified DOM state via `eval`

...and it still doesn't work: document it as `⏸ blocked` with reason, move to the next test. Don't burn 30 tool calls on one step.
