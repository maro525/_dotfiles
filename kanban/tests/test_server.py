"""HTTP layer tests against a real server on an ephemeral port."""

from __future__ import annotations

import json
import os
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Iterator
from pathlib import Path

import pytest

from taskboard.scanner import Scanner
from taskboard.server import BoardState, serve

TASK = """\
# Task: ABC-1 — first

## Meta
- linear_id: ABC-1
- tier: S
- status: planning

## Brief
Something real.
"""


@pytest.fixture()
def decisions(tmp_path: Path) -> Path:
    folder = tmp_path / "proj" / ".claude" / "docs" / "decisions"
    folder.mkdir(parents=True)
    (folder / "task-ABC-1-first.md").write_text(TASK, encoding="utf-8")
    return folder


@pytest.fixture()
def server(decisions: Path) -> Iterator[str]:
    srv = serve(roots=(str(decisions),), port=0)
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{srv.server_address[1]}"
    finally:
        srv.shutdown()
        srv.server_close()


def get(url: str, headers: dict[str, str] | None = None):
    request = urllib.request.Request(url, headers=headers or {})
    return urllib.request.urlopen(request, timeout=5)


def test_index_is_served(server: str) -> None:
    response = get(f"{server}/")
    assert response.status == 200
    assert b"Task Board" in response.read()


def test_static_assets_are_served(server: str) -> None:
    assert get(f"{server}/app.js").status == 200
    assert get(f"{server}/style.css").status == 200


def test_board_api_returns_cards(server: str) -> None:
    payload = json.loads(get(f"{server}/api/board").read())
    assert payload["counts"]["planning"] == 1
    assert payload["cards"][0]["id"] == "ABC-1"
    assert "planning" in payload["columns"]


def test_board_api_sets_an_etag(server: str) -> None:
    assert get(f"{server}/api/board").headers["ETag"]


def test_conditional_request_returns_304(server: str) -> None:
    etag = get(f"{server}/api/board").headers["ETag"]
    with pytest.raises(urllib.error.HTTPError) as excinfo:
        get(f"{server}/api/board", {"If-None-Match": etag})
    assert excinfo.value.code == 304
    # A 304 must not carry a body.
    assert excinfo.value.read() == b""


def test_unknown_path_is_404(server: str) -> None:
    with pytest.raises(urllib.error.HTTPError) as excinfo:
        get(f"{server}/../etc/passwd")
    assert excinfo.value.code == 404


def test_healthz(server: str) -> None:
    assert json.loads(get(f"{server}/healthz").read()) == {"ok": True}


def test_state_version_bumps_only_when_content_changes(decisions: Path) -> None:
    state = BoardState(Scanner(roots=(str(decisions),)), poll_seconds=60)
    first = state.version
    assert state.refresh() is False, "no on-disk change means no new version"
    assert state.version == first

    target = decisions / "task-ABC-1-first.md"
    target.write_text(TASK.replace("planning", "done"), encoding="utf-8")
    os.utime(target, (1_800_000_000, 1_800_000_000))
    assert state.refresh() is True
    assert state.version == first + 1


def test_repeated_refresh_without_filesystem_change_never_bumps(decisions: Path) -> None:
    """Rescanning must not churn the ETag just because scan metadata moved."""
    state = BoardState(Scanner(roots=(str(decisions),)), poll_seconds=60)
    first = state.version
    for _ in range(3):
        assert state.refresh() is False
    assert state.version == first


def test_touch_bumps_version_because_it_reorders_the_board(decisions: Path) -> None:
    """Cards sort most-recently-modified first, so an mtime change is real."""
    state = BoardState(Scanner(roots=(str(decisions),)), poll_seconds=60)
    first = state.version
    os.utime(decisions / "task-ABC-1-first.md", (1_900_000_000, 1_900_000_000))
    assert state.refresh() is True
    assert state.version == first + 1


def test_wait_for_change_returns_immediately_when_already_ahead(decisions: Path) -> None:
    state = BoardState(Scanner(roots=(str(decisions),)), poll_seconds=60)
    assert state.wait_for_change(-1, timeout=0.1) == state.version


def read_sse_data_lines(url: str, count: int, timeout: float) -> list[str]:
    """Collect `count` `data:` lines from an SSE stream."""
    lines: list[str] = []
    with urllib.request.urlopen(url, timeout=timeout) as stream:
        for raw in stream:
            text = raw.decode().strip()
            if text.startswith("data:"):
                lines.append(text)
                if len(lines) >= count:
                    return lines
    return lines


def test_sse_advertises_a_retry_interval(server: str) -> None:
    with urllib.request.urlopen(f"{server}/events", timeout=5) as stream:
        assert stream.headers["Content-Type"].startswith("text/event-stream")
        assert stream.readline().decode().startswith("retry:")


def test_sse_replays_current_version_on_connect(server: str) -> None:
    """Guards the race where a change lands between the first fetch and connect."""
    assert read_sse_data_lines(f"{server}/events", 1, timeout=5) == ["data: 0"]


def test_sse_emits_an_event_when_a_file_changes(decisions: Path) -> None:
    srv = serve(roots=(str(decisions),), port=0, poll_seconds=0.2)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"
    received: list[str] = []
    ready = threading.Event()

    def listen() -> None:
        ready.set()
        received.extend(read_sse_data_lines(f"{base}/events", 2, timeout=10))

    listener = threading.Thread(target=listen, daemon=True)
    listener.start()
    ready.wait(timeout=5)
    time.sleep(0.4)

    target = decisions / "task-ABC-1-first.md"
    target.write_text(TASK.replace("planning", "done"), encoding="utf-8")
    listener.join(timeout=10)
    srv.shutdown()
    srv.server_close()

    # First line is the on-connect replay; the second is the real change.
    assert len(received) == 2, received
    assert received[1] == "data: 1"
