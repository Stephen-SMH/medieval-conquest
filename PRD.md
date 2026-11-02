# Medieval Conquest — Product Requirements

A turn-based medieval strategy game on a map of provinces. Each faction gathers food, gold, wood and iron, recruits armies of different unit types, and marches them across the map to attack and conquer. Unit types counter each other: spears beat cavalry, cavalry beats archers, and so on.

- **Engine:** Godot 4.7, GDScript, Compatibility renderer
- **Platforms:** desktop (macOS, Windows, Linux), web (HTML5) and Android
- **Input:** mouse and touch
- **View:** 2D top-down painted map with province borders
- **Reference game:** *Strategy & Tactics: Medieval Wars* (HeroCraft, Android). Section 8 describes the version 2 redesign that follows its style. Where section 8 conflicts with sections 3–7, section 8 wins.

---

## 1. Goals

| # | Goal |
|---|---|
| G1 | Choosing **what army to build** matters as much as where to send it, because unit types counter each other. |
| G2 | **Food and supply** limit how big and how far armies can go. |
| G3 | A match against 3 AI factions can be won in about 60–90 minutes. |
| G4 | Every battle result can be explained: the player sees why they won or lost. |

**Out of scope for v1:** real-time tactical battles (v1 uses auto-resolve), multiplayer, naval warfare, religion, family trees.

---

## 2. Core loop (one turn = one season)

```
Collect income ─► Build / recruit ─► Move armies ─► Battles & sieges ─► End turn (AI factions play)
      ▲                                                                          │
      └────────────────────── Next season: upkeep, food, events ◄────────────────┘
```

---

## 3. Functional requirements

### 3.1 Map and provinces

| ID | Requirement |
|---|---|
| MP-1 | The map has **about 30 provinces**. Each is a clickable polygon (`Polygon2D` + `Area2D`). |
| MP-2 | Provinces form a **graph**: each lists its neighbours. Armies move only between neighbours. |
| MP-3 | Each province has: owner, terrain, settlement level, population, buildings, garrison, and resource output. |
| MP-4 | Some provinces have a **river border** with a neighbour, or a **road** to it. |
| MP-5 | **Fog of war:** the player only sees armies in their own provinces and in neighbouring provinces. |
| MP-6 | The camera pans (drag / WASD) and zooms (mouse wheel). Map modes: political (owners), terrain, resources. |

**Terrain**

| Terrain | Move cost | Food output | Battle effect |
|---|---|---|---|
| Plains | 1 | high | cavalry +20% attack |
| Forest | 2 | low | cavalry −30% attack; archers −20% attack (no clear line of fire); defender +10% |
| Hills | 2 | medium | archers +20% when defending; attacker −10% |
| Mountains | 3 | very low | defender +30%; cavalry −50% |
| Marsh | 3 | low | everyone −20% attack; heavy units −30% |

| Border | Effect |
|---|---|
| River | attacker −25% the turn they cross; move cost +1 |
| Road | move cost −1 (minimum 1) |

### 3.2 Factions and turns

| ID | Requirement |
|---|---|
| FC-1 | v1 has **4 factions**: the player and 3 AI factions, each starting with a capital and 2 provinces. |
| FC-2 | A turn is one **season** (Spring, Summer, Autumn, Winter). |
| FC-3 | Turn order: the player plays first, then each AI faction. Battles happen when an army moves into an enemy province. |
| FC-4 | Each faction has a colour, banner and name. |

### 3.3 Resources

| Resource | Comes from | Used for |
|---|---|---|
| **Gold** | taxes (population), markets, trade | recruiting, unit upkeep, buildings |
| **Food** | farms, depends on terrain and season | feeding armies and population |
| **Wood** | forest provinces, lumber camps | buildings, archers' bows, siege engines |
| **Iron** | hill and mountain mines | swordsmen, heavy cavalry, armour upgrades |
| **Manpower** | population (5% per season) | every unit costs manpower to recruit |

| ID | Requirement |
|---|---|
| RS-1 | All resources are stored at the **faction level** (one shared pool). |
| RS-2 | The top bar shows each resource with its **change per turn** (e.g. Food 420 (+35)). |
| RS-3 | Hovering a resource shows a breakdown of where it comes from and where it goes. |

### 3.4 Food and supply

| ID | Requirement |
|---|---|
| FD-1 | Every unit eats food each turn (see unit table). The population also eats: 1 food per 1,000 people. |
| FD-2 | Farm output depends on season: **Spring ×1, Summer ×1.25, Autumn ×1.5 (harvest), Winter ×0.25**. |
| FD-3 | If food falls below 0: each army loses **10% of its men per turn** (starvation), and province happiness drops. |
| FD-4 | **Supply range:** an army in its own territory, or within 2 provinces of it, is supplied. An army further away **forages** from the province it's in: it takes food from that province, which can run out. When it does, the army loses 5% of its men per turn. |
| FD-5 | **Winter attrition:** armies outside their own territory in winter lose 5% of their men per turn, 10% in mountains. |
| FD-6 | A **Granary** building stores extra food so it can carry over winter. |

### 3.5 Unit types

| Unit | Role | HP | Attack | Defense | Speed (moves) | Range | Cost (gold / other) | Upkeep (gold / food) |
|---|---|---|---|---|---|---|---|---|
| Militia | cheap filler | 80 | 6 | 4 | 2 | melee | 30 / — | 1 / 1 |
| Spearmen | anti-cavalry | 100 | 8 | 10 | 2 | melee | 60 / 10 wood | 2 / 1 |
| Swordsmen | heavy infantry | 110 | 12 | 8 | 2 | melee | 90 / 15 iron | 3 / 1 |
| Archers | ranged | 70 | 10 | 4 | 2 | ranged | 70 / 15 wood | 2 / 1 |
| Crossbowmen | armour piercing ranged | 75 | 13 | 5 | 2 | ranged | 100 / 10 wood, 10 iron | 3 / 1 |
| Light cavalry | fast raider, flanker | 90 | 10 | 5 | 4 | melee | 110 / — | 4 / 2 |
| Heavy cavalry | shock charge | 130 | 15 | 10 | 3 | melee | 180 / 25 iron | 6 / 3 |
| Catapult | siege | 60 | 20 (vs walls) | 2 | 1 | ranged | 150 / 40 wood | 4 / 1 |

Each unit is a **regiment** of 100 men. HP and Attack scale with how many men are left.

### 3.6 Unit counters

Damage multiplier when the **row** unit attacks the **column** unit:

| Attacker ↓ / Defender → | Militia | Spear | Sword | Archer | Crossbow | Light cav | Heavy cav | Catapult |
|---|---|---|---|---|---|---|---|---|
| **Militia** | 1.0 | 0.8 | 0.7 | 1.0 | 1.0 | 0.8 | 0.6 | 1.5 |
| **Spearmen** | 1.1 | 1.0 | 0.75 | 1.0 | 1.0 | **2.0** | **2.0** | 1.5 |
| **Swordsmen** | 1.3 | **1.5** | 1.0 | 1.2 | 1.2 | 0.9 | 0.8 | 1.5 |
| **Archers** | 1.2 | **1.25** | 0.8 | 1.0 | 1.0 | 0.7 | 0.5 | 1.0 |
| **Crossbowmen** | 1.2 | 1.2 | **1.3** | 1.0 | 1.0 | 0.9 | **1.3** | 1.0 |
| **Light cavalry** | 1.2 | 0.5 | 0.9 | **2.0** | **2.0** | 1.0 | 0.7 | **2.0** |
| **Heavy cavalry** | 1.5 | 0.6 | 1.3 | **2.0** | 1.5 | 1.3 | 1.0 | **2.0** |
| **Catapult** | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 0.5 | 0.5 | 1.0 |

The rock-paper-scissors in short:

- **Spearmen beat cavalry** (cavalry charging into spears takes double damage).
- **Cavalry beats archers and siege** (fast units catch slow ranged units).
- **Archers beat spearmen** (slow, lightly armoured blocks of infantry).
- **Swordsmen beat spearmen** (better in close combat).
- **Crossbows beat armour** (swordsmen and heavy cavalry).
- **Catapults** are weak in a field battle but needed to break walls.

### 3.7 Armies and generals

| ID | Requirement |
|---|---|
| AR-1 | An **army** is a group of up to **12 regiments** led by a **general**. |
| AR-2 | Armies without a general can't leave their province (garrisons only). |
| AR-3 | Generals have **Command** (+% attack for the army), **Logistics** (−% food upkeep, + supply range) and **one trait** (e.g. "Horse Lord": cavalry +15%; "Siege Master": sieges 1 turn faster; "Cautious": defense +10%, attack −5%). |
| AR-4 | Generals gain experience from battles and can level up (choose a stat). |
| AR-5 | Armies can **merge**, **split**, and move regiments between each other when they're in the same province. |
| AR-6 | Damaged regiments recover **10% men per turn** in their own territory if they don't move, using manpower. |

### 3.8 Movement

| ID | Requirement |
|---|---|
| MV-1 | An army's **movement points** = the lowest Speed among its regiments. |
| MV-2 | Entering a province costs its terrain move cost (with road and river changes). |
| MV-3 | Clicking a destination shows the path and the number of turns it will take (pathfinding over the province graph with A*). |
| MV-4 | Entering a province with an **enemy army** stops movement and starts a battle. |
| MV-5 | Entering an undefended enemy province **occupies** it. A province with walls must be **besieged** first. |
| MV-6 | **Zone of control:** an army that moves next to an enemy army must stop. |

### 3.9 Battles (auto-resolve in v1)

| ID | Requirement |
|---|---|
| BT-1 | A battle runs in **3 phases**: **Ranged** (archers, crossbows, catapults shoot), **Charge** (cavalry attacks first and picks its best targets), then **Melee** (rounds until one side breaks or 6 rounds pass). |
| BT-2 | In each phase, every regiment picks a target. Melee units prefer the enemy they have the best multiplier against. |
| BT-3 | Damage = `Attack × counterMultiplier × terrainMod × generalMod × moraleMod × random(0.85–1.15) − Defense / 2`. |
| BT-4 | **Morale:** every army starts at 100 morale. Losing regiments, losing the general, and being outnumbered lower it. At 30 morale the army **routs**: it retreats to a neighbouring friendly province and loses 20% more men. |
| BT-5 | The defender gets the terrain bonus. The attacker gets the river penalty if crossing one. |
| BT-6 | After the battle, a **report** shows each regiment's losses, which counters mattered, and why the battle was won or lost. |
| BT-7 | The player can see a **battle forecast** (expected outcome: decisive win / win / close / loss / decisive loss) before attacking. |

### 3.10 Sieges

| ID | Requirement |
|---|---|
| SG-1 | Provinces with **walls** (Wooden palisade → Stone walls → Castle) must be besieged. |
| SG-2 | A siege lasts until the defender runs out of food (palisade 2 turns, stone walls 4, castle 6) or the attacker **assaults**. |
| SG-3 | An **assault** is a battle where the defender gets +50% defense (palisade), +100% (stone) or +150% (castle). Each catapult reduces this bonus by 25 percentage points. |
| SG-4 | The besieging army must stay in the province. If it leaves or is defeated, the siege ends. |

### 3.11 Provinces and buildings

| Building | Effect | Cost |
|---|---|---|
| Farm (Lv 1–3) | +food | 100 gold, 20 wood |
| Market (Lv 1–3) | +gold | 150 gold, 30 wood |
| Lumber camp | +wood (forest only) | 80 gold |
| Mine | +iron (hills/mountains only) | 120 gold, 20 wood |
| Granary | stores food over winter | 100 gold, 40 wood |
| Barracks | recruit Spearmen, Swordsmen | 150 gold, 40 wood |
| Archery range | recruit Archers, Crossbowmen | 150 gold, 50 wood |
| Stable | recruit cavalry | 200 gold, 40 wood |
| Siege workshop | recruit Catapults | 200 gold, 80 wood |
| Walls (palisade → stone → castle) | defense, siege length | 100 / 300 / 600 gold, wood & iron |

| ID | Requirement |
|---|---|
| PV-1 | Each province has **4 building slots** (capital: 6). One building can be built per province per turn. Buildings take 1–2 turns. |
| PV-2 | Recruiting takes **1 turn**. Each province can recruit up to 2 regiments per turn. |
| PV-3 | **Happiness** (0–100): lowered by high taxes, starvation, recent conquest; raised by garrisons and markets. Below 20, the province may **revolt** and spawn rebel militia. |
| PV-4 | The player sets a faction-wide **tax level** (low / normal / high), trading gold against happiness. |

### 3.12 Inventory (faction stockpile)

There is no item inventory per character. The faction **stockpile** holds Gold, Food, Wood and Iron, with a capacity:

| ID | Requirement |
|---|---|
| ST-1 | Food can be stored up to `500 + 500 × granaries`. Anything above that spoils at the end of the turn. |
| ST-2 | Wood and iron are stored up to `1,000 + 500 × capital level`. |
| ST-3 | Gold has no cap. |
| ST-4 | v2: generals can hold **equipment** (sword, armour, banner) found after battles that give small bonuses. |

### 3.13 AI

| ID | Requirement |
|---|---|
| AI-1 | Each AI faction has a **personality**: Aggressive, Defensive or Economic, which changes its weights. |
| AI-2 | Each turn the AI: builds economy buildings when food or gold is low; recruits to **counter** the armies it can see (e.g. sees cavalry → recruits spearmen); attacks neighbouring provinces where its forecast is "win" or better; defends threatened provinces. |
| AI-3 | The AI follows the same rules as the player (no free resources) on Normal difficulty. On Hard it gets +25% income. |

### 3.14 Diplomacy (minimal v1)

| ID | Requirement |
|---|---|
| DP-1 | Factions are either **at war** or **at peace** with each other. |
| DP-2 | The player can **propose peace** (accepted if the AI is losing) or **declare war**. |
| DP-3 | Breaking a peace treaty within 4 turns lowers happiness in all the player's provinces. |

### 3.15 Victory and defeat

| Condition | Result |
|---|---|
| Own **every capital** or **70% of provinces** | Victory |
| Lose your capital and have no other province with walls | Defeat |
| Turn 80 reached | The faction with the highest score wins (provinces, gold, armies) |

### 3.16 Save system

| ID | Requirement |
|---|---|
| SV-1 | Save at any time during the player's turn. 5 manual slots + 1 autosave at the start of each turn. |
| SV-2 | Saves include map state, factions, resources, armies, sieges, AI state and the random seed. |
| SV-3 | Saves go in `user://` (browser storage on the web). |

---

## 4. Data model (Godot Resources)

```
UnitTypeData   id, name, hp, attack, defense, speed, ranged, cost{gold, wood, iron, manpower},
               upkeep{gold, food}, required_building, sprite
CounterTable   matrix[attacker_id][defender_id] → multiplier
TerrainData    id, move_cost, food_mod, battle_mods{unit_class → mod}
BuildingData   id, name, cost{}, build_turns, effects{}, allowed_terrain[], max_level
ProvinceData   id, name, polygon, neighbours[], river_borders[], roads[], terrain, base_food,
               base_gold, population
TraitData      id, name, modifiers{}
```

Runtime state (saved):

```
Province   owner, buildings[], garrison, happiness, food_stock, siege
Army       id, owner, general, regiments[{type, men}], province, movement_left, path[]
Faction    id, name, color, resources{}, tax_level, relations{}, ai_personality
```

---

## 5. Screens

1. Title (New campaign / Load / Settings)
2. Faction select
3. Campaign map with top resource bar, end-turn button, minimap
4. Province panel (buildings, recruit, garrison, happiness)
5. Army panel (regiments, general, merge/split)
6. Battle forecast popup and battle report
7. Diplomacy screen
8. End-of-match screen

---

## 6. Non-functional requirements

| ID | Requirement |
|---|---|
| NF-1 | An AI turn takes less than 2 seconds for all 3 AI factions combined. |
| NF-2 | Battles use a seeded random number generator, so a replayed save gives the same result. |
| NF-3 | 60 fps panning and zooming the map, on desktop and in the browser. |
| NF-4 | All units, buildings, terrain and counters are data (`.tres`), so balance can be changed without code changes. |

---

## 7. Milestones

| Milestone | Contents |
|---|---|
| **M1 — Map** | Province map with 10 provinces, selection, neighbours, pan and zoom, map modes |
| **M2 — Armies and movement** | Armies with regiments, pathfinding, movement points, turns |
| **M3 — Battles** | Auto-resolve with the 3 phases, counter table, terrain, morale, battle report |
| **M4 — Economy** | Gold, food, wood, iron, manpower; buildings; recruiting; seasons; food and supply |
| **M5 — AI** | 3 AI factions with personalities, sieges, victory and defeat |
| **M6 — Full map** | 30 provinces, generals and traits, diplomacy, save/load, web export |

M1–M4 are built. M5 and M6 are replaced by the version 2 milestones in section 8.8.

---

## 8. Version 2: the S&T: Medieval Wars style

### 8.1 What we take from the reference game

*Strategy & Tactics: Medieval Wars* (HeroCraft) is a turn-based Android game on a map of European regions. It has 4 historical campaigns (English, French, Crusaders, and a Viking campaign), 25 missions, 21 unit types, economic and military research, campaign missions with a turn limit, and hotseat multiplayer.

What we keep, because it's what made the game memorable:

- **Every unit is its own token on the map.** Each token shows its unit type as an icon (horse, infantry, bow…), a **health bar** underneath and a **soldier count** (1–20).
- **Tap a unit, then tap a neighbouring region** to move there, attack it or retreat into it.
- **A failed attack sends the attacker back** to the region it attacked from. A beaten defender retreats to another friendly region, or is destroyed if it has nowhere to go.
- **Civilizations with their own troops**, such as Viking Berserkers.
- **Campaigns of missions** with objectives and a turn limit.
- **Economic and military research.**
- **Hotseat multiplayer** on one device.

What we do differently:

- **No paywall.** The reference game had 3 free campaigns and sold the rest. Here, 3 civilizations are open from the start and more **unlock by finishing campaigns**.
- **One unit per region, as in the original.** An earlier draft allowed 4 units per region to stop "one big stack" play; the stack limit is now **1** because the original works that way: each region holds one figure group of up to 20 soldiers, so position and unit choice matter.
- **Gold only.** Like the original, the economy is gold alone (8.9); food, wood, iron and manpower are gone.
- **Generous turn limits.** Reviewers disliked strict turn limits. Missions use turn limits for a **star rating** (3 stars if fast), and only lose the mission when the limit is far exceeded.
- **Original content.** Our own map, region names, unit names, art and text. Only the mechanics are inspired by the reference game.

### 8.2 Units (replaces armies of regiments, 3.7)

| ID | Requirement |
|---|---|
| UT-1 | A **unit** has a type, an owner, **soldiers** (1–20) and **HP**. Max HP = the type's HP; soldiers = ceil(HP ÷ HP per soldier). |
| UT-2 | On the map, each unit is a **group of 3–5 painted figures** (2–3 riders, 1–2 engines) on its region, rendered from CC0 3D models with the faction's colour on tunics and shields, with the faction's **banner on a pole** behind them, gold **chevrons** for rank, a thin **health bar** (green → yellow → red, white tip) and the **soldier number** in italic below. A light-blue pennant marks a general. A **red X** beside the bar shows a unit that has no moves left this turn. |
| UT-3 | **A region holds one unit.** Moving a unit into a friendly region held by the **same type** merges them (up to 20 soldiers; the rest stay behind). Two friendly units can **swap** regions. Any other move into an occupied friendly region is blocked. Recruiting needs an empty region of your own, or reinforces a weakened unit of the same type there. |
| UT-4 | A unit can **split its soldiers across several orders** a turn (OR-3); each order is a detachment. **Cavalry detachments get two steps**: a move, then a move or an attack. Infantry, archers and siege detachments get one. |
| UT-5 | **No generals.** (Removed in version 6, as in the reference game.) |
| UT-6 | **No experience or ranks.** Troops get stronger only through research (version 6: the Forge between missions). |
| UT-7 | **Healing:** a unit that neither moves nor fights regains 2 soldiers per turn in its own region, 4 with Barracks. Each soldier costs gold. |
| UT-8 | **Merging** adds the soldiers together. |

### 8.3 Orders: plan with arrows, resolve with the hourglass

| ID | Requirement |
|---|---|
| OR-1 | **Planning.** Click a unit to select it; nearby regions show what it can do: **blue** to move, **red** to attack, **grey** blocked. Clicking a region opens the slider window (OR-3) and then gives the order, drawn as a big **spear-shaped arrow** (blue move, red attack, gold outline, tapered tail) with a small shield showing how many soldiers go. The unit **stays selected**, so further arrows can send the rest to other neighbouring regions. Nothing happens yet. |
| OR-2 | **Cancel.** Clicking an **arrow** cancels that one order and frees its soldiers. Clicking the unit again just selects it and lists its orders. **Right-click the unit**, press **U** or the **Cancel all orders** button to cancel all of them. Re-opening an order's slider (click its target again) also offers **Remove this order**. Recruit, mercenary and build orders are also queued until the turn resolves. |
| OR-3 | **Split a unit.** Every arrow, march or attack, opens a window with a slider for **how many soldiers go**, by default all not yet given an order; ranged units attacking get two sliders, **shoot** (bow) and **melee** (crossed swords). A unit may have several orders, each a **detachment**: e.g. of 20 soldiers, 14 attack region A, 4 march to empty region B and 2 stay home. Soldiers with no order **stay home**. A unit sends **at most one detachment to each region**; clicking an order's target again changes its count. No two detachments of a unit may pass through or end in the same region. A detachment may march into a friendly region held by the **same type** (a merge, up to 20); only a **whole unit** may move into one held by another type (a swap). A unit with a single order for every soldier is replaced by a new arrow, as before. While some soldiers have no order the unit shows a small shield with **how many stay home**; the **red X** appears only once every soldier has an order and no cavalry detachment has a step left. A siege takes the whole unit. |
| OR-4 | **Ranged units** shoot from their own region (longbows 2 regions away); only enemy ranged units shoot back, and horse archers (Mamluks) ride off before anyone can. Ranged attacks never capture a region. |
| OR-5 | **Retreat** is simply a blue arrow into one of your regions, for the whole unit or a detachment. A detachment that marches into an **empty** friendly or neutral region becomes a **new unit** of the same type there. |
| OR-6 | The attack window shows a **forecast** (BT-7) before the order is confirmed. |
| OR-7 | **Who plans when.** Every faction plans against the same state: the humans one after another (in hotseat behind a "pass the device" screen), then the AI. The **hourglass** ends your planning; when the last faction is done, the turn resolves. |
| OR-8 | **Saves and the AI.** A save made mid-planning keeps every unit's orders and counts (save version 3; a version 1–2 save's single order loads as one detachment). The computer mostly gives single orders, but a big unit attacking with a decisive forecast leaves a fifth of its soldiers (at least 3) to hold an empty region of its own that enemies threaten. |

### 8.4 Resolution (adapts 3.9)

| ID | Requirement |
|---|---|
| BR-0 | **Detachments.** When the turn resolves, a unit with several orders, or one order for only some of its soldiers, splits into detachments, each a unit of the same type with the same rank and experience, and **HP shared out per soldier** (a detachment never gets less than one soldier's worth). The soldiers with no order stay home as the original unit and **keep its general**; if every soldier leaves, the original unit (and its general) leads the **largest** detachment. A unit that splits doesn't heal that turn. The detachments then resolve like any order below. |
| BR-1 | Orders resolve in a fixed, seeded order: **1.** all ranged volleys; **2.** head-on attacks (A attacks B while B attacks A) as one field battle; **3.** moves into empty or friendly regions, with swaps and merges; units of different factions moving into the same empty region **fight for it**; **4.** sieges, then attacks on occupied regions: several attackers on one region fight **one after another, strongest first**, and later attackers face whatever is left; **5.** detachments of one unit that end in the same region (back home after a failed attack, a blocked march or a volley) **rejoin**, keeping their HP; then captures; **6.** the economy and upkeep. Steps 1–4 run again for cavalry detachments' second step. A unit that split takes in no other unit that turn, so its detachments always fit when they return, and **one unit per region** always holds afterwards (a final guard merges or moves any unit that would share a region). |
| BR-2 | A **failed attacker** ends the turn in the region it attacked from (shown marching out and back). A failed detachment re-merges with the soldiers at home, or, if nobody is left there, becomes the unit there. A home region that every soldier left stays yours. |
| BR-3 | A **beaten defender** retreats to a free neighbouring region of its own, or is destroyed if there is none. A winning melee attacker (or detachment) moves in only if the region is now empty, and holds it as its own unit. |
| BR-4 | After the hourglass, the turn **plays out on the map** in the same order: split units' detachments step apart as **separate small figure groups**, all volleys together (arrows arc, catapults throw stones), then marches, clashes (dust and sparks, the defender recoils, numbers drain), retreats, detachments marching home into their unit, units that fade and sink, and captures (the new colour sweeps across the region and a banner drops in). A speed setting (Normal, Fast, Off) and a click skip it; computer factions play faster. The results are decided before anything is shown. |
| BR-5 | The same orders with the same seed always give the same result. |

### 8.5 Civilizations

Every civilization uses the base roster from 3.5 plus **one or two special units** and a **national bonus**. The base roster is Militia, Spearmen, Swordsmen, Archers, Crossbowmen, Light cavalry, Heavy cavalry, Catapult and **Pikemen** (heavy spear: ×2.5 against cavalry, but archers and swordsmen cut them up; needs Chain Mail).

| Civilization | Status | Special units | National bonus |
|---|---|---|---|
| **Norse (Vikings)** | open | **Berserker** (infantry: attack rises as HP falls, never routs), **Huscarl** (heavy axe infantry) | Raiding: a move can go 2 regions along the coast, through an empty coastal region |
| **Anglish (English)** | open | **Longbowman** (archer: +1 range — can shoot 2 regions away), **Yeoman** (cheap spear) | +15% defense in their own regions |
| **Frankish (French)** | open | **Knight** (heavy cavalry, +25% charge), **Sergeant** (armoured spear) | Cavalry recruit 20% cheaper |
| **Crusader Orders** | open | **Brother Knight** (best-armoured heavy cavalry, +15% charge, needs Stirrups), **Mounted Sergeant** (tougher light cavalry, no tech needed) | Hospitals: resting units heal 2 more soldiers a turn |
| **Byzantine** | unlocks after any campaign | **Cataphract** (armoured horse), **Varangian Guard** | +25% gold from markets |
| **Saracen** | unlocks after two campaigns | **Mamluk** (horse archer: shoots and rides off untouched), **Ghazi** | Mercenaries cost 25% less (attrition no longer exists, 8.9) |

Across base and special units this gives **21 unit types**, the same as the reference game. The new ones fit the counter table (data/counters.tres): Pikemen have their own row and column; Brother Knights fight as heavy cavalry and Mounted Sergeants as light cavalry.

| New unit | Class | HP | Attack | Defense | Moves | Gold | Strong against | Weak against |
|---|---|---|---|---|---|---|---|---|
| Pikemen | infantry | 105 | 8 | 11 | 1 | 95 | all cavalry (×2.5; cavalry hits them at ×0.35–0.4) | archers (×1.5), crossbows (×1.4), swordsmen (×1.7) |
| Brother Knight | heavy cavalry | 145 | 15 | 13 | 2 | 280 | archers, swordsmen, other heavy horse | spears and pikes |
| Mounted Sergeant | light cavalry | 110 | 11 | 8 | 2 | 145 | archers, crossbows, catapults | spears and pikes |

### 8.6 Campaigns, missions and modes

| ID | Requirement |
|---|---|
| CP-1 | Every civilization has a **campaign of 3 to 5 missions** on its own scenario map (12–20 regions): **25 missions** in all, as in the reference game (see the table below). |
| CP-2 | A mission has: a starting setup (owners, units, gold, walls, researched techs), **objectives** — capture these regions, hold a region for N turns, destroy a faction, **kill or capture a named general**, **survive N turns** (often with little gold), or conquest — a **par turn count** and a **hard limit** (par × 2). Losing your capital loses the mission. |
| CP-3 | Finishing at or under par gives 3 stars; under 1.5 × par 2 stars; otherwise 1 star. Passing the hard limit loses the mission. |
| CP-4 | Missions unlock in order. Finishing campaigns unlocks civilizations (8.5); the Byzantine and Saracen campaigns open when their civilization does. Each campaign starts with an easy capture mission and ends with its hardest, and `tools/sim_campaigns.gd` plays every mission with AI stand-ins to check the ramp. |
| CP-5 | **Skirmish:** pick a map, your civilization, 1–3 AI opponents and difficulty. Win by conquest. |
| CP-6 | **Hotseat:** 2–4 human players take turns on one device. A "pass the device" screen hides the map between turns. |
| CP-7 | Mission briefings and victory/defeat screens with short text. |

| Campaign | Map | Missions (objective) |
|---|---|---|
| **Norse — The Saga of the Sea-Wolves** | The Fjordmark | 1 Landfall (capture 3 settlements) · 2 The Abbey Road (take Greyhaven's hall) · 3 The Lean Winter (survive 6 turns with 100 gold) · 4 Blood-Feud (kill or capture Sigrid) · 5 Throne of the Fjordmark (conquest) |
| **Anglish — The Longbow Wars** | The Wealdshire | 1 Raiders on the Coast (hold Kingsbarrow 5 turns) · 2 Mustering the Shires (capture 3 shires) · 3 Burn the Longships (destroy the raiders) · 4 Hunt the Black Count (kill or capture Baudouin) · 5 Crown of the Weald (take two capitals) |
| **Frankish — Banners of the Valmont** | The Valmont | 1 The Unruly Marches (capture 3 marches) · 2 The Northmen Come (hold Belcourt 6 turns against an invasion) · 3 The Siege of Brévine (take the keep) · 4 The Lowland Towns (capture 3 river towns) · 5 King of the Valmont (conquest) |
| **Crusader Orders — The Sunward Vow** | The Sunward Coast | 1 The Pilgrims' Road (capture 3 villages) · 2 The Keep on the Rock (hold Castel Aubade 6 turns) · 3 The Emir's Champion (kill or capture Rashid) · 4 The Kingdom by the Sea (take two capitals) |
| **Byzantine — The Purple and the Gold** | The Porphyry Straits | 1 The Rebel Strategos (take Theronike) · 2 The Empty Treasury (survive 6 turns from 100 gold) · 3 The Empire Restored (conquest) |
| **Saracen — Banners of the Sands** | The Amber Sands | 1 Riders of the Wadi (capture 3 oases) · 2 The Iron Brothers (kill or capture Aimon) · 3 Sultan of the Sands (take two capitals) |

### 8.7 Research (new)

| ID | Requirement |
|---|---|
| RE-1 | Two research trees, **Economy** and **Military**, each with about 6 techs in 3 tiers. |
| RE-2 | One tech is researched at a time. Research costs gold and takes 2–4 turns. |
| RE-3 | Economy (gold only, 8.9): Crop Rotation (+1 gold per region), Coinage (+15% gold), Mining (+3 gold from hills, +5 from mountains), Logistics (−20% upkeep), Heavy Plough (+2 gold from plains), Guilds (+25% from markets). |
| RE-4 | Military examples: Chain Mail (+10% infantry defense), Composite Bows (+15% ranged attack), Stirrups (+15% cavalry charge), Siege Engineering (unlocks Catapult, −1 siege turn), Drill (start units as Veteran). |
| RE-5 | Some units need a tech before they can be recruited: Pikemen need Chain Mail; heavy cavalry, Knights, Cataphracts and Brother Knights need Stirrups; Catapults need Siege Engineering. |

### 8.8 Version 2 milestones

| Milestone | Contents |
|---|---|
| **V1 — Unit tokens** | Unit tokens with icon, health bar, soldier count and rank; stack limit 4; tap-to-select with green/red/grey neighbours; move, attack, ranged attack, retreat and undo; battle rules BR-1..BR-5; healing and merging; recruiting creates units. Economy from M4 adapted to units. |
| **V2 — AI and missions** | AI turns for every non-player faction (personalities, recruit to counter, attack when the forecast is good, defend, retreat damaged units); sieges (3.10); mission objectives, par and hard turn limits, stars; victory and defeat screens; save and load. |
| **V3 — Civilizations and campaigns** | Norse, Anglish and Frankish with special units and bonuses; 3 campaigns × 3 missions on original maps; campaign select and briefings; Byzantine and Saracen unlocks; skirmish mode. |
| **V4 — Research, hotseat and mobile** | Both research trees; hotseat for 2–4 players; title screen and settings; touch controls (tap, pinch zoom, drag pan); Android and web export presets. |
| **V5 — Campaign expansion** | The Crusader Orders (open) with Brother Knight, Mounted Sergeant and hospitals; Pikemen in the base roster (21 unit types); campaigns for Crusader, Byzantine and Saracen on three new maps; Norse, Anglish and Frankish campaigns grown to 5 missions; general-hunt and survival objectives; 25 missions. |

### 8.9 Gold economy, mercenaries and the map (replaces 3.3, 3.4 and 3.12)

This decision replaces sections 3.3 (resources), 3.4 (food and supply) and 3.12 (stockpile): the game has one resource, **gold**, as in the original.

| ID | Requirement |
|---|---|
| GE-1 | Every region pays its owner **10 gold** a turn; a town pays 15, the capital 10 more, and each market level 8 more. The number is shown on the map under the region's name with a coin-stack icon. |
| GE-2 | Gold pays for recruiting, mercenaries, healing, buildings, research and unit upkeep. Costs that used wood or iron were converted to gold (1 wood = 1 gold, 1 iron = 2 gold) so the balance stays about the same. |
| GE-3 | If gold would go negative, 5% of every unit deserts and the treasury stays at 0. |
| GE-4 | Food, wood, iron, manpower, starvation, foraging, supply range, winter attrition, spoilage and storage caps are gone. Taxes and happiness are dropped too: with gold as the only resource they no longer trade off against anything, so revolts are gone as well. |
| GE-5 | **Mercenaries** can be hired only in regions with a **town** or a **camp** icon. A town offers spearmen, crossbowmen and swordsmen; a camp militia, archers and light cavalry; each starts with 2 available and restocks 1 every 3 turns (up to 4). They cost 1.5 × the unit's gold price, take the region's one recruit slot for the turn, and arrive at the end of the turn. |
| GE-6 | The map is a parchment political map: clear faction colours, a thin dark border inside a faction and a **double line** (dark plus each side's colour) where two factions meet, a dark teal sea with paper grain, region names in a serif map font, a crown for the capital, a tower for walls, a tent for a camp, houses for a town, and small ships on coastal regions with dotted lanes for coastal raids. |
| GE-7 | The HUD is minimal: a riveted plaque at the top with the gold and the turn; wooden shield buttons in the corners for recruit, treasury, menu, messages and the end-turn hourglass; a cloth banner on the right listing the turn's orders (green) and battles (red); and faint calligraphy across the map at each turn ("Turn: …"). Everything else is in popups. |

### 8.10 Sound, music and the tutorial

| ID | Requirement |
|---|---|
| SM-1 | **Music** on its own bus: a menu track, two calm map tracks that alternate, and a victory and a defeat sting. The music crossfades between the menu and the map. All audio is CC0 and credited in CREDITS.md. |
| SM-2 | **Sound effects** on their own bus: button clicks, selecting a unit, placing an order, the hourglass, and during playback (BR-4) footsteps or hooves for marches, arrow volleys, catapult throws and impacts, sword clashes, a destroyed unit and a horn for a capture; coins when recruiting or hiring. |
| SM-3 | **Music and Sound volume** sliders in Settings, saved with the other settings. With no audio files or no audio device the game is simply silent. |
| TU-1 | A **tutorial** mission on a 7-region map, reachable from the title menu, teaches one thing per step in a parchment hint box and waits for the player to do it: select, march, cancel, attack with the split slider, cavalry's two steps and the red X, the hourglass, gold income, mercenaries and recruiting. Any step can be skipped, and the tutorial left. |
| TU-2 | A new player (no campaign progress) is asked once whether to play the tutorial. |

