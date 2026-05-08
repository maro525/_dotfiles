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

<!-- Inline sections per step — not a table. Embed screenshots with ![alt](path). -->

### テスト1: {workflow name}

**1-1** ✅ {what happened}

![test-1-1](screenshots/test-1-1.png)

**1-2** ✅ {what happened}

![test-1-2](screenshots/test-1-2.png)

---

### テスト2: {workflow name}

...

---

## 次ステップの提案

1. {what passed cleanly}
2. {what needs follow-up and why}
3. {data residue left for reuse}
