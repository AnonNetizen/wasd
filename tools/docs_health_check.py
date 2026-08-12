#!/usr/bin/env python3
"""Validate the live documentation graph without a generated knowledge index."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Protocol, runtime_checkable
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
COMMON_RULE = Path("docs/AI协作/项目规则.md")
CURRENT_STATE = Path("docs/AI记忆/current_state.json")
ADR_DOC = Path("docs/决策记录.md")
CODE_DOCS_INDEX = Path("docs/代码/README.md")
STATE_LIMIT_BYTES = 8 * 1024

ADAPTERS = (
    Path(".codebuddy/rules/game-coding-rules.md"),
    Path(".codex/rules/game-coding-rules.md"),
    Path(".opencode/rules/game-coding-rules.md"),
    Path(".claude/rules/game-coding-rules.md"),
)
STATE_KEYS = {
    "schema_version",
    "updated_at",
    "phase",
    "summary",
    "active_plan",
    "protocols",
    "blockers",
}
PROTOCOL_KEYS = {"meta", "run", "replay", "game"}
FORBIDDEN_REFERENCES = (
    "docs/AI知识库索引.md",
    "docs/_kb_index.json",
    "docs/AI记忆/项目记忆.md",
    "docs/AI记忆/会话日志/",
    "docs/reports/",
    "docs/AI协作/工作包/",
    "docs/修改建议.md",
    "docs/正式项目工作规划.md",
    "docs/AI辅助开发机会清单.md",
    "docs/局内刷取参考研究.md",
    "docs/小服务器玩法备忘.md",
    "docs/简单设计思路.md",
)
TEXT_SUFFIXES = {
    ".md",
    ".json",
    ".yaml",
    ".yml",
    ".py",
    ".gd",
    ".toml",
    ".tscn",
    ".tres",
    ".cfg",
    ".ini",
    ".txt",
}
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")
DOC_REFERENCE_RE = re.compile(r"^\s*#\s*Doc:\s*([^\s#]+)", re.MULTILINE)
ADR_ROW_RE = re.compile(r"^\|\s*(\d+)\s*\|", re.MULTILINE)
IGNORED_PARTS = {
    ".git",
    ".godot",
    ".vscodecounter",
    ".pytest_cache",
    ".tmp",
    ".venv",
    "node_modules",
    "__pycache__",
}


@runtime_checkable
class _ReconfigurableTextStream(Protocol):
    def reconfigure(self, *, encoding: str) -> None:
        pass


def main() -> int:
    _configure_utf8_output()
    errors = check_repository(ROOT)
    if errors:
        for error in errors:
            print(f"[docs-health] {error}")
        return 1
    print("docs health check passed")
    return 0


def check_repository(root: Path) -> list[str]:
    """Return all documentation health errors for *root*."""
    root = root.resolve()
    errors: list[str] = []
    markdown = _collect_files(root, {".md"})
    _check_markdown_links(root, markdown, errors)
    _check_code_docs_index(root, errors)
    _check_doc_references(root, errors)
    _check_adr_numbers(root, errors)
    _check_current_state(root, errors)
    _check_adapters(root, errors)
    _check_forbidden_references(root, errors)
    return errors


def _configure_utf8_output() -> None:
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, _ReconfigurableTextStream):
            stream.reconfigure(encoding="utf-8")


def _collect_files(root: Path, suffixes: set[str]) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in suffixes:
            continue
        if _is_ignored(root, path):
            continue
        files.append(path)
    return sorted(files, key=lambda item: _rel(root, item))


def _is_ignored(root: Path, path: Path) -> bool:
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        return True
    lowered = tuple(part.lower() for part in parts)
    if any(part in IGNORED_PARTS or part == "draft" for part in lowered):
        return True
    return "addons" in lowered


def _check_markdown_links(root: Path, paths: list[Path], errors: list[str]) -> None:
    for source in paths:
        in_fence = False
        for line_number, line in enumerate(_read_text(source).splitlines(), start=1):
            if line.lstrip().startswith(("```", "~~~")):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for match in MARKDOWN_LINK_RE.finditer(line):
                raw_target = _clean_link_target(match.group(1))
                if not raw_target or _is_external_link(raw_target):
                    continue
                target, anchor = _resolve_link(source, raw_target)
                if not target.exists():
                    errors.append(
                        f"missing Markdown link target in {_rel(root, source)}:{line_number}: {raw_target}"
                    )
                    continue
                if anchor and target.is_file() and target.suffix.lower() == ".md":
                    if _normalize_anchor(anchor) not in _markdown_anchors(_read_text(target)):
                        errors.append(
                            f"missing Markdown anchor in {_rel(root, source)}:{line_number}: {raw_target}"
                        )


def _clean_link_target(value: str) -> str:
    value = value.strip()
    if value.startswith("<") and ">" in value:
        return value[1 : value.index(">")].strip()
    title_match = re.match(r"^(\S+?)(?:\s+[\"'].*[\"'])?$", value)
    return title_match.group(1) if title_match else value


def _is_external_link(target: str) -> bool:
    if target.startswith("#"):
        return False
    parsed = urlparse(target)
    return bool(parsed.scheme) and parsed.scheme.lower() != "file"


def _resolve_link(source: Path, raw_target: str) -> tuple[Path, str]:
    decoded = unquote(raw_target).replace("\\", "/")
    path_part, _, anchor = decoded.partition("#")
    path_part = path_part.split("?", 1)[0]
    if not path_part:
        return source.resolve(), anchor
    candidate = Path(path_part)
    if candidate.is_absolute():
        return candidate.resolve(), anchor
    return (source.parent / candidate).resolve(), anchor


def _markdown_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith(("```", "~~~")):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not match:
            continue
        base = _normalize_anchor(match.group(1))
        if not base:
            continue
        index = counts.get(base, 0)
        counts[base] = index + 1
        anchors.add(base if index == 0 else f"{base}-{index}")
    return anchors


def _normalize_anchor(value: str) -> str:
    value = unquote(value).strip().lower()
    value = re.sub(r"<[^>]+>", "", value)
    value = re.sub(r"[`*_~]", "", value)
    value = re.sub(r"[^\w\-\u4e00-\u9fff ]", "", value, flags=re.UNICODE)
    return re.sub(r"[\s-]+", "-", value).strip("-")


def _check_code_docs_index(root: Path, errors: list[str]) -> None:
    index = root / CODE_DOCS_INDEX
    if not index.exists():
        return
    for reference in sorted(set(re.findall(r"docs/代码/[^`\s)]+\.md", _read_text(index)))):
        if not (root / reference).exists():
            errors.append(f"docs/代码/README.md references missing module doc: {reference}")


def _check_doc_references(root: Path, errors: list[str]) -> None:
    client = root / "client"
    if not client.exists():
        return
    for source in sorted(client.rglob("*.gd")):
        if _is_ignored(root, source):
            continue
        for reference in DOC_REFERENCE_RE.findall(_read_text(source)):
            normalized = reference.replace("\\", "/")
            if not (root / normalized).exists():
                errors.append(f"invalid # Doc: path in {_rel(root, source)}: {reference}")


def _check_adr_numbers(root: Path, errors: list[str]) -> None:
    path = root / ADR_DOC
    if not path.exists():
        errors.append(f"missing {ADR_DOC.as_posix()}")
        return
    numbers = [int(value) for value in ADR_ROW_RE.findall(_read_text(path))]
    if not numbers:
        errors.append(f"no ADR rows found in {ADR_DOC.as_posix()}")
        return
    seen: set[int] = set()
    for number in numbers:
        if number in seen:
            errors.append(f"duplicate ADR number in {ADR_DOC.as_posix()}: {number}")
        seen.add(number)
    for previous, current in zip(numbers, numbers[1:]):
        if current != previous + 1:
            errors.append(
                f"ADR sequence is not contiguous in {ADR_DOC.as_posix()}: {previous} -> {current}"
            )


def _check_current_state(root: Path, errors: list[str]) -> None:
    path = root / CURRENT_STATE
    if not path.exists():
        errors.append(f"missing {CURRENT_STATE.as_posix()}")
        return
    size = path.stat().st_size
    if size > STATE_LIMIT_BYTES:
        errors.append(
            f"{CURRENT_STATE.as_posix()} exceeds 8 KiB: {size} bytes"
        )
    try:
        data = json.loads(_read_text(path))
    except json.JSONDecodeError as exc:
        errors.append(f"invalid JSON in {CURRENT_STATE.as_posix()}: {exc}")
        return
    if not isinstance(data, dict):
        errors.append(f"{CURRENT_STATE.as_posix()} must contain a JSON object")
        return
    actual_keys = set(data)
    if actual_keys != STATE_KEYS:
        errors.append(
            f"{CURRENT_STATE.as_posix()} keys must be exactly {sorted(STATE_KEYS)}; "
            f"missing={sorted(STATE_KEYS - actual_keys)}, extra={sorted(actual_keys - STATE_KEYS)}"
        )
    if data.get("schema_version") != 2:
        errors.append(f"{CURRENT_STATE.as_posix()} schema_version must be 2")
    for key in ("updated_at", "phase", "summary", "active_plan"):
        if not isinstance(data.get(key), str) or not data.get(key, "").strip():
            errors.append(f"{CURRENT_STATE.as_posix()} {key} must be a non-empty string")
    updated_at = data.get("updated_at")
    if isinstance(updated_at, str) and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", updated_at):
        errors.append(f"{CURRENT_STATE.as_posix()} updated_at must use YYYY-MM-DD")
    active_plan = data.get("active_plan")
    if isinstance(active_plan, str) and active_plan and not (root / active_plan).exists():
        errors.append(f"{CURRENT_STATE.as_posix()} active_plan does not exist: {active_plan}")
    protocols = data.get("protocols")
    if not isinstance(protocols, dict) or set(protocols) != PROTOCOL_KEYS:
        errors.append(
            f"{CURRENT_STATE.as_posix()} protocols keys must be exactly {sorted(PROTOCOL_KEYS)}"
        )
    elif (
        not all(isinstance(protocols.get(key), int) and protocols[key] > 0 for key in ("meta", "run", "replay"))
        or not isinstance(protocols.get("game"), str)
        or not protocols["game"].strip()
    ):
        errors.append(
            f"{CURRENT_STATE.as_posix()} protocols meta/run/replay must be positive integers and game a string"
        )
    blockers = data.get("blockers")
    if not isinstance(blockers, list) or not all(isinstance(item, str) for item in blockers):
        errors.append(f"{CURRENT_STATE.as_posix()} blockers must be a list of strings")


def _check_adapters(root: Path, errors: list[str]) -> None:
    common = root / COMMON_RULE
    if not common.exists():
        errors.append(f"missing shared rule body: {COMMON_RULE.as_posix()}")
    common_reference = COMMON_RULE.as_posix()
    for relative in ADAPTERS:
        path = root / relative
        if not path.exists():
            errors.append(f"missing platform rule adapter: {relative.as_posix()}")
            continue
        text = _read_text(path)
        line_count = len(text.splitlines())
        if line_count > 50:
            errors.append(f"platform rule adapter exceeds 50 lines: {relative.as_posix()} ({line_count})")
        if common_reference not in text:
            errors.append(
                f"platform rule adapter does not reference {common_reference}: {relative.as_posix()}"
            )


def _check_forbidden_references(root: Path, errors: list[str]) -> None:
    for path in _collect_files(root, TEXT_SUFFIXES):
        relative = _rel(root, path)
        if relative in {"tools/docs_health_check.py", "tools/test_docs_health_check.py"}:
            continue
        text = _read_text(path).replace("\\", "/").lower()
        for forbidden in FORBIDDEN_REFERENCES:
            if forbidden.lower() in text:
                errors.append(f"retired documentation path referenced by {relative}: {forbidden}")


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _rel(root: Path, path: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


if __name__ == "__main__":
    raise SystemExit(main())
