---
name: project-doc-sync
description: Synchronize long-lived docs, ADRs, AI memory, and knowledge indexes. Use when changing rules, AI tooling, data schema, design decisions, or documentation structure.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from ADR/documentation skill patterns and this repo's doc maintenance guide
---

# Project Doc Sync

Use this skill for any durable project knowledge change: rules, ADRs, AI tooling, data schema, design, tests, CI, or docs structure.

## Required Reads

- `docs/AI协作/文档维护指南.md`
- The target document's AI 修改说明
- `docs/AI导航.md`
- `docs/AI记忆/current_state.json`

## Workflow

1. Classify the change type using `docs/AI协作/文档维护指南.md` §3.
2. Update the authority document first, then indexes and references.
3. Add an ADR only when the decision crosses the project threshold: major and long-lived, with cross-system boundaries, protocol/version consequences, project-wide red lines, or a costly hard-to-reverse workflow/tooling choice. Ordinary features, local behavior/UI changes, bug fixes, tuning, content, localization, tests, documentation clarification, and implementation details do not get ADRs; when uncertain, default to no ADR.
4. Update `docs/AI记忆/项目记忆.md`, `docs/AI记忆/current_state.json`, and the current session log for important changes.
5. Update `docs/AI知识库索引.md` and `docs/_kb_index.json` when long-lived docs or task routes change.
6. Run `py -3 tools/docs_health_check.py` and JSON validation for changed JSON.

## Keep It Lean

- Treat ADRs as exceptions, not routine task output. When an ADR is justified, prefer one clear sentence for the decision and one for the reason.
- Do not duplicate full history in `项目记忆.md`; put details in the session log.
- Keep new docs human-maintainable and path-stable.

## Red Lines

- Do not modify AI entry/rule docs without checking platform counterparts.
- Do not add a long-lived doc without AI 修改说明.
- Do not leave `current_state.json.latest_adr` behind `docs/决策记录.md`.
