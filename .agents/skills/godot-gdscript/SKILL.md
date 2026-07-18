---
name: godot-gdscript
description: Godot 4.7.1 GDScript implementation guidance for this project. Use when editing Godot scenes, scripts, autoloads, gameplay systems, or typed GDScript.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from Agent Skills patterns, GodotPrompter Godot/GDScript patterns, the official Godot 4.7 GDScript style guide, and this repo's rules
---

# Godot GDScript

Use this skill only for Godot/GDScript implementation or review work in `client/`.

## Required Context

- Read `AGENTS.md`, the current platform rules, and `docs/AI导航.md` before editing.
- For full project code, read `docs/代码文档规范.md` and the relevant `docs/代码/<module_id>.md` if it exists.

## Project Rules To Preserve

- Use Godot 4.7.1 stable and typed GDScript.
- Tunables belong in `client/data/` CSV / JSON, not magic numbers in scripts.
- Player-visible text uses locale keys and `tr()`, not hardcoded text.
- Inputs use InputMap actions, not physical key or joystick constants.
- Randomness uses `RNG.<stream>` and gameplay time uses `GameClock` in the full project.
- UI popups go through `UIManager`, high-frequency entities through `PoolManager`, damage through `Combat.apply_damage`, saves through `SaveManager`, audio through `AudioManager`.
- Do not add one-off branches by `character_id`, `relic_id`, or similar IDs; use capability, tag, primitive, or strategy data.

## Integrated Godot Guidance

- Treat the official Godot 4.7 GDScript style guide as the baseline for all new or touched `.gd` files: https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html
- Project rules remain stricter where they apply: typed GDScript, data-driven config, generated constants, project autoloads, and docs sync override generic examples.
- Do not broad-reformat unrelated scripts just because the style guide exists; clean only the code you touch unless the user explicitly asks for a style pass.
- Use official naming: files/functions/variables/signals in `snake_case`, `class_name`/node names/enums in `PascalCase`, constants and enum members in `CONSTANT_CASE`.
- Order script sections like the official guide: file annotations, `class_name`, `extends`, doc comment, signals, enums, constants, static variables, exports, regular members, `@onready` members, static methods, lifecycle callbacks, public methods, private methods, inner classes.
- Prefer `and`/`or`/`not` over symbolic boolean operators, avoid unnecessary parentheses, use one space around operators and after commas, avoid vertical alignment, write comments as `# ` / `## ` with own-line comments preferred, use double quotes by default, keep leading/trailing zeroes on floats, lowercase hex, and underscores for large numbers.
- Prefer explicit static types for fields, parameters, return values, typed arrays, and dictionaries when available.
- Use `:=` only when the right-hand side makes the type obvious on the same line; use explicit annotations for `get_node()`, external data, and complex or ambiguous expressions.
- Use `is` checks before `as` casts when the type is not guaranteed.
- After `await`, check `is_instance_valid(self)` when the node could have been freed.
- Connect complex signal behavior to named methods; keep inline lambdas small and local.
- Add `_:` fallback branches to `match` statements that consume external data or state.
- Call `super()` when overriding project base-class virtual methods that have parent behavior.
- Structure scenes by responsibility: children emit signals upward, parents call child methods downward, peer communication goes through project autoloads.
- Keep reusable data in small focused resources or JSON config as the module requires; never put per-frame gameplay logic inside resources.

## Implementation Workflow

1. Confirm the task targets the formal Godot project under `client/`.
2. Read the smallest relevant scene/script/data docs; do not blindly scan the repo.
3. Prefer small edits that fit existing nodes and signals.
4. Keep scripts single-responsibility and typed: parameters, return values, fields.
5. If you add or change a public API, signal, data schema, autoload, or dependency direction, update module docs and AI navigation.
6. Validate with the relevant commands, usually `py -3 tools/validate_data.py` and `py -3 tools/godot_bridge.py headless-boot`.

## Common Pitfalls

- Do not use generic Godot examples that hardcode speed, damage, text, or key bindings.
- Do not bypass project autoloads for convenience.
- Do not resurrect or copy historical MVP prototype code into full project `client/`.
- Do not manually edit generated `client/scripts/contracts/*.gd`.
- Do not import external Godot starter projects, broad plugin scaffolds, C# patterns, 3D/mobile/multiplayer/XR guidance, or generic setup flows unless the user explicitly asks and the project docs allow it.
