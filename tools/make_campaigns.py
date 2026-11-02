"""Generates the campaigns in data/campaigns/ (PRD CP-1..CP-4, CP-7): one per
civilization, 3 to 5 missions each, on that civilization's map.

Each mission names its factions, where they start and how many regions they
hold; territories grow outwards from the start regions. Objectives that name
regions are worked out from the map, so they always exist.

    python3 tools/make_campaigns.py
"""

import json
import re
from collections import deque

CIV_COLORS = {"norse": "#2e708f", "anglish": "#b33b3b", "frankish": "#2f4fa8", "crusader": "#c4962c",
              "byzantine": "#7a40a0", "saracen": "#3d8a4a"}
CAPITAL_BUILDINGS = {"market": 1, "barracks": 1}


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
    """factions: list of dicts {id, name, civ, start (slot index or region), size, ai, units}
    and optionally "gold" (starting gold) and "techs" (already researched)."""
    data, graph, names = load_map(map_id)
    starts = []
    for faction in factions:
        faction["size"] = max(faction["size"], len(faction["units"]))
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
        if objective["type"] == "destroy_general":
            # No generals any more: break the enemy leader's war-band, the first army it lists.
            target = next(f for f in factions if f["id"] == objective["faction"])
            objective = {"type": "destroy_units", "faction": target["id"], "unit_type": target["units"][0], "count": 15}
        resolved.append(objective)

    units = []
    for faction in factions:
        territory = [r for r, f in owners.items() if f == faction["id"]]
        territory.sort(key=lambda r: (r != faction["start_region"], r))
        if len(faction["units"]) > len(territory):
            print(f"  warning: {mission_id}: {faction['id']} has room for {len(territory)} of {len(faction['units'])} units")
        for i, unit_type in enumerate(faction["units"][: len(territory)]):
            region = territory[i]  # One unit per region.
            units.append({"owner": faction["id"], "region": region, "type": unit_type})
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

    entries = []
    for f in factions:
        entry = {"id": f["id"], "name": f["name"], "civ": f["civ"], "color": CIV_COLORS[f["civ"]] if f["id"] == player
                 else f.get("color", CIV_COLORS[f["civ"]]), "human": f["id"] == player, "ai": f.get("ai", "balanced")}
        if f.get("techs"):
            entry["techs"] = f["techs"]
        entries.append(entry)
    result = {
        "id": mission_id, "name": title, "map": map_id,
        "factions": entries,
        "owners": owners,
        "capitals": {f["id"]: f["start_region"] for f in factions},
        "buildings": buildings,
        "units": units,
        "mission": {"player": player, "par": par, "objectives": resolved,
                    "briefing": briefing, "victory_text": victory, "defeat_text": defeat},
    }
    gold = {f["id"]: {"gold": f["gold"]} for f in factions if "gold" in f}
    if gold:
        result["resources"] = gold
    return result


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
    mission("fjordmark", "norse_3", "The Lean Winter", "norse", [
        {"id": "norse", "name": "Hakon's Raiders", "civ": "norse", "start": 0, "size": 4, "general": "Hakon", "gold": 100,
         "units": ["huscarl", "spearmen", "archers", "berserker"]},
        {"id": "elmsworth", "name": "Thanes of Elmsworth", "civ": "anglish", "start": 1, "size": 4, "general": "Eadric", "gold": 300,
         "units": ["yeoman", "longbowman", "spearmen", "swordsmen"], "ai": "aggressive"},
    ], [{"type": "survive", "turns": 6}], 7,
        "The fleet is iced into the fjord and the silver is spent. The thanes smell weakness. Keep Skarholm and the army alive "
        "for six turns, until the thaw, without the gold to buy fresh spears.",
        "The ice breaks, and Hakon's raiders are still standing. The thanes go home hungry.",
        "Hunger and Anglish arrows finish what the winter began.", walls={"norse": 1}),
    mission("fjordmark", "norse_4", "Blood-Feud", "norse", [
        {"id": "norse", "name": "Hakon's Raiders", "civ": "norse", "start": 0, "size": 4, "general": "Hakon",
         "units": ["berserker", "huscarl", "archers", "spearmen", "light_cavalry"]},
        {"id": "kaldvik", "name": "Kaldvik Rebels", "civ": "norse", "start": 2, "size": 4, "general": "Sigrid",
         "units": ["berserker", "huscarl", "archers", "spearmen"], "ai": "balanced", "color": "#a8742c"},
    ], [{"type": "destroy_general", "faction": "kaldvik"}], 9,
        "Sigrid of Kaldvik has sworn Hakon's death and taken half the jarls with her. A feud ends one way: "
        "find her war-band and break it.",
        "Sigrid is in chains, and the jarls of Kaldvik kneel again.",
        "Sigrid's oath is kept. Hakon's line is ended."),
    mission("fjordmark", "norse_5", "Throne of the Fjordmark", "norse", [
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
    mission("wealdshire", "anglish_2", "Mustering the Shires", "weald", [
        {"id": "weald", "name": "Kingdom of the Weald", "civ": "anglish", "start": 0, "size": 3, "general": "Elswyth",
         "units": ["longbowman", "yeoman", "spearmen", "light_cavalry"]},
        {"id": "wyndle", "name": "Wyndle Free Towns", "civ": "anglish", "start": 2, "size": 2, "general": "Godric",
         "units": ["yeoman", "archers"], "ai": "defensive", "color": "#c07a3a"},
    ], [{"type": "capture", "regions": "nearest_neutral", "count": 3}], 6,
        "The raiders are gone for now, but the next fleet will come. Bring the nearest shires under the crown, "
        "so their bowmen answer the queen's call.",
        "The shires send their bowmen to Kingsbarrow.",
        "The shires keep their bowmen at home."),
    mission("wealdshire", "anglish_3", "Burn the Longships", "weald", [
        {"id": "weald", "name": "Kingdom of the Weald", "civ": "anglish", "start": 0, "size": 4, "general": "Elswyth",
         "units": ["longbowman", "longbowman", "yeoman", "swordsmen", "light_cavalry", "spearmen"]},
        {"id": "raiders", "name": "Gullmouth Raiders", "civ": "norse", "start": 3, "size": 3, "general": "Ulf",
         "units": ["berserker", "huscarl", "archers", "spearmen", "berserker"], "ai": "balanced"},
    ], [{"type": "destroy", "faction": "raiders"}], 10,
        "Carry the war to Gullmouth and burn the raiders out of the Weald for good.",
        "No longship will beach on our shore again.",
        "The raiders still hold the coast."),
    mission("wealdshire", "anglish_4", "Hunt the Black Count", "weald", [
        {"id": "weald", "name": "Kingdom of the Weald", "civ": "anglish", "start": 0, "size": 4, "general": "Elswyth",
         "techs": ["chain_mail"], "units": ["longbowman", "pikemen", "longbowman", "yeoman", "swordsmen", "light_cavalry"]},
        {"id": "ashcombe", "name": "Count of Ashcombe", "civ": "frankish", "start": 1, "size": 4, "general": "Baudouin",
         "units": ["knight", "sergeant", "crossbowmen", "light_cavalry"], "ai": "balanced"},
    ], [{"type": "destroy_general", "faction": "ashcombe"}], 11,
        "Baudouin, the Black Count of Ashcombe, rides through the Weald burning barns. His knights are deadly in the open: "
        "meet them with pikes and bows, then take the count.",
        "The Black Count is the queen's prisoner, and his ransom fills the treasury.",
        "Baudouin's knights ride on, and the Weald burns.", walls={"weald": 1}),
    mission("wealdshire", "anglish_5", "Crown of the Weald", "weald", [
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
    mission("valmont", "frankish_2", "The Northmen Come", "belcourt", [
        {"id": "belcourt", "name": "Duchy of Belcourt", "civ": "frankish", "start": 0, "size": 4, "general": "Robert",
         "units": ["knight", "sergeant", "crossbowmen", "spearmen"]},
        {"id": "chaumiere", "name": "Norse of Chaumière", "civ": "norse", "start": 2, "size": 4, "general": "Ragnvald", "gold": 450,
         "units": ["berserker", "huscarl", "berserker", "archers", "spearmen"], "ai": "aggressive"},
    ], [{"type": "hold", "region": "capital:belcourt", "turns": 6}], 7,
        "Ragnvald's Northmen have come up the river in force while the duke's vassals bicker. Hold Belcourt for six turns "
        "until the vassals arrive.",
        "The vassals ride in, and the Northmen fall back to their ships.",
        "Belcourt burns, and the Northmen winter in the duke's hall.", walls={"belcourt": 1}),
    mission("valmont", "frankish_3", "The Siege of Brévine", "belcourt", [
        {"id": "belcourt", "name": "Duchy of Belcourt", "civ": "frankish", "start": 0, "size": 4, "general": "Robert",
         "units": ["knight", "knight", "sergeant", "sergeant", "crossbowmen", "catapult", "spearmen"]},
        {"id": "brevine", "name": "Lords of Brévine", "civ": "frankish", "start": 1, "size": 4, "general": "Aimery",
         "units": ["sergeant", "crossbowmen", "spearmen", "swordsmen", "archers"], "ai": "defensive", "color": "#8a6a30"},
    ], [{"type": "capture", "regions": ["capital:brevine"]}], 10,
        "Lord Aimery has shut himself in his stone keep. Besiege it or storm it, but take Brévine.",
        "The keep of Brévine opens its gates.",
        "Brévine's walls hold.", walls={"brevine": 2}),
    mission("valmont", "frankish_4", "The Lowland Towns", "belcourt", [
        {"id": "belcourt", "name": "Duchy of Belcourt", "civ": "frankish", "start": 0, "size": 4, "general": "Robert",
         "units": ["knight", "light_cavalry", "sergeant", "crossbowmen", "knight"]},
        {"id": "vaudrey", "name": "Anglish of Vaudrey", "civ": "anglish", "start": 3, "size": 4, "general": "Edwin",
         "units": ["longbowman", "yeoman", "swordsmen", "archers"], "ai": "defensive"},
        {"id": "chaumiere", "name": "Norse of Chaumière", "civ": "norse", "start": 2, "size": 3, "general": "Ragnvald",
         "units": ["huscarl", "archers", "spearmen"], "ai": "defensive"},
    ], [{"type": "capture", "regions": ["castelroux", "pierrefonde", "marlenne"]}], 11,
        "The river towns of the lowlands, Castelroux, Pierrefonde and Marlenne, pay their tolls to Anglish and Norse "
        "interlopers. Make them pay the duke.",
        "The lowland tolls now fill Belcourt's coffers.",
        "The lowland towns pay their tolls to others.", walls={"belcourt": 1}),
    mission("valmont", "frankish_5", "King of the Valmont", "belcourt", [
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

# --- Crusader Orders: the Sunward Vow, on the Sunward Coast ------------------------------

write("crusader", "crusader", "The Sunward Vow",
      "Grand Master Aubert's brotherhood has landed on a far, dry shore, sworn to hold it with stone and steel.", [
    mission("sunward", "crusader_1", "The Pilgrims' Road", "order", [
        {"id": "order", "name": "Order of the Sunward Keep", "civ": "crusader", "start": 0, "size": 3, "general": "Aubert",
         "units": ["brother_knight", "mounted_sergeant", "spearmen", "crossbowmen"]},
        {"id": "jebel", "name": "Emir of Jebel Nur", "civ": "saracen", "start": 1, "size": 3, "general": "Hamid",
         "units": ["ghazi", "archers", "spearmen"], "ai": "defensive"},
    ], [{"type": "capture", "regions": "nearest_neutral", "count": 3}], 6,
        "The brothers have a keep at Castel Aubade and little else. Secure the wells and villages along the pilgrims' road "
        "so the order can feed itself.",
        "The road is safe, and the wells answer to the order.",
        "The road is lost, and the keep stands alone."),
    mission("sunward", "crusader_2", "The Keep on the Rock", "order", [
        {"id": "order", "name": "Order of the Sunward Keep", "civ": "crusader", "start": 0, "size": 4, "general": "Aubert",
         "techs": ["chain_mail"], "units": ["brother_knight", "pikemen", "crossbowmen", "spearmen"]},
        {"id": "pelerin", "name": "Riders of Mont Pélerin", "civ": "saracen", "start": 3, "size": 4, "general": "Tariq", "gold": 450,
         "units": ["mamluk", "ghazi", "ghazi", "archers", "light_cavalry"], "ai": "aggressive"},
    ], [{"type": "hold", "region": "capital:order", "turns": 6}], 7,
        "Tariq's riders have come down from Mont Pélerin to drive the order into the sea. Hold Castel Aubade for six turns; "
        "the hospital keeps your wounded fighting.",
        "Tariq's riders break on the rock and ride home.",
        "Castel Aubade falls, and the order's banner comes down.", walls={"order": 1}),
    mission("sunward", "crusader_3", "The Emir's Champion", "order", [
        {"id": "order", "name": "Order of the Sunward Keep", "civ": "crusader", "start": 0, "size": 4, "general": "Aubert",
         "techs": ["chain_mail", "stirrups"],
         "units": ["brother_knight", "mounted_sergeant", "pikemen", "crossbowmen", "archers"]},
        {"id": "jebel", "name": "Emir of Jebel Nur", "civ": "saracen", "start": 1, "size": 5, "general": "Rashid", "gold": 450,
         "units": ["mamluk", "ghazi", "archers", "spearmen", "light_cavalry"], "ai": "balanced"},
    ], [{"type": "destroy_general", "faction": "jebel"}], 10,
        "Rashid, the emir's champion, leads every raid on our villages and slips away on his fast horses. Run him down.",
        "Rashid is taken, and the raids stop.",
        "Rashid's horsemen ride rings around the brothers."),
    mission("sunward", "crusader_4", "The Kingdom by the Sea", "order", [
        {"id": "order", "name": "Order of the Sunward Keep", "civ": "crusader", "start": 0, "size": 5, "general": "Aubert",
         "techs": ["chain_mail", "stirrups"],
         "units": ["brother_knight", "brother_knight", "mounted_sergeant", "pikemen", "crossbowmen", "spearmen"]},
        {"id": "jebel", "name": "Emir of Jebel Nur", "civ": "saracen", "start": 1, "size": 5, "general": "Rashid", "gold": 500,
         "units": ["mamluk", "ghazi", "ghazi", "archers", "mamluk"], "ai": "balanced"},
        {"id": "khirbat", "name": "Exarch of Khirbat", "civ": "byzantine", "start": 2, "size": 5, "general": "Leontios", "gold": 500,
         "units": ["cataphract", "varangian_guard", "archers", "spearmen", "crossbowmen"], "ai": "aggressive"},
    ], [{"type": "capture", "regions": ["capital:jebel", "capital:khirbat"]}], 12,
        "An emir in the hills and an imperial exarch on the coast both claim the Sunward shore. Take both their seats, "
        "and the order will rule from the mountains to the sea.",
        "The order's banner flies over Jebel Nur and Khirbat. The vow is kept.",
        "The order is driven back to its single keep.", walls={"jebel": 1, "khirbat": 1}),
])

# --- Byzantine: the Purple and the Gold, on the Porphyry Straits -------------------------

write("byzantine", "byzantine", "The Purple and the Gold",
      "Empress Kassia must win back the straits from rebels, raiders and rivals, starting with an empty treasury.", [
    mission("porphyry", "byzantine_1", "The Rebel Strategos", "empire", [
        {"id": "empire", "name": "Empire of the Golden Horn", "civ": "byzantine", "start": 0, "size": 3, "general": "Kassia",
         "units": ["cataphract", "varangian_guard", "archers", "spearmen"]},
        {"id": "theronike", "name": "Rebels of Theronike", "civ": "byzantine", "start": 3, "size": 3, "general": "Bardas",
         "units": ["spearmen", "archers", "swordsmen"], "ai": "defensive", "color": "#a0507a"},
    ], [{"type": "capture", "regions": ["capital:theronike"]}], 8,
        "The strategos Bardas has crowned himself in Theronike, a day's march from the capital. Take his city before "
        "other governors follow his lead.",
        "Bardas is led through the capital in chains.",
        "Bardas holds Theronike, and other cities wonder who will win."),
    mission("porphyry", "byzantine_2", "The Empty Treasury", "empire", [
        {"id": "empire", "name": "Empire of the Golden Horn", "civ": "byzantine", "start": 0, "size": 4, "general": "Kassia",
         "gold": 100, "units": ["varangian_guard", "cataphract", "archers", "spearmen"]},
        {"id": "kastro", "name": "Sea-Raiders of Kastro Neon", "civ": "norse", "start": 1, "size": 4, "general": "Thorvald",
         "gold": 250, "units": ["berserker", "huscarl", "archers"], "ai": "aggressive"},
        {"id": "phylakion", "name": "Emir of Phylakion", "civ": "saracen", "start": 2, "size": 3, "general": "Faris",
         "units": ["mamluk", "ghazi", "archers"], "ai": "defensive"},
    ], [{"type": "survive", "turns": 6}], 7,
        "The civil war has emptied the treasury, and sea-raiders and an emir circle the straits. Keep the empire standing "
        "for six turns while the markets refill the coffers.",
        "The coffers fill, the walls hold, and the raiders look for easier prey.",
        "With no gold for the guard, the capital opens its gates.", walls={"empire": 2}, extra_buildings={"empire": {"market": 2}}),
    mission("porphyry", "byzantine_3", "The Empire Restored", "empire", [
        {"id": "empire", "name": "Empire of the Golden Horn", "civ": "byzantine", "start": 0, "size": 5, "general": "Kassia",
         "techs": ["chain_mail", "stirrups"],
         "units": ["cataphract", "varangian_guard", "varangian_guard", "archers", "crossbowmen", "pikemen"]},
        {"id": "phylakion", "name": "Emir of Phylakion", "civ": "saracen", "start": 2, "size": 5, "general": "Faris", "gold": 350,
         "units": ["mamluk", "ghazi", "ghazi", "archers"], "ai": "balanced"},
        {"id": "kastro", "name": "Order of Kastro Neon", "civ": "crusader", "start": 1, "size": 5, "general": "Gilles", "gold": 350,
         "units": ["brother_knight", "mounted_sergeant", "crossbowmen", "spearmen"], "ai": "aggressive"},
    ], [{"type": "conquest"}], 13,
        "Crusading knights hold Kastro Neon and an emir holds Phylakion. Drive them both from the straits and the empire "
        "is whole again.",
        "From shore to shore the straits fly the purple. The empire is restored.",
        "The straits stay divided, and the empire's glory fades.", walls={"empire": 1}),
])

# --- Saracen: Banners of the Sands, on the Amber Sands -----------------------------------

write("saracen", "saracen", "Banners of the Sands",
      "Emir Zaydan rides out from the desert to unite the oases and drive the foreign knights into the sea.", [
    mission("amber_sands", "saracen_1", "Riders of the Wadi", "emirate", [
        {"id": "emirate", "name": "Emirate of the Sands", "civ": "saracen", "start": 0, "size": 3, "general": "Zaydan",
         "units": ["mamluk", "ghazi", "archers", "light_cavalry"]},
        {"id": "tamr", "name": "Knights of Hisn Tamr", "civ": "crusader", "start": 2, "size": 2, "general": "Aimon",
         "units": ["mounted_sergeant", "spearmen"], "ai": "defensive"},
    ], [{"type": "capture", "regions": "nearest_neutral", "count": 3}], 6,
        "The oasis towns along the wadi pay no one. Ride out and bring three of them under the emir's banner.",
        "The oases open their gates, and their riders join Zaydan.",
        "The oases close their gates to Zaydan."),
    mission("amber_sands", "saracen_2", "The Iron Brothers", "emirate", [
        {"id": "emirate", "name": "Emirate of the Sands", "civ": "saracen", "start": 0, "size": 4, "general": "Zaydan",
         "techs": ["chain_mail"], "units": ["mamluk", "mamluk", "ghazi", "pikemen", "archers", "spearmen"]},
        {"id": "tamr", "name": "Knights of Hisn Tamr", "civ": "crusader", "start": 2, "size": 4, "general": "Aimon",
         "units": ["brother_knight", "mounted_sergeant", "spearmen", "crossbowmen"], "ai": "defensive"},
    ], [{"type": "destroy_general", "faction": "tamr"}], 10,
        "Aimon, master of the iron brothers of Hisn Tamr, has burned the date groves. His knights are slow to wheel and "
        "heavy in the sand: wear them down with arrows, then take the master.",
        "Aimon is captured, and his brothers sue for peace.",
        "The iron brothers ride on through the burning groves.", walls={"emirate": 1}),
    mission("amber_sands", "saracen_3", "Sultan of the Sands", "emirate", [
        {"id": "emirate", "name": "Emirate of the Sands", "civ": "saracen", "start": 0, "size": 5, "general": "Zaydan",
         "techs": ["chain_mail"], "gold": 600,
         "units": ["mamluk", "mamluk", "ghazi", "pikemen", "archers", "crossbowmen"]},
        {"id": "tamr", "name": "Knights of Hisn Tamr", "civ": "crusader", "start": 2, "size": 3, "general": "Aimon",
         "units": ["brother_knight", "crossbowmen", "spearmen"], "ai": "balanced"},
        {"id": "ruba", "name": "Imperial Ruba Sahra", "civ": "byzantine", "start": 3, "size": 3, "general": "Manuel",
         "units": ["varangian_guard", "archers", "spearmen"], "ai": "defensive"},
    ], [{"type": "capture", "regions": ["capital:tamr", "capital:ruba"]}], 15,
        "Two foreign strongholds still hold the coast: the knights at Hisn Tamr and an imperial garrison at Ruba Sahra. "
        "Take both, and Zaydan is sultan of all the sands.",
        "Zaydan is proclaimed sultan from the walls of Hisn Tamr.",
        "The foreigners keep the coast, and the sands stay divided.", walls={"emirate": 1}),
])
