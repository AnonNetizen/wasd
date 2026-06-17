---
name: code-review-factual
description: Fact-based review for bugs, risks, regressions, and missing tests. Use when the user asks to review/check risks/problems, or automatically before committing a large code change.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from mature code-review skill patterns and ADR #50 / ADR #69
---

# Code Review Factual

Use this skill for review-style requests and for the mandatory pre-commit review after large code changes.

Do not run a formal review for tiny changes such as typos, single-line wording, small documentation edits, read-only diagnostics, or temporary verification unless the user explicitly asks.

## Review Priorities

1. Correctness bugs and behavioral regressions.
2. Violations of project red lines: data-driven config, locale, InputMap, autoloads, contracts, generated constants, `draft/` ban.
3. Missing validation or tests required by `docs/测试策略.md`.
4. Maintainability risks that will plausibly cause future bugs.

## Output Rules

- Findings first, ordered by severity.
- Include file/line references when available.
- If no actual issue is found, say so clearly.
- Do not invent weak issues or over-optimize to appear useful.
- Keep summaries brief and secondary.

## Severity Guide

- Critical: data loss, security issue, broken startup, broken save/load, corrupt generated contracts.
- High: player-visible regression, deterministic replay break, schema mismatch, wrong autoload path.
- Medium: missing required tests/docs, brittle edge case, likely future maintenance issue.
- Low: clarity or non-blocking cleanup.

## Project-Specific Checks

- Full project player-visible text must use locale keys.
- Tunables must live in `client/data/` CSV / JSON.
- Contract IDs must come from `docs/词表与契约.md` and generated constants.
- Save changes must preserve `meta` and `run` save requirements.
- Godot changes should pass the relevant `tools/godot_bridge.py` checks.
