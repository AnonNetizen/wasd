# Credits

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是代码库级致谢与第三方来源清单；新增 / 移除外部资源、外部库、工具或工作人员时，必须同步 `client/data/credits.json`、`client/locale/strings.csv`、`client/data/README.md`、`docs/AI导航.md` 与必要的发行许可说明。

This project keeps two credits records in sync:

- Repository-facing credits: this file.
- In-game credits data source: `client/data/credits.json`.

## Staff

| Name | Role |
|------|------|
| AnonNetizen | Project Lead / Design Direction |
| OpenAI Codex | AI-assisted Development |

## Engine And External Libraries

| Name | Usage | License | Notice |
|------|-------|---------|--------|
| [Godot Engine](https://godotengine.org/license/) | Game engine and runtime | MIT | Required when distributing Godot with the game; keep the Godot license text in release materials. |

## External Workflow References

These resources informed project-owned AI skills or workflows. The external packages are not vendored into the active project and are not redistributed in the game build.

| Name | Usage | License | Status |
|------|-------|---------|--------|
| [jame581/GodotPrompter](https://github.com/jame581/GodotPrompter) | Godot / GDScript AI skill patterns | MIT | Patterns absorbed into project-owned skills; review before redistribution. |
| [abagames/headless-godot-skill-kit](https://github.com/abagames/headless-godot-skill-kit) | Headless Godot validation workflow | MIT | Patterns absorbed into project-owned skills; review before redistribution. |
| [Donchitos/Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) | Playtest / production workflow reference | MIT | Patterns absorbed into project-owned skills; review before redistribution. |

## Maintenance Notes

- Add new runtime libraries, paid assets, audio, fonts, templates, marketplace packs, code snippets, AI-generated assets that require disclosure, or contributors here and in `client/data/credits.json`.
- Keep proper names, project names, URLs, license identifiers, and copyright notices in their original language.
- Player-visible section titles and role / usage labels belong in `client/locale/strings.csv`.
- Before release, verify each third-party entry against its upstream license and export package contents.
