"""Generates the campaigns in data/campaigns/ (PRD CP-1..CP-4, CP-7): one per
open civilization, 3 missions each, on that civilization's map.

Each mission names its factions, where they start and how many regions they
hold; territories grow outwards from the start regions. Objectives that name
regions are worked out from the map, so they always exist.

    python3 tools/make_campaigns.py
"""

import json
import re
from collections import deque

CIV_COLORS = {"norse": "#2e708f", "anglish": "#b33b3b", "frankish": "#2f4fa8", "byzantine": "#7a40a0", "saracen": "#3d8a4a"}
CAPITAL_BUILDINGS = {"farm": 1, "market": 1, "barracks": 1, "archery_range": 1}


def load_map(map_id):
    with open(f"data/maps/{map_id}.json") as f:
        data = json.load(f)
    return data, {r["id"]: r["neighbours"] for r in data["regions"]}, {r["id"]: r["name"] for r in data["regions"]}


def distances(graph, start):
    dist = {start: 0}
    queue = deque([start])
    while queue:
        current = queue.popleft()
        for nxt in graph[current]:
            if nxt not in dist:
                dist[nxt] = dist[current] + 1
                queue.append(nxt)
    return dist


def grow(graph, starts_and_sizes):
    """Grows each faction's territory outwards from its start, taking turns."""
    owners = {start: faction for faction, start, _ in starts_and_sizes}
    remaining = {faction: size - 1 for faction, _, size in starts_and_sizes}
    frontier = {faction: deque([start]) for faction, start, _ in starts_and_sizes}
    progress = True
    while progress:
        progress = False
        for faction, _, _ in starts_and_sizes:
            while remaining[faction] > 0 and frontier[faction]:
                current = frontier[faction][0]
                free = [n for n in sorted(graph[current]) if n not in owners]
                if not free:
                    frontier[faction].popleft()
                    continue
                owners[free[0]] = faction
                frontier[faction].append(free[0])
                remaining[faction] -= 1
                progress = True
                break
    return owners


def mission(map_id, mission_id, title, player, factions, objectives, par, briefing, victory, defeat,
            walls=None, neutral_garrison=True, extra_buildings=None):
    """factions: list of dicts {id, name, civ, start (slot index or region), size, ai, units}."""
    data, graph, names = load_map(map_id)
    starts = []
    for faction in factions:
        start = faction["start"]
        if isinstance(start, int):
            start = data["starts"][start]
        faction["start_region"] = start
        starts.append((faction["id"], start, faction["size"]))
    owners = grow(graph, starts)

    # Objectives can name things by role; turn them into real regions.
    player_start = next(f["start_region"] for f in factions if f["id"] == player)
    resolved = []
    for objective in objectives:
        objective = dict(objective)
        if objective.get("regions") == "nearest_neutral":
            dist = distances(graph, player_start)
            neutral = sorted((r for r in graph if r not in owners), key=lambda r: (dist[r], r))
            objective["regions"] = neutral[: objective.pop("count")]
        elif isinstance(objective.get("regions"), list):
            objective["regions"] = [
                next(f["start_region"] for f in factions if f["id"] == r[len("capital:"):]) if r.startswith("capital:") else r
                for r in objective["regions"]
            ]
        if objective.get("region") == "capital:" + player:
            objective["region"] = player_start
        resolved.append(objective)

    units = []
    for faction in factions:
        territory = [r for r, f in owners.items() if f == faction["id"]]
        territory.sort(key=lambda r: (r != faction["start_region"], r))
        for i, unit_type in enumerate(faction["units"]):
            region = territory[min(i // 4, len(territory) - 1)]
            entry = {"owner": faction["id"], "region": region, "type": unit_type}
            if i == 0:
                entry["general"] = {"name": faction["general"], "command": 2, "logistics": 2}
            units.append(entry)
    if neutral_garrison:
        for region in sorted(graph):
            if region not in owners and sum(map(ord, region)) % 3 == 0:
                units.append({"owner": "neutral", "region": region, "type": "militia", "soldiers": 12})

    buildings = {}
    for faction in factions:
        buildings[faction["start_region"]] = dict(CAPITAL_BUILDINGS)
    for slot, level in (walls or {}).items():
        region = next(f["start_region"] for f in factions if f["id"] == slot)
        buildings[region]["walls"] = level
    for faction_id, extra in (extra_buildings or {}).items():
        region = next(f["start_region"] for f in factions if f["id"] == faction_id)
        buildings[region].update(extra)

    return {
        "id": mission_id, "name": title, "map": map_id,
        "factions": [{"id": f["id"], "name": f["name"], "civ": f["civ"], "color": CIV_COLORS[f["civ"]] if f["id"] == player
                      else f.get("color", CIV_COLORS[f["civ"]]), "human": f["id"] == player, "ai": f.get("ai", "balanced")}
                     for f in factions],
        "owners": owners,
        "capitals": {f["id"]: f["start_region"] for f in factions},
        "buildings": buildings,
        "units": units,
        "mission": {"player": player, "par": par, "objectives": resolved,
                    "briefing": briefing, "victory_text": victory, "defeat_text": defeat},
    }


def write(campaign_id, civ, name, description, missions):
    for i, m in enumerate(missions):
        m["campaign"] = campaign_id
        m["mission_index"] = i
    data = {"id": campaign_id, "civ": civ, "name": name, "description": description, "missions": missions}
    text = json.dumps(data, indent=1, ensure_ascii=False)
    text = re.sub(r"\[\s+([^\[\]\{\}]*?)\s+\]", lambda m: "[" + re.sub(r"\s*\n\s*", " ", m.group(1)) + "]", text)
    with open(f"data/campaigns/{campaign_id}.json", "w") as f:
        f.write(text + "\n")
    print(campaign_id, [m["name"] for m in missions])


# --- Norse: the Saga of the Sea-Wolves, on the Fjordmark ---------------------------------

write("norse", "norse", "The Saga of the Sea-Wolves",
      "Jarl Hakon's raiders sail south to carve a kingdom from the Fjordmark.", [
    mission("fjordmark", "norse_1", "Landfall", "norse", [
        {"id": "norse", "name": "Hakon's Raiders", "civ": "norse", "start": 0, "size": 2, "general": "Hakon",
         "units": ["berserker", "spearmen", "archers", "huscarl"]},
        {"id": "elmsworth", "name": "Thanes of Elmsworth", "civ": "anglish", "start": 1, "size": 3, "general": "Eadric",
         "units": ["yeoman", "spearmen", "archers"], "ai": "defensive"},
    ], [{"type": "capture", "regions": "nearest_neutral", "count": 3}], 5,
        "The longships are beached. Seize the three settlements nearest the shore before the thanes muster.",
        "The coast is ours. The skalds will sing of this landfall.",
        "The raid ends in ash and cold water."),
    mission("fjordmark", "norse_2", "The Abbey Road", "norse", [
        {"id": "norse", "name": "Hakon's Raiders", "civ": "norse", "start": 0, "size": 3, "general": "Hakon",
         "units": ["berserker", "berserker", "huscarl", "archers", "spearmen", "light_cavalry"]},
        {"id": "greyhaven", "name": "Lords of Greyhaven", "civ": "anglish", "start": 3, "size": 5, "general": "Wulfstan",
         "units": ["yeoman", "longbowman", "spearmen", "swordsmen", "archers"], "ai": "balanced"},
    ], [{"type": "capture", "regions": ["capital:greyhaven"]}], 9,
        "Greyhaven's lords hide behind a palisade with the silver of three abbeys. Take their hall.",
        "Greyhaven falls, and its silver pays for a hundred new ships.",
        "Greyhaven's bowmen hold the road.", walls={"greyhaven": 1}),
    mission("fjordmark", "norse_3", "Throne of the Fjordmark", "norse", [
        {"id": "norse", "name": "Jarldom of Hakon", "civ": "norse", "start": 0, "size": 4, "general": "Hakon",
         "units": ["berserker", "huscarl", "huscarl", "archers", "spearmen", "light_cavalry", "berserker"]},
        {"id": "kaldvik", "name": "Kaldvik Rebels", "civ": "norse", "start": 2, "size": 4, "general": "Sigrid",
         "units": ["berserker", "spearmen", "archers", "huscarl"], "ai": "aggressive", "color": "#a8742c"},
        {"id": "stonereach", "name": "Franks of Stonereach", "civ": "frankish", "start": 1, "size": 4, "general": "Odo",
         "units": ["knight", "sergeant", "crossbowmen", "spearmen"], "ai": "balanced"},
    ], [{"type": "conquest"}], 14,
        "A rival jarl and a Frankish count both claim the Fjordmark. There can be only one throne.",
        "Hakon is crowned king of the Fjordmark. The saga is complete.",
        "Another sits on the throne Hakon bled for."),
])

# --- Anglish: the Longbow Wars, on the Wealdshire ----------------------------------------

write("anglish", "anglish", "The Longbow Wars",
      "Queen Elswyth must hold the Weald against raiders from the sea and a grasping neighbour.", [
    mission("wealdshire", "anglish_1", "Raiders on the Coast", "weald", [
        {"id": "weald", "name": "Kingdom of the Weald", "civ": "anglish", "start": 0, "size": 3, "general": "Elswyth",
         "units": ["longbowman", "yeoman", "yeoman", "spearmen", "archers"]},
        {"id": "raiders", "name": "Gullmouth Raiders", "civ": "norse", "start": 3, "size": 2, "general": "Ulf",
         "units": ["berserker", "berserker", "huscarl", "archers", "spearmen"], "ai": "aggressive"},
    ], [{"type": "hold", "region": "capital:weald", "turns": 5}], 6,
        "Longships have been sighted. Hold Kingsbarrow for five turns until the fyrd arrives.",
        "The raiders' fury broke on our walls of bowmen.",
        "Kingsbarrow burns.", walls={"weald": 1}),
    mission("wealdshire", "anglish_2", "Burn the Longships", "weald", [
        {"id": "weald", "name": "Kingdom of the Weald", "civ": "anglish", "start": 0, "size": 4, "general": "Elswyth",
         "units": ["longbowman", "longbowman", "yeoman", "swordsmen", "light_cavalry", "spearmen"]},
        {"id": "raiders", "name": "Gullmouth Raiders", "civ": "norse", "start": 3, "size": 3, "general": "Ulf",
         "units": ["berserker", "huscarl", "archers", "spearmen", "berserker"], "ai": "balanced"},
    ], [{"type": "destroy", "faction": "raiders"}], 10,
        "Carry the war to Gullmouth and burn the raiders out of the Weald for good.",
        "No longship will beach on our shore again.",
        "The raiders still hold the coast."),
    mission("wealdshire", "anglish_3", "Crown of the Weald", "weald", [
        {"id": "weald", "name": "Kingdom of the Weald", "civ": "anglish", "start": 0, "size": 4, "general": "Elswyth",
         "units": ["longbowman", "longbowman", "yeoman", "yeoman", "swordsmen", "heavy_cavalry", "archers"]},
        {"id": "ashcombe", "name": "Count of Ashcombe", "civ": "frankish", "start": 1, "size": 4, "general": "Baudouin",
         "units": ["knight", "sergeant", "crossbowmen", "spearmen", "knight"], "ai": "aggressive"},
        {"id": "wyndle", "name": "Wyndle Free Towns", "civ": "anglish", "start": 2, "size": 3, "general": "Godric",
         "units": ["yeoman", "archers", "spearmen"], "ai": "defensive", "color": "#c07a3a"},
    ], [{"type": "capture", "regions": ["capital:ashcombe", "capital:wyndle"]}], 12,
        "Unite the Weald: take Ashcombe from its Frankish count and bring the free towns of Wyndle under the crown.",
        "Elswyth is crowned Queen of all the Weald.",
        "The Weald stays divided.", walls={"ashcombe": 2}),
])

# --- Frankish: Banners of the Valmont, on the Valmont ------------------------------------

write("frankish", "frankish", "Banners of the Valmont",
      "Duke Robert of Belcourt rides out to make himself king of the Valmont.", [
    mission("valmont", "frankish_1", "The Unruly Marches", "belcourt", [
        {"id": "belcourt", "name": "Duchy of Belcourt", "civ": "frankish", "start": 0, "size": 3, "general": "Robert",
         "units": ["knight", "sergeant", "crossbowmen", "light_cavalry"]},
        {"id": "brevine", "name": "Lords of Brévine", "civ": "frankish", "start": 1, "size": 3, "general": "Aimery",
         "units": ["spearmen", "crossbowmen", "sergeant"], "ai": "defensive", "color": "#8a6a30"},
    ], [{"type": "capture", "regions": "nearest_neutral", "count": 3}], 6,
        "The marches beyond Belcourt answer to no one. Bring three of them under your banner.",
        "The marches bow to Belcourt.",
        "The marches stay wild."),
    mission("valmont", "frankish_2", "The Siege of Brévine", "belcourt", [
        {"id": "belcourt", "name": "Duchy of Belcourt", "civ": "frankish", "start": 0, "size": 4, "general": "Robert",
         "units": ["knight", "knight", "sergeant", "sergeant", "crossbowmen", "catapult", "spearmen"]},
        {"id": "brevine", "name": "Lords of Brévine", "civ": "frankish", "start": 1, "size": 4, "general": "Aimery",
         "units": ["sergeant", "crossbowmen", "spearmen", "swordsmen", "archers"], "ai": "defensive", "color": "#8a6a30"},
    ], [{"type": "capture", "regions": ["capital:brevine"]}], 10,
        "Lord Aimery has shut himself in his stone keep. Besiege it or storm it, but take Brévine.",
        "The keep of Brévine opens its gates.",
        "Brévine's walls hold.", walls={"brevine": 2}, extra_buildings={"belcourt": {"siege_workshop": 1}}),
    mission("valmont", "frankish_3", "King of the Valmont", "belcourt", [
        {"id": "belcourt", "name": "Kingdom of Belcourt", "civ": "frankish", "start": 0, "size": 5, "general": "Robert",
         "units": ["knight", "knight", "sergeant", "sergeant", "crossbowmen", "crossbowmen", "light_cavalry", "spearmen"]},
        {"id": "chaumiere", "name": "Norse of Chaumière", "civ": "norse", "start": 2, "size": 4, "general": "Ragnvald",
         "units": ["berserker", "huscarl", "archers", "spearmen"], "ai": "aggressive"},
        {"id": "vaudrey", "name": "Anglish of Vaudrey", "civ": "anglish", "start": 3, "size": 4, "general": "Edwin",
         "units": ["longbowman", "yeoman", "yeoman", "swordsmen"], "ai": "balanced"},
    ], [{"type": "conquest"}], 14,
        "Norse settlers and Anglish adventurers have carved out holdings in the Valmont. Drive them out and take the crown.",
        "Robert is crowned King of the Valmont.",
        "The Valmont slips from Robert's grasp."),
])
