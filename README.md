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
- [ ] M3 — Battles
- [ ] M4 — Economy
