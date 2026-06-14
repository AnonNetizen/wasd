# AI Resource Vendor Packages

> This directory stores upstream external AI skill / agent packages as Git submodules.
> Selected AI tools from these packages are installed into project tool locations; templates and starter projects are intentionally excluded.

## Installed Packages

| Package | Source | Purpose | Status |
|---------|--------|---------|--------|
| `GodotPrompter` | `https://github.com/jame581/GodotPrompter` | Godot agent skills and prompt patterns | OpenCode plugin enabled from this submodule, pinned at `e09aa6dcf2a0a85139b74cb4432374961bb8c5d3` |
| `headless-godot-skill-kit` | `https://github.com/abagames/headless-godot-skill-kit` | Headless Godot workflow, testing, export and scene-editing references | `.agents/skills/headless-godot` installed, pinned at `d671685670957576474cd701892f35ea21cc675b` |
| `Claude-Code-Game-Studios` | `https://github.com/Donchitos/Claude-Code-Game-Studios` | Large studio-style Claude Code agents / skills / workflow reference | `.claude/` tools installed without templates, pinned at `984023ddac0d5e27624f2baacde6105e45de375f` |

## Active Install Map

| Installed tool | Path | Source |
|----------------|------|--------|
| GodotPrompter OpenCode plugin | `.opencode/opencode.json` `plugin` entry | `GodotPrompter/.opencode/plugins/godot-prompter.js` |
| Headless Godot Agent Skill | `.agents/skills/headless-godot/` | `headless-godot-skill-kit/.agents/skills/headless-godot/` |
| Claude Code agents / skills / hooks / rules | `.claude/` | `Claude-Code-Game-Studios/.claude/` |

## Rules

- Do not add this directory wholesale to `.opencode/opencode.json` `skills.paths`.
- Do not copy templates, starter projects, examples, production state, MCP servers, or unrelated generated artifacts unless the user asks for them.
- If a specific pattern conflicts with project rules, project `AGENTS.md` and ADRs win.
- Preserve upstream `LICENSE` files and attribution when extracting material.
