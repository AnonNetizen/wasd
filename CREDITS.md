# Credits

> 权威范围：仓库级第三方来源、许可证与致谢记录。

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

These Godot plugins are vendored under `client/addons/` at fixed versions. Their upstream copyright and license files remain part of the source tree. Runtime/editor resources may be distributable; GUT is development-only and explicitly excluded from release exports, so it remains repository-facing credit only.

| Name | Usage | License | Notice |
|------|-------|---------|--------|
| [@icons](https://github.com/Voxybuns/at-icons) | Godot editor icon browser and icon resource library | MIT | Keep `client/addons/at-icons/LICENSE.txt` with redistributed source or resources. |
| [Script-IDE](https://github.com/Maran23/script-ide) | Godot script editor tabs, outline and quick-open workflow | MIT | Keep `client/addons/script-ide/LICENSE` with redistributed source or resources. |
| [Phantom Camera](https://github.com/ramokz/phantom-camera) | Godot runtime camera framework and player-damage screen shake | MIT | Keep `client/addons/phantom_camera/LICENSE` with redistributed source or resources. |
| [G.U.I.D.E](https://github.com/godotneers/G.U.I.D.E) by Jan Thomä | Godot runtime input mapping, remapping, contexts and prompt rendering | MIT | Keep `client/addons/guide/LICENSE.md` with redistributed source or resources. |
| [GUT](https://github.com/bitwes/Gut) by Tom “Butch” Wesley | Godot unit and integration test framework | MIT | Fixed at `v9.7.1`; keep `client/addons/gut/LICENSE.md` with vendored source. Excluded from game exports. |
| [Anonymous Pro](https://www.marksimonson.com/fonts/view/anonymous-pro) by Mark Simonson | Font bundled with GUT | SIL Open Font License 1.1 | Keep `client/addons/GUT_THIRD_PARTY_NOTICES.md` and `client/addons/gut/fonts/OFL.txt`; Reserved Font Name `Anonymous Pro`. Excluded from game exports with GUT. |
| Courier Prime | Font bundled with GUT | SIL Open Font License 1.1 | Keep `client/addons/GUT_THIRD_PARTY_NOTICES.md` plus the original copyright and license records embedded in the TTF name metadata. Excluded from game exports with GUT. |
| Lobster Two | Font bundled with GUT | SIL Open Font License 1.1 | Keep `client/addons/GUT_THIRD_PARTY_NOTICES.md` plus the original TTF metadata; Reserved Font Name `Lobster`. Excluded from game exports with GUT. |
| [Source Code Pro](https://github.com/adobe-fonts/source-code-pro) by Adobe | Bitmap font resource bundled with GUT | SIL Open Font License 1.1 | Keep `client/addons/GUT_THIRD_PARTY_NOTICES.md` and the vendored OFL text; Reserved Font Name `Source`. Excluded from game exports with GUT. |
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
