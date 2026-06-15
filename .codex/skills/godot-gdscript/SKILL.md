---
name: godot-gdscript
description: Godot 4.6.3 GDScript implementation guidance for this project. Use when editing Godot scenes, scripts, autoloads, gameplay systems, MVP client, or typed GDScript.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from Agent Skills patterns, GodotPrompter Godot/GDScript patterns, and this repo's rules
---

# Godot GDScript

Use this skill only for Godot/GDScript implementation or review work in `client/` or `MinimumViableProduct/client/`.

## Required Context

- Read `AGENTS.md`, the current platform rules, and `docs/AI导航.md` before editing.
- For full project code, read `docs/代码文档规范.md` and the relevant `docs/代码/<module_id>.md` if it exists.
- For MVP code, stay inside `MinimumViableProduct/` and read `MinimumViableProduct/README.md` plus MVP module docs.

## Project Rules To Preserve

- Use Godot 4.6.3 and typed GDScript.
- Tunables belong in `client/data/*.json` or MVP config, not magic numbers in scripts.
- Player-visible text uses locale keys and `tr()`, not hardcoded text.
- Inputs use InputMap actions, not physical key or joystick constants.
- Randomness uses `RNG.<stream>` and gameplay time uses `GameClock` in the full project.
- UI popups go through `UIManager`, high-frequency entities through `PoolManager`, damage through `Combat.apply_damage`, saves through `SaveManager`, audio through `AudioManager`.
- Do not add one-off branches by `character_id`, `relic_id`, or similar IDs; use capability, tag, primitive, or strategy data.

## Integrated Godot Guidance

- Prefer explicit static types for fields, parameters, return values, typed arrays, and dictionaries when available.
- Use `is` checks before `as` casts when the type is not guaranteed.
- After `await`, check `is_instance_valid(self)` when the node could have been freed.
- Connect complex signal behavior to named methods; keep inline lambdas small and local.
- Add `_:` fallback branches to `match` statements that consume external data or state.
- Call `super()` when overriding project base-class virtual methods that have parent behavior.
- Structure scenes by responsibility: children emit signals upward, parents call child methods downward, peer communication goes through project autoloads.
- Keep reusable data in small focused resources or JSON config as the module requires; never put per-frame gameplay logic inside resources.

## Implementation Workflow

1. Identify whether the task targets full project `client/` or MVP `MinimumViableProduct/client/`.
2. Read the smallest relevant scene/script/data docs; do not blindly scan the repo.
3. Prefer small edits that fit existing nodes and signals.
4. Keep scripts single-responsibility and typed: parameters, return values, fields.
5. If you add or change a public API, signal, data schema, autoload, or dependency direction, update module docs and AI navigation.
6. Validate with the relevant commands, usually `py -3 tools/validate_data.py` and MVP `py -3 tools/godot_bridge.py headless-boot` when MVP scenes/scripts changed.

## Common Pitfalls

- Do not use generic Godot examples that hardcode speed, damage, text, or key bindings.
- Do not bypass project autoloads for convenience.
- Do not mix MVP prototype code into full project `client/`.
- Do not manually edit generated `client/scripts/contracts/*.gd`.
- Do not import external Godot starter projects, broad plugin scaffolds, C# patterns, 3D/mobile/multiplayer/XR guidance, or generic setup flows unless the user explicitly asks and the project docs allow it.
