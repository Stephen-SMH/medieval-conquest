# Handoff: where the work stopped (2026-11-02, second session)

The game is being made to play like HeroCraft's **S&T: Medieval Wars** (Android), using only our own art and text. Never use HeroCraft assets.
Run the tests with `godot --headless -s tests/run_tests.gd` (Godot 4.7.2). They must report `0 failed`.
After adding a script with a new `class_name`, run `godot --headless --import` once, or other scripts can't find the class.

## Branches

| Branch | State |
|---|---|
| `main` | `real-maps` merged in. Tests pass. |
| `st-rules-pass` | **The S&T rules pass, stages E to M, done** on top of `main` (647 checks pass). Not merged into `main` and not pushed yet. |
| `wip/st-rules-bundles-forge-missions` (remote) | Old unfinished start on E/G/H. Superseded by `st-rules-pass`; can be deleted. |

## S&T rules pass: all done (PRD 8.7, 8.9, 8.11–8.15)

- **F, A, D, C, B** (first session): no generals or ranks, mixed armies, ranged fire only wounds, faction-by-faction turns, support orders.
- **E** reinforcement bundles (`Economy.bundles`, `scripts/ui/recruit_window.gd`, `odometer.gd`, `site_marks.gd`). Save version 5.
- **G** the Forge replaces research (`scripts/game/forge.gd`, `scripts/ui/forge_window.gd`, `Progress.upgrades`). Techs and research are gone.
- **H** S&T missions (`scripts/game/mission.gd`): primary/additional/defeat, crowns, scripted events and notes, briefing scroll (`briefing_scroll.gd`), victory screen (`end_screen.gd`), rank. Old missions (`objectives`/`par`) convert on load. Save version 6.
- **I** drag from an army to aim its order (`main.gd`: `_aim_unit`, `_aim_at`).
- **J** sea links are neighbours across a "sea" border (`MapData`); landings fight like river crossings.
- **K** pause menu (`scripts/ui/pause_menu.gd`): restart, resume, objectives, surrender, info, exit.
- **L** battle visuals (`effects.gd`): gold crossed swords, cracked shields, "Battle won/lost" card (`Hud.battle_result`).
- **M** main menu with a bottom row of square buttons (`square_button.gd`), Scenarios table with map preview (`scenarios.gd`, `map_preview.gd`), Continue, Records, Credits. Six historical scenarios from the real maps' starts, made by `python3 tools/make_scenarios.py`.

## Web build, CI and releases (2026-11-02)

- The repo is **public**. `.github/workflows/build.yml` tests and exports Web, Windows, Linux, macOS and Android on
  every push to `main` and every PR. A `v*` tag also makes a GitHub release and deploys the web build to GitHub
  Pages (https://stephen-smh.github.io/medieval-conquest/). See README "Export" and "Releases".
- `tools/fetch_godot_templates.py` reads only the named templates out of the 1.3 GB archive (range requests);
  `tools/export.sh` exports and zips into `dist/`; `tools/set_version.py` stamps a tag's version.
- Web has no system fonts: `scripts/fonts.gd` (autoload "Fonts") gives the game fonts two cut-down Noto symbol
  fallbacks made by `tools/make_symbol_fonts.sh`. Their line height is lowered to IM Fell's on purpose; Godot sizes
  lines by the tallest fallback. Fallbacks set in a font's `.import` file are lost on export.
- **Android signing:** no release keystore secrets are set yet, so CI makes a debug APK. README "Releases" has
  the commands. Android export in CI is untested locally (no Android SDK on this machine).

## Known issues and notes

- **Balance:** bundles made soldiers dearer (a soldier costs a tenth of the old 20-soldier price). With `tools/sim_campaigns.gd`, some old conquest finales got harder (Norse 5, Anglish 5, Crusader 3, Byzantine 3). These campaigns are due to be replaced (below), so they weren't retuned.
- **Scenario balance:** checked only with an AI stand-in that keeps its must-hold regions garrisoned (the script is not in the repo; it's like `sim_campaigns.gd` but over `Scenarios.all()`). Heartlands loses its capital quickly with that stand-in; a person does better.
- `tests/test_v2.gd` writes save slot 3 into the real `user://saves` (it did before this session too).

## Next: real-history campaigns (user approved)

Rewrite the campaigns as real history on the real maps, with our own wording:
- England, France, Crusades and Vikings, in the H mission format (primary/additional/defeat, crowns, events, a `history` intro).
- More standalone historical scenarios. Done so far: 1242 Battle on the Ice, 1066 Year of Three Kings, 1429 Siege of Orléans, 1000 Svolder, 1176 Barbarossa, 1187 Hattin. Still to add, e.g. 1013 invasion of England and 1191 Third Crusade.
- `tools/make_scenarios.py` shows the pattern: start from a map's `history` owners, override owners and armies per mission, and garrison the objective regions.
- Then update the tutorial and the PRD (section 8). `tests/test_v3.gd` and `tests/test_v5.gd` expect six campaigns and 25 missions; they will need updating with the new campaigns.

## Facts about S&T confirmed from the user's video stills

- **Soldier-type icons:** bow, crossbow, crossed spears, lion shield (heavy infantry), horse head (cavalry), pitchfork (militia/peasant levy). Civ variants have their own names, e.g. "Norwegian archers".
- **Upgrades:** a ★ marks an upgraded type. Mixing types gives no bonus by itself.
- **Selected army:** a green cloth banner on the right lists its soldiers, one icon each; tapping an icon shows a name tooltip; the army gets a green glow.
- **Attack and Move popups:** one row per type (icon, count, slider) in two columns; a total slider at the bottom between ✓ and ✕.
- **The ⚔+ (Support) button** sits in the ring that appears on a target region (✕ / ⚔ / ⚔+).
- **Turns:** each side plays its own turn with its arrows drawn; "Turn: Kingdom of England" plus the flag, and "Tap to skip enemy turn".
- **Cavalry and the red X:** cavalry moves twice. A red X marks a spent army. The health bar turns yellow when damaged.
- **Scale:** maps have 40–60 regions. Skirmish maps show a crown with about 70 turns left.
- **Free game:** skip all shop and in-app-purchase screens and the "buy gold" button.

## Environment notes

- **Godot:** installed with `brew install --cask godot` (4.7.2) on the second machine.
- **Android:** Android builds need JDK 17 and the SDK (set up on the first machine). See the README section "Build for Android".
- **Screenshots:** take them in a window, not headless. A scene-based capture script lives only in the session scratchpad: it loads `scenes/main.tscn` or `scenes/menu.tscn`, runs a small action against the scene root, waits some frames and saves the viewport. Point `Settings.config_path` and `Progress.path` at scratch files first so the player's own settings and progress aren't touched. The main scene still autosaves to `user://saves/slot_auto.json`.
- **GitHub account:** use **Stephen-SMH** for GitHub, never AvocadoRiri.
- **Commit trailer:** end commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or your own model's line).
