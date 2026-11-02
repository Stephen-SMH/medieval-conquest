# Handoff: where the work stopped (2026-11-03)

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

## Region cap and the PC playthrough video (2026-11-03)

The user wants the game to match S&T **exactly**, including art and animation as seen in
`~/Downloads/Strategy And Tactics - Medieval Wars Playthrough P1 - (720p).mp4` (28 min, the **PC** version).
Copy rules, screen flow, layouts and how animations behave; draw all art ourselves in the same style,
because the repo and releases are public. There's no ffmpeg on this Mac; frames were grabbed with a small
Swift AVFoundation script (`AVAssetImageGenerator`), and contact sheets were made with PIL.

**Done: the 20-soldier region cap** (user's bug report; tests in `tests/test_room.gd`).
- `Unit.CAP` is 20. `Orders.room()`: an order into a region gets 20, less the soldiers there who stay, less
  those already ordered in. Soldiers ordered to march or attack out free their places.
- `Orders.arrivals()` says where each order's soldiers end up. Supporters and archer-only volleys stay
  home, so they need no room. Plain attacks that need room are refused (support instead).
- The slider window stops at the room ("Room for N more in X").
- Resolver: **attacks now run before moves**, so beaten attackers are home before others march into their
  places. **Supporters never move in** (S&T tutorial 6/9). The old "a split army takes in nobody" rule is gone.
  Rejoins are capped; any extra soldiers go to `_one_per_region`.
- Scenario armies over 20 were cut to 20 in `tools/make_scenarios.py`.
- The video's region numbers go above 10 (Oxford shows 12), so S&T's real cap is unknown. 20 is the user's number.

**Done the same day (commit 0f30c39, local, not pushed):**
- **Order window as in S&T.** `wood_popup.gd`, `st_frame.gd`, `dot_slider.gd`, `corner_button.gd`, and
  `planks.png`/`iron.png` from `tools/make_theme.gd -- frame`. Its title uses Grenze Gotisch.
- **Type badges.** Dark round badges in the window. Axemen show an axe: huscarls and the Varangian Guard get
  one axe, berserkers crossed axes (the user's mobile still shows this).
- **Forecast removed** from the window and the settings.
- **Playback as in S&T.** Arrows stay on the map and burn during their battle (`OrdersLayer.playing`,
  `burn`, `drop`). "Battle won" shows in big gothic letters over a dim. "Turn: …" with its flag sits low on the
  screen. There's no curtain and no battle toast.

**The user wants the game EXACTLY like S&T: rules, screens, animation, maps, history, campaigns.**
- Be proactive: study the videos and don't wait to be told each item.
- A second video, `~/Downloads/Medieval Wars_Strategy&Tactics 1.mp4` (10.7 min, the **mobile** version), is
  the main reference. It matches our HUD layout. Grab frames with an AVFoundation Swift script; there's no ffmpeg.
- Keep to the line: copy rules, layouts, flows and animation timing, but **make all art and words our own**.
  The repo and releases are public, and copying HeroCraft's art, text or campaign titles would be infringement.

**Still to do, in priority order:**
1. **Army figures.** S&T's are 2–3 hand-painted realistic figures, larger than ours, with a banner pole and the
   number under them. Ours are low-poly Quaternius renders.
   - Options: re-render with more realistic CC0 models (chainmail, kite shields, helmets), a painterly
     post-pass (outline, oil-paint smoothing, warm light), bigger figures, and darker realistic colours.
   - Copying S&T's sprites is not an option.
2. **England & Wales map** like S&T's, about 45 regions. These exist in S&T but not in our `british_isles`:
   Cumbria, Stamford, Dunwich, Leominster, Glamorgan, Pembrokeshire, Caernarfonshire, Anglesey, Salisbury,
   Glastonbury, Plymouth, Guildford, Rochester, plus Scotland and the Isle of Man as edges.
   - Each region shows a coin with income 10 (some 5 or 15), a castle sign where fortified, and a tent for camps.
3. **Campaigns as in S&T** (menu list: Tutorial, England, France, Crusades, Vikings; with XI, XI, XI, XII, IX
   missions). Use our own names: S&T calls them "Excalibur", "Great France" and "In Praise of Odin!".
   - Tutorial: north England, England vs Denmark, 9 parchment tips.
   - England mission 1: south England and Wales vs Denmark. Objectives: "destroy 7 units", "lose no more
     than 3 cavalry", "destroy all enemy forces".
   - Crusades: Third Crusade, second half of 1191–1192. Main objective Acre and Jerusalem; additional
     objective Paphos and Lefkosa, held for 2 turns; defeat after 9 turns.
   - Factions are real kingdoms ("Kingdom of England", "Kingdom of Denmark").
4. **Scenarios as in S&T's list:**
   - Robin Hood
   - Viking wars 789–1066
   - Battle of Bråvalla 770–775
   - Cnut the Great's war on Norway and Sweden
   - Unification of Norway 870
   - Italian Wars 1494–1559
   - Russian feudal war 1146–1154
   - Reconquista 790–1300
   - Each has a flag, ★ difficulty, map size (L/M) and 1/2 players. Modes are vs computer or a 2-player duel.
5. **Main menu:**
   - full-screen painted key art (our own) with the logo top right;
   - a bottom row of 7 square wood buttons: campaign, army, battle, continue, records, settings, globe;
   - corner shields. Skip the "$" shop.
6. **Loading screen:** wood, the logo, a red progress bar with %, and a tip line.
7. **Victory scroll:**
   - objectives ✓/✗ with points; your and enemy losses by type icon;
   - development points; awards (bronze, silver and gold crowns) and turns;
   - total, rank ("Knecht", "Sergeant") with a bar;
   - buttons: castle (back), replay, arrow (next).
8. **Briefing scroll:** year in the title, history text, MAIN / ADDITIONAL OBJECTIVE / DEFEAT CONDITIONS and
   crown turn limits. A right rail holds anvil (Forge), arrow (start) and castle (back).
9. **Forge:**
   - parchment grid of sketched upgrade cards joined by arrows, a red bracket on the selected one;
   - infantry row (tent, men, crossed swords, gauntlet, tents, handshake); archers row (bow, archers, eye,
     gauntlet, arrow, handshake);
   - economy tab (houses, coins);
   - odometer for points, cost in a dark circle, "Do you want to buy this upgrade? Price N".
10. **Playback details still missing:**
    - the camera pans to each enemy action;
    - a moving army has a dark shadow disc and slides;
    - a gold shield pops over the loser before it fades.
11. **The "!" shield** cycles to the next army with no orders.

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
