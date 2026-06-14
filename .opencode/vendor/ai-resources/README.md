# AI Resource Vendor Packages

> This directory stores external AI skill / agent packages for manual review.
> Packages here are installed as Git submodules and are not loaded by OpenCode by default.

## Installed Packages

| Package | Source | Purpose | Status |
|---------|--------|---------|--------|
| `GodotPrompter` | `https://github.com/jame581/GodotPrompter` | Godot agent skills and prompt patterns | Review-only, pinned at `e09aa6dcf2a0a85139b74cb4432374961bb8c5d3` |
| `headless-godot-skill-kit` | `https://github.com/abagames/headless-godot-skill-kit` | Headless Godot workflow, testing, export and scene-editing references | Review-only, pinned at `d671685670957576474cd701892f35ea21cc675b` |
| `Claude-Code-Game-Studios` | `https://github.com/Donchitos/Claude-Code-Game-Studios` | Large studio-style Claude Code agents / skills / workflow reference | Review-only, pinned at `984023ddac0d5e27624f2baacde6105e45de375f` |

## Rules

- Do not add this directory to `.opencode/opencode.json` `skills.paths` without a separate review.
- Do not copy hooks, MCP servers, commands, or permissions from these packages into active project config without user approval.
- If a specific pattern is useful, extract a small project-local skill under `.opencode/skills/<name>/SKILL.md` instead of enabling an entire package.
- Preserve upstream `LICENSE` files and attribution when extracting material.
