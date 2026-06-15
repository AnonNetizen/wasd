---
name: godot-scene-validation
description: Validate Godot scene trees, MVP headless boot, data contracts, and engine version. Use after Godot scene/script/config changes or when diagnosing launch failures.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from Claude run/verify patterns, headless-godot CLI rules, and local Godot Bridge workflow
---

# Godot Scene Validation

Use this skill when a change may affect Godot startup, scene structure, MVP gameplay, data loading, or engine compatibility.

## Commands

- `py -3 tools/godot_bridge.py godot-version`
- `py -3 tools/godot_bridge.py export-tree`
- `py -3 tools/godot_bridge.py validate-data`
- `py -3 tools/godot_bridge.py headless-boot`
- `py -3 tools/validate_data.py`
- `py -3 tools/sync_contracts.py --check` after contract or generated constants changes

## Workflow

1. Determine project target: MVP currently has a runnable Godot project; full `client/` may still be scaffold-only.
2. Run the smallest relevant validation first.
3. If a command fails, preserve the exact error and map it to scene path, script path, or data file.
4. Fix root cause rather than suppressing errors.
5. Re-run the failed command and any adjacent data/contract checks.

## Headless Godot Notes

- Prefer `tools/godot_bridge.py` over raw `godot` commands; it encodes the project path and MVP/full-client boundary.
- If raw Godot CLI is unavoidable, use `--headless --path <project>` so the command is not dependent on the current directory.
- Capture logs for raw headless runs, preferably under a project-local `logs/` directory that is not committed unless explicitly useful.
- If sandbox or CI runs fail because of `user://`, XDG, or config/cache writes, set project-local `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` for that command.
- Never edit `.tscn` files as raw text for structural scene changes; use Godot/editor APIs, project scripts, or small verified patches.
- Keep startup smoke checks separate from gameplay logic tests: boot verifies scene loading; tests verify behavior.
- Do not copy generic headless templates, patch scripts, or starter project files into this repo.

## Interpretation

- `godot-version` should report Godot `4.6.3`.
- `export-tree` verifies scene loading and gives node structure for diagnosis.
- `headless-boot` verifies MVP startup in a non-interactive environment.
- Data validation failures are contract/schema problems and should be fixed in data, locale, or contract source rather than ignored.

## Boundaries

- Do not use this skill to enter `draft/` or `DRAFT/`.
- Do not treat a successful headless boot as a full gameplay balance pass.
- Do not change full project architecture just to satisfy an MVP validation issue.
