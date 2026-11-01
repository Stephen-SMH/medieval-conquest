# Medieval Conquest

A turn-based medieval strategy game in the style of *Strategy & Tactics: Medieval Wars*: every unit is a token on
a map of regions, and you click a unit, then a neighbouring region, to move or attack.

Godot 4.7, GDScript, Compatibility renderer (desktop and web).

The requirements are in [PRD.md](PRD.md); version 2 is section 8.

## Run

Open `project.godot` in Godot 4.7 and press F5, or run `godot --path .` from this folder.

## Controls

| Action | Input |
|---|---|
| Select a unit | Click its token |
| Select a whole stack | Click your region (not a token) |
| Move / attack | With units selected, click a **green** region to move, a **red** one to attack (a forecast shows first). Right-click works too. |
| Undo the last move | U, or the Undo button (attacks can't be undone) |
| Merge, hire a general | Buttons in the unit panel |
| Build and recruit | Click your region with no units, or "Build and recruit" in the unit panel |
| See the last battle | The Battle report button |
| End the turn | Enter, or the End turn button |
| Pan / zoom | WASD, arrow keys or drag / mouse wheel or `=` `-` |
| Map mode: political / terrain / resources | `1` / `2` / `3` |
| Deselect | Esc |

## Unit tokens

Each token shows the unit type as an icon (shield and spear for infantry, bow for archers, horse for cavalry,
catapult for siege), the soldier count (1–20), a health bar that goes green → yellow → red, rank stars for
veterans, and a gold **G** if a general leads it. A diamond marks a civilization's special unit. Greyed-out
tokens have no orders left this turn.

- **At most 4 units per region.** A unit moves 1 region a turn (cavalry 2) and can either move or attack;
  cavalry can move 1 and then attack.
- **Attacks** come from one region. Melee units fight in person. Archers, crossbowmen and catapults shoot from
  their own region: only enemy archers shoot back, and a ranged attack never takes the region.
- **If the attack fails**, the survivors stay in the region they attacked from. **If it succeeds**, every defender
  retreats to a neighbouring region of its own with room, or is destroyed, and the melee attackers move in.
- **Retreat:** a unit that fought can still move into one of your regions if it has a move point left.
- **Healing:** a unit that rests in your region regains 2 soldiers a turn (4 with Barracks), paid in gold.
- **Merging:** two units of the same type in a region merge, up to 20 soldiers; the rank is the soldier-weighted average.
- **Ranks:** Recruit, Veteran (+10% attack and defense), Elite (+20%), Hero (+30%), earned in battle.
- **Generals:** +10% attack per Command level for units in their region; lost if their unit is destroyed.

## How battles work

A battle has three phases: two ranged volleys, a cavalry charge (infantry meets it, spearmen at full strength),
then up to 6 melee rounds until a side's morale falls to 30 and it routs. Damage follows the counter table in
[data/counters.tres](data/counters.tres) (spearmen ×2.0 against cavalry, cavalry ×2.0 against archers, ...),
terrain, rivers (−25% for the attacker), walls, generals, ranks and morale. A forecast simulates the battle
20 times before you confirm. After the battle, tokens shake, losses float up, and the Battle report explains the result.

## How the economy works

All numbers are in [scripts/game/economy.gd](scripts/game/economy.gd) and the `.tres` files under `data/`.

- **Resources:** gold, food, wood, iron and soldiers (manpower), shared by the whole faction. The resource bar shows
  each one's change this turn; hover it for the breakdown.
- **Gold** comes from taxes and markets and pays unit upkeep and healing. Without gold, 5% of every unit deserts.
- **Food** comes from the land and farms, ×1 spring, ×1.25 summer, ×1.5 autumn, ×0.25 winter. People and supplied
  units eat. Without food, every unit loses 10% and nobody heals.
- **Supply:** units within 2 regions of your territory are supplied; beyond that they forage, and lose 5% a turn when
  the land is bare. In winter, units outside your territory lose 5% (10% in mountains).
- **Buildings:** 4 slots per region (6 in a capital). **Recruiting** needs the right building; the unit appears at
  the end of your turn if the region has room.
- **Happiness** follows taxes, markets, garrisons and food. Below 20, an empty region may revolt.

## Tests

```
godot --headless --import          # once, to register classes
godot --headless -s tests/run_tests.gd
```

## Layout

```
scenes/   Godot scenes (.tscn)
scripts/  views and UI at the top level; game rules in scripts/game/; Resource classes in scripts/data/
data/     maps/*.json (geography), scenarios/*.json (setups), and .tres rules (terrains, units, counters, buildings)
tests/    headless test suites
```

## Progress

- [x] M1–M4 (version 1): province map, armies, battles, economy
- [x] V1 — Unit tokens: icons, health bars, soldier counts, ranks; 4-unit stacks; move, attack, ranged attack, retreat, undo; battle results; healing and merging; recruiting units
- [ ] V2 — AI and missions
- [ ] V3 — Civilizations and campaigns
- [ ] V4 — Research, hotseat and mobile
