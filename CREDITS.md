# Credits

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是代码库级致谢与第三方来源清单；新增 / 移除外部资源、外部库、工具或工作人员时，必须同步 `client/data/credits.json`、`client/locale/strings.csv`、`client/data/README.md`、`docs/AI导航.md` 与必要的发行许可说明。

This project keeps two credits records in sync:

- Repository-facing credits: this file.
- In-game credits data source: `client/data/credits.json`.

## Staff

| Name | Role |
|------|------|
| Anon London / 伦敦阿农 | Project Lead / Design Direction |
| OpenAI Codex | AI-assisted Development |

## Engine And External Libraries

| Name | Usage | License | Notice |
|------|-------|---------|--------|
| [Godot Engine](https://godotengine.org/license/) | Game engine and runtime | MIT | Required when distributing Godot with the game; keep the Godot license text in release materials. |
| [GodotSteam](https://codeberg.org/godotsteam/godotsteam) | Steamworks integration in Steamworks Slime Lab | MIT | Included as the official GDExtension in the Lab Windows build; keep its license text in `THIRD_PARTY_NOTICES.txt`. |

## Development Tools

These Godot plugins are vendored under `client/addons/` as project-maintained forks. Their upstream copyright and MIT license files remain part of the source tree; the current credits data treats them as included in distributable project resources.

| Name | Usage | License | Notice |
|------|-------|---------|--------|
| [@icons](https://github.com/Voxybuns/at-icons) | Godot editor icon browser and icon resource library | MIT | Keep `client/addons/at-icons/LICENSE.txt` with redistributed source or resources. |
| [Script-IDE](https://github.com/Maran23/script-ide) | Godot script editor tabs, outline and quick-open workflow | MIT | Keep `client/addons/script-ide/LICENSE` with redistributed source or resources. |
| [Phantom Camera](https://github.com/ramokz/phantom-camera) | Godot runtime camera framework and player-damage screen shake | MIT | Keep `client/addons/phantom_camera/LICENSE` with redistributed source or resources. |
| [G.U.I.D.E](https://github.com/godotneers/G.U.I.D.E) by Jan Thomä | Godot runtime input mapping, remapping, contexts and prompt rendering | MIT | Keep `client/addons/guide/LICENSE.md` with redistributed source or resources. |
| [Xelu's Free Controller & Key Prompts](https://thoseawesomeguys.com/prompts/) by Nicolae Berbece | Controller and keyboard prompt artwork bundled with G.U.I.D.E | CC0 1.0 | Preserve provenance in `client/addons/guide/THIRD_PARTY_NOTICES.md`; CC0 does not require attribution. |
| [Lato](https://www.latofonts.com/) | Keyboard prompt font bundled with G.U.I.D.E | SIL Open Font License 1.1 | Keep `client/addons/guide/THIRD_PARTY_NOTICES.md` with the font and do not use the reserved font name for a modified font. |

## External Workflow References

These resources informed project-owned AI skills or workflows. The external packages are not vendored into the active project and are not redistributed in the game build.

| Name | Usage | License | Status |
|------|-------|---------|--------|
| [jame581/GodotPrompter](https://github.com/jame581/GodotPrompter) | Godot / GDScript AI skill patterns | MIT | Patterns absorbed into project-owned skills; review before redistribution. |
| [abagames/headless-godot-skill-kit](https://github.com/abagames/headless-godot-skill-kit) | Headless Godot validation workflow | MIT | Patterns absorbed into project-owned skills; review before redistribution. |
| [Donchitos/Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) | Playtest / production workflow reference | MIT | Patterns absorbed into project-owned skills; review before redistribution. |
| [affaan-m/ECC](https://github.com/affaan-m/ECC) | Agent harness workflow and AI surface audit reference | MIT | Patterns absorbed into project-owned skills; review before redistribution. |
| [Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) | GDScript code style reference | CC BY 3.0 documentation | Referenced in project rules; not redistributed in the game build. |

## Maintenance Notes

- Add new runtime libraries, paid assets, audio, fonts, templates, marketplace packs, code snippets, AI-generated assets that require disclosure, or contributors here and in `client/data/credits.json`.
- Keep proper names, project names, URLs, license identifiers, and copyright notices in their original language.
- Player-visible section titles and role / usage labels belong in `client/locale/strings.csv`.
- Before release, verify each third-party entry against its upstream license and export package contents.
