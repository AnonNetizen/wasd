#!/usr/bin/env python3
"""Project-specific first-tier lint rules for formal GDScript."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DIR = ROOT / "client"

IGNORE_PARTS = {"draft", "DRAFT", ".git"}
CONTRACTS_DIR = CLIENT_DIR / "scripts" / "contracts"

AMBIGUOUS_INFERENCE_RE = re.compile(
    r"\b(?:var|const)\s+[A-Za-z_][A-Za-z0-9_]*\s*:=\s*.*"
    r"(?:"
    r"FileAccess\.open|DirAccess\.open|JSON\.parse_string|"
    r"\bload\s*\(|\.instantiate\s*\(|\bget_node\s*\(|\bget_node_or_null\s*\("
    r")"
)
DIRECT_RANDOM_RE = re.compile(r"(?<![A-Za-z0-9_.])(?:randi|randf|randi_range|randf_range)\s*\(")
DIRECT_TIME_RE = re.compile(r"\bTime\.(?:get_ticks_msec|get_ticks_usec)\s*\(")
DIRECT_PAUSE_RE = re.compile(r"\bget_tree\s*\(\s*\)\.paused\b")
HAN_RE = re.compile(r"[\u4e00-\u9fff]")

DIRECT_RANDOM_ALLOWED = {
    "client/scripts/autoload/rng.gd",
}
DIRECT_PAUSE_ALLOWED = {
    "client/scripts/autoload/game_state.gd",
}
# Internal editor-only tooling is excluded from release and intentionally uses
# Chinese labels. Keep this path allowlist narrow so runtime/player UI remains
# subject to the locale-key rule.
HARDCODED_CHINESE_ALLOWED = {
    "client/addons/module_authoring/module_authoring_main_screen.gd",
    "client/addons/module_authoring/module_json_document_self_test.gd",
}


@dataclass(frozen=True)
class LintError:
    path: Path
    line_number: int
    rule: str
    message: str

    def format(self) -> str:
        return f"[gdscript-lint] {_rel(self.path)}:{self.line_number}: {self.rule}: {self.message}"


def main() -> int:
    _configure_utf8_output()

    errors: list[LintError] = []
    for path in _gdscript_paths():
        lines = path.read_text(encoding="utf-8").splitlines()
        errors.extend(_check_section_order(path, lines))
        errors.extend(_check_ambiguous_inference(path, lines))
        errors.extend(_check_hardcoded_chinese_strings(path, lines))
        errors.extend(_check_forbidden_apis(path, lines))

    if errors:
        for error in sorted(errors, key=lambda item: (_rel(item.path), item.line_number, item.rule)):
            print(error.format())
        return 1

    print("gdscript lint passed")
    return 0


def _configure_utf8_output() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")


def _gdscript_paths() -> list[Path]:
    if not CLIENT_DIR.exists():
        return []

    paths: list[Path] = []
    for path in CLIENT_DIR.rglob("*.gd"):
        if _is_ignored(path):
            continue
        paths.append(path)
    return sorted(paths)


def _check_section_order(path: Path, lines: list[str]) -> list[LintError]:
    errors: list[LintError] = []
    class_line = 0
    extends_line = 0
    seen_onready = False

    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line).strip()
        if not code:
            continue
        if line[:1].isspace():
            continue

        if code.startswith(("func ", "static func ", "class ")):
            break
        if code.startswith("class_name ") and not class_line:
            class_line = line_number
        elif code.startswith("extends ") and not extends_line:
            extends_line = line_number
        elif code.startswith("@onready var "):
            seen_onready = True
        elif seen_onready and code.startswith("var "):
            errors.append(
                LintError(
                    path,
                    line_number,
                    "section-order",
                    "regular member variables must appear before @onready variables",
                )
            )

    if class_line and extends_line and extends_line < class_line:
        errors.append(
            LintError(
                path,
                class_line,
                "section-order",
                "class_name must appear before extends",
            )
        )

    return errors


def _check_ambiguous_inference(path: Path, lines: list[str]) -> list[LintError]:
    errors: list[LintError] = []
    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line)
        if AMBIGUOUS_INFERENCE_RE.search(code):
            errors.append(
                LintError(
                    path,
                    line_number,
                    "ambiguous-inference",
                    "use an explicit type annotation for ambiguous := expressions",
                )
            )
    return errors


def _check_hardcoded_chinese_strings(path: Path, lines: list[str]) -> list[LintError]:
    if _is_relative_to(path, CONTRACTS_DIR) or _rel(path) in HARDCODED_CHINESE_ALLOWED:
        return []

    errors: list[LintError] = []
    for line_number, line in enumerate(lines, start=1):
        for literal in _string_literals(line):
            if HAN_RE.search(literal):
                errors.append(
                    LintError(
                        path,
                        line_number,
                        "hardcoded-chinese-string",
                        "Chinese string literal in GDScript; use locale keys or add a narrow lint allowlist",
                    )
                )
                break
    return errors


def _check_forbidden_apis(path: Path, lines: list[str]) -> list[LintError]:
    errors: list[LintError] = []
    rel = _rel(path)

    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line)
        if rel not in DIRECT_RANDOM_ALLOWED and DIRECT_RANDOM_RE.search(code):
            errors.append(
                LintError(
                    path,
                    line_number,
                    "direct-random",
                    "use the RNG autoload streams instead of raw random functions",
                )
            )
        if DIRECT_TIME_RE.search(code):
            errors.append(
                LintError(
                    path,
                    line_number,
                    "direct-time",
                    "use GameClock for gameplay time instead of raw Time tick APIs",
                )
            )
        if rel not in DIRECT_PAUSE_ALLOWED and DIRECT_PAUSE_RE.search(code):
            errors.append(
                LintError(
                    path,
                    line_number,
                    "direct-pause",
                    "use GameState for pause flow instead of direct get_tree().paused access",
                )
            )
    return errors


def _code_part(line: str) -> str:
    result: list[str] = []
    quote = ""
    escaped = False
    for char in line:
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                result.append(char)
                quote = ""
            continue

        if char in {"'", '"'}:
            quote = char
            result.append(char)
        elif char == "#":
            break
        else:
            result.append(char)
    return "".join(result)


def _string_literals(line: str) -> list[str]:
    literals: list[str] = []
    current: list[str] = []
    quote = ""
    escaped = False

    for char in line:
        if quote:
            if escaped:
                current.append(char)
                escaped = False
            elif char == "\\":
                current.append(char)
                escaped = True
            elif char == quote:
                literals.append("".join(current))
                current = []
                quote = ""
            else:
                current.append(char)
            continue

        if char in {"'", '"'}:
            quote = char
            current = []
        elif char == "#":
            break

    return literals


def _is_ignored(path: Path) -> bool:
    return bool(set(path.relative_to(ROOT).parts).intersection(IGNORE_PARTS))


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
