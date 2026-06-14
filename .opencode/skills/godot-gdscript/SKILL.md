---
name: godot-gdscript
description: Godot 4.6.3 GDScript implementation guidance for this project. Use when editing Godot scenes, scripts, autoloads, gameplay systems, MVP client, or typed GDScript.
license: MIT
compatibility: opencode
metadata:
  source: project-adapted from OpenCode skills docs and mature Godot/GDScript skill patterns
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
