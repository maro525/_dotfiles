# Skill Auto-Routing

**UserPromptSubmit hook automatically suggests the appropriate skill based on user intent.**

## Overview

When a user types a prompt, the `agent-router.py` hook analyzes it and suggests one of 4 core skills via `additionalContext`. This is a **soft recommendation** -- Claude should follow it unless the user's intent is clearly different.

## How It Works

The hook runs on every `UserPromptSubmit` event and follows this priority:

```
1. Explicit skill command detected? → Do nothing (user already specified)
2. Skill intent detected + NOT lightweight? → Suggest skill
3. Agent intent detected (OpenCode / firecrawl MCP / Explore)? → Suggest agent
4. None of the above → No suggestion
```

## When to Follow the Suggestion

**MUST follow** the skill suggestion when:
- The `additionalContext` contains `[Skill Routing]`
- The user's prompt clearly aligns with the suggested skill's purpose
- There is no conflicting explicit instruction from the user

**MAY ignore** the skill suggestion when:
- The user explicitly asks for something different from the suggested skill
- The task is clearly too small for the suggested workflow (e.g., XS task suggested for /startproject)
- The user asks a follow-up question within an existing workflow

## Skill Intent Triggers

### /startproject
- New feature or project requests
- Issue/ticket execution requests
- Planning and requirements gathering
- Keywords: "new feature", "start project", "plan", "issue #", "develop"

### /team-implement
- Approved plan ready for implementation
- Explicit implementation requests after planning
- Keywords: "implement", "code this", "approved", "proceed"

### /team-review
- Code review requests after implementation
- Quality or security check requests
- Keywords: "review", "check", "quality", "security review"

### /fs-ops
- Filesystem operations (mkdir, rm, cp, mv, chmod, ln, touch)
- Directory restructuring or file reorganization
- Keywords: "mkdir", "rm", "delete", "remove", "move", "copy", "chmod", "touch", "create directory", "create folder", "restructure"

### /deploy
- PR creation, push, or deployment requests
- **All ad-hoc git operations** (commit, log, diff, branch, blame, stash, etc.)
- Keywords: "deploy", "create PR", "push", "merge", "release", "commit", "git log", "diff", "branch", "checkout", "blame", "stash", "pull", "fetch"

## Lightweight Task Exclusion

The following are NOT routed to skills:
- Questions and explanations ("what is", "why", "explain")
- Single-file operations ("fix this", "rename", "format")
- Direct commands ("lint", "run tests")
- Short prompts (under 30 characters)

> **Note**: Git operations ("commit", "push", "diff", etc.) are NOT excluded.
> They are routed to `/deploy` skill (Ad-hoc Git mode) for context isolation.
>
> **Note**: Filesystem operations ("mkdir", "rm", "mv", etc.) are NOT excluded.
> They are routed to `/fs-ops` skill for impact analysis and context isolation.

## Interaction with Existing Hooks

- `agent-router.py` handles **both** skill routing and agent routing in a single hook
- Skill routing takes priority over agent routing
- `enforce-tool-routing.py` (PreToolUse) is unaffected -- it handles Bash command routing
- Skills with `context: fork` bypass PreToolUse hooks entirely

## For Claude: Responding to Skill Suggestions

When you receive a `[Skill Routing]` suggestion in additionalContext:

1. **Acknowledge the suggestion** to the user (in Japanese)
2. **Invoke the suggested skill** using the Skill tool
3. If the suggestion seems wrong, explain why and ask the user what they prefer

Example response pattern:
```
ユーザーの意図は新機能の開発のようです。`/startproject` で計画フェーズを開始します。
→ /startproject {feature description}
```
