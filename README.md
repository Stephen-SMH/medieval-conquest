# Medieval Conquest

A turn-based medieval strategy game: gather food and gold, recruit counter-based armies, and march them across a province map to conquer.

Godot 4.7, GDScript, Compatibility renderer (desktop and web).

The requirements and game systems are in [PRD.md](PRD.md).

## Run

Open `project.godot` in Godot 4.7 and press F5, or run `godot --path .` from this folder.

## Controls

| Action | Input |
|---|---|
| Select a province | Left click |
| Select an army | Left click its banner (a shield is a garrison with no general) |
| March the selected army | Right click a province, or left click it twice (the first click shows the path) |
| Cancel a planned march / deselect | Esc, or click the sea |
| End the turn | Enter, or the End turn button |
| Build or recruit | Select one of your provinces; the buttons are under its details (hover a button for details or why it's greyed out) |
| See where a resource comes from | Hover it in the resource bar |
| Set taxes | The Tax menu in the resource bar |
| Pan the map | WASD / arrow keys, or drag with any mouse button |
| Zoom | Mouse wheel (towards the cursor), or `=` / `-` |
| Map mode: political / terrain / resources | `1` / `2` / `3`, or the buttons at the top |

## How movement works

- An army's movement points each turn are the lowest speed among its regiments.
- Entering a province costs its terrain's move cost: roads −1 (minimum 1), rivers +1.
- An army with full movement points can always enter one province, even if it costs more than its speed.
- The path line shows a green dot for steps reached this turn and orange for later turns.
  Unfinished marches continue automatically at the start of the next turn.
- Entering a province next to an enemy army stops the march (zone of control).
- You see enemy armies only in your provinces, where your armies stand, and next to those.

## How battles work

Marching into a province with an enemy army starts a battle, fought automatically in three phases:

1. **Ranged:** archers, crossbowmen and catapults shoot twice. Catapults are weak against troops in the field.
2. **Charge:** cavalry strikes first. Spearmen brace and strike back at the riders.
3. **Melee:** up to 6 rounds, until one side's morale falls to 30 and it routs.

Damage follows the counter table in [data/counters.tres](data/counters.tres) (spearmen ×2.0 against cavalry,
cavalry ×2.0 against archers, ...), the terrain (the defender's bonus in forests and mountains, cavalry on plains),
a −25% penalty for attacking across a river, the generals' Command, and morale. Regiments hit softer as they lose men.

- Before an attack you can see, a forecast simulates the battle 20 times and rates it from *Decisive win* to *Decisive loss*.
- A routed side loses another 20% of its men. A beaten defender retreats to a neighbouring province it owns,
  or is destroyed if it has none. A beaten attacker stays where it was. If the defenders hold for all 6 rounds, the attack fails.
- The winner of an attack moves in. Marching into an undefended enemy province captures it.
- The battle report lists each regiment's losses and explains the result.

## How the economy works

All numbers are in [scripts/game/economy.gd](scripts/game/economy.gd) and the `.tres` files under `data/`.

- **Resources:** gold, food, wood, iron and men (manpower), shared by the whole faction. The resource bar shows
  each one's change this turn; hover it for the breakdown. Ending the turn applies exactly those changes.
- **Gold** comes from taxes (population × tax level × happiness) and markets, and pays army upkeep.
  If gold runs out, 5% of every army deserts.
- **Food** comes from the land and farms, ×1 in spring, ×1.25 in summer, ×1.5 in autumn and ×0.25 in winter.
  The population eats 1 per 1,000 people, and supplied armies eat their upkeep. If food runs out, every army
  loses 10% of its men and provinces become unhappy.
- **Supply:** armies within 2 provinces of your territory (3 with a Logistics 3 general) eat from the stockpile.
  Beyond that they forage from the province they stand in; when it runs out they lose 5% a turn.
- **Winter:** armies outside your territory lose 5% a turn, 10% in the mountains.
- **Storage:** food up to 500, plus 500 per granary; wood and iron up to 1,000, plus 500 per capital you hold. The rest is lost.
- **Buildings:** 4 slots per province (6 in a capital), one construction at a time. Lumber camps need forest; mines need hills or mountains.
- **Recruiting:** each unit needs its building (militia need none) and costs gold, wood or iron, and 100 men.
  Up to 2 per province per turn; they join the province's garrison at the end of the turn.
  A garrison needs a general (100 gold) before it can march.
- **Happiness** moves 10 points a turn towards a target set by taxes, markets, a garrison, the capital and starvation.
  A conquered province starts at 15. Below 20, a province without a garrison may revolt and raise rebel militia.

Manpower grows by 0.5% of the population a turn, not the PRD's 5%: at 5% one capital would add 7 regiments a turn,
so manpower would never limit anything.

## Tests

```
godot --headless --import          # once, to register classes
godot --headless -s tests/run_tests.gd
```

## Layout

```
scenes/   Godot scenes (.tscn)
scripts/  GDScript: views and UI at the top level, game rules in scripts/game/,
          Resource classes for game data in scripts/data/
data/     game data: map.json (provinces, borders, factions, starting armies)
          and .tres rules (terrains, unit types, the counter table)
tests/    headless test suites
assets/   art, audio, fonts
```

## Progress

- [x] M1 — Province map: selection, neighbours, hover, pan and zoom, map modes, rivers and roads
- [x] M2 — Armies and movement: regiments, generals, A* paths with turn counts, zone of control, merge and split, fog of war
- [x] M3 — Battles: auto-resolve in 3 phases with the counter table, terrain, rivers and morale; forecast; battle report; occupation
- [x] M4 — Economy: five resources with per-turn changes, seasons, food and supply, buildings, recruiting, storage, taxes, happiness and revolts
