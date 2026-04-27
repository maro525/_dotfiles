/**
 * Permissions extension for pi.
 *
 * Replicates Claude Code's allow/deny/ask permission model for bash commands.
 *
 * Install: symlink or copy to ~/.pi/agent/extensions/permissions/
 *
 *   mkdir -p ~/.pi/agent/extensions/permissions
 *   ln -sf /path/to/permissions.ts ~/.pi/agent/extensions/permissions/index.ts
 *
 * Then restart pi or run /reload.
 */

import type { BashOperations, ExtensionAPI, Tool } from "@mariozechner/pi-coding-agent";
import { createBashTool, createLocalBashOperations } from "@mariozechner/pi-coding-agent";

// ─── Pattern Lists (port of claude/settings.json permissions) ────────────────

/**
 * Patterns that are ALWAYS allowed (no prompt).
 * Uses glob-like syntax: * = any chars, ** = any path segments.
 */
const ALLOW_PATTERNS = [
  // Version / info
  "* --version",
  // File operations
  "cat *",
  "cp *",
  "echo *",
  "find *",
  "ls *",
  "tree *",
  "wc *",
  "xxd *",
  "lsof:*",
  "ss:*",
  // Text processing
  "grep *",
  "xargs:*",
  // Git (read-only + safe writes)
  "git status:*",
  "git status",
  "git branch:*",
  "git branch",
  "git diff *",
  "git diff:*",
  "git log *",
  "git log:*",
  "git show *",
  "git remote get-url:*",
  "git fetch:*",
  "git stash:*",
  "git checkout:*",
  "git add *",
  "git commit *",
  "git init:*",
  "git merge *",
  "git push *",
  "git push:*",
  // Node / npm / pnpm
  "node:*",
  "npm install:*",
  "npm run *",
  "npm test *",
  "npx biome check:*",
  "npx biome format:*",
  "npx eslint *",
  "npx prettier *",
  "npx tsc *",
  "npx vinxi build:*",
  "pnpm add:*",
  "pnpm biome check:*",
  "pnpm build:*",
  "pnpm build:v6:*",
  "pnpm check:*",
  "pnpm dev:*",
  "pnpm dlx:*",
  "pnpm exec eslint *",
  "pnpm exec prettier *",
  "pnpm exec tsc *",
  "pnpm install:*",
  "pnpm lint:*",
  "pnpm run *",
  "pnpm run type-check:*",
  "pnpm test *",
  "pnpm test-query:*",
  // Python / uv
  "uv install:*",
  "uv pip list:*",
  "uv run *",
  "uv sync:*",
  // BigQuery
  "bq ls:*",
  "bq query:*",
  "bq show:*",
  // GitHub CLI
  "gh pr create:*",
  "gh pr:*",
  "gh run:*",
  // Network
  "curl*",
  // Shell control flow keywords (safe)
  "do",
  "done",
  "else",
  "fi",
  "then",
  "for:*",
  // Agent browser skill
  "agent-browser:*",
  // Directory creation / move
  "mkdir *",
  "mkdir:*",
  "mv *",
  "touch d*",
];

/**
 * Patterns that are ALWAYS denied.
 */
const DENY_PATTERNS = [
  "sudo *",
  "rm -rf *",
  "wget *",
  "git reset *",
];

/**
 * Patterns that require user confirmation before execution.
 */
const ASK_PATTERNS = [
  "git rebase *",
  "rm *",
];

/**
 * Glob → RegExp converter.
 *
 *   *     → [^/]*   (any chars except /)
 *   **    → .*      (any chars including /)
 *   ?     → [^/]    (single char except /)
 *   other → escaped
 */
function globToRegex(pattern: string): RegExp {
  const escaped = pattern
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*\*/g, "\x00")
    .replace(/\*/g, "[^/]*")
    .replace(/\x00/g, ".*")
    .replace(/\?/g, "[^/]");
  return new RegExp(`^${escaped}$`);
}

// Pre-compile all patterns
const ALLOW_RE = ALLOW_PATTERNS.map(globToRegex);
const DENY_RE = DENY_PATTERNS.map(globToRegex);
const ASK_RE = ASK_PATTERNS.map(globToRegex);

/**
 * Check a command string against a list of compiled regexes.
 */
function matches(cmd: string, patterns: RegExp[]): boolean {
  return patterns.some((re) => re.test(cmd.trim()));
}

/**
 * Determine the permission level for a command.
 * Returns "allow", "deny", or "ask".
 */
function permissionLevel(cmd: string): "allow" | "deny" | "ask" {
  if (matches(cmd, DENY_RE)) return "deny";
  if (matches(cmd, ASK_RE)) return "ask";
  if (matches(cmd, ALLOW_RE)) return "allow";
  // Default: ask for anything not explicitly allowed
  return "ask";
}

/**
 * Build an interactive confirmation bash command.
 * Shows the original command and waits for user input.
 */
function confirmationScript(cmd: string): string {
  const encoded = Buffer.from(cmd).toString("base64");
  return (
    `echo "========================================" && ` +
    `echo "⚠️  PERMISSION CHECK" && ` +
    `echo "Command: $(echo '${encoded}' | base64 -d)" && ` +
    `echo "========================================" && ` +
    `read -p "Allow this command? [y/N]: " _perm_confirm && ` +
    `if [ "$_perm_confirm" = "y" ] || [ "$_perm_confirm" = "Y" ]; then ` +
    `  echo "✅ Approved. Executing..." && ` +
    `  eval "$(echo '${encoded}' | base64 -d)"; ` +
    `else ` +
    `  echo "❌ Denied by user." && ` +
    `  exit 1; ` +
    `fi`
  );
}

// ─── Extension ───────────────────────────────────────────────────────────────

export default function permissionsExtension(pi: ExtensionAPI) {
  const cwd = process.cwd();
  const local = createLocalBashOperations();

  let blockedCount = 0;
  let approvedCount = 0;

  const permissionOps: BashOperations = {
    async exec(command, commandCwd, options) {
      const level = permissionLevel(command);

      if (level === "deny") {
        blockedCount++;
        const msg =
          `🚫 PERMISSION DENIED: "${command}"\n` +
          `This command matches a deny pattern and was blocked.\n` +
          `Blocked commands so far: ${blockedCount}`;
        return { exitCode: 1, stdout: "", stderr: msg };
      }

      if (level === "ask") {
        const confirmCmd = confirmationScript(command);
        const result = await local.exec(confirmCmd, commandCwd, options);

        if (result.exitCode === 0) {
          approvedCount++;
        } else {
          blockedCount++;
        }
        return result;
      }

      // "allow" — execute directly
      approvedCount++;
      return local.exec(command, commandCwd, options);
    },
  };

  const permissionTool = createBashTool(cwd, {
    operations: permissionOps,
  });

  pi.registerTool(permissionTool);

  // Log startup message
  console.log(
    `[permissions] Extension loaded. ` +
    `Allow: ${ALLOW_PATTERNS.length}, ` +
    `Deny: ${DENY_PATTERNS.length}, ` +
    `Ask: ${ASK_PATTERNS.length} patterns.`
  );
}
