# Dogfood Report: {APP_NAME}

| Field | Value |
|-------|-------|
| **Date** | {YYYY-MM-DD} |
| **App URL** | {http://localhost:PORT} |
| **Session** | {session-customer / session-admin} |
| **Scope** | `dogfood-output/test-plan.md` に従った N テスト |
| **Accounts** | Customer: {email} / Admin: {email} |
| **Fixtures** | {reused files} |

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
| **Total** | **0** |

## 実行サマリ

{1-3 paragraph overview: what passed, what blocked, any app fixes applied}

### 実施できたこと

- {workflow-level bullets}

### 未実施分

- {test-id + reason}

## Issues

<!-- Append each issue as it's found. Don't batch. -->

### ISSUE-001: {short title}

| Field | Value |
|-------|-------|
| **Severity** | critical / high / medium / low |
| **Category** | visual / functional / ux / content / performance / console / a11y |
| **URL** | {url} |
| **Repro Video** | {path or N/A} |

**Description**

{what vs expected vs actual}

**Repro Steps**

1. {step}
   ![Step 1](screenshots/issue-001-step-1.png)

2. {step}
   ![Step 2](screenshots/issue-001-step-2.png)

3. **Observe:** {breakage}
   ![Result](screenshots/issue-001-result.png)

---

## テスト実行状況

進捗: **{DONE}/{TOTAL}** ステップ実行済

<!--
  Inline sections per step — not a table. Embed screenshots with ![alt](path).

  REQUIRED for every step: copy the test item from the plan verbatim so the
  report is self-contained. Each step MUST include:
    - 先頭のチェックボックス (`- [x]` = 実行済 / `- [ ]` = 未実行)
    - 操作者 (actor: 顧客B / 管理者A / ...)
    - 操作 (action — copied from the plan's 操作 column)
    - 確認ポイント (verification point — copied from the plan's 確認ポイント column)
    - 結果 (✅/⏸/❌ + what actually happened; reference ISSUE-NNN if a bug.
      未実行の場合は理由を書く)

  Render rules:
    - GitHub-flavored task list: `- [x]` for executed, `- [ ]` for not-executed.
    - Initialize all steps as `- [ ]` when copying the plan, then flip to `- [x]`
      as each step is executed (✅/⏸/❌ regardless of pass/fail).
    - Status icon meaning: ✅=pass, ⏸=partially run/blocked mid-step, ❌=fail.
      "Not yet run at all" is represented by leaving the box unchecked + 未実行 label.
    - Keep nested content indented 2 spaces under the task list item so the
      checkbox renders correctly on GitHub.
    - Never collapse a step to just a status + screenshot. The plan content
      must be present in the report itself.
-->

### テスト1: {workflow name}

対象: {scope — 計画書から転記}

ステータス遷移: `{S0} -> {S1} -> ...` （計画書から転記）

- [x] **1-1** ✅
  - 操作者: {顧客B / 管理者A}
  - 操作: {計画書の「操作」をそのまま転記}
  - 確認ポイント: {計画書の「確認ポイント」をそのまま転記}
  - 結果: {実際に起きたこと。問題があれば ISSUE-NNN を参照}

  ![test-1-1](screenshots/test-1-1.png)

- [x] **1-2** ✅
  - 操作者: ...
  - 操作: ...
  - 確認ポイント: ...
  - 結果: ...

  ![test-1-2](screenshots/test-1-2.png)

- [ ] **1-3** ⏸ 未実行
  - 操作者: ...
  - 操作: ...
  - 確認ポイント: ...
  - 結果: 未実行（理由: {blocked by ... / 時間切れ / 前ステップ失敗で中断 等}）

---

### テスト2: {workflow name}

...

---

## 次ステップの提案

1. {what passed cleanly}
2. {what needs follow-up and why}
3. {data residue left for reuse}
