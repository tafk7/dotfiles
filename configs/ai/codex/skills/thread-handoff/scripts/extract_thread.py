#!/usr/bin/env python3
"""Extract a compact visible transcript from a saved Codex thread."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract visible messages and settings from a saved Codex thread."
    )
    parser.add_argument("thread_id", help="Codex thread/session UUID")
    parser.add_argument(
        "--codex-home",
        type=Path,
        default=Path.home() / ".codex",
        help="Codex home directory (default: ~/.codex)",
    )
    parser.add_argument(
        "--last-messages",
        type=int,
        default=24,
        help="Maximum visible messages to print (default: 24; 0 means all)",
    )
    return parser.parse_args()


def find_rollout(codex_home: Path, thread_id: str) -> Path:
    matches = sorted((codex_home / "sessions").glob(f"**/*{thread_id}.jsonl"))
    if not matches:
        raise FileNotFoundError(f"no rollout found for thread {thread_id}")
    if len(matches) > 1:
        exact = [path for path in matches if path.stem.endswith(thread_id)]
        if len(exact) == 1:
            return exact[0]
        raise RuntimeError(
            f"multiple rollouts found for {thread_id}: "
            + ", ".join(str(path) for path in matches)
        )
    return matches[0]


def read_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"invalid JSON in {path}:{line_number}: {exc}") from exc
            records.append(record)
    return records


def inherited_records(
    codex_home: Path,
    thread_id: str,
    cutoff: int | None = None,
    seen: set[str] | None = None,
) -> list[dict[str, Any]]:
    seen = seen or set()
    if thread_id in seen:
        raise RuntimeError(f"cycle in thread ancestry at {thread_id}")
    seen.add(thread_id)

    path = find_rollout(codex_home, thread_id)
    records = read_records(path)
    if not records or records[0].get("type") != "session_meta":
        raise RuntimeError(f"missing session metadata in {path}")

    meta = records[0].get("payload", {})
    history_base = meta.get("history_base") or {}
    parent_id = history_base.get("thread_id") or meta.get("forked_from_id")
    parent_cutoff = history_base.get("end_ordinal_exclusive")
    if parent_cutoff is None:
        parent_cutoff = meta.get("forked_from_ordinal_exclusive")

    result: list[dict[str, Any]] = []
    if parent_id:
        result.extend(
            inherited_records(codex_home, parent_id, parent_cutoff, seen.copy())
        )

    for record in records:
        ordinal = record.get("ordinal")
        if cutoff is None or ordinal is None or ordinal < cutoff:
            result.append(record)
    return result


def content_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for item in content:
        if not isinstance(item, dict):
            continue
        text = item.get("text")
        if isinstance(text, str):
            parts.append(text)
    return "\n".join(parts).strip()


def visible_messages(records: list[dict[str, Any]]) -> list[dict[str, str]]:
    messages: list[dict[str, str]] = []
    for record in records:
        if record.get("type") != "response_item":
            continue
        payload = record.get("payload", {})
        item_type = payload.get("type")
        role = payload.get("role")
        if item_type == "message" and role in {"user", "assistant"}:
            text = content_text(payload.get("content"))
        elif item_type == "agent_message":
            role = "assistant"
            text = content_text(payload.get("content"))
        else:
            continue
        if text.startswith("<environment_context>") or text.startswith(
            "<permissions instructions>"
        ):
            continue
        if text:
            messages.append(
                {
                    "role": str(role),
                    "text": text,
                    "timestamp": str(record.get("timestamp", "")),
                    "ordinal": str(record.get("ordinal", "")),
                }
            )
    return messages


def last_settings(records: list[dict[str, Any]]) -> dict[str, Any]:
    settings: dict[str, Any] = {}
    for record in records:
        payload = record.get("payload", {})
        if record.get("type") == "turn_context":
            settings.update(
                model=payload.get("model"),
                reasoning_effort=payload.get("effort"),
            )
        elif record.get("type") == "event_msg" and payload.get("type") == "thread_settings_applied":
            applied = payload.get("thread_settings", {})
            settings.update(
                model=applied.get("model"),
                reasoning_effort=applied.get("reasoning_effort"),
                model_provider=applied.get("model_provider_id"),
                cwd=applied.get("cwd"),
            )
    return {key: value for key, value in settings.items() if value is not None}


def main() -> int:
    args = parse_args()
    if args.last_messages < 0:
        raise SystemExit("--last-messages must be zero or greater")

    try:
        records = inherited_records(args.codex_home, args.thread_id)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    messages = visible_messages(records)
    if args.last_messages:
        messages = messages[-args.last_messages :]

    print(f"# Extracted Codex thread: {args.thread_id}")
    settings = last_settings(records)
    if settings:
        print("\n## Last recorded settings")
        for key, value in settings.items():
            print(f"- {key}: `{value}`")

    print("\n## Visible transcript")
    if not messages:
        print("\n_No visible user or assistant messages found._")
        return 0

    for message in messages:
        label = message["role"].capitalize()
        location = f'{message["timestamp"]} / ordinal {message["ordinal"]}'
        print(f"\n### {label} ({location})\n")
        print(message["text"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
