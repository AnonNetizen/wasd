#!/usr/bin/env python3
"""Docs health check for the wasd knowledge base."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Protocol, runtime_checkable
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]
KB_INDEX = ROOT / "docs" / "_kb_index.json"
CURRENT_STATE = ROOT / "docs" / "AI记忆" / "current_state.json"
DOCS_DIR = ROOT / "docs"
CODE_DOCS_INDEX = ROOT / "docs" / "代码" / "README.md"
KB_HUMAN_INDEX = ROOT / "docs" / "AI知识库索引.md"

IGNORE_PARTS = {"draft", "DRAFT", ".git"}
EXCLUDED_LONG_LIVED_DIRS = {
    "docs/AI记忆/会话日志",
}
ROOT_MARKDOWN_FILES = [
    "AGENTS.md",
    "CLAUDE.md",
    "CODEX.md",
    "OPENCODE.md",
    "README.md",
    "CONTRIBUTING.md",
]
REQUIRED_DOC_FIELDS = {
    "path",
    "type",
    "authority",
    "status",
    "owner_scope",
    "last_reviewed",
    "canonical_for",
    "must_read_for",
    "related_docs",
    "related_code",
    "update_triggers",
    "keywords",
}
LIST_FIELDS = {
    "canonical_for",
    "must_read_for",
    "related_docs",
    "related_code",
    "update_triggers",
    "keywords",
}
STRING_FIELDS = {
    "path",
    "type",
    "authority",
    "status",
    "owner_scope",
    "last_reviewed",
}
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")


@runtime_checkable
class _ReconfigurableTextStream(Protocol):
    def reconfigure(self, *, encoding: str) -> None:
        pass


def main() -> int:
    _configure_utf8_output()

    errors: list[str] = []
    reports: list[str] = []

    long_lived_docs = _collect_long_lived_markdown()
    data = _load_kb_index(errors)
    documents: list[dict[str, Any]] = []
    indexed_paths: list[Path] = []

    if data is not None:
        documents = _check_kb_index(data, errors)
        indexed_paths = [ROOT / document["path"] for document in documents if isinstance(document.get("path"), str)]

    _check_long_lived_coverage(long_lived_docs, indexed_paths, errors)
    _check_ai_modify_notes(long_lived_docs, errors)
    inbound_links = _check_markdown_links(long_lived_docs, errors)
    _check_code_docs_index(errors)
    _check_doc_references(errors)
    _check_adr_numbers(errors)
    _check_adr_matrix_sync(errors)
    _check_current_state(errors)
    _report_orphan_documents(long_lived_docs, documents, inbound_links, reports)
    _report_authority_sync_risks(documents, reports)

    for report in reports:
        print(f"[docs-health] report: {report}")

    if errors:
        for error in errors:
            print(f"[docs-health] {error}")
        return 1

    print("docs health check passed")
    return 0


def _configure_utf8_output() -> None:
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, _ReconfigurableTextStream):
            stream.reconfigure(encoding="utf-8")


def _load_kb_index(errors: list[str]) -> dict[str, Any] | None:
    if not KB_INDEX.exists():
        errors.append("missing docs/_kb_index.json")
        return None

    try:
        return json.loads(KB_INDEX.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"invalid JSON in docs/_kb_index.json: {exc}")
        return None


def _check_kb_index(data: dict[str, Any], errors: list[str]) -> list[dict[str, Any]]:
    if data.get("schema_version") != 2:
        errors.append("docs/_kb_index.json schema_version must be 2")

    documents = data.get("documents")
    if not isinstance(documents, list):
        errors.append("docs/_kb_index.json documents must be a list")
        return []

    valid_documents: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    for index, document in enumerate(documents):
        if not isinstance(document, dict):
            errors.append(f"docs/_kb_index.json documents[{index}] must be an object")
            continue

        missing = REQUIRED_DOC_FIELDS.difference(document.keys())
        if missing:
            errors.append(f"{document.get('path', f'documents[{index}')} missing fields: {sorted(missing)}")

        for field in STRING_FIELDS.intersection(document.keys()):
            if not isinstance(document.get(field), str) or not document.get(field):
                errors.append(f"{document.get('path', f'documents[{index}')} field {field} must be a non-empty string")

        for field in LIST_FIELDS.intersection(document.keys()):
            if not isinstance(document.get(field), list):
                errors.append(f"{document.get('path', f'documents[{index}')} field {field} must be a list")

        path_value = document.get("path")
        if not isinstance(path_value, str) or not path_value:
            errors.append(f"documents[{index}] has invalid path")
            continue
        if path_value in seen_paths:
            errors.append(f"duplicate path in docs/_kb_index.json: {path_value}")
        seen_paths.add(path_value)

        _check_path_exists(path_value, f"indexed path {path_value}", errors)

        for related in document.get("related_docs", []):
            if isinstance(related, str):
                _check_path_exists(related, f"related doc {related} referenced by {path_value}", errors)

        for related in document.get("related_code", []):
            if isinstance(related, str):
                _check_path_exists(related, f"related code {related} referenced by {path_value}", errors)

        valid_documents.append(document)

    return valid_documents


def _collect_long_lived_markdown() -> list[Path]:
    candidates: list[Path] = []
    for filename in ROOT_MARKDOWN_FILES:
        path = ROOT / filename
        if path.exists():
            candidates.append(path)

    if DOCS_DIR.exists():
        candidates.extend(DOCS_DIR.rglob("*.md"))
    unique: dict[str, Path] = {}
    for path in candidates:
        if _is_ignored(path) or _is_excluded_long_lived_doc(path):
            continue
        unique[_rel(path)] = path
    return [unique[key] for key in sorted(unique)]


def _check_long_lived_coverage(long_lived_docs: list[Path], indexed_paths: list[Path], errors: list[str]) -> None:
    for path in long_lived_docs:
        if not _is_covered_by_index(path, indexed_paths):
            errors.append(f"long-lived Markdown is not covered by docs/_kb_index.json: {_rel(path)}")


def _check_ai_modify_notes(paths: list[Path], errors: list[str]) -> None:
    for path in paths:
        text = path.read_text(encoding="utf-8")
        first_lines = "\n".join(text.splitlines()[:12])
        if "AI 修改说明" not in first_lines:
            errors.append(f"missing top-of-file AI 修改说明: {_rel(path)}")


def _check_markdown_links(paths: list[Path], errors: list[str]) -> dict[str, set[str]]:
    inbound: dict[str, set[str]] = {}
    markdown_set = {_rel(path) for path in paths}

    for path in paths:
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for match in MARKDOWN_LINK_RE.finditer(line):
                raw_target = _clean_markdown_link_target(match.group(1))
                if not raw_target or _is_external_link(raw_target):
                    continue

                target_path, anchor = _resolve_markdown_link(path, raw_target)
                if not target_path.exists():
                    errors.append(f"missing Markdown link target in {_rel(path)}:{line_number}: {raw_target}")
                    continue

                target_rel = _rel(target_path) if _is_inside_root(target_path) else target_path.as_posix()
                if target_rel in markdown_set and target_rel != _rel(path):
                    inbound.setdefault(target_rel, set()).add(_rel(path))

                if anchor and target_path.suffix.lower() == ".md":
                    _check_markdown_anchor(path, line_number, raw_target, target_path, anchor, errors)

    return inbound


def _check_markdown_anchor(
    source_path: Path,
    line_number: int,
    raw_target: str,
    target_path: Path,
    anchor: str,
    errors: list[str],
) -> None:
    anchors = _markdown_anchors(target_path.read_text(encoding="utf-8"))
    normalized = _normalize_anchor(anchor)
    if normalized and normalized not in anchors:
        errors.append(f"missing Markdown anchor in {_rel(source_path)}:{line_number}: {raw_target}")


def _check_code_docs_index(errors: list[str]) -> None:
    if not CODE_DOCS_INDEX.exists():
        return

    text = CODE_DOCS_INDEX.read_text(encoding="utf-8")
    for match in re.finditer(r"`(docs/代码/[^`]+\.md)`", text):
        target = ROOT / match.group(1)
        if not target.exists():
            errors.append(f"docs/代码/README.md references missing module doc: {match.group(1)}")


def _check_doc_references(errors: list[str]) -> None:
    candidates = list((ROOT / "client").rglob("*.gd")) if (ROOT / "client").exists() else []

    for path in candidates:
        if _is_ignored(path):
            continue
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"^# Doc:\s*(.+)$", text, flags=re.MULTILINE):
            target_text = match.group(1).strip()
            _check_path_exists(target_text, f"# Doc reference {target_text} in {_rel(path)}", errors)


def _check_adr_numbers(errors: list[str]) -> None:
    path = ROOT / "docs" / "决策记录.md"
    if not path.exists():
        return

    numbers = _adr_numbers(path.read_text(encoding="utf-8"))
    if not numbers:
        errors.append("docs/决策记录.md has no ADR rows")
        return
    if len(numbers) != len(set(numbers)):
        errors.append("docs/决策记录.md has duplicate ADR numbers")
    expected = list(range(numbers[0], numbers[-1] + 1))
    if numbers != expected:
        errors.append(f"docs/决策记录.md ADR numbers are not continuous: expected {expected}, got {numbers}")


def _check_adr_matrix_sync(errors: list[str]) -> None:
    adr_path = ROOT / "docs" / "决策记录.md"
    if not adr_path.exists() or not KB_HUMAN_INDEX.exists():
        return

    numbers = _adr_numbers(adr_path.read_text(encoding="utf-8"))
    if not numbers:
        return
    latest = numbers[-1]

    matrix_text = _section_text(KB_HUMAN_INDEX.read_text(encoding="utf-8"), "ADR 追踪矩阵")
    covered = _adr_numbers_mentioned(matrix_text)
    if latest not in covered:
        errors.append(f"docs/AI知识库索引.md ADR matrix does not cover latest ADR #{latest}")


def _check_current_state(errors: list[str]) -> None:
    if not CURRENT_STATE.exists():
        errors.append("missing docs/AI记忆/current_state.json")
        return

    try:
        data = json.loads(CURRENT_STATE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"invalid JSON in docs/AI记忆/current_state.json: {exc}")
        return

    if not isinstance(data, dict):
        errors.append("docs/AI记忆/current_state.json must be an object")
        return

    required_fields = {
        "schema_version",
        "updated_at",
        "current_phase",
        "current_status",
        "latest_adr",
        "open_decisions",
        "last_completed",
        "next_actions",
        "last_verified",
        "blockers",
        "notes",
    }
    missing = required_fields.difference(data.keys())
    if missing:
        errors.append(f"docs/AI记忆/current_state.json missing fields: {sorted(missing)}")

    if data.get("schema_version") != 1:
        errors.append("docs/AI记忆/current_state.json schema_version must be 1")

    latest_adr = _latest_adr_number()
    if latest_adr is not None and data.get("latest_adr") != latest_adr:
        errors.append(f"current_state latest_adr must be {latest_adr}, got {data.get('latest_adr')}")

    open_decisions = data.get("open_decisions")
    expected_open_decisions = _open_decision_ids()
    if not isinstance(open_decisions, list) or not all(isinstance(item, str) for item in open_decisions):
        errors.append("current_state open_decisions must be a list of strings")
    elif open_decisions != expected_open_decisions:
        errors.append(f"current_state open_decisions must be {expected_open_decisions}, got {open_decisions}")

    for field in ("last_completed", "next_actions", "last_verified", "blockers", "notes"):
        if not isinstance(data.get(field), list):
            errors.append(f"current_state {field} must be a list")

    if isinstance(data.get("next_actions"), list) and not data["next_actions"]:
        errors.append("current_state next_actions must not be empty")
    if isinstance(data.get("last_verified"), list) and not data["last_verified"]:
        errors.append("current_state last_verified must not be empty")

    if isinstance(data.get("last_verified"), list):
        for index, item in enumerate(data["last_verified"]):
            if not isinstance(item, dict):
                errors.append(f"current_state last_verified[{index}] must be an object")
                continue
            for field in ("date", "command", "result"):
                if not isinstance(item.get(field), str) or not item.get(field):
                    errors.append(f"current_state last_verified[{index}].{field} must be a non-empty string")

    memory_path = ROOT / "docs" / "AI记忆" / "项目记忆.md"
    if latest_adr is not None and memory_path.exists():
        memory_text = memory_path.read_text(encoding="utf-8")
        if f"{latest_adr} 条已落地决策" not in memory_text:
            errors.append(f"docs/AI记忆/项目记忆.md ADR count must mention {latest_adr} 条已落地决策")
        if "current_state.json" not in memory_text:
            errors.append("docs/AI记忆/项目记忆.md must reference current_state.json")


def _report_orphan_documents(
    long_lived_docs: list[Path],
    documents: list[dict[str, Any]],
    inbound_links: dict[str, set[str]],
    reports: list[str],
) -> None:
    referenced_by_kb: dict[str, set[str]] = {}
    for document in documents:
        source = document.get("path")
        if not isinstance(source, str):
            continue
        source_path = ROOT / source if isinstance(source, str) else None
        if source_path is not None and source_path.is_dir():
            for path in long_lived_docs:
                if _is_relative_to(path, source_path):
                    referenced_by_kb.setdefault(_rel(path), set()).add("docs/_kb_index.json")

        for related in document.get("related_docs", []):
            if not isinstance(related, str) or related == source:
                continue
            related_path = ROOT / related.rstrip("/")
            if related_path.is_dir():
                for path in long_lived_docs:
                    if _is_relative_to(path, related_path):
                        referenced_by_kb.setdefault(_rel(path), set()).add(source)
            elif related.endswith(".md"):
                referenced_by_kb.setdefault(related, set()).add(source)

    exempt = {"README.md", "AGENTS.md", "CODEX.md", "OPENCODE.md", "CONTRIBUTING.md"}
    for path in long_lived_docs:
        rel = _rel(path)
        if rel in exempt:
            continue
        inbound_sources = inbound_links.get(rel, set()) | referenced_by_kb.get(rel, set())
        if not inbound_sources:
            reports.append(f"orphan Markdown has no inbound doc reference: {rel}")


def _report_authority_sync_risks(documents: list[dict[str, Any]], reports: list[str]) -> None:
    changed = _git_changed_files()
    if not changed:
        return

    for document in documents:
        path_value = document.get("path")
        doc_type = document.get("type")
        if not isinstance(path_value, str) or doc_type not in {"authority", "entrypoint", "machine_index"}:
            continue
        if path_value not in changed:
            continue

        related_docs = [related for related in document.get("related_docs", []) if isinstance(related, str)]
        changed_related = [related for related in related_docs if related.rstrip("/") in changed]
        if not changed_related and related_docs:
            reports.append(f"authority changed without related docs changed: {path_value} -> {related_docs}")


def _check_path_exists(path_value: str, label: str, errors: list[str]) -> None:
    normalized = path_value.replace("\\", "/").rstrip("/")
    path = ROOT / normalized
    if not path.exists():
        errors.append(f"missing {label}")


def _clean_markdown_link_target(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1].strip()
    if " \"" in target:
        target = target.split(" \"", 1)[0].strip()
    if " '" in target:
        target = target.split(" '", 1)[0].strip()
    return unquote(target)


def _is_external_link(target: str) -> bool:
    parsed = urlparse(target)
    return bool(parsed.scheme in {"http", "https", "mailto", "tel"})


def _resolve_markdown_link(source_path: Path, target: str) -> tuple[Path, str]:
    path_part, anchor = _split_fragment(target)
    if not path_part:
        return source_path, anchor
    if path_part.startswith("/"):
        return (ROOT / path_part.lstrip("/")).resolve(), anchor
    return (source_path.parent / path_part).resolve(), anchor


def _split_fragment(target: str) -> tuple[str, str]:
    before_query = target.split("?", 1)[0]
    if "#" not in before_query:
        return before_query, ""
    path_part, anchor = before_query.split("#", 1)
    return path_part, anchor


def _markdown_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    for match in re.finditer(r"^(#{1,6})\s+(.+?)\s*#*\s*$", text, flags=re.MULTILINE):
        slug = _normalize_anchor(match.group(2))
        if not slug:
            continue
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        anchors.add(slug if count == 0 else f"{slug}-{count}")
    return anchors


def _normalize_anchor(anchor: str) -> str:
    text = unquote(anchor).strip().lower()
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"[^\w\s\-\u4e00-\u9fff]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text.strip("-")


def _adr_numbers(text: str) -> list[int]:
    return [int(match.group(1)) for match in re.finditer(r"^\|\s*(\d+)\s*\|", text, flags=re.MULTILINE)]


def _latest_adr_number() -> int | None:
    path = ROOT / "docs" / "决策记录.md"
    if not path.exists():
        return None
    numbers = _adr_numbers(path.read_text(encoding="utf-8"))
    if not numbers:
        return None
    return numbers[-1]


def _open_decision_ids() -> list[str]:
    path = ROOT / "docs" / "修改建议.md"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    active_text = text.split("# 框架结构性增强建议", 1)[0]
    return re.findall(r"^##\s+([A-Z])\.", active_text, flags=re.MULTILINE)


def _adr_numbers_mentioned(text: str) -> set[int]:
    numbers: set[int] = set()
    for start, end in re.findall(r"#(\d+)\s*~\s*#?(\d+)", text):
        start_number = int(start)
        end_number = int(end)
        numbers.update(range(min(start_number, end_number), max(start_number, end_number) + 1))
    for number in re.findall(r"#(\d+)", text):
        numbers.add(int(number))
    return numbers


def _section_text(text: str, heading_keyword: str) -> str:
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.startswith("## ") and heading_keyword in line:
            start = index
            break
    if start is None:
        return ""
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if lines[index].startswith("## "):
            end = index
            break
    return "\n".join(lines[start:end])


def _git_changed_files() -> set[str]:
    try:
        result = subprocess.run(
            ["git", "-c", "core.quotepath=false", "status", "--short"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    except OSError:
        return set()
    if result.returncode != 0:
        return set()

    changed: set[str] = set()
    for line in result.stdout.splitlines():
        if not line:
            continue
        path_text = line[3:].strip()
        if " -> " in path_text:
            path_text = path_text.split(" -> ", 1)[1].strip()
        path_text = path_text.strip('"').replace("\\", "/")
        if path_text:
            changed.add(path_text)
    return changed


def _is_covered_by_index(path: Path, indexed_paths: list[Path]) -> bool:
    for indexed_path in indexed_paths:
        if not indexed_path.exists():
            continue
        if indexed_path.is_file() and path == indexed_path:
            return True
        if indexed_path.is_dir() and _is_relative_to(path, indexed_path):
            return True
    return False


def _is_excluded_long_lived_doc(path: Path) -> bool:
    rel = _rel(path)
    return any(rel == excluded or rel.startswith(f"{excluded}/") for excluded in EXCLUDED_LONG_LIVED_DIRS)


def _is_ignored(path: Path) -> bool:
    relative_parts = set(path.relative_to(ROOT).parts)
    return bool(relative_parts.intersection(IGNORE_PARTS))


def _is_inside_root(path: Path) -> bool:
    return _is_relative_to(path.resolve(), ROOT.resolve())


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


if __name__ == "__main__":
    sys.exit(main())
