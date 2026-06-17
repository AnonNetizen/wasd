---
name: ai-resource-curator
description: Evaluate, adapt, and audit external AI skills, agents, MCP servers, plugins, rules, and agent-harness workflow resources. Use when adding resources from Agent Skills, Claude, OpenCode, MCP, Cursor, ECC, or AI marketplaces.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from Agent Skills standard, Anthropic skills repo, OpenCode skills docs, MCP registry, ECC harness patterns, and marketplace patterns
---

# AI Resource Curator

Use this skill when searching, selecting, adapting, installing, or auditing AI skills/resources.

## Source Priority

1. Official specs/docs: `agentskills.io`, OpenCode docs, Claude Code skills docs.
2. Official/reference repos: `anthropics/skills`, `modelcontextprotocol/servers`, MCP Registry.
3. Mature community marketplaces: large, maintained, licensed repos such as `wshobson/agents`.
4. Agent-harness workflow repos such as `affaan-m/ECC`, used for procedure extraction only.
5. Rule collections: Cursor rules and similar prompt libraries, used as inspiration only.

## Selection Criteria

- Relevant to this Godot/GDScript roguelike project.
- Clear license and maintainable source.
- Low context footprint through progressive disclosure.
- No secret requirements or unsafe default permissions.
- No broad autonomous side effects unless explicitly invoked.
- Does not duplicate existing subagents/commands unless it adds reusable procedural knowledge.
- Improves one of: context budget, skill/agent quality, verification loops, security posture, or handoff reliability.

## Installation Rules

- Install project-local skill copies under `.codebuddy/skills/<name>/SKILL.md`, `.codex/skills/<name>/SKILL.md`, and `.opencode/skills/<name>/SKILL.md` when the skill is meant to be generally available.
- Keep the three platform skill directories synchronized for shared project skills; platform-specific skills must be explicitly justified and documented.
- Keep skill names lowercase hyphen-case and matching directory names.
- Keep `SKILL.md` concise; move large references into supporting files only when necessary.
- Adapt external ideas to project rules instead of blindly copying generic instructions.
- Document sources and rejection reasons in `docs/AI协作/AI技能资源评估.md` when doing a resource sweep.
- Do not install broad external vendor directories, hooks, plugin scaffolds, or bulk subagents. Extract only the useful procedure into a project-owned skill.
- For large harness repos, prefer updating an existing project skill or workflow doc over creating a new always-visible command.

## Safety Checks

- Do not install unknown scripts, hooks, plugins, or MCP servers with write/network access without explicit justification.
- Do not store tokens, local absolute private paths, or user-level secrets in repo config.
- If a resource changes `.opencode/`, remind the user to restart OpenCode; if it changes `.codex/` or `.codebuddy/`, note that new sessions may be needed for those tools to reload project files.

## AI Surface Audit

Use this lightweight audit after adding or considering external AI resources:

1. Inventory `.codebuddy/`, `.codex/`, `.opencode/`, `AGENTS.md`, platform entry files, and `docs/AI协作/AI技能资源评估.md`.
2. Classify each changed skill / agent / command as keep, improve, merge, retire, or reject; include a self-contained reason.
3. Estimate context footprint from file length and description length; flag skills over 400 lines, agents over 200 lines, rule files over 100 lines, and verbose always-loaded entry docs.
4. Check duplication across skills, commands, platform rules, and AI memory; merge procedure into the most specific existing project-owned file.
5. Check verification coverage: JSON validation for config, docs health check for docs/index changes, data validation for credits/resource data, and git diff whitespace checks.
6. Check security posture: no active external hooks, no broad MCP/server install, no committed tokens, no private local paths, no vendor tree, and no unreviewed scripts.
7. Record accepted, partially absorbed, and rejected material in `docs/AI协作/AI技能资源评估.md`; update credits when the source informed project-owned workflows.

## After Installation

- Update `CLAUDE.md`, `CODEX.md`, `OPENCODE.md`, `.codebuddy/`, `.codex/`, `.opencode/`, `docs/AI协作/README.md`, `docs/AI协作/工具适配指南.md`, `docs/AI导航.md`, and AI memory as needed.
- Run JSON validation, docs health check, and whitespace diff check.
