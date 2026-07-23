#!/usr/bin/env python3
"""Third-tier advisory semantic lint for GDScript project rules.

This lint intentionally reports warnings instead of failing by default. Use
--strict locally when a warning class has been reviewed and is ready to block.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DIR = ROOT / "client"
SCRIPTS_DIR = CLIENT_DIR / "scripts"
CONTRACTS_DIR = SCRIPTS_DIR / "contracts"

IGNORE_PARTS = {"draft", "DRAFT", ".git", "__pycache__"}
NON_LONG_TERM_PARTS = {"contracts", "tests", "test", "templates", "debug", "dev_tools"}

SPECIAL_BRANCH_RE = re.compile(
    r"^\s*(?:if|elif)\s+.*\b(?:character_id|relic_id|mode_id|game_mode_id)\b\s*(?:==|!=|in)\s*"
)
FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:->\s*[^:]+)?\s*:")
FUNC_WITH_RETURN_RE = re.compile(r"^\s*(?:static\s+)?func\s+[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\)\s*->\s*[^:]+\s*:")
CONTRACT_REF_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*|[A-Z][A-Z0-9_]*)\.([A-Z][A-Z0-9_]*)\b")
CONTRACT_PRELOAD_RE = re.compile(
    r"^\s*const\s+([A-Z][A-Z0-9_]*)\s*:=\s*preload\(\"res://scripts/contracts/([a-z0-9_]+\.gd)\"\)"
)
CONSTANT_RE = re.compile(r"^\s*const\s+([A-Z][A-Z0-9_]*)\b")
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Z][A-Za-z0-9_]*)\b")
POOL_REGISTER_RE = re.compile(
    r"\bPoolManager\.register_pool\s*\(\s*[^,]+,\s*"
    r"(?:Callable\s*\(\s*self\s*,\s*[\"'](?P<callable>[A-Za-z_][A-Za-z0-9_]*)[\"']\s*\)"
    r"|(?P<direct>[A-Za-z_][A-Za-z0-9_]*))",
    re.DOTALL,
)
INSTANTIATE_CALL_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\.instantiate\s*\(")
QUEUE_FREE_CALL_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\.queue_free\s*\(")
ADD_CHILD_CALL_RE = re.compile(r"\badd_child\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\b")
NODE_NEW_ASSIGN_RE = re.compile(
    r"^\s*(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)"
    r"(?:\s*:\s*([A-Z][A-Za-z0-9_]*))?\s*(?::=|=)\s*([A-Z][A-Za-z0-9_]*)\.new\s*\("
)
NODE_TYPED_VAR_RE = re.compile(r"^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_]*)")
INLINE_NODE_NEW_ADD_RE = re.compile(r"\badd_child\s*\(\s*([A-Z][A-Za-z0-9_]*)\.new\s*\(")

HIGH_FREQUENCY_ENTITY_TERMS = (
    "bullet",
    "damage_number",
    "enemy",
    "hazard",
    "hit_spark",
    "particle",
    "pickup",
    "projectile",
)
POPUP_UI_TERMS = (
    "dialog",
    "level_panel",
    "menu",
    "modal",
    "overlay",
    "pause_panel",
    "popup",
    "result_panel",
    "settings_panel",
)
NODE_CLASS_NAMES = {
    "AnimationPlayer",
    "Area2D",
    "Button",
    "CanvasLayer",
    "CheckButton",
    "CollisionShape2D",
    "ColorRect",
    "Control",
    "GridContainer",
    "HBoxContainer",
    "Label",
    "Line2D",
    "MarginContainer",
    "Marker2D",
    "Node",
    "Node2D",
    "OptionButton",
    "PanelContainer",
    "Polygon2D",
    "RichTextLabel",
    "Sprite2D",
    "StaticBody2D",
    "Timer",
    "VBoxContainer",
}


@dataclass(frozen=True)
class AdvisoryWarning:
    path: Path
    line_number: int
    rule: str
    message: str

    def format(self) -> str:
        return f"[semantic-lint] {_rel(self.path)}:{self.line_number}: {self.rule}: {self.message}"


@dataclass(frozen=True)
class BypassRule:
    rule: str
    pattern: re.Pattern[str]
    message: str


BYPASS_RULES: tuple[BypassRule, ...] = (
    BypassRule(
        "autoload-bypass-rng",
        re.compile(r"\bRandomNumberGenerator\.new\s*\(|(?<![A-Za-z0-9_.])(?:randi|randf|randi_range|randf_range)\s*\("),
        "business scripts should use RNG autoload streams instead of raw random APIs",
    ),
    BypassRule(
        "autoload-bypass-time",
        re.compile(r"\bTime\.(?:get_ticks_msec|get_ticks_usec|get_unix_time|get_unix_time_from_system)\s*\("),
        "business scripts should use GameClock for gameplay time",
    ),
    BypassRule(
        "autoload-bypass-pause",
        re.compile(r"\bget_tree\s*\(\s*\)\.paused\b"),
        "business scripts should use GameState for pause flow",
    ),
    BypassRule(
        "autoload-bypass-save-data",
        re.compile(r"\b(?:FileAccess|DirAccess)\.[A-Za-z_]+\s*\(|\bConfigFile\.new\s*\("),
        "business scripts should route data/save/settings IO through DataLoader, SaveManager, or Settings",
    ),
    BypassRule(
        "autoload-bypass-audio",
        re.compile(r"\bAudioStreamPlayer(?:2D|3D)?\.new\s*\(|\.[Pp]lay\s*\("),
        "business scripts should use AudioManager for audio playback",
    ),
    BypassRule(
        "autoload-bypass-combat",
        re.compile(r"\b(?:hp|health)\s*(?:[-+*/]?=)|\btake_damage\s*\("),
        "business scripts should route damage through Combat.apply_damage",
    ),
)


def main(argv: list[str] | None = None) -> int:
    _configure_utf8_output()

    parser = argparse.ArgumentParser(description="Run third-tier advisory semantic lint.")
    parser.add_argument("--strict", action="store_true", help="return non-zero when warnings are found")
    args = parser.parse_args(argv)

    warnings = run_checks()
    if warnings:
        for warning in sorted(warnings, key=lambda item: (_rel(item.path), item.line_number, item.rule)):
            print(warning.format())
        print(f"semantic lint advisory found {len(warnings)} warning(s)")
        return 1 if args.strict else 0

    print("semantic lint advisory passed")
    return 0


def run_checks() -> list[AdvisoryWarning]:
    warnings: list[AdvisoryWarning] = []
    contract_symbols = _contract_symbols()

    for path in _gdscript_paths():
        lines = path.read_text(encoding="utf-8").splitlines()
        warnings.extend(_check_special_id_branches(path, lines))
        warnings.extend(_check_autoload_bypass(path, lines))
        warnings.extend(_check_type_signatures(path, lines))
        warnings.extend(_check_doc_header(path, lines))
        warnings.extend(_check_contract_constants(path, lines, contract_symbols))

    return warnings


def _configure_utf8_output() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")


def _gdscript_paths() -> list[Path]:
    if not CLIENT_DIR.exists():
        return []
    return sorted(path for path in CLIENT_DIR.rglob("*.gd") if not _is_ignored(path))


def _check_special_id_branches(path: Path, lines: list[str]) -> list[AdvisoryWarning]:
    if _is_relative_to(path, CONTRACTS_DIR):
        return []

    warnings: list[AdvisoryWarning] = []
    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line)
        if SPECIAL_BRANCH_RE.search(code):
            warnings.append(
                AdvisoryWarning(
                    path,
                    line_number,
                    "special-id-branch",
                    "id-specific branches should usually become data, capability, primitive, or strategy rules",
                )
            )
    return warnings


def _check_autoload_bypass(path: Path, lines: list[str]) -> list[AdvisoryWarning]:
    if not _is_business_script(path):
        return []

    warnings: list[AdvisoryWarning] = []
    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line)
        for bypass_rule in BYPASS_RULES:
            if bypass_rule.pattern.search(code):
                warnings.append(AdvisoryWarning(path, line_number, bypass_rule.rule, bypass_rule.message))
    warnings.extend(_check_pool_ui_bypass(path, lines))
    return warnings


def _check_pool_ui_bypass(path: Path, lines: list[str]) -> list[AdvisoryWarning]:
    pool_factories = _registered_pool_factories(lines)
    node_typed_vars = {
        match.group(1)
        for line in lines
        if (match := NODE_TYPED_VAR_RE.match(_code_part(line))) is not None
        and _is_node_class_name(match.group(2))
    }
    current_func = ""
    runtime_node_vars: set[str] = set()
    warnings: list[AdvisoryWarning] = []

    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line)
        func_match = FUNC_RE.match(code)
        if func_match is not None:
            current_func = func_match.group(1)
            runtime_node_vars.clear()

        node_new_match = NODE_NEW_ASSIGN_RE.search(code)
        if node_new_match is not None:
            variable_name, declared_type, constructed_type = node_new_match.groups()
            if variable_name in node_typed_vars or _is_node_class_name(declared_type or constructed_type):
                runtime_node_vars.add(variable_name)

        inline_node_new_match = INLINE_NODE_NEW_ADD_RE.search(code)
        if (
            inline_node_new_match is not None
            and current_func not in pool_factories
            and _is_node_class_name(inline_node_new_match.group(1))
        ):
            warnings.append(
                AdvisoryWarning(
                    path,
                    line_number,
                    "runtime-node-construction",
                    "long-lived gameplay/UI nodes should be authored in scenes or instantiated from editable row templates",
                )
            )

        instantiate_match = INSTANTIATE_CALL_RE.search(code)
        direct_pool_risk = (
            instantiate_match is not None
            and current_func not in pool_factories
            and _identifier_has_term(instantiate_match.group(1), HIGH_FREQUENCY_ENTITY_TERMS)
        )

        queue_free_match = QUEUE_FREE_CALL_RE.search(code)
        direct_free_risk = queue_free_match is not None and _identifier_has_term(
            queue_free_match.group(1), HIGH_FREQUENCY_ENTITY_TERMS
        )

        add_child_match = ADD_CHILD_CALL_RE.search(code)
        if (
            add_child_match is not None
            and add_child_match.group(1) in runtime_node_vars
            and current_func not in pool_factories
        ):
            warnings.append(
                AdvisoryWarning(
                    path,
                    line_number,
                    "runtime-node-construction",
                    "long-lived gameplay/UI nodes should be authored in scenes or instantiated from editable row templates",
                )
            )
        direct_add_risk = add_child_match is not None and (
            _identifier_has_term(add_child_match.group(1), HIGH_FREQUENCY_ENTITY_TERMS)
            or _identifier_has_term(add_child_match.group(1), POPUP_UI_TERMS)
        )

        if direct_pool_risk or direct_free_risk or direct_add_risk:
            warnings.append(
                AdvisoryWarning(
                    path,
                    line_number,
                    "autoload-bypass-pool-ui",
                    "high-frequency entities should use PoolManager and popup UI should use UIManager",
                )
            )

    return warnings


def _registered_pool_factories(lines: list[str]) -> set[str]:
    source = "\n".join(_comment_free_part(line) for line in lines)
    factories: set[str] = set()
    for match in POOL_REGISTER_RE.finditer(source):
        factory = match.group("callable") or match.group("direct")
        if factory:
            factories.add(factory)
    return factories


def _identifier_has_term(identifier: str, terms: tuple[str, ...]) -> bool:
    snake_case = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", identifier).lower().strip("_")
    padded = f"_{snake_case}_"
    return any(f"_{term}_" in padded for term in terms)


def _is_node_class_name(class_name: str) -> bool:
    return class_name in NODE_CLASS_NAMES or class_name.endswith("Container")


def _check_type_signatures(path: Path, lines: list[str]) -> list[AdvisoryWarning]:
    if _is_relative_to(path, CONTRACTS_DIR):
        return []

    warnings: list[AdvisoryWarning] = []
    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line)
        match = FUNC_RE.match(code)
        if match is None:
            continue
        func_name = match.group(1)
        params = match.group(2).strip()
        if not FUNC_WITH_RETURN_RE.match(code):
            warnings.append(
                AdvisoryWarning(
                    path,
                    line_number,
                    "missing-return-type",
                    f"function {func_name} is missing an explicit return type",
                )
            )
        for param in _split_params(params):
            if not _param_has_type(param):
                warnings.append(
                    AdvisoryWarning(
                        path,
                        line_number,
                        "missing-param-type",
                        f"parameter {param.split('=', 1)[0].strip()} in {func_name} is missing an explicit type",
                    )
                )
    return warnings


def _check_doc_header(path: Path, lines: list[str]) -> list[AdvisoryWarning]:
    if not _requires_doc_header(path):
        return []
    first_lines = "\n".join(lines[:5])
    if "# Doc:" in first_lines:
        return []
    return [
        AdvisoryWarning(
            path,
            1,
            "missing-doc-header",
            "long-term GDScript should start with # Doc: docs/代码/<module_id>.md",
        )
    ]


def _check_contract_constants(
    path: Path,
    lines: list[str],
    contract_symbols: dict[str, set[str]],
) -> list[AdvisoryWarning]:
    if _is_relative_to(path, CONTRACTS_DIR):
        return []

    local_aliases = _contract_aliases(lines)
    symbols = dict(contract_symbols)
    symbols.update({alias: contract_symbols.get(class_name, set()) for alias, class_name in local_aliases.items()})

    warnings: list[AdvisoryWarning] = []
    for line_number, line in enumerate(lines, start=1):
        code = _code_part(line)
        for class_or_alias, constant_name in CONTRACT_REF_RE.findall(code):
            if class_or_alias not in symbols:
                continue
            if constant_name not in symbols[class_or_alias]:
                warnings.append(
                    AdvisoryWarning(
                        path,
                        line_number,
                        "unknown-contract-constant",
                        f"{class_or_alias}.{constant_name} is not generated in client/scripts/contracts",
                    )
                )
    return warnings


def _contract_symbols() -> dict[str, set[str]]:
    symbols: dict[str, set[str]] = {}
    if not CONTRACTS_DIR.exists():
        return symbols

    for path in sorted(CONTRACTS_DIR.glob("*.gd")):
        class_name = ""
        constants: set[str] = set()
        for line in path.read_text(encoding="utf-8").splitlines():
            class_match = CLASS_NAME_RE.match(line)
            if class_match:
                class_name = class_match.group(1)
            const_match = CONSTANT_RE.match(line)
            if const_match:
                constants.add(const_match.group(1))
        if class_name:
            symbols[class_name] = constants
    return symbols


def _contract_aliases(lines: list[str]) -> dict[str, str]:
    aliases: dict[str, str] = {}
    file_to_class: dict[str, str] = {}
    for path in CONTRACTS_DIR.glob("*.gd") if CONTRACTS_DIR.exists() else []:
        text = path.read_text(encoding="utf-8")
        match = CLASS_NAME_RE.search(text)
        if match:
            file_to_class[path.name] = match.group(1)

    for line in lines:
        match = CONTRACT_PRELOAD_RE.match(line)
        if match:
            alias, file_name = match.groups()
            class_name = file_to_class.get(file_name)
            if class_name:
                aliases[alias] = class_name
    return aliases


def _split_params(params: str) -> list[str]:
    if not params:
        return []

    result: list[str] = []
    current: list[str] = []
    depth = 0
    quote = ""
    escaped = False
    for char in params:
        if quote:
            current.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in {"'", '"'}:
            quote = char
            current.append(char)
        elif char in "([{":
            depth += 1
            current.append(char)
        elif char in ")]}":
            depth = max(0, depth - 1)
            current.append(char)
        elif char == "," and depth == 0:
            result.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    if current:
        result.append("".join(current).strip())
    return [param for param in result if param]


def _param_has_type(param: str) -> bool:
    clean_param = param.split("=", 1)[0].strip()
    if clean_param in {"", "..."}:
        return True
    return ":" in clean_param


def _requires_doc_header(path: Path) -> bool:
    if not _is_relative_to(path, SCRIPTS_DIR):
        return False
    rel_parts = set(path.relative_to(SCRIPTS_DIR).parts)
    if rel_parts.intersection(NON_LONG_TERM_PARTS):
        return False
    return True


def _is_business_script(path: Path) -> bool:
    if not _is_relative_to(path, SCRIPTS_DIR):
        return False
    relative_parts = set(path.relative_to(SCRIPTS_DIR).parts)
    if relative_parts.intersection({"autoload", "contracts", "boot", "debug", "dev_tools", "editor", "tests", "test", "templates"}):
        return False
    return True


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


def _comment_free_part(line: str) -> str:
    result: list[str] = []
    quote = ""
    escaped = False
    for char in line:
        if quote:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
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


def _is_ignored(path: Path) -> bool:
    return bool(set(path.relative_to(ROOT).parts).intersection(IGNORE_PARTS))


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    sys.exit(main())
