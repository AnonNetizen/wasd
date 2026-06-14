---
name: game-ai-reference
description: Use when the user asks to reuse external AI libraries, GodotPrompter, headless-godot, CCGS, Claude-Code-Game-Studios, or compare external game AI advice with this project's own rules.
---

# Game AI Reference

This is the only active cross-tool adapter for the external AI libraries. It keeps the active context small and routes agents to the few useful upstream references on demand.

## Authority Order

1. User's latest explicit instruction.
2. `AGENTS.md`, current platform rules, `docs/决策记录.md`, `docs/游戏设计文档.md`, `docs/词表与契约.md`, `docs/测试策略.md`, and AI memory.
3. Project-owned agents, commands, and skills in `.codebuddy/`, `.codex/`, `.opencode/`, and `.opencode/skills/`.
4. This adapter and selected external references.

If external advice conflicts with project gameplay, design, data contracts, testing, docs, language, or git policy, the project wins.

## Active Library Model

- Project-owned skills are canonical for day-to-day work: `.opencode/skills/*/SKILL.md`.
- External packages remain as upstream source snapshots under `.opencode/vendor/ai-resources/`.
- Do not load entire vendor directories into active skills paths.
- Do not recreate CCGS `design/`, `production/`, template, example, starter project, or status directories unless the user explicitly asks and the project docs allow it.
- Do not rely on external hooks, release flows, commit flows, or hidden status files.

## GodotPrompter References

Use project skills first: `godot-gdscript`, `godot-scene-validation`, and `godot-test-diagnostics`.

Read these vendor references only when the project skill does not cover the question:

- `.opencode/vendor/ai-resources/GodotPrompter/skills/gdscript-patterns/SKILL.md`
- `.opencode/vendor/ai-resources/GodotPrompter/skills/gdscript-advanced/SKILL.md`
- `.opencode/vendor/ai-resources/GodotPrompter/skills/scene-organization/SKILL.md`
- `.opencode/vendor/ai-resources/GodotPrompter/skills/resource-pattern/SKILL.md`
- `.opencode/vendor/ai-resources/GodotPrompter/skills/input-handling/SKILL.md`
- `.opencode/vendor/ai-resources/GodotPrompter/skills/godot-testing/SKILL.md`

Ignore GodotPrompter C#, 3D, mobile, multiplayer, XR, dedicated-server, and addon guidance unless the user explicitly asks for those topics.

## Headless Godot References

Use `tools/godot_bridge.py` and the project validation skills first. If raw Godot CLI guidance is needed, read:

- `.opencode/vendor/ai-resources/headless-godot-skill-kit/.agents/skills/headless-godot/SKILL.md`
- `.opencode/vendor/ai-resources/headless-godot-skill-kit/.agents/skills/headless-godot/skills/headless_cli.md`
- `.opencode/vendor/ai-resources/headless-godot-skill-kit/.agents/skills/headless-godot/skills/testing_headless.md`

Adapt shell examples to this repository's Windows/PowerShell and `py -3` conventions.

## CCGS References

Use project native subagents first for gameplay, numeric design, IP, copy, UI art, game art, marketing, data, contracts, balancing, and factual review.

Use CCGS only as a second opinion, specialist review, or workflow inspiration. Start with:

- `.opencode/vendor/ai-resources/Claude-Code-Game-Studios/.claude/docs/agent-roster.md`
- `.opencode/vendor/ai-resources/Claude-Code-Game-Studios/.claude/agents/godot-gdscript-specialist.md`
- `.opencode/vendor/ai-resources/Claude-Code-Game-Studios/.claude/agents/gameplay-programmer.md`
- `.opencode/vendor/ai-resources/Claude-Code-Game-Studios/.claude/agents/qa-lead.md`
- `.opencode/vendor/ai-resources/Claude-Code-Game-Studios/.claude/agents/producer.md`

Avoid CCGS Unity, Unreal, networking, live-ops, production status, template, and standalone GDD workflows unless explicitly requested.

## Required Summary

When using an external reference, mention:

- External reference used: `<path>`
- Project authority applied: `<project docs/rules>`
- External advice ignored or adapted: `<conflict, unsupported workflow, or not relevant>`
