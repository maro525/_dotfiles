"""Phase derivation tests.

The cases here are drawn from a survey of 1,449 real TASK_FILEs, so the odd
looking status strings are all values that actually occur.
"""

from __future__ import annotations

import pytest

from taskboard.model import ParsedTask
from taskboard.phases import classify, evidence_phase, normalize_status


def make_task(
    *,
    status: str | None = None,
    sections: frozenset[str] = frozenset(),
    tags: frozenset[str] = frozenset(),
) -> ParsedTask:
    return ParsedTask(
        path="/tmp/task-ABC-1-x.md",
        project="p",
        task_id="ABC-1",
        title="t",
        tier="M",
        tier_raw="M",
        status_raw=status,
        created=None,
        branch=None,
        pr_url=None,
        filled_sections=sections,
        decision_tags=tags,
        mtime=0.0,
        size=0,
    )


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("done", "done"),
        ("completed", "done"),
        ("planning", "planning"),
        ("in-progress", "implementing"),
        ("in_progress", "implementing"),
        ("implementing", "implementing"),
        ("in-review", "review"),
        ("in_review", "review"),
        ("in review", "review"),
        ("review", "review"),
        ("implemented", "review"),
        ("pr-open", "review"),
        ("deployed", "deploy"),
        ("merging_and_deploying", "deploy"),
        ("**done**", "done"),
        ("`done`", "done"),
        ("done (PR open)", "done"),
        ("in-review (PR #87)", "review"),
        ("completed (deployed 2026-07-23)", "done"),
        ("active", "implementing"),
        ("reviewed", "review"),
        ("ready-for-commit", "review"),
    ],
)
def test_normalize_status_maps_real_world_values(raw: str, expected: str) -> None:
    assert normalize_status(raw) == expected


def test_normalize_status_prefers_done_over_trailing_commentary() -> None:
    # `done (PR #24 In Review)` is done -- the trailing text must not win.
    assert normalize_status("done (PR #24 In Review)") == "done"


def test_normalize_status_handles_underscore_word_boundaries() -> None:
    # Underscores are word characters, so a naive \breview\b would miss this.
    assert normalize_status("implemented_pending_device_review") == "review"


@pytest.mark.parametrize("raw", [None, "", "   ", "???", "🙂"])
def test_normalize_status_returns_none_when_unrecognized(raw: str | None) -> None:
    assert normalize_status(raw) is None


def test_evidence_never_claims_done() -> None:
    task = make_task(
        sections=frozenset({"brief", "design", "implementation notes", "review", "deploy"})
    )
    assert evidence_phase(task) == "deploy"


def test_evidence_uses_decision_log_tags() -> None:
    task = make_task(tags=frozenset({"startproject", "team-implement"}))
    assert evidence_phase(task) == "implementing"


def test_evidence_none_when_no_signal() -> None:
    assert evidence_phase(make_task()) is None


def test_stale_status_detected_when_evidence_is_ahead() -> None:
    """The headline case: 23% of real files look like this."""
    card = classify(make_task(status="planning", sections=frozenset({"brief", "review", "deploy"})))
    assert card.phase == "deploy"
    assert card.declared_phase == "planning"
    assert card.evidence_phase == "deploy"
    assert card.stale_status is True


def test_declared_wins_when_ahead_of_evidence() -> None:
    card = classify(make_task(status="in-review", sections=frozenset({"brief"})))
    assert card.phase == "review"
    assert card.stale_status is False


def test_done_is_terminal_and_never_marked_stale() -> None:
    card = classify(make_task(status="done", sections=frozenset({"brief", "implementation notes"})))
    assert card.phase == "done"
    assert card.stale_status is False


def test_evidence_only_when_status_missing() -> None:
    card = classify(make_task(status=None, sections=frozenset({"brief", "implementation notes"})))
    assert card.phase == "implementing"
    assert card.declared_phase is None
    assert card.stale_status is False


def test_declared_only_when_no_evidence() -> None:
    card = classify(make_task(status="planning"))
    assert card.phase == "planning"
    assert card.evidence_phase is None


def test_unknown_when_no_signal_at_all() -> None:
    card = classify(make_task())
    assert card.phase == "unknown"
    assert card.stale_status is False
