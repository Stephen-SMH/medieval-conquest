"""Generates the historical scenarios in data/scenarios/ (PRD M) from the
real maps' historical starts ("history" in data/maps/<map>.json): who holds
what in that year, plus armies, a mission in the S&T form (PRD H) and a
listing for the Scenarios table (difficulty 1-3, order, and how many
scenario wins unlock it). Garrisons are laid out from each capital outwards;
every region an objective names and every region the player must not lose
gets one too, capitals get walls, and a scenario may change owners
("owners": {region: faction}), give a realm its own army types
("faction_armies": {faction: [type, ...]}) and place armies itself
("armies": {region: [type, soldiers]}, for its owner).

    python3 tools/make_scenarios.py
"""

import json
from collections import deque

# The army types each realm fields, strongest first: the capital gets the first.
ARMIES = {
    "anglish": ["swordsmen", "longbowman", "yeoman", "spearmen", "archers", "light_cavalry"],
    "frankish": ["knight", "sergeant", "crossbowmen", "spearmen", "archers", "light_cavalry"],
    "norse": ["huscarl", "berserker", "archers", "spearmen", "light_cavalry"],
    "crusader": ["brother_knight", "mounted_sergeant", "crossbowmen", "pikemen", "spearmen"],
    "saracen": ["mamluk", "ghazi", "archers", "spearmen", "light_cavalry"],
    "byzantine": ["cataphract", "varangian_guard", "archers", "spearmen"],
    "": ["swordsmen", "spearmen", "archers", "light_cavalry", "militia"],
}

SCENARIOS = [
    {
        "map": "livonia", "id": "lake_peipus_1242", "name": "1242: The Battle on the Ice",
        "listing": {"difficulty": 1, "order": 2, "unlock_after": 0},
        "history": "In 1240 the knights of the Livonian Order crossed the border, took Izborsk and were let into Pskov. "
                   "Novgorod called back Prince Alexander, who drove them from Koporye and now marches on Pskov.",
        "briefing": "Free Pskov and Izborsk before the Order can gather its strength.",
        "primary": [{"type": "capture", "regions": ["pskov", "izborsk"]}],
        "additional": [{"type": "capture", "regions": ["dorpat"], "points": 200}],
        "defeat": [{"type": "lose_region", "region": "novgorod"}],
        "crowns": [6, 8, 10], "time": 14,
        "faction_armies": {"novgorod": ["spearmen", "archers", "pikemen", "light_cavalry", "swordsmen"]},
        "armies": {"pskov": ["brother_knight", 14], "izborsk": ["crossbowmen", 12], "novgorod": ["pikemen", 20], "luga": ["spearmen", 14]},
        "events": [{"turn": 3, "type": "reinforcements", "faction": "order", "region": "dorpat", "unit": "brother_knight", "soldiers": 8,
                    "text": "The brother knights ride out of Dorpat to meet Alexander's army."}],
        "victory": "On the ice of Lake Peipus the Order's charge breaks. Pskov is free, and the Order gives up its conquests.",
        "defeat_text": "The Order holds Pskov, and its banners creep towards Novgorod.",
    },
    {
        "map": "british_isles", "id": "three_kings_1066", "name": "1066: The Year of Three Kings",
        "listing": {"difficulty": 1, "order": 3, "unlock_after": 0},
        "history": "King Edward died in January and Harold Godwinson took the crown. In September Harald Hardrada, king of "
                   "Norway, sailed up the Humber with Harold's exiled brother Tostig and seized the north.",
        "briefing": "York has opened its gates to Hardrada after his victory at Fulford. March north, retake York and "
                    "throw the Norwegians out of Stamford Bridge.",
        "primary": [{"type": "capture", "regions": ["stamford_bridge", "york"]}],
        "additional": [{"type": "capture", "regions": ["caithness"], "points": 200}],
        "defeat": [{"type": "lose_region", "region": "london"}],
        "crowns": [6, 9, 12], "time": 15,
        "owners": {"york": "norway"},
        "armies": {"stamford_bridge": ["huscarl", 18], "york": ["berserker", 12], "london": ["swordsmen", 20], "doncaster": ["yeoman", 16],
                   "lincoln": ["archers", 12], "durham": ["spearmen", 12], "lancaster": ["spearmen", 0], "newcastle": ["archers", 0]},
        "events": [{"turn": 2, "type": "message",
                    "text": "Word comes from the south: Duke William of Normandy waits for a fair wind across the Channel."}],
        "victory": "At Stamford Bridge Hardrada falls, and the age of the great Viking invasions ends with him.",
        "defeat_text": "The Norwegians hold the north, and Harold's crown slips.",
    },
    {
        "map": "france", "id": "orleans_1429", "name": "1429: The Siege of Orléans",
        "listing": {"difficulty": 2, "order": 4, "unlock_after": 1},
        "history": "The English and their Burgundian allies hold Paris and the north, and English forts ring Orléans. "
                   "The uncrowned Dauphin Charles keeps court south of the Loire, and a girl from Domrémy has come to him at Chinon.",
        "briefing": "Hold Orléans, then open the road to Reims, where French kings are crowned.",
        "primary": [{"type": "capture", "regions": ["reims"]}],
        "additional": [{"type": "capture", "regions": ["paris"], "points": 300}],
        "defeat": [{"type": "lose_region", "region": "orleans"}, {"type": "lose_region", "region": "bourges"}],
        "crowns": [9, 12, 16], "time": 20,
        "armies": {"orleans": ["pikemen", 22], "bourges": ["knight", 24], "chartres": ["longbowman", 10], "reims": ["swordsmen", 10],
                   "paris": ["longbowman", 14], "le_mans": ["spearmen", 0], "avranches": ["archers", 0], "beauvais": ["archers", 0]},
        "gold": {"france": 600},
        "events": [{"turn": 1, "type": "reinforcements", "faction": "france", "region": "chinon", "unit": "sergeant", "soldiers": 10,
                    "text": "Joan of Arc arrives at Chinon with a relief force for Orléans."}],
        "victory": "Charles is crowned at Reims with Joan beside him, and the war turns at last.",
        "defeat_text": "Orléans falls, and the road south lies open to the English.",
    },
    {
        "map": "scandinavia", "id": "svolder_1000", "name": "1000: The Age of the Vikings",
        "listing": {"difficulty": 2, "order": 5, "unlock_after": 1},
        "history": "Olaf Tryggvason rules Norway from Nidaros and presses the new faith on its chieftains. King Sweyn "
                   "Forkbeard of Denmark, the Swedes and the exiled jarls of Lade have sworn to bring him down.",
        "briefing": "Take Trondheim, Olaf's seat, and claim Viken in the south for the Danish crown.",
        "primary": [{"type": "capture", "regions": ["trondheim"]}],
        "additional": [{"type": "capture", "regions": ["oslo", "tonsberg"], "points": 200}],
        "defeat": [{"type": "lose_region", "region": "zealand"}],
        "crowns": [12, 16, 20], "time": 24,
        "armies": {"trondheim": ["huscarl", 16], "bergen": ["archers", 10], "oslo": ["spearmen", 10]},
        "gold": {"danes": 600},
        "events": [],
        "victory": "Olaf's longships are taken off Svolder, and Norway is shared among the victors.",
        "defeat_text": "Olaf keeps his throne, and the Danes go home empty-handed.",
    },
    {
        "map": "holy_roman_empire", "id": "barbarossa_1176", "name": "1176: Barbarossa and Henry the Lion",
        "listing": {"difficulty": 3, "order": 6, "unlock_after": 2},
        "history": "Emperor Frederick Barbarossa begged his cousin Henry the Lion, duke of Saxony and Bavaria, for knights "
                   "against the Italian cities. Henry refused, and the emperor was beaten at Legnano.",
        "briefing": "Bring the over-mighty duke to heel: take Brunswick, the Lion's seat.",
        "primary": [{"type": "capture", "regions": ["brunswick"]}],
        "additional": [{"type": "capture", "regions": ["lubeck"], "points": 150},
                       {"type": "capture", "regions": ["regensburg"], "points": 150}],
        "defeat": [{"type": "lose_region", "region": "frankfurt"}],
        "crowns": [10, 13, 16], "time": 20,
        "faction_armies": {"saxony": ["pikemen", "crossbowmen", "spearmen", "swordsmen", "archers"]},
        "armies": {"brunswick": ["pikemen", 20], "luneburg": ["crossbowmen", 14], "goslar": ["knight", 20], "frankfurt": ["sergeant", 24],
                   "mainz": ["crossbowmen", 16]},
        "walls": {"frankfurt": 2},
        "events": [{"turn": 4, "type": "reinforcements", "faction": "saxony", "region": "brunswick", "unit": "crossbowmen", "soldiers": 4,
                    "text": "Henry the Lion calls his Saxon vassals to Brunswick."}],
        "victory": "Henry the Lion is stripped of his duchies and sent into exile; the emperor's word is law again.",
        "defeat_text": "The Lion keeps his lands, and the emperor's authority is broken.",
    },
    {
        "map": "levant", "id": "hattin_1187", "name": "1187: On the Eve of Hattin",
        "listing": {"difficulty": 2, "order": 7, "unlock_after": 3},
        "history": "Saladin has united Egypt and Syria under the Ayyubid banner. Reynald of Châtillon has broken the truce "
                   "by raiding a caravan from Kerak, and the sultan is gathering the largest army the kingdom has ever faced.",
        "briefing": "History says Jerusalem falls this year. Keep it, and carry the war to Damascus.",
        "primary": [{"type": "capture", "regions": ["damascus"]}],
        "additional": [{"type": "capture", "regions": ["aleppo"], "points": 300}],
        "defeat": [{"type": "lose_region", "region": "jerusalem"}],
        "crowns": [10, 14, 18], "time": 22,
        "gold": {"ayyubids": 900},
        "faction_armies": {"ayyubids": ["mamluk", "pikemen", "ghazi", "archers", "spearmen"]},
        "armies": {"damascus": ["pikemen", 28], "banias": ["ghazi", 18], "bostra": ["pikemen", 16], "baalbek": ["archers", 14],
                   "jerusalem": ["brother_knight", 18]},
        "walls": {"damascus": 2, "jerusalem": 2},
        "events": [{"turn": 2, "type": "reinforcements", "faction": "ayyubids", "region": "banias", "unit": "mamluk", "soldiers": 10,
                    "text": "Saladin's army gathers on the Golan heights above the Sea of Galilee."},
                   {"turn": 4, "type": "reinforcements", "faction": "ayyubids", "region": "damascus", "unit": "ghazi", "soldiers": 2,
                    "text": "Volunteers stream into Damascus to defend the sultan's city."}],
        "victory": "Damascus opens its gates. The kingdom of Jerusalem has outlived the sultan's great host.",
        "defeat_text": "Jerusalem falls to Saladin, as it did in 1187.",
    },
]


def load_map(map_id):
    with open(f"data/maps/{map_id}.json") as f:
        data = json.load(f)
    graph = {r["id"]: list(r["neighbours"]) for r in data["regions"]}
    for a, b in data.get("sea_links", []):
        graph[a].append(b)
        graph[b].append(a)
    return data, graph


def order_from(graph, start, regions):
    """`regions` sorted by distance from `start` (then by name)."""
    dist = {start: 0}
    queue = deque([start])
    while queue:
        current = queue.popleft()
        for nxt in graph[current]:
            if nxt not in dist:
                dist[nxt] = dist[current] + 1
                queue.append(nxt)
    return sorted(regions, key=lambda r: (dist.get(r, 99), r))


def build(spec):
    data, graph = load_map(spec["map"])
    history = data["history"]
    owners = dict(history["owners"])
    owners.update(spec.get("owners", {}))
    player = next(f["id"] for f in history["factions"] if f.get("human"))
    civ_of = {f["id"]: f.get("civ", "") for f in history["factions"]}
    armies = {}  # region -> (type, soldiers), for the region's owner
    for faction in history["factions"]:
        held = order_from(graph, history["capitals"][faction["id"]], [r for r, f in owners.items() if f == faction["id"]])
        kinds = spec.get("faction_armies", {}).get(faction["id"], ARMIES[faction.get("civ", "")])
        # About one army for every two regions, the capital's the strongest.
        for i, region in enumerate(held[: max(2, (len(held) + 1) // 2)]):
            armies[region] = (kinds[i % len(kinds)], 20 if i == 0 else 15 if i < 3 else 12)
    # Every region an objective names, and every region the player must keep, is held by an army.
    named = []
    for objective in spec["primary"] + spec["additional"]:
        named += objective.get("regions", []) + ([objective["region"]] if "region" in objective else [])
    named += [d["region"] for d in spec["defeat"] if "region" in d]
    for region in named:
        owner = owners[region]
        if region not in armies and owner != "neutral":
            armies[region] = (spec.get("faction_armies", {}).get(owner, ARMIES[civ_of[owner]])[1], 15)
    for region, (kind, soldiers) in spec.get("armies", {}).items():
        if soldiers > 0:
            armies[region] = (kind, soldiers)
        else:
            armies.pop(region, None)  # No army there.
    units = [{"owner": owners[r], "region": r, "type": kind, "soldiers": soldiers}
             for r, (kind, soldiers) in sorted(armies.items()) if owners[r] != "neutral"]
    for region in sorted(r for r, f in owners.items() if f == "neutral"):
        units.append({"owner": "neutral", "region": region, "type": "militia", "soldiers": 10})
    buildings = json.loads(json.dumps(history["buildings"]))
    for region in list(history["capitals"].values()) + list(spec.get("walls", {})):
        level = spec.get("walls", {}).get(region, 1)
        buildings.setdefault(region, {})["walls"] = max(buildings.get(region, {}).get("walls", 0), level)
    mission = {
        "player": player, "primary": spec["primary"], "additional": spec["additional"],
        "defeat": [{"type": "time", "turns": spec["time"]}] + spec["defeat"],
        "crowns": spec["crowns"], "events": spec["events"],
        "history": spec["history"], "briefing": spec["briefing"],
        "victory_text": spec["victory"], "defeat_text": spec["defeat_text"],
    }
    for objective in spec["primary"] + spec["additional"]:
        for region in objective.get("regions", []) + ([objective["region"]] if "region" in objective else []):
            assert region in graph, f"{spec['id']}: no region {region}"
    return {
        "id": spec["id"], "name": spec["name"], "map": spec["map"], "listing": spec["listing"],
        "factions": history["factions"], "owners": owners, "capitals": history["capitals"],
        "buildings": buildings, "units": units, "mission": mission,
        **({"resources": {f: {"gold": g} for f, g in spec["gold"].items()}} if "gold" in spec else {}),
    }


for spec in SCENARIOS:
    scenario = build(spec)
    with open(f"data/scenarios/{spec['id']}.json", "w") as f:
        f.write(json.dumps(scenario, indent=1, ensure_ascii=False) + "\n")
    print(spec["id"], len(scenario["units"]), "armies")
