---
name: webapp-test-plan
description: Generate a comprehensive manual/automation-ready test plan from a webapp codebase. Analyzes routes, domain enums (status, role), role-separated flows, UI surfaces (tabs/filters/docs/chat), and fixture requirements. Produces `dogfood-output/test-plan.md` with per-step screenshot refs aligned to the `webapp-test-run` skill. Use when asked to "plan test coverage", "design dogfood tests", "build a test plan for this app", or "QA checklist".
---

# Webapp Test Plan Generator

Produce a structured test plan that:
- Covers the full lifecycle of the primary domain entity (e.g. Order, Booking, Ticket)
- Separates role-based operations (customer vs admin) clearly
- Enumerates UI surfaces beyond the happy path: tabs, filters, document DL, chat, notifications
- Lists required fixtures (upload files, seeded users)
- Aligns screenshot naming with the `webapp-test-run` skill so the plan can be executed downstream

## Output

Default output: `./dogfood-output/test-plan.md`

If the directory doesn't exist, create it.

## Workflow

```
1. Survey      Stack, auth separation, primary domain entity
2. Enumerate   Status transitions, derived group statuses, role actions
3. Map         Routes × actors × actions, UI surfaces
4. Catalogue   Fixtures (uploads, seed users)
5. Draft       test-plan.md with workflow tables
```

### 1. Survey the stack

Use Explore (or Glob/Grep) to identify:

- **Framework**: Next.js App Router? Pages Router? Remix? — check `app/` vs `pages/` vs `src/routes/`
- **Auth separation**: look for `/admin/*` route prefix, separate sign-in pages, or role-based middleware
- **ORM + schema**: `prisma/schema.prisma` (or equivalent) — find the primary entity and its status enum
- **Real-time features**: Supabase subscriptions, Pusher, Socket.IO, Ably
- **File uploads**: look for `input[type=file]`, Dropzone, Uploadcare, etc.

### 2. Enumerate the domain state machine

For the primary entity (Order/Booking/Ticket/etc):

- List every status in the enum
- Find the status-transition logic file (`lib/domain/*/logic.ts` or similar) — this is the source of truth
- Identify **admin-only statuses** that are hidden/renamed from customer view (e.g. `LOST` → customer sees `ESTIMATION_COMPLETED`)
- If entities are grouped (e.g. `OrderGroup`, cart, bundle), enumerate **derived group statuses** (PARTIALLY_X, ALL_X)

Produce a table like:

```markdown
| OrderStatus          | 管理者ラベル | 顧客ラベル     |
|----------------------|--------------|----------------|
| ESTIMATION_REQUESTED | 見積依頼中   | 見積依頼中     |
| ESTIMATION_COMPLETED | 見積済み     | 見積済み       |
| LOST                 | 失注         | 見積済み (隠蔽)|
| ARRANGED             | 手配済み     | 注文済み (隠蔽)|
```

### 3. Map routes × actors × actions

For each role, list the main routes:

- **Customer**: `/dashboard`, `/dashboard/orders/[id]`, `/dashboard/cart`, `/dashboard/cart/confirmation`
- **Admin**: `/admin/dashboard`, `/admin/dashboard/orders/[id]`

For each route, catalogue:
- Interactive elements (buttons, toggles, filters)
- Tabs and what each tab shows
- Document DL entry points (見積書 / 請求書 / etc.)
- Chat / messaging surfaces

### 4. Catalogue fixtures

Look for existing test files in `public/`, `docs/`, or `e2e/fixtures/`. Common needs:
- 3D models (STL / STEP / OBJ)
- PDFs (drawings, order sheets)
- Images (PNG / JPEG / WebP)
- Size-boundary files (just under / over the limit)
- Invalid extension file

Prefer ASCII filenames. Call out any that need to be created.

### 5. Draft the plan

Use `templates/test-plan-template.md` as the starting skeleton. Structure:

1. **前提** — target URLs, actors, test rationale
2. **実装分析サマリ** — 4-8 bullet-point findings from steps 1-3
3. **アップロード準備** — constraint limits + fixture table + 既存再利用候補
4. **スクショ撮影ルール** — naming: `test-<N>-<M>.png`, per-step screenshot required, variants (`-a`/`-b`/`-customer`/`-admin`)
5. **テスト 1..N** — one section per workflow with this table shape:
   ```
   | #   | 操作者  | 操作 | 確認ポイント | スクショ       |
   |-----|---------|------|--------------|----------------|
   | 1-1 | 顧客B   | ...  | ...          | `test-1-1.png` |
   ```
6. **実行順序** — short numbered list with rationale (basics first, edge cases after)
7. **ステータス一覧（参考）** — enum → label tables, derived statuses

### Guidance on workflow selection

Priority order for a standard CRUD-with-approval webapp:

1. **Happy path end-to-end** — create → review → approve → fulfill → close
2. **Grouped/bundle happy path** — same but with N items
3. **Payment / branching flows** — if conditional logic (prepaid vs invoice, shipping options)
4. **Exception statuses** — reject, cancel, lost, expired
5. **Self-service cancel / delete**
6. **Real-time / messaging**
7. **List UI (tabs, filters, search)** — each for both roles
8. **Document downloads**

Aim for **5-9 tests total**. Each test should have 5-17 steps. If a test has 20+ steps, split it.

### Role naming convention

Use Japanese shorthand if the app is in Japanese (顧客B / 管理者A), English otherwise (customer / admin). Consistency matters more than choice.

### Don't

- Don't invent workflows the app doesn't support — verify each action maps to an actual button/route
- Don't write tests that require prod data — list them in "要: X アカウント" and move on
- Don't write vague steps ("確認する") without a concrete observable — always name the element or label to look for
- Don't skip screenshot column — the downstream `webapp-test-run` skill relies on it

## Template

See `templates/test-plan-template.md` for the starting skeleton.
