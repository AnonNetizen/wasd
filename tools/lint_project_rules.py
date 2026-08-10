#!/usr/bin/env python3
"""Second-tier project rule lint for data, locale, and release boundaries."""

from __future__ import annotations

import ast
import csv
import json
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "client" / "data"
DATA_README = CLIENT_DATA / "README.md"
LOCALE_CSV = ROOT / "client" / "locale" / "strings.csv"
EXPORT_PRESETS = ROOT / "client" / "export_presets.cfg"
PROJECT_GODOT = ROOT / "client" / "project.godot"
FORMAL_CLIENT_BOOT = (
    ROOT / "client" / "scripts" / "boot" / "formal_client_boot.gd"
)
TITLE_MENU_SCRIPT = ROOT / "client" / "scripts" / "ui" / "title_menu.gd"
TITLE_MENU_SCENE = ROOT / "client" / "scenes" / "ui" / "title_menu.tscn"
INPUT_SERVICE_SCRIPT = (
    ROOT / "client" / "scripts" / "autoload" / "input_service.gd"
)
GAMEPLAY_RUN_LOOP_SCRIPT = (
    ROOT / "client" / "scripts" / "gameplay" / "gameplay_run_loop.gd"
)
SMOKE_COMMAND_CATALOG = ROOT / "client" / "tools" / "smoke_commands.json"
GODOT_BRIDGE_SCRIPT = ROOT / "tools" / "godot_bridge.py"
GODOT_RUNTIME_WORKFLOW = ROOT / ".github" / "workflows" / "godot-runtime.yml"

IGNORE_DATA_FILES = {"_contracts.json"}
IGNORED_FIELD_LEAVES = {"schema_version"}
DEBUG_RESOURCE_RE = re.compile(r"(?:^|[/_\\-])(?:debug|dev_tools|gm_|debug_console)(?:[/_\\.-]|$)", re.IGNORECASE)
DEBUG_TEST_ARENA_RE = re.compile(
    r"debug[_-]?test[_-]?arena",
    re.IGNORECASE,
)
REQUIRED_RELEASE_DEBUG_EXCLUDES = {
    "scenes/debug/*",
    "scripts/debug/*",
    "tools/debug_test_arena_smoke.gd",
    "tools/debug_tools_smoke.gd",
}
REQUIRED_RELEASE_TEST_EXCLUDES = {
    ".gutconfig.json",
    "addons/gut/*",
    "tests/*",
}
GUT_EDITOR_PLUGIN_PATH = "res://addons/gut/plugin.cfg"
SMOKE_ISOLATION_POLICY = "temporary_user_environment"
ISOLATED_BRIDGE_FUNCTIONS = (
    "_run_gut",
    "_run_isolated_command",
    "_verify_release_debug_resource_exclusion",
)
RUNTIME_BRIDGE_GUT_COMMAND_RE = re.compile(
    r"(?m)^\s*python(?:3(?:\.\d+)?)?\s+tools/godot_bridge\.py\s+"
    r"--project\s+client\s+gut\s*$"
)
INPUT_SERVICE_UI_MANAGER_RE = re.compile(r"\bUIManager\b|autoload/ui_manager\.gd")
RUN_LOOP_PRESENTATION_NODE_RE = re.compile(
    r"(?:\b(?:get_node|get_node_or_null|find_child)\s*\(\s*(?:\^?"
    r"[\"'](?:[^\"']*/)?(?:Visual|Presentation)(?:/[^\"']*)?[\"']|"
    r"(?:NodePath|StringName)\s*\(\s*[\"'](?:[^\"']*/)?"
    r"(?:Visual|Presentation)(?:/[^\"']*)?[\"']\s*\))|"
    r"[$%](?:\^?[\"'](?:[^\"']*/)?(?:Visual|Presentation)"
    r"(?:/[^\"']*)?[\"']|(?:[A-Za-z0-9_]+/)*(?:Visual|Presentation)"
    r"(?:/[A-Za-z0-9_]+)*))"
)


@dataclass(frozen=True)
class LintError:
    path: Path
    field: str
    rule: str
    message: str

    def format(self) -> str:
        return f"[project-rules-lint] {_rel(self.path)}:{self.field}: {self.rule}: {self.message}"


def main() -> int:
    _configure_utf8_output()

    errors: list[LintError] = []
    errors.extend(_check_data_fields_documented())
    errors.extend(_check_locale_bilingual())
    errors.extend(_check_release_presets())
    errors.extend(_check_gut_editor_plugin_disabled())
    errors.extend(_check_debug_test_arena_standalone())
    errors.extend(_check_architecture_boundaries())

    if errors:
        for error in sorted(errors, key=lambda item: (_rel(item.path), item.field, item.rule)):
            print(error.format())
        return 1

    print("project rules lint passed")
    return 0


def _configure_utf8_output() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")


def _check_data_fields_documented() -> list[LintError]:
    errors: list[LintError] = []
    if not DATA_README.exists():
        return [
            LintError(
                DATA_README,
                "$",
                "data-readme-fields",
                "client/data/README.md is required to document data fields",
            )
        ]

    text = DATA_README.read_text(encoding="utf-8")
    documented_tokens = _documented_field_tokens(text)

    for path in _data_files():
        for field_path in _data_field_paths(path):
            if _is_ignored_field(field_path):
                continue
            if not _is_documented_field(field_path, documented_tokens):
                errors.append(
                    LintError(
                        path,
                        field_path,
                        "data-readme-fields",
                        "data field is not documented in client/data/README.md",
                    )
                )

    return errors


def _check_locale_bilingual() -> list[LintError]:
    errors: list[LintError] = []
    if not LOCALE_CSV.exists():
        return [LintError(LOCALE_CSV, "$", "locale-bilingual", "missing locale CSV")]

    with LOCALE_CSV.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        for required in ("keys", "zh_CN", "en"):
            if required not in fieldnames:
                errors.append(
                    LintError(
                        LOCALE_CSV,
                        "header",
                        "locale-bilingual",
                        f"missing required column {required}",
                    )
                )
        if errors:
            return errors

        seen: set[str] = set()
        for line_number, row in enumerate(reader, start=2):
            key = (row.get("keys") or "").strip()
            if not key:
                errors.append(LintError(LOCALE_CSV, f"line {line_number}", "locale-bilingual", "empty locale key"))
                continue
            if key in seen:
                errors.append(
                    LintError(LOCALE_CSV, f"line {line_number}", "locale-bilingual", f"duplicate locale key {key}")
                )
            seen.add(key)
            for locale in ("zh_CN", "en"):
                if not (row.get(locale) or "").strip():
                    errors.append(
                        LintError(
                            LOCALE_CSV,
                            f"line {line_number}",
                            "locale-bilingual",
                            f"missing {locale} translation for {key}",
                        )
                    )

    return errors


def _check_release_presets() -> list[LintError]:
    if not EXPORT_PRESETS.exists():
        return []

    errors: list[LintError] = []
    presets: dict[str, dict[str, tuple[str, int]]] = {}
    current_section = ""
    preset_section_re = re.compile(r"preset\.\d+")

    for line_number, raw_line in enumerate(
        EXPORT_PRESETS.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current_section = line[1:-1]
            continue
        if (
            "=" not in line
            or preset_section_re.fullmatch(current_section) is None
        ):
            continue

        key, raw_value = line.split("=", 1)
        key = key.strip()
        value = _unquote(raw_value.strip())
        presets.setdefault(current_section, {})[key] = (value, line_number)

    for section, values in presets.items():
        name = values.get("name", ("", 0))[0]
        export_path = values.get("export_path", ("", 0))[0]
        if _value_mentions_debug(name) or _value_mentions_debug(export_path):
            continue

        custom_features, features_line = values.get(
            "custom_features",
            ("", 0),
        )
        if _contains_debug_feature(custom_features):
            errors.append(
                LintError(
                    EXPORT_PRESETS,
                    f"line {features_line}",
                    "release-debug-assets",
                    "release preset custom_features must not include "
                    f"debug/dev_tools: {custom_features}",
                )
            )
        for key in ("include_filter", "export_files", "resources"):
            value, line_number = values.get(key, ("", 0))
            if value and DEBUG_RESOURCE_RE.search(value):
                errors.append(
                    LintError(
                        EXPORT_PRESETS,
                        f"line {line_number}",
                        "release-debug-assets",
                        "release preset must not include debug/dev_tools "
                        f"resources in {section}:{key}",
                    )
                )

        exclude_filter, exclude_line = values.get(
            "exclude_filter",
            ("", 0),
        )
        excluded = {
            item.strip().replace("\\", "/").removeprefix("res://")
            for item in exclude_filter.split(",")
            if item.strip()
        }
        missing = sorted(REQUIRED_RELEASE_DEBUG_EXCLUDES - excluded)
        if missing:
            errors.append(
                LintError(
                    EXPORT_PRESETS,
                    f"line {exclude_line}" if exclude_line > 0 else section,
                    "release-debug-assets",
                    "release preset must explicitly exclude test-arena "
                    f"resources: {', '.join(missing)}",
                )
            )
        missing_tests = sorted(REQUIRED_RELEASE_TEST_EXCLUDES - excluded)
        if missing_tests:
            errors.append(
                LintError(
                    EXPORT_PRESETS,
                    f"line {exclude_line}" if exclude_line > 0 else section,
                    "release-test-assets",
                    "release preset must explicitly exclude GUT and test "
                    f"resources: {', '.join(missing_tests)}",
                )
            )

    return errors


def _check_gut_editor_plugin_disabled() -> list[LintError]:
    if not PROJECT_GODOT.exists():
        return []

    current_section = ""
    for line_number, raw_line in enumerate(
        PROJECT_GODOT.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            current_section = line[1:-1]
            continue
        if (
            current_section == "editor_plugins"
            and line.startswith("enabled=")
            and GUT_EDITOR_PLUGIN_PATH in line
        ):
            return [
                LintError(
                    PROJECT_GODOT,
                    f"line {line_number}",
                    "gut-editor-plugin-offline",
                    "GUT EditorPlugin must stay disabled because it performs "
                    "an online update check during headless editor boot; use "
                    "res://addons/gut/gut_cmdln.gd instead",
                )
            ]
    return []


def _check_debug_test_arena_standalone() -> list[LintError]:
    errors: list[LintError] = []
    for path in (
        FORMAL_CLIENT_BOOT,
        TITLE_MENU_SCRIPT,
        TITLE_MENU_SCENE,
    ):
        if not path.exists():
            continue
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(),
            start=1,
        ):
            if DEBUG_TEST_ARENA_RE.search(line) is None:
                continue
            errors.append(
                LintError(
                    path,
                    f"line {line_number}",
                    "standalone-debug-test-arena",
                    "formal boot and title UI must not reference the "
                    "standalone Developer Test Arena",
                )
            )
    return errors


def _check_architecture_boundaries() -> list[LintError]:
    errors: list[LintError] = []
    errors.extend(_check_source_boundary(
        INPUT_SERVICE_SCRIPT,
        INPUT_SERVICE_UI_MANAGER_RE,
        "input-service-ui-one-way",
        "InputService must only receive UI stack facts; it must not reference "
        "or subscribe back to UIManager",
    ))
    errors.extend(_check_source_boundary(
        GAMEPLAY_RUN_LOOP_SCRIPT,
        RUN_LOOP_PRESENTATION_NODE_RE,
        "runloop-presentation-facade",
        "GameplayRunLoop must use GameplayFeedbackController or Player public "
        "facades instead of reading Visual/Presentation nodes",
    ))
    errors.extend(_check_test_user_environment_isolation())
    return errors


def _check_source_boundary(
    path: Path,
    pattern: re.Pattern[str],
    rule: str,
    message: str,
) -> list[LintError]:
    if not path.exists():
        return [LintError(path, "$", rule, f"required source is missing; {message}")]
    errors: list[LintError] = []
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        code = _without_gdscript_comment(line)
        if pattern.search(code) is None:
            continue
        errors.append(LintError(path, f"line {line_number}", rule, message))
    return errors


def _without_gdscript_comment(line: str) -> str:
    quote = ""
    escaped = False
    for index, character in enumerate(line):
        if escaped:
            escaped = False
            continue
        if character == "\\" and quote:
            escaped = True
            continue
        if character in {"\"", "'"}:
            if not quote:
                quote = character
            elif quote == character:
                quote = ""
            continue
        if character == "#" and not quote:
            return line[:index]
    return line


def _check_test_user_environment_isolation() -> list[LintError]:
    errors: list[LintError] = []
    if not SMOKE_COMMAND_CATALOG.exists():
        errors.append(LintError(
            SMOKE_COMMAND_CATALOG,
            "$",
            "test-user-environment-isolation",
            "smoke catalog is required",
        ))
    else:
        try:
            catalog = json.loads(SMOKE_COMMAND_CATALOG.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as error:
            errors.append(LintError(
                SMOKE_COMMAND_CATALOG,
                "$",
                "test-user-environment-isolation",
                f"smoke catalog must be readable JSON: {error}",
            ))
        else:
            commands = catalog.get("commands") if isinstance(catalog, dict) else None
            if not isinstance(commands, list) or not commands:
                errors.append(LintError(
                    SMOKE_COMMAND_CATALOG,
                    "commands",
                    "test-user-environment-isolation",
                    "smoke catalog commands must be a non-empty array",
                ))
                commands = []
            for index, descriptor in enumerate(commands):
                isolation = (
                    descriptor.get("isolation")
                    if isinstance(descriptor, dict)
                    else None
                )
                if isolation == SMOKE_ISOLATION_POLICY:
                    continue
                errors.append(LintError(
                    SMOKE_COMMAND_CATALOG,
                    f"commands[{index}].isolation",
                    "test-user-environment-isolation",
                    "every smoke command must use temporary_user_environment",
                ))

    if not GODOT_BRIDGE_SCRIPT.exists():
        errors.append(LintError(
            GODOT_BRIDGE_SCRIPT,
            "$",
            "test-user-environment-isolation",
            "the canonical GUT runner is required",
        ))
    else:
        bridge_text = GODOT_BRIDGE_SCRIPT.read_text(encoding="utf-8")
        bridge_errors = _bridge_isolation_errors(bridge_text)
        for field, message in bridge_errors:
            errors.append(LintError(
                GODOT_BRIDGE_SCRIPT,
                field,
                "test-user-environment-isolation",
                message,
            ))

    if not GODOT_RUNTIME_WORKFLOW.exists():
        errors.append(LintError(
            GODOT_RUNTIME_WORKFLOW,
            "$",
            "test-user-environment-isolation",
            "the runtime CI workflow is required",
        ))
    else:
        workflow_text = "\n".join(
            _without_gdscript_comment(line)
            for line in GODOT_RUNTIME_WORKFLOW.read_text(encoding="utf-8").splitlines()
        )
        runtime_commands = "\n".join(
            _runtime_workflow_run_commands(workflow_text)
        )
        if (
            RUNTIME_BRIDGE_GUT_COMMAND_RE.search(runtime_commands) is None
            or "gut_cmdln.gd" in runtime_commands
        ):
            errors.append(LintError(
                GODOT_RUNTIME_WORKFLOW,
                "runtime-tests",
                "test-user-environment-isolation",
                "runtime CI must call the isolated Godot Bridge GUT entrypoint",
            ))
    return errors


def _bridge_isolation_errors(source: str) -> list[tuple[str, str]]:
    try:
        module = ast.parse(source)
    except SyntaxError:
        return [(
            "$",
            "Godot Bridge must be valid Python before isolation can be verified",
        )]
    errors: list[tuple[str, str]] = []
    for function_name in ISOLATED_BRIDGE_FUNCTIONS:
        function = _find_top_level_function(module, function_name)
        if (
            function is None
            or not _function_runs_in_temporary_environment(function)
        ):
            errors.append((
                function_name,
                f"{function_name} must run every process inside one temporary "
                "directory with an environment derived from that directory",
            ))
    smoke_function = _find_top_level_function(module, "_run_smoke_command")
    if smoke_function is None or not _smoke_entry_uses_isolated_runner(
        smoke_function
    ):
        errors.append((
            "_run_smoke_command",
            "smoke commands must route through _run_isolated_command and must "
            "not execute a process directly",
        ))
    return errors


def _find_top_level_function(
    module: ast.Module,
    name: str,
) -> ast.FunctionDef | ast.AsyncFunctionDef | None:
    functions = [
        node
        for node in module.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == name
    ]
    if len(functions) != 1:
        return None
    return functions[0]


def _function_runs_in_temporary_environment(
    function: ast.FunctionDef | ast.AsyncFunctionDef,
) -> bool:
    run_calls = [
        node
        for node in ast.walk(function)
        if _is_named_call(node, "_run_command")
    ]
    if not run_calls:
        return False
    for node in ast.walk(function):
        if not isinstance(node, ast.With):
            continue
        directory_name = _temporary_directory_alias(node)
        if directory_name is None:
            continue
        scope_nodes = set(ast.walk(node))
        if not all(call in scope_nodes for call in run_calls):
            continue
        if _temporary_scope_runs_are_isolated(
            node,
            directory_name,
            run_calls,
        ):
            return True
    return False


def _temporary_directory_alias(node: ast.With) -> str | None:
    for item in node.items:
        call = item.context_expr
        if not (
            isinstance(call, ast.Call)
            and isinstance(call.func, ast.Attribute)
            and isinstance(call.func.value, ast.Name)
            and call.func.value.id == "tempfile"
            and call.func.attr == "TemporaryDirectory"
            and isinstance(item.optional_vars, ast.Name)
        ):
            continue
        return item.optional_vars.id
    return None


def _temporary_scope_runs_are_isolated(
    scope: ast.With,
    directory_name: str,
    run_calls: list[ast.Call],
) -> bool:
    store_counts: Counter[str] = Counter(
        node.id
        for node in ast.walk(scope)
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Store)
    )
    events = [
        node
        for node in ast.walk(scope)
        if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign))
        or _is_named_call(node, "_run_command")
    ]
    events.sort(key=lambda node: (
        getattr(node, "lineno", 0),
        getattr(node, "col_offset", 0),
        0 if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign)) else 1,
    ))
    derived_names: set[str] = {directory_name}
    isolated_environment_names: set[str] = set()
    checked_calls: set[ast.Call] = set()
    for event in events:
        if isinstance(event, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            value = event.value
            targets = _assignment_target_names(event)
            is_isolated_environment = (
                isinstance(value, ast.Call)
                and isinstance(value.func, ast.Name)
                and value.func.id == "_isolated_user_environment"
                and bool(value.args)
                and _expression_references_names(value.args[0], derived_names)
            )
            is_derived = (
                value is not None
                and _expression_references_names(value, derived_names)
            )
            for target in targets:
                isolated_environment_names.discard(target)
                derived_names.discard(target)
                if is_derived:
                    derived_names.add(target)
                if is_isolated_environment:
                    isolated_environment_names.add(target)
            continue
        call = event
        env_names = [
            keyword.value.id
            for keyword in call.keywords
            if keyword.arg == "env" and isinstance(keyword.value, ast.Name)
        ]
        if (
            len(env_names) != 1
            or env_names[0] not in isolated_environment_names
        ):
            return False
        checked_calls.add(call)
    if checked_calls != set(run_calls):
        return False
    protected_names = derived_names | isolated_environment_names
    return all(store_counts[name] == 1 for name in protected_names)


def _assignment_target_names(
    node: ast.Assign | ast.AnnAssign | ast.AugAssign,
) -> set[str]:
    raw_targets: list[ast.expr]
    if isinstance(node, ast.Assign):
        raw_targets = node.targets
    else:
        raw_targets = [node.target]
    names: set[str] = set()
    for target in raw_targets:
        names.update(
            child.id
            for child in ast.walk(target)
            if isinstance(child, ast.Name)
        )
    return names


def _expression_references_names(
    node: ast.AST,
    names: set[str],
) -> bool:
    return any(
        isinstance(child, ast.Name)
        and isinstance(child.ctx, ast.Load)
        and child.id in names
        for child in ast.walk(node)
    )


def _is_named_call(node: ast.AST, name: str) -> bool:
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == name
    )


def _smoke_entry_uses_isolated_runner(
    function: ast.FunctionDef | ast.AsyncFunctionDef,
) -> bool:
    isolated_calls = [
        node
        for node in ast.walk(function)
        if _is_named_call(node, "_run_isolated_command")
    ]
    direct_calls = [
        node
        for node in ast.walk(function)
        if _is_named_call(node, "_run_command")
        or (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in {"os", "subprocess"}
            and node.func.attr in {"system", "run", "Popen"}
        )
    ]
    return len(isolated_calls) == 1 and not direct_calls


def _runtime_workflow_run_commands(source: str) -> list[str]:
    lines = source.splitlines()
    jobs_index = next(
        (
            index for index, line in enumerate(lines)
            if line.strip() == "jobs:" and len(line) - len(line.lstrip()) == 0
        ),
        -1,
    )
    if jobs_index < 0:
        return []
    runtime_index = -1
    runtime_indent = -1
    for index in range(jobs_index + 1, len(lines)):
        line = lines[index]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if stripped and indent == 0:
            break
        if stripped == "runtime-tests:":
            runtime_index = index
            runtime_indent = indent
            break
    if runtime_index < 0:
        return []

    commands: list[str] = []
    index = runtime_index + 1
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if stripped and indent <= runtime_indent:
            break
        match = re.match(r"^\s*run:\s*(.*)$", line)
        if match is None:
            index += 1
            continue
        value = match.group(1).strip()
        run_indent = indent
        if value not in {"|", "|-", "|+", ">", ">-", ">+"}:
            commands.append(value.strip("\"'"))
            index += 1
            continue
        block: list[str] = []
        index += 1
        while index < len(lines):
            block_line = lines[index]
            block_stripped = block_line.strip()
            block_indent = len(block_line) - len(block_line.lstrip())
            if block_stripped and block_indent <= run_indent:
                break
            if block_stripped:
                block.append(block_stripped)
            index += 1
        separator = " " if value.startswith(">") else "\n"
        commands.append(separator.join(block))
    return commands


def _data_files() -> list[Path]:
    if not CLIENT_DATA.exists():
        return []
    paths = [
        path
        for path in CLIENT_DATA.iterdir()
        if path.is_file() and path.name not in IGNORE_DATA_FILES and path.suffix.lower() in {".json", ".csv"}
    ]
    return sorted(paths)


def _data_field_paths(path: Path) -> set[str]:
    if path.suffix.lower() == ".csv":
        with path.open(encoding="utf-8-sig", newline="") as handle:
            return {field.strip() for field in (csv.DictReader(handle).fieldnames or []) if field.strip()}

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return set()

    fields: set[str] = set()
    _collect_json_fields(data, "", fields)
    return fields


def _collect_json_fields(data: Any, prefix: str, fields: set[str]) -> None:
    if isinstance(data, dict):
        for key, value in data.items():
            if not isinstance(key, str):
                continue
            path = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                _collect_json_fields(value, path, fields)
            elif isinstance(value, list):
                if not value or all(not isinstance(item, (dict, list)) for item in value):
                    fields.add(path)
                _collect_json_fields(value, path, fields)
            else:
                fields.add(path)
    elif isinstance(data, list):
        array_prefix = f"{prefix}[]" if prefix else "[]"
        for item in data:
            _collect_json_fields(item, array_prefix, fields)


def _documented_field_tokens(text: str) -> set[str]:
    tokens = set(re.findall(r"(?<!`)`([^`\n]+?)`(?!`)", text))
    return {
        token.strip()
        for token in tokens
        if token.strip()
        and "/" not in token
        and "," not in token
        and not token.strip().endswith((".json", ".csv", ".md", ".gd", ".py"))
        and " " not in token.strip()
    }


def _is_ignored_field(field_path: str) -> bool:
    leaf = field_path.rsplit(".", 1)[-1].removesuffix("[]")
    return leaf in IGNORED_FIELD_LEAVES


def _is_documented_field(field_path: str, documented_tokens: set[str]) -> bool:
    if field_path in documented_tokens:
        return True

    normalized_path = field_path.replace("[]", "")
    leaf = field_path.rsplit(".", 1)[-1].removesuffix("[]")
    for token in documented_tokens:
        if token == leaf:
            return True
        if token.startswith("*."):
            token_suffix = token[2:]
            if field_path.endswith(f".{token_suffix}") or field_path == token_suffix:
                return True
        if "*" in token and _token_pattern(token).search(field_path):
            return True
        if field_path.endswith(f".{token}") or normalized_path.endswith(f".{token.replace('[]', '')}"):
            return True
    return False


def _token_pattern(token: str) -> re.Pattern[str]:
    escaped = re.escape(token)
    escaped = escaped.replace(r"\*", r"[^.]+")
    return re.compile(escaped)


def _contains_debug_feature(value: str) -> bool:
    features = {item.strip().lower() for item in value.split(",") if item.strip()}
    return bool(features.intersection({"debug", "dev_tools"}))


def _value_mentions_debug(value: str) -> bool:
    lowered = value.lower()
    return "debug" in lowered or "dev_tools" in lowered


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    sys.exit(main())
