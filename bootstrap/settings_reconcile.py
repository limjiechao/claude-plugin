#!/usr/bin/env python3
import json
import os
from pathlib import Path
from typing import Any


def _replace_tokens(value: Any, *, claude_dir: str, hooks_dir: str) -> Any:
    if isinstance(value, str):
        return value.replace("@@HOOKS_DIR@@", hooks_dir).replace("@@CLAUDE_DIR@@", claude_dir)
    if isinstance(value, list):
        return [_replace_tokens(item, claude_dir=claude_dir, hooks_dir=hooks_dir) for item in value]
    if isinstance(value, dict):
        return {
            key: _replace_tokens(item, claude_dir=claude_dir, hooks_dir=hooks_dir)
            for key, item in value.items()
        }
    return value


def _key(item: Any) -> str:
    return json.dumps(item, sort_keys=True)


def _reconcile_list(existing: list[Any], old_entries: list[Any], new_entries: list[Any]) -> list[Any]:
    stale = {_key(item) for item in old_entries} - {_key(item) for item in new_entries}
    kept = [item for item in existing if _key(item) not in stale]
    seen: set[str] = set()
    out: list[Any] = []
    for item in kept + new_entries:
        item_key = _key(item)
        if item_key not in seen:
            seen.add(item_key)
            out.append(item)
    return out


def _reconcile(base_node: dict[str, Any], old_node: dict[str, Any], new_node: dict[str, Any]) -> dict[str, Any]:
    for key, old_value in list(old_node.items()):
        if key not in new_node and key in base_node and base_node[key] == old_value:
            del base_node[key]

    for key, new_value in new_node.items():
        old_value = old_node.get(key) if isinstance(old_node, dict) else None
        if isinstance(new_value, dict) and isinstance(base_node.get(key), dict):
            _reconcile(
                base_node[key],
                old_value if isinstance(old_value, dict) else {},
                new_value,
            )
        elif isinstance(new_value, list) and isinstance(base_node.get(key), list):
            base_node[key] = _reconcile_list(
                base_node[key],
                old_value if isinstance(old_value, list) else [],
                new_value,
            )
        else:
            base_node[key] = new_value
    return base_node


def _load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with path.open() as file:
        return json.load(file)


def _write_json(path: Path, value: Any) -> None:
    with path.open("w") as file:
        json.dump(value, file, indent=2)


def reconcile_settings_file(
    *,
    settings_path: Path,
    snippet_path: Path,
    last_snippet_path: Path,
    claude_dir: str,
    hooks_dir: str,
) -> None:
    base = _load_json(settings_path, {})
    new_snippet_raw = _load_json(snippet_path, {})
    old_snippet_raw = _load_json(last_snippet_path, {})

    new_snippet = _replace_tokens(new_snippet_raw, claude_dir=claude_dir, hooks_dir=hooks_dir)
    old_snippet = _replace_tokens(old_snippet_raw, claude_dir=claude_dir, hooks_dir=hooks_dir)

    merged = _reconcile(base, old_snippet, new_snippet)
    merged["statusLine"] = {"type": "command", "command": f"bash {claude_dir}/statusline.sh"}

    _write_json(settings_path, merged)
    _write_json(last_snippet_path, new_snippet_raw)


def main() -> None:
    reconcile_settings_file(
        settings_path=Path(os.environ["SETTINGS_PATH"]),
        snippet_path=Path(os.environ["SNIPPET"]),
        last_snippet_path=Path(os.environ["LASTSNIP"]),
        claude_dir=os.environ["CLAUDE_DIR"],
        hooks_dir=os.environ["HOOKS_DIR"],
    )
    print("settings reconciled ->", os.environ["SETTINGS_PATH"])


if __name__ == "__main__":
    main()
