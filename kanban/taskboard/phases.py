"""Phase derivation.

The `status:` field alone cannot drive this board. In a survey of 1,449 real
TASK_FILEs, 338 (23%) declared a phase behind what the file actually contained
-- e.g. `status: planning` on a file whose `## Deploy` section already holds a
merged PR URL. That is expected rather than exceptional: when `/startproject`
runs in one agent and `/team-implement` in another, nobody owns the `status:`
line, because only `/orchestrate` ever wrote it.

So a card's column is the furthest-along of two independent signals:

  declared  -- the normalized `status:` field
  evidence  -- which sections hold real content, plus which Decision Log
               entry prefixes are present

with one asymmetry: `done` is a claim about intent that no amount of file
content can prove, so only `declared` may assert it.
"""

from __future__ import annotations

import re

from .model import PHASE_RANK, Card, ParsedTask, Phase

#: Ordered longest-match-first. The first pattern that matches wins, so more
#: specific states must precede the generic ones they contain.
_STATUS_RULES: tuple[tuple[re.Pattern[str], Phase], ...] = (
    (re.compile(r"\b(?:done|complete|completed|closed|shipped|finished)\b"), "done"),
    (re.compile(r"\b(?:deploy|deployed|deploying|merged|merging|released)\b"), "deploy"),
    (
        re.compile(
            r"\b(?:in[-_ ]?review|reviewing|reviewed|review|pr[-_ ]?open|"
            r"awaiting[-_ ]?review|ready[-_ ]?for[-_ ]?review)\b"
        ),
        "review",
    ),
    # `implemented` means the implementation is finished, so the task now sits
    # in review -- not in `implementing`.
    (re.compile(r"\b(?:implemented|ready[-_ ]?for[-_ ]?commit|committed)\b"), "review"),
    (
        re.compile(
            r"\b(?:implementing|in[-_ ]?progress|in[-_ ]?flight|wip|"
            r"active|coding|building)\b"
        ),
        "implementing",
    ),
    (re.compile(r"\b(?:planning|planned|plan|proposal|draft|todo|backlog|new)\b"), "planning"),
)

#: Evidence rules, checked from the furthest-along phase backwards. A phase is
#: reached when its section holds real content or its skill logged a decision.
_EVIDENCE_RULES: tuple[tuple[Phase, str, str], ...] = (
    ("deploy", "deploy", "deploy"),
    ("review", "review", "team-review"),
    ("implementing", "implementation notes", "team-implement"),
    ("planning", "brief", "startproject"),
)

#: Markdown emphasis to drop before matching. Underscore is deliberately *not*
#: here: deleting it would weld `in_review` into `inreview` and destroy the very
#: word boundaries the rules rely on. Separators are turned into spaces instead.
_NOISE = str.maketrans("", "", "*`")


def normalize_status(status_raw: str | None) -> Phase | None:
    """Map a freeform `status:` value onto a phase, or None if unrecognized.

    Handles the real-world spread: `done`, `completed`, `in-review`,
    `in_review`, `in review`, `implemented`, `pr-open`, plus markdown emphasis
    and trailing commentary such as `done (PR #24 In Review)`.

    Trailing commentary is a hazard: `done (PR #24 In Review)` must classify as
    `done`, not `review`. Rule order handles that, since `done` is checked
    first.
    """
    if not status_raw:
        return None
    text = status_raw.translate(_NOISE).strip().lower()
    if not text:
        return None
    # Underscores are word characters, so `implemented_pending_device_review`
    # would not match `\breview\b`. Normalize separators to spaces first.
    text = re.sub(r"[_/]+", " ", text)
    for pattern, phase in _STATUS_RULES:
        if pattern.search(text):
            return phase
    return None


def evidence_phase(task: ParsedTask) -> Phase | None:
    """Derive the furthest phase the file shows actual evidence of reaching.

    Never returns `done`: completion is a declaration, not something the
    presence of content can demonstrate.
    """
    for phase, section, tag in _EVIDENCE_RULES:
        if section in task.filled_sections or tag in task.decision_tags:
            return phase
    # A Design section alone still means planning happened.
    if "design" in task.filled_sections or "orchestrate" in task.decision_tags:
        return "planning"
    return None


def classify(task: ParsedTask) -> Card:
    """Place a parsed task into a column and flag a stale `status:` field."""
    declared = normalize_status(task.status_raw)
    evidence = evidence_phase(task)

    if declared is None and evidence is None:
        return Card(task, "unknown", None, None, stale_status=False)

    if declared == "done":
        # Terminal. Evidence can never override a completion claim.
        return Card(task, "done", declared, evidence, stale_status=False)

    if declared is None:
        assert evidence is not None
        return Card(task, evidence, None, evidence, stale_status=False)

    if evidence is None:
        return Card(task, declared, declared, None, stale_status=False)

    declared_rank = PHASE_RANK[declared]
    evidence_rank = PHASE_RANK[evidence]
    if evidence_rank > declared_rank:
        # The file has moved on but nobody updated `status:` -- surface it.
        return Card(task, evidence, declared, evidence, stale_status=True)
    return Card(task, declared, declared, evidence, stale_status=False)
