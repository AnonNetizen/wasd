---
name: playtest-review
description: Full-project playtest review workflow for feel, config tuning, milestone readiness, and actionable follow-up. Use after manual playtests or when turning playtest notes into prioritized work.
license: MIT
compatibility: agent-skills
metadata:
  source: project-adapted from game production/playtest review patterns and this repo's prototype workflow history
---

# Playtest Review

Use this skill when reviewing a playable build, tuning session, or manual gameplay notes.

## Required Context

- Read the user's latest playtest notes or explicit observations first.
- For full project work, read `docs/游戏设计文档.md`, `docs/修改建议.md`, and `docs/测试策略.md` only as needed.
- Use `docs/TODO.md` as the backlog target when converting findings into future work.

## Review Shape

1. Separate facts from interpretation: observed behavior, player feeling, likely cause, and proposed change.
2. Classify each item as gameplay feel, tuning, UX clarity, technical bug, content gap, performance, or workflow friction.
3. Tie tuning suggestions to data/config locations when known; avoid suggesting code changes for pure numbers.
4. Prioritize with P0/P1/P2/P3 and explain the player or workflow impact in one sentence.
5. Call out what should not change yet when evidence is weak.

## Project Rules

- Full project changes still obey data-driven config, locale, InputMap, RNG/GameClock, and autoload rules.
- User asks for "有没有问题 / 风险 / 看一下" require factual findings; if no issue is found, say so.
- Design changes that settle a durable rule need ADR and memory updates.

## Evidence Checklist

- Build or scene tested.
- Input device used: keyboard, mouse, controller, or mixed.
- Run length and whether the run reached the intended milestone.
- Main friction point and one positive signal.
- Config values touched or proposed.
- Validation commands run after changes, if any.

## Output

- Start with the highest-impact findings or a clear "未发现实际问题".
- Keep recommendations actionable and scoped.
- End with next actions grouped by priority when there is follow-up work.
