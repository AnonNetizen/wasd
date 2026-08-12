---
name: project-doc-sync
description: Keep project documentation minimal, authoritative, and free of duplicate maintenance surfaces.
license: MIT
compatibility: agent-skills
---

# Project Doc Sync

Use for rules, documentation structure, public module contracts, design, schema, test policy, ADRs, or current project state.

## Required Reads

- `docs/AI协作/项目规则.md`
- `docs/AI协作/文档维护指南.md`
- The direct authority document for the requested change

## Workflow

1. Classify the change with the minimum-change matrix in the maintenance guide.
2. If the change is private implementation, tests, or behavior-preserving refactoring, do not update documentation.
3. Otherwise update the single direct authority first; add a module document only for a public contract.
4. Add an ADR only for major, long-lived, cross-system, protocol, project-red-line, or costly hard-to-reverse decisions.
5. Do not create project memory, session logs, verification reports, or knowledge-index entries; Git / PR / CI hold history.
6. Run `python tools/docs_health_check.py` for document paths, links, ADR, current-state, adapter, or `# Doc:` changes.

## Keep It Lean

- Do not copy the same task route, validation matrix, or status into navigation, TODO, current state, and module docs.
- Module docs describe public contracts, not private file inventories or individual test cases.
- Current state stays under 8 KiB and contains only present-tense navigation.
