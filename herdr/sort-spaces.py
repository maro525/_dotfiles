#!/usr/bin/env python3
"""Sort herdr workspaces (spaces) by label.

herdr has no `spaces_sort` setting: the sidebar order is manual (drag) order,
exposed only through the socket API (`workspace.list` / `workspace.move_block`).
This script reorders every workspace lexicographically by label, the same way
the dorzey/herdr-sort-spaces-plugin does, without needing the plugin installed.

Usage:
    python3 sort-spaces.py          # A-Z
    python3 sort-spaces.py desc     # Z-A

Bind it from ~/.config/herdr/config.toml:

    [[keys.command]]
    key = "prefix+shift+s"
    type = "shell"
    command = "python3 \"$HOME/.config/herdr/sort-spaces.py\""
    description = "sort spaces A-Z"

herdr runs custom commands with HERDR_SOCKET_PATH set, which this script
honors; outside herdr it falls back to the default (or HERDR_SESSION) socket.
"""

from __future__ import annotations

import json
import os
import socket
import sys
from pathlib import Path

TIMEOUT_SECONDS = 5.0


def socket_path() -> Path:
    """Same resolution order as the herdr CLI."""
    if override := os.environ.get("HERDR_SOCKET_PATH"):
        return Path(override)
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    base = config_home / "herdr"
    if session := os.environ.get("HERDR_SESSION"):
        return base / "sessions" / session / "herdr.sock"
    return base / "herdr.sock"


def call(path: Path, method: str, params: dict) -> dict:
    """One request per connection: the server closes after the response."""
    payload = json.dumps({"id": "1", "method": method, "params": params}) + "\n"
    try:
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    except AttributeError:  # Windows named pipes are not supported.
        raise SystemExit("sort-spaces: Unix domain sockets only")
    try:
        conn.settimeout(TIMEOUT_SECONDS)
        conn.connect(str(path))
        conn.sendall(payload.encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk
    except OSError as exc:
        raise SystemExit(f"sort-spaces: cannot reach herdr at {path}: {exc}")
    finally:
        conn.close()

    if not buf.strip():
        raise SystemExit(f"sort-spaces: empty response from herdr {method}")
    response = json.loads(buf.decode().splitlines()[0])
    if "result" not in response:
        raise SystemExit(f"sort-spaces: herdr {method} failed: {response}")
    return response["result"]


def main(argv: list[str]) -> int:
    reverse = any(arg in {"desc", "-r", "--desc", "--reverse"} for arg in argv[1:])
    path = socket_path()

    workspaces = call(path, "workspace.list", {}).get("workspaces") or []
    if len(workspaces) < 2:
        print("nothing to sort")
        return 0

    current = [w["workspace_id"] for w in workspaces]
    # Case-insensitive, stable: ties keep their existing relative order.
    ordered = sorted(workspaces, key=lambda w: (w.get("label") or "").casefold())
    if reverse:
        ordered.reverse()
    wanted = [w["workspace_id"] for w in ordered]

    if wanted == current:
        print("already sorted")
        return 0

    # No anchor: move the whole block to the end of the list, in this order.
    call(path, "workspace.move_block", {"workspace_ids": wanted})
    print("sorted: " + ", ".join(w.get("label") or w["workspace_id"] for w in ordered))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
