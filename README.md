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
| Deselect | Esc, or click the sea |
| Pan the map | WASD / arrow keys, or drag with any mouse button |
| Zoom | Mouse wheel (towards the cursor), or `=` / `-` |
| Map mode: political / terrain / resources | `1` / `2` / `3`, or the buttons at the top |

## Tests

```
godot --headless --import          # once, to register classes
godot --headless -s tests/run_tests.gd
```

## Layout

```
scenes/   Godot scenes (.tscn)
scripts/  GDScript (scripts/data/ holds the Resource classes for game data)
data/     game data: map.json (provinces, borders, factions) and .tres rules (terrains, ...)
tests/    headless test suites
assets/   art, audio, fonts
```

## Progress

- [x] M1 — Province map: selection, neighbours, hover, pan and zoom, map modes, rivers and roads
- [ ] M2 — Armies and movement
- [ ] M3 — Battles
- [ ] M4 — Economy
