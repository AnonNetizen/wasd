# AI Resource Vendor Packages

> This directory stores upstream external AI skill / agent packages as Git submodules.
> The active project layer uses curated project skills plus `.agents/skills/game-ai-reference`; full external packages are kept only as reference sources.

## Installed Packages

| Package | Source | Purpose | Status |
|---------|--------|---------|--------|
| `GodotPrompter` | `https://github.com/jame581/GodotPrompter` | Godot agent skills and prompt patterns | Reference only; plugin not enabled, pinned at `e09aa6dcf2a0a85139b74cb4432374961bb8c5d3` |
| `headless-godot-skill-kit` | `https://github.com/abagames/headless-godot-skill-kit` | Headless Godot workflow, testing, export and scene-editing references | Reference only; no active skill copy, pinned at `d671685670957576474cd701892f35ea21cc675b` |
| `Claude-Code-Game-Studios` | `https://github.com/Donchitos/Claude-Code-Game-Studios` | Large studio-style Claude Code agents / skills / workflow reference | Reference only through `game-ai-reference`, pinned at `984023ddac0d5e27624f2baacde6105e45de375f` |

## Active Reference Map

| Active project entry | Path | Uses |
|----------------------|------|------|
| External AI library adapter | `.agents/skills/game-ai-reference/` | Selected GodotPrompter, headless-godot, and CCGS vendor files on demand |
| Project Godot skills | `.opencode/skills/godot-gdscript/`, `.opencode/skills/godot-scene-validation/`, `.opencode/skills/godot-test-diagnostics/` | Consolidated Godot implementation, validation, and testing guidance |

## Rules

- Do not add this directory wholesale to `.opencode/opencode.json` `skills.paths`.
- Do not enable external plugins, hooks, active `.claude/` tools, templates, starter projects, examples, production state, MCP servers, or unrelated generated artifacts unless the user asks for them.
- If a specific pattern conflicts with project rules, project `AGENTS.md`, GDD, ADRs, and current platform rules win.
- Preserve upstream `LICENSE` files and attribution when extracting material.
