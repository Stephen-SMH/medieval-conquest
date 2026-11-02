# Handoff: where the work stopped (2026-11-02)

The game is being made to play like HeroCraft's **S&T: Medieval Wars** (Android), using only our own art and text. Never use HeroCraft assets.
Run the tests with `godot --headless -s tests/run_tests.gd` (Godot 4.7.2). They must report `0 failed`.

## Branches

| Branch | State |
|---|---|
| `main` | Stable; tests pass (506 checks). Stages F, A, B, C, D below are done. |
| `wip/st-rules-bundles-forge-missions` | **Unfinished** work on stages E/G/H, stopped mid-edit and untested. Use it as a starting point or redo it. |
| `real-maps` | **Finished**, not merged: 6 real-history maps (619 checks passed on that branch). Merge into main. A small conflict is likely in `MapData.province_at` (`scripts/map_data.gd`). |

## S&T rules pass: progress

Done on main:
- **F:** generals and ranks removed.
- **A:** mixed armies (one army per region, mixing soldier types).
- **D:** ranged fire only wounds; it never eliminates.
- **C:** turns are taken faction by faction, not simultaneously.
- **B:** Support orders join a friendly attack.

Still to do (in this order):
- **E. Recruiting by bundles.**
  - Cards are fixed bundles, e.g. 2 archers for 100, 4 swordsmen for 300, 6 cavalry for 500, 12 archers for 700.
  - Buying asks "Buy the selected reinforcements? Price N".
  - Then the top bar says "Select a province" and only your town/camp provinces are lit.
  - The bundle arrives **next turn**.
  - The footer says "Reinforcements ordered here arrive next turn".
  - Gold shows as an odometer (000600).
  - A used or unavailable camp shows a red no-sign over its tent.
- **G. Forge between missions.**
  - Missions award **development points**.
  - The Forge (anvil button on the briefing) buys permanent per-type upgrades.
  - An upgraded type shows a ★ on its icon.
  - Remove in-mission research.
- **H. Missions like S&T.**
  - Each mission has a PRIMARY objective, ADDITIONAL objectives and DEFEAT conditions. Defeat examples: primary not done in N turns, lose all troops, lose X before turn N.
  - Gold/silver/bronze **crowns** for finishing within e.g. 8/10/12 turns.
  - HUD: gold, turn, crown with turns left (counting down), and crossed swords with the remaining primary count.
  - Scripted events show a parchment note at the top left ("Enemy reinforcements arrived in the province of X: <unit> – 2").
  - **Briefing:** a parchment scroll with a history intro and the objectives, plus round buttons for anvil, start and back.
  - **Victory screen:**
    - objectives with ✓/✗ and their points, plus development points
    - decorations (crown thresholds) and turns taken
    - losses and enemy losses by type icon
    - "Your rank: Serf…" with a progress bar
    - back, restart and next buttons
- **I.** Drag-to-aim arrows, with click-click still working.
- **J.** Sea crossing along `sea_links: [[a, b], ...]` between port regions, drawn as dashed lines between boat icons.
- **K.** Pause menu: a bottom bar with restart, resume, objectives, surrender, info and exit.
- **L.** Battle visuals:
  - gold crossed swords on a region while it fights
  - a cracked gold shield on hits
  - a "Battle lost/won" overlay with a ✓ shield
- **M.** Main menu:
  - a bottom row of square wooden buttons: Campaigns, Scenarios, Skirmish/Hotseat, Continue, Records, Settings, Credits, plus Tutorial
  - a Scenarios parchment table (done ✓, flag, size S/M/L, difficulty stars, name) with a map preview and padlocks

The real maps add per-region `income` (5/10/15), `port`, `port_at`, `town_at`, `fortress`, plus `sea_links`, `sea_labels`, `scenery` and a `history` start. The game must use `region.income` when it is present.

## After the rules pass: real-history campaigns (user approved)

Rewrite the campaigns as real history on the real maps, with our own wording:
- England, France, Crusades and Vikings
- ~11 standalone historical scenarios, e.g. 1013 invasion of England, Lake Peipus 1242, Stamford Bridge 1066, Third Crusade 1191, siege of Orléans 1429

Each needs a history-style briefing and objectives in the H format. Then update the tutorial and the PRD (section 8).

## Facts about S&T confirmed from the user's video stills

- **Soldier-type icons:** bow, crossbow, crossed spears, lion shield (heavy infantry), horse head (cavalry), pitchfork (militia/peasant levy). Civ variants have their own names, e.g. "Norwegian archers".
- **Upgrades:** a ★ marks an upgraded type. Mixing types gives no bonus by itself.
- **Selected army:**
  - A green cloth banner on the right lists its soldiers, one icon each.
  - Tapping an icon shows a name tooltip.
  - The army gets a green glow.
- **Attack and Move popups:**
  - one row per type (icon, count, slider) in two columns
  - a total slider at the bottom between ✓ and ✕
- **The ⚔+ (Support) button:** it sits in the ring that appears on a target region (✕ / ⚔ / ⚔+).
- **Turns:**
  - Each side plays its own turn with its arrows drawn.
  - The screen shows "Turn: Kingdom of England" plus the flag, and "Tap to skip enemy turn".
- **Cavalry and the red X:** cavalry moves twice. A red X marks a spent army. The health bar turns yellow when damaged.
- **Scale:** maps have 40–60 regions. Skirmish maps show a crown with about 70 turns left.
- **Free game:** skip all shop and in-app-purchase screens and the "buy gold" button.

## Environment notes

- **Android:** Android builds need JDK 17 and the SDK (already set up on the first machine). See the README section "Build for Android".
- **Screenshots:** take them in a window, not headless. The scene-based capture script `shot.gd` lived in the first machine's scratchpad. Write a new one on the new machine.
- **GitHub account:** use **Stephen-SMH** for GitHub, never AvocadoRiri.
- **Commit trailer:** end commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (or your own model's line).
