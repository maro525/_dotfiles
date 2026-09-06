# Adaptive Execution

**Task size determines resource allocation. Use the minimum context needed.**

## Task Size Classification

Claude automatically classifies tasks into 4 tiers based on hybrid criteria.

### Classification Table

| Tier | Files | Complexity | Risk | External Research |
|------|-------|-----------|------|-------------------|
| **XS** | 1 | No logic change | None | Not needed |
| **S** | 1-3 | Single pattern | Low | Not needed |
| **M** | 4-10 | Multi-pattern | Medium | If needed |
| **L** | 10+ | Architecture change | High | Required |

### Classification Logic

```
tier = max(file_tier, complexity_tier, risk_tier)
```

Evaluate all three dimensions independently. The highest tier wins.

### Hard Triggers (Auto-L)

Any of the following automatically escalates to L:

- Database migration or schema change
- Authentication / authorization changes
- Payment / billing logic
- Public API surface changes
- New core dependency addition

### Examples

| Task | Tier | Reasoning |
|------|------|-----------|
| Fix typo in README | XS | 1 file, no logic, no risk |
| Add input validation to existing endpoint | S | 1-2 files, clear pattern |
| Add new API endpoint with tests | M | 4-6 files, some design decisions |
| Implement user authentication system | L | 10+ files, architecture change, auth (hard trigger) |
| Refactor 3 related modules | M | 4-10 files, multi-pattern, medium risk |
| Add new external library integration | L | New core dependency (hard trigger) |

## Workflow per Tier

### /startproject

| Tier | Phase 1 (Understand) | Phase 2 (Research & Design) | Phase 3 (Plan) |
|------|---------------------|---------------------------|----------------|
| **XS** | Skip /startproject entirely | - | - |
| **S** | Codebase read + brief | Skip | Simple task list |
| **M** | Codebase read + brief | OpenCode consultation only (no team) | Task list + design |
| **L** | Full codebase analysis | firecrawl MCP + OpenCode を並列実行 | Full plan |

> `/startproject` は `agent: Plan`（読み取り専用）で動く。Write / Edit / Agent を持たないため、
> リサーチは Bash・MCP から直接実行し、teammate は起動しない。
> 成果物は OUTPUT として `/orchestrate` に返し、TASK_FILE への書き込みと Linear 投稿は `/orchestrate` が行う。

### /team-implement

| Tier | Team Structure | Branch |
|------|---------------|--------|
| **XS** | Claude implements directly | No branch needed |
| **S** | Claude implements directly | Feature branch |
| **M** | Claude directly or 1-2 teammates | Feature branch |
| **L** | Full team (module-based ownership) | Feature branch |

### /team-review

| Tier | Review Approach |
|------|----------------|
| **XS** | Skip review |
| **S** | Claude self-review (single pass) |
| **M** | 2 reviewers (Security + Quality) |
| **L** | Full 4 reviewers (Security, Quality, Test, Simplify) |

### External Research (firecrawl MCP + OpenCode)

外部リサーチは firecrawl MCP（一次情報）と OpenCode `--agent plan -m github-copilot/gpt-5.6-sol`（実装知見）を並列実行する。

| Tier | Usage |
|------|-------------|
| **XS** | Never |
| **S** | Never |
| **M** | Only if task involves unknown libraries or external APIs |
| **L** | Standard（`/startproject` 内は Agent ツールが無いため直接実行。それ以外はサブエージェント経由） |

### OpenCode Design Consultation

設計相談も外部リサーチと同じ呼び出し形を使う: `opencode run --agent plan -m github-copilot/gpt-5.6-sol`（詳細は `rules/tool-routing.md`）。

| Tier | OpenCode Usage |
|------|------------|
| **XS** | Never |
| **S** | Only if debugging a non-obvious issue |
| **M** | Subagent for design questions |
| **L** | `/startproject` 内は Bash から直接実行。それ以外はサブエージェント経由 |

## Escalation

Tasks can escalate upward during execution (never downward).

### Checkpoints

1. **After planning** — Re-evaluate before implementation starts
2. **At 30-40% implementation** — Check if scope expanded
3. **Before review** — Verify final scope matches tier

### Escalation Triggers

- File count exceeds tier threshold
- Unresolved design questions accumulate
- New dependency added mid-implementation
- Risk dimension changes (e.g., touching auth code unexpectedly)

### Escalation Behavior

Escalation is **additive** — add resources for the new tier without restarting:

- S → M: Add OpenCode consultation for open design questions
- M → L: Spawn additional teammates for uncovered modules
- Never restart completed work

## Presentation

When classifying, briefly state the tier and reasoning to the user:

```
**Task Size: M (Medium)**
- Files: ~6 (4-10 range)
- Complexity: Multi-pattern (new rule + skill updates)
- Risk: Medium (affects framework behavior)
- External research: Not needed
```

User can override the classification if they disagree.
