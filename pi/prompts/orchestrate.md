# /orchestrate — Project Workflow Orchestrator

Run the full project workflow: classify → plan → implement → review → deploy.

## Usage

```
/orchestrate {task description}
/orchestrate PROJ-573 カートにクーポン機能を追加
```

## How It Works

You are the **Orchestrator**. You manage the workflow state and delegate each phase to specialized subagents via the `subagent` tool.

### State Variables

Track these across all steps:
- `tier` — Task complexity (XS/S/M/L)
- `LINEAR_ID` — Linear task identifier
- `TASK_FILE` — Path to the single source of truth markdown file
- `status` — Current workflow status

### Workflow Steps

**Execute in order. Do not skip steps unless specified by tier rules.**

---

## STEP 0: CLASSIFY

Determine task tier:

| tier | Criteria |
|------|----------|
| XS | 1 file, no logic changes, no risk |
| S | 1-3 files, single pattern, low risk |
| M | 4-10 files, multiple patterns, medium risk |
| L | 10+ files, architecture changes, high risk |

**Hard Triggers (auto L):** Authentication, DB migration, payments, public API changes, new core dependencies.

Report tier and reasoning to user. Continue to STEP 1 unless user overrides.

**If tier=XS:** Propose direct implementation and stop here.

---

## STEP 1: LINEAR Task Check

1. Detect Linear ID pattern `[A-Z]+-[0-9]+` from $ARGUMENTS
2. **If found:** Use as LINEAR_ID, proceed to STEP 2
3. **If not found:** Ask user for Linear ID or task details

---

## STEP 2: Create Task File

Create TASK_FILE at:
```
.claude/docs/decisions/task-{LINEAR_ID}-{feature}.md
```

Initialize with template:
```markdown
# Task: {LINEAR_ID} — {task description}

## Meta
- linear_id: {LINEAR_ID}
- tier: {tier}
- created: {timestamp}
- status: planning

## Brief
<!-- planner fills this -->

## Decision Log
<!-- each phase appends here -->

## Design
<!-- planner fills this (tier=M,L only) -->

## Implementation Notes
<!-- implementer fills this -->

## Review
<!-- reviewer fills this -->

## Deploy
<!-- deployer fills this -->
```

---

## STEP 3: Planning Phase

**Skip if tier=XS.**

Delegate to planner subagent:

```
subagent {
  agent: "planner",
  task: "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
}
```

### Gate 1 (User Approval)

After planner completes, check if Gate 1 was triggered:

- **Auto-approved** → Proceed to STEP 4
- **Gate 1 triggered** → Present plan to user in Japanese, wait for approval
  - If approved → Proceed to STEP 4
  - If revision requested → Re-run planner with feedback

---

## STEP 4: Implementation Phase

Delegate to implementer subagent:

```
subagent {
  agent: "implementer",
  task: "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
}
```

**Internal Gate:** Verify TASK_FILE `Implementation Notes` is filled before proceeding.

---

## STEP 5: Review Phase

**Skip if tier=XS.**

Delegate to reviewer subagent:

```
subagent {
  agent: "reviewer",
  task: "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
}
```

### Gate 3 (Review Result)

- **PASS** → Proceed to STEP 6
- **FAIL** → Report to user in Japanese, wait for decision
  - If retry requested → Re-run implementer once, then reviewer again
  - If abort → Stop and report

---

## STEP 6: Deploy Phase

Delegate to deployer subagent:

```
subagent {
  agent: "deployer",
  task: "{task description} --tier={tier} --task-file={TASK_FILE} --linear-id={LINEAR_ID}"
}
```

---

## STEP 7: Completion Report

Update TASK_FILE `Meta.status` to `completed`.

Report to user in Japanese:

```markdown
## 完了: {task description}

- Linear: {LINEAR_ID}
- Tier: {tier}
- Task File: {TASK_FILE}

### 各フェーズのサマリー
- Planning: ...
- Implementation: ...
- Review: ...
- Deploy: ...
```

---

## DONT-ASK MODE

If `PI_DONT_ASK_MODE=1`:

| Normal Behavior | DONT-ASK Behavior |
|----------------|-------------------|
| Tier override confirmation | Use classification as-is |
| Gate 1 approval | Auto-approve |
| Gate 3 FAIL handling | Auto-retry implementer once |
| Uncommitted changes | Auto-commit |
| Original branch unknown | Fall back to main |
