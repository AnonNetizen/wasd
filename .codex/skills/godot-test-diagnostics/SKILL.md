---
name: godot-test-diagnostics
description: Godot test and diagnostics workflow for GUT/GdUnit4, headless failures, scene-script issues, runtime logs, and the canonical isolated Steamworks Lab smoke runner. Use when adding tests, diagnosing Godot errors, running Steamworks Lab smoke, or preparing CI test gates.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from Godot MCP diagnostics resources, headless-godot testing rules, wshobson debugging/testing patterns, and this repo's Godot Bridge workflow
---

# Godot Test Diagnostics

Use this skill when Godot behavior needs evidence from tests, logs, scene loading, or headless startup. It complements `godot-scene-validation`: use that skill for routine bridge checks; use this one for deeper diagnosis or test planning.

## Required Context

- Read `docs/测试策略.md` before writing or changing tests.
- Read `docs/AI导航.md` and the relevant module docs before diagnosing full project code.
- Use `tools/godot_bridge.py` first for formal client startup and scene diagnostics.

## Diagnostic Workflow

1. Capture the exact failing command, Godot version, scene path, script path, and error text.
2. Classify the failure: data contract, scene tree, script parse/type, autoload, runtime behavior, determinism, or test harness.
3. Run the smallest reproducible check first:
   - `py -3 tools/godot_bridge.py godot-version`
   - `py -3 tools/godot_bridge.py export-tree`
   - `py -3 tools/godot_bridge.py headless-boot`
   - `py -3 tools/validate_data.py`
   - `py -3 tools/sync_contracts.py --check`
4. If a Godot log points at generated contracts or data IDs, fix the authority source first, then regenerate or revalidate.
5. Re-run the failing command and one adjacent check to confirm the fix is not local-only.

## Raw Headless Fallback

- Prefer `tools/godot_bridge.py`; use raw Godot CLI only when the bridge does not expose the needed check.
- Raw commands must include `--headless --path <project>` and should capture the full log.
- Use project-local XDG data/config/cache paths when CI or sandbox environments cannot write to normal user directories.
- Do not import external test harness templates into this repo; adapt only the needed command pattern.

## Steamworks Slime Lab

- Use `py -3 tools/steamworks_lab_toolchain.py smoke --suite <suite>` as the only automated Lab smoke entry; do not hand-compose PowerShell loops or ENet host/client processes.
- Run the smallest affected suite first, inspect fixture and compatibility boundaries, then run `smoke --suite all`; `battle` defaults to five serial runs.
- Any test that can read or write `user://` must inject dedicated fixture paths before `add_child()` triggers `_ready()`, or run inside the toolchain's isolated user environment. Backing up real player files is not an acceptable fixture strategy.
- Require exit code `0`, the suite's exact `ALL PASS` marker, and no `SCRIPT ERROR` / `ERROR:` log; ENet also rejects `above the MTU`.
- On Windows raw fallback, prefer the sibling console executable and never use PowerShell automatic variables such as `$Host` as writable process variables.

## Test Planning

- Follow `docs/测试策略.md` for L0-L5 responsibilities.
- Prefer deterministic tests: fixed seed, `RNG.<stream>`, and controlled `GameClock` time.
- For future full project tests, prefer GUT/GdUnit4-style isolated unit tests for autoloads, `Combat`, `ModifierEngine`, `StatusEffect`, and `SaveManager`.
- Only re-record golden replays when behavior intentionally changes; bug fixes should normally preserve golden output.
- Treat manual playtest notes as L5 evidence, not a substitute for L0-L3 gates.

## CI Gate Notes

- Current Stage 1 CI is lightweight and does not run Godot tests yet.
- When adding Godot test CI later, gate it behind reproducible local commands first, then update `docs/CICD规划.md` and `docs/AI协作/实时验证回路.md`.
- Do not add marketplace test plugins, broad MCP servers, or machine-specific Godot paths to repo config without explicit justification.

## Red Lines

- Do not bypass project autoloads to make a test easy.
- Do not use raw random/time APIs in tests.
- Do not treat headless boot success as gameplay balance validation.
- Do not enter `draft/` or `DRAFT/` while investigating logs or repo state.
