"""Generates the campaigns in data/campaigns/ as S&T has them: England (11
missions), France (11), Crusades (12) and Vikings (9), each mission a real
event on the real maps (data/maps/, from tools/make_real_maps.py), in the S&T
mission form (PRD H): primary and additional objectives, defeat conditions,
crowns, events, a history intro and a briefing. The words are our own.

A mission names its factions (the first is the player), who holds what (the
regions not named go to "rest", or stay neutral), each faction's capital,
and armies. Every faction gets garrisons from its capital outwards, about one
army for every two regions; "armies" adds or changes them ({region: [type,
soldiers]}, 0 soldiers for none). Neutral regions hold militia.

    python3 tools/make_history_campaigns.py
"""

import json
from collections import deque

# The army types each civilization fields, strongest first: the capital gets the first.
ARMIES = {
    "anglish": ["swordsmen", "longbowman", "yeoman", "spearmen", "archers", "light_cavalry"],
    "frankish": ["knight", "sergeant", "crossbowmen", "spearmen", "archers", "light_cavalry"],
    "norse": ["huscarl", "berserker", "archers", "spearmen", "light_cavalry"],
    "crusader": ["brother_knight", "mounted_sergeant", "crossbowmen", "pikemen", "spearmen"],
    "saracen": ["mamluk", "ghazi", "archers", "spearmen", "light_cavalry"],
    "byzantine": ["cataphract", "varangian_guard", "archers", "spearmen"],
    "": ["swordsmen", "spearmen", "archers", "light_cavalry", "militia"],
}


def F(fid, name, civ, color, ai="balanced"):
    return {"id": fid, "name": name, "civ": civ, "color": color, "ai": ai}


ENGLAND = F("england", "Kingdom of England", "anglish", "#b5423a")
DENMARK = F("denmark", "Kingdom of Denmark", "norse", "#cfd2e6", "aggressive")
NORWAY = F("norway", "Kingdom of Norway", "norse", "#d1a23a", "aggressive")
FRANCE = F("france", "Kingdom of France", "frankish", "#3d6fb6")
CRUSADERS = F("crusaders", "Crusaders", "crusader", "#c4962c")
AYYUBIDS = F("ayyubids", "Ayyubid Sultanate", "saracen", "#3d8a4a", "aggressive")
WELSH = "caernarfonshire anglesey pembrokeshire glamorgan"

# Region groups on the France map.
ENG_ISLE = "plymouth dorchester winchester london dover"
NORMANDY = "rouen caen formigny avranches"
ANJOU = "le_mans angers chinon tours"
AQUITAINE = "poitiers la_rochelle limoges perigueux bordeaux bayonne cahors"
BRITTANY = "rennes nantes vannes brest"
FLANDERS = "brugge ghent antwerp"
LOW_LANDS = "brussels mons"
EMPIRE_WEST = "liege metz nancy"
SOUTH = "toulouse carcassonne montpellier pau avignon marseille"
# On the Levant map.
CYPRUS = "paphos lefkosa famagusta"
RUM = "konya philomelion laranda eregli nigde"
NORTH_SYRIA = "aleppo ma_arra hamah homs raqqa palmyra"
DAMASCUS = "damascus baalbek banias bostra"
EGYPT = "al_arish damietta"
# On the British Isles map.
SCOTS = "glasgow roxburgh edinburgh dunblane scone st_andrews argyll aberdeen elgin inverness galloway carlisle"
CYMRY = "bangor mathrafal aberystwyth st_davids brecon cardiff"
IRISH = "dublin tara armagh ailech tuam limerick cashel waterford cork"
NORTHUMBRIA = "bamburgh newcastle durham york lancaster doncaster"

BRITTANY_F = F("brittany", "Duchy of Brittany", "", "#2f7d4a", "defensive")
BURGUNDY_F = F("burgundy", "Duchy of Burgundy", "frankish", "#d1a23a", "defensive")
ENGLISH_KING = F("england", "Kingdom of England", "anglish", "#b5423a", "aggressive")
SELJUKS = F("seljuks", "Sultanate of Rum", "saracen", "#8a5a2a", "defensive")
BYZANTINES = F("byzantines", "Byzantine Empire", "byzantine", "#7a40a0", "defensive")
ARMENIANS = F("armenians", "Armenian Princes", "", "#b07040", "defensive")
FATIMIDS = F("fatimids", "Fatimid Caliphate", "saracen", "#5aa04a", "defensive")
SYRIA = F("syria", "Seljuk Emirs of Syria", "saracen", "#3d8a4a", "aggressive")
VIKINGS = F("vikings", "Norse Raiders", "norse", "#d1a23a")
SCOTLAND_F = F("scotland", "Kingdom of Alba", "", "#3d6fb6", "defensive")
WALES_F = F("wales", "Welsh Kingdoms", "", "#2f7d4a", "defensive")
IRELAND_F = F("ireland", "Irish Kingdoms", "", "#7b4fa8", "defensive")
CELTS = {"scotland": SCOTS, "wales": CYMRY, "ireland": IRISH}
CELT_CAPITALS = {"scotland": "scone", "wales": "bangor", "ireland": "tara"}

CAMPAIGNS = [
    {
        "id": "anglish", "civ": "anglish", "order": 1, "name": "England",
        "description": "Defend the English lands from the Danes, the Norwegians and the French, fight for the Holy Land, "
                       "win the Hundred Years' War and end the Wars of the Roses.",
        "missions": [
            {
                "name": "Invasion of England by Norway and Denmark, 1013", "map": "england",
                "factions": [ENGLAND, DENMARK], "rest": "england",
                "owners": {"denmark": "glamorgan hereford warwick gloucester glastonbury salisbury dorchester winchester guildford "
                                      "rochester hastings", "neutral": "anglesey isle_of_man"},
                "capitals": {"england": "london", "denmark": "winchester"},
                "auto": False,
                "armies": {"london": ["swordsmen", 9], "york": ["spearmen", 6], "lincoln": ["archers", 8], "cambridge": ["longbowman", 8],
                           "stamford": ["yeoman", 6], "leicester": ["light_cavalry", 4], "oxford": ["spearmen", 5], "exeter": ["archers", 4],
                           "nottingham": ["yeoman", 10], "leominster": ["spearmen", 3], "pembrokeshire": ["archers", 6],
                           "winchester": ["huscarl", 6], "warwick": ["berserker", 5], "hereford": ["spearmen", 4], "glamorgan": ["archers", 3],
                           "gloucester": ["spearmen", 3], "salisbury": ["huscarl", 4], "glastonbury": ["archers", 3],
                           "hastings": ["berserker", 3], "rochester": ["spearmen", 3], "dorchester": ["light_cavalry", 2],
                           "guildford": ["huscarl", 3]},
                "primary": [{"type": "destroy_units", "faction": "", "unit_type": "", "count": 7}],
                "additional": [{"type": "lose_at_most", "unit_class": "cavalry", "count": 3},
                               {"type": "destroy", "faction": "denmark", "text": "Destroy all enemy forces", "points": 300}],
                "defeat": [{"type": "lose_army"}, {"type": "lose_region", "region": "london", "before": 8}],
                "crowns": [8, 10, 12], "time": 12,
                "events": [{"turn": 3, "type": "reinforcements", "faction": "denmark", "region": "hastings", "unit": "berserker", "soldiers": 4,
                            "text": "Enemy reinforcements have landed at Hastings."}],
                "history": "Fog and war have always lain over these lands. Britons, Saxons and Danes have fought here for "
                           "centuries. In 1013 Sweyn Forkbeard, king of Denmark, brought a great fleet to England, and his Danes "
                           "and Norwegians now hold the south coast and the Severn.",
                "briefing": "Break the Danish host before it reaches London.",
                "victory": "The Danes are thrown back to their ships, and London stands.",
                "defeat_text": "Sweyn's banners fly over London, and King Æthelred flees to Normandy.",
            },
            {
                "name": "Edmund Ironside, 1016", "map": "england",
                "factions": [ENGLAND, DENMARK], "rest": "england",
                "owners": {"denmark": "newcastle cumbria york stamford_bridge lancaster doncaster lincoln nottingham stamford norwich "
                                      "dunwich cambridge london", "neutral": WELSH + " isle_of_man"},
                "capitals": {"england": "winchester", "denmark": "york"},
                "armies": {"london": ["huscarl", 18], "winchester": ["swordsmen", 20], "oxford": ["longbowman", 15], "guildford": ["yeoman", 14]},
                "primary": [{"type": "capture", "regions": ["london"]}],
                "additional": [{"type": "capture", "regions": ["lincoln"]}],
                "defeat": [{"type": "lose_region", "region": "winchester"}],
                "crowns": [6, 9, 12], "time": 14,
                "events": [{"turn": 4, "type": "reinforcements", "faction": "denmark", "region": "cambridge", "unit": "huscarl", "soldiers": 10,
                            "text": "Cnut's fleet brings fresh Danes up the rivers of East Anglia."}],
                "history": "King Æthelred is dead, and his son Edmund, called Ironside, has been chosen king in London. Cnut, "
                           "Sweyn's son, holds the Danelaw and has laid siege to the city.",
                "briefing": "Relieve London before it starves, and keep Winchester out of Danish hands.",
                "victory": "London is free. Edmund and Cnut will share the kingdom, and England is not lost.",
                "defeat_text": "Winchester falls, and Cnut is crowned king of all England.",
            },
            {
                "name": "Stamford Bridge, 1066", "map": "england",
                "factions": [ENGLAND, NORWAY], "rest": "england",
                "owners": {"norway": "stamford_bridge york", "neutral": WELSH + " isle_of_man"},
                "capitals": {"england": "london", "norway": "stamford_bridge"},
                "armies": {"stamford_bridge": ["huscarl", 20], "york": ["berserker", 15], "london": ["swordsmen", 20],
                           "doncaster": ["yeoman", 16], "lincoln": ["light_cavalry", 10], "nottingham": ["longbowman", 12]},
                "primary": [{"type": "capture", "regions": ["york", "stamford_bridge"]}],
                "additional": [{"type": "lose_at_most", "unit_class": "cavalry", "count": 3}],
                "defeat": [{"type": "lose_region", "region": "london"}],
                "crowns": [4, 6, 8], "time": 10,
                "events": [{"turn": 2, "type": "reinforcements", "faction": "norway", "region": "stamford_bridge", "unit": "huscarl", "soldiers": 6,
                            "text": "Hardrada's men march up from the ships at Riccall."},
                           {"turn": 3, "type": "message", "text": "Word comes from the south: Duke William's fleet waits for a fair wind."}],
                "history": "Harald Hardrada, king of Norway, has sailed up the Humber with the exiled Tostig, beaten the "
                           "northern earls at Fulford and taken York.",
                "briefing": "March north fast, retake York and destroy the Norwegians at Stamford Bridge.",
                "victory": "Hardrada falls at Stamford Bridge, and of three hundred ships only twenty-four sail home.",
                "defeat_text": "The Norwegians hold the north, and Harold's crown slips.",
            },
            {
                "name": "Hastings, 1066", "map": "england",
                "factions": [ENGLAND, F("normandy", "Duchy of Normandy", "frankish", "#2f4fa8", "aggressive")], "rest": "england",
                "owners": {"normandy": "hastings rochester", "neutral": WELSH + " isle_of_man"},
                "capitals": {"england": "london", "normandy": "hastings"},
                "armies": {"hastings": ["knight", 20], "rochester": ["sergeant", 15], "london": ["swordsmen", 20], "guildford": ["yeoman", 15]},
                "primary": [{"type": "capture", "regions": ["hastings"]}],
                "additional": [{"type": "destroy_units", "faction": "normandy", "unit_type": "knight", "count": 15}],
                "defeat": [{"type": "lose_region", "region": "london"}],
                "crowns": [5, 7, 9], "time": 12,
                "events": [{"turn": 2, "type": "reinforcements", "faction": "normandy", "region": "hastings", "unit": "knight", "soldiers": 8,
                            "text": "More Norman ships land at Pevensey."}],
                "history": "Three days after Stamford Bridge, Duke William of Normandy landed at Pevensey and built a fort at "
                           "Hastings. King Harold has marched his weary army back south.",
                "briefing": "Throw the Normans into the sea before William can march on London.",
                "victory": "The Norman knights break on the shield wall, and William's claim dies with his army.",
                "defeat_text": "William is crowned in Westminster on Christmas Day.",
            },
            {
                "name": "The Anarchy, 1139", "map": "england",
                "factions": [ENGLAND, F("angevins", "Empress Matilda", "anglish", "#7b4fa8")], "rest": "england",
                "owners": {"angevins": "gloucester glastonbury hereford leominster oxford exeter", "neutral": WELSH + " isle_of_man"},
                "capitals": {"england": "london", "angevins": "gloucester"},
                "primary": [{"type": "capture", "regions": ["gloucester", "oxford"]}],
                "additional": [{"type": "capture", "regions": ["exeter"]}],
                "defeat": [{"type": "lose_region", "region": "london"}],
                "crowns": [8, 11, 14], "time": 16,
                "history": "King Stephen took the crown when Henry I died, but Henry's daughter, the Empress Matilda, has landed "
                           "in England, and her half-brother Robert of Gloucester holds the west for her.",
                "briefing": "Take Gloucester and Oxford, and end Matilda's war.",
                "victory": "Matilda escapes over the snow from Oxford, and her cause is broken.",
                "defeat_text": "Matilda's army holds London, and England is torn for another decade.",
            },
            {
                "name": "Arsuf, 1191", "map": "levant",
                "factions": [ENGLAND, AYYUBIDS, F("seljuks", "Sultanate of Rum", "saracen", "#8a5a2a", "defensive"),
                             F("armenians", "Kingdom of Armenia", "", "#b07040", "defensive")],
                "rest": "ayyubids",
                "owners": {"england": "acre tyre tripoli tortosa krak_des_chevaliers antioch st_simeon paphos lefkosa famagusta",
                           "seljuks": "konya philomelion laranda eregli nigde marash antalya alanya",
                           "armenians": "seleucia tarsus adana sis"},
                "capitals": {"england": "acre", "ayyubids": "jerusalem", "seljuks": "konya", "armenians": "sis"},
                "armies": {"acre": ["longbowman", 20], "tyre": ["swordsmen", 15], "caesarea": ["mamluk", 16], "jaffa": ["ghazi", 15]},
                "primary": [{"type": "capture", "regions": ["caesarea", "jaffa"]}],
                "additional": [{"type": "destroy_units", "faction": "ayyubids", "unit_type": "mamluk", "count": 15}],
                "defeat": [{"type": "lose_region", "region": "acre"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "Acre has fallen to the crusaders after two years of siege. King Richard now marches south along "
                           "the coast towards Jaffa, the port of Jerusalem, with Saladin's horse archers harrying every step.",
                "briefing": "Keep the column together, take Caesarea and Jaffa, and hold Acre behind you.",
                "victory": "At Arsuf Richard's knights charge at last, and Saladin's army breaks. Jaffa is yours.",
                "defeat_text": "Acre falls back to Saladin, and the crusade is over.",
            },
            {
                "name": "Lincoln, 1217", "map": "england",
                "factions": [ENGLAND, F("france", "Prince Louis of France", "frankish", "#3d6fb6", "aggressive")], "rest": "england",
                "owners": {"france": "london rochester guildford hastings winchester cambridge norwich dunwich stamford lincoln",
                           "neutral": WELSH + " isle_of_man"},
                "capitals": {"england": "gloucester", "france": "london"},
                "armies": {"lincoln": ["knight", 15], "london": ["sergeant", 20], "gloucester": ["swordsmen", 20], "nottingham": ["longbowman", 15]},
                "primary": [{"type": "capture", "regions": ["lincoln", "london"]}],
                "additional": [{"type": "destroy_units", "faction": "france", "unit_type": "knight", "count": 10}],
                "defeat": [{"type": "lose_region", "region": "gloucester"}],
                "crowns": [7, 10, 13], "time": 15,
                "history": "King John is dead. The rebel barons have offered his crown to Prince Louis of France, who holds "
                           "London and half the kingdom. The boy king Henry III was crowned at Gloucester, and the old knight "
                           "William Marshal leads his army.",
                "briefing": "Relieve the castle at Lincoln, then drive Louis out of London.",
                "victory": "The French are routed in the streets of Lincoln, and Louis gives up his claim.",
                "defeat_text": "Gloucester falls, and a French prince rules England.",
            },
            {
                "name": "The Conquest of Wales, 1282", "map": "england",
                "factions": [ENGLAND, F("wales", "Principality of Wales", "", "#2f7d4a", "defensive")], "rest": "england",
                "owners": {"wales": "caernarfonshire anglesey leominster", "neutral": "isle_of_man"},
                "capitals": {"england": "chester", "wales": "caernarfonshire"},
                "armies": {"caernarfonshire": ["spearmen", 20], "anglesey": ["archers", 15], "leominster": ["spearmen", 15],
                           "chester": ["swordsmen", 20], "hereford": ["longbowman", 15]},
                "primary": [{"type": "destroy", "faction": "wales"}],
                "additional": [{"type": "lose_at_most", "unit_class": "cavalry", "count": 5}],
                "defeat": [{"type": "lose_region", "region": "chester"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "Llywelyn ap Gruffudd, Prince of Wales, has risen against King Edward I, and Snowdonia has closed "
                           "its passes behind him.",
                "briefing": "Take Anglesey, the granary of Gwynedd, and end the Welsh principality.",
                "victory": "Llywelyn falls at Orewin Bridge, and Edward's castles rise over Wales.",
                "defeat_text": "Chester burns, and the Welsh hold the march.",
            },
            {
                "name": "Crécy and Calais, 1346", "map": "france",
                "factions": [ENGLAND, FRANCE, F("burgundy", "Duchy of Burgundy", "frankish", "#d1a23a", "defensive")],
                "rest": "france",
                "owners": {"england": "plymouth dorchester winchester london dover formigny bordeaux bayonne",
                           "burgundy": "dijon besancon auxerre macon troyes",
                           "neutral": "rennes nantes vannes brest brugge ghent antwerp brussels mons liege metz nancy pau avignon marseille"},
                "capitals": {"england": "london", "france": "paris", "burgundy": "dijon"},
                "armies": {"formigny": ["longbowman", 20], "calais": ["crossbowmen", 15], "crecy": ["knight", 15]},
                "primary": [{"type": "capture", "regions": ["crecy", "calais"]}],
                "additional": [{"type": "capture", "regions": ["rouen"]}],
                "defeat": [{"type": "lose_region", "region": "london"}],
                "crowns": [7, 10, 12], "time": 14,
                "history": "Edward III claims the French crown through his mother. He has landed in Normandy with an army of "
                           "longbowmen and marches for the Somme, with King Philip VI's great host behind him.",
                "briefing": "Beat the French knights at Crécy, then take Calais as a gate into France.",
                "victory": "The French chivalry dies under the longbows at Crécy, and Calais is English for two hundred years.",
                "defeat_text": "London falls, and Edward's claim with it.",
            },
            {
                "name": "Agincourt, 1415", "map": "france",
                "factions": [ENGLAND, FRANCE, F("burgundy", "Duchy of Burgundy", "frankish", "#d1a23a", "defensive")],
                "rest": "france",
                "owners": {"england": "plymouth dorchester winchester london dover calais formigny bordeaux bayonne",
                           "burgundy": "dijon besancon auxerre macon troyes amiens arras brugge ghent antwerp brussels mons",
                           "neutral": "rennes nantes vannes brest liege metz nancy pau avignon marseille"},
                "capitals": {"england": "london", "france": "paris", "burgundy": "dijon"},
                "armies": {"formigny": ["longbowman", 20], "rouen": ["knight", 20], "crecy": ["knight", 15], "calais": ["swordsmen", 15]},
                "primary": [{"type": "capture", "regions": ["rouen"]},
                            {"type": "destroy_units", "faction": "france", "unit_type": "knight", "count": 20}],
                "additional": [{"type": "capture", "regions": ["paris"], "points": 300}],
                "defeat": [{"type": "lose_region", "region": "calais"}],
                "crowns": [8, 11, 14], "time": 16,
                "history": "Henry V has taken Harfleur, but sickness has cut his army down. He marches for Calais, and the "
                           "flower of French chivalry waits for him in the mud between two woods.",
                "briefing": "Destroy the French knights and take Rouen, the heart of Normandy.",
                "victory": "Agincourt is won. By the Treaty of Troyes Henry will be heir to the French crown.",
                "defeat_text": "Calais falls, and the English are driven from France.",
            },
            {
                "name": "Bosworth, 1485", "map": "england",
                "factions": [F("tudor", "Henry Tudor", "anglish", "#e2dcc4"), F("york", "King Richard III", "anglish", "#6e2a5a")],
                "rest": "york",
                "owners": {"tudor": "pembrokeshire glamorgan caernarfonshire anglesey leominster", "neutral": "isle_of_man"},
                "capitals": {"tudor": "pembrokeshire", "york": "london"},
                "armies": {"pembrokeshire": ["swordsmen", 20], "glamorgan": ["longbowman", 15], "leominster": ["yeoman", 15],
                           "caernarfonshire": ["spearmen", 15]},
                "primary": [{"type": "capture", "regions": ["leicester", "london"]}],
                "additional": [{"type": "lose_at_most", "unit_class": "cavalry", "count": 3}],
                "defeat": [{"type": "lose_region", "region": "pembrokeshire"}],
                "crowns": [9, 12, 15], "time": 18,
                "gold": {"tudor": 800},
                "history": "Henry Tudor, last hope of the House of Lancaster, has landed at Milford Haven with French money and "
                           "a few thousand men. The Welsh are rising for him, and King Richard gathers his army at Leicester.",
                "briefing": "March through Wales, beat Richard near Leicester and take London.",
                "victory": "Richard falls at Bosworth Field. Henry VII is crowned, and the Wars of the Roses are over.",
                "defeat_text": "Henry is driven back into the sea, and York keeps the crown.",
            },
        ],
    },
    {
        "id": "frankish", "civ": "frankish", "order": 2, "name": "France",
        "description": "Win back Normandy and Aquitaine from the English kings, break Flanders and the south, and drive "
                       "the English out of France for good.",
        "missions": [
            {
                "name": "Château Gaillard, 1204", "map": "france",
                "factions": [FRANCE, F("england", "King John", "anglish", "#b5423a"), BURGUNDY_F], "rest": "france",
                "owners": {"england": " ".join([ENG_ISLE, NORMANDY, ANJOU, AQUITAINE]), "burgundy": "dijon besancon auxerre macon",
                           "neutral": " ".join([BRITTANY, FLANDERS, LOW_LANDS, EMPIRE_WEST, SOUTH])},
                "capitals": {"france": "paris", "england": "london", "burgundy": "dijon"},
                "walls": {"rouen": 2},
                "primary": [{"type": "capture", "regions": ["rouen", "caen"]}],
                "additional": [{"type": "capture", "regions": ["le_mans"]}],
                "defeat": [{"type": "lose_region", "region": "paris"}],
                "crowns": [7, 10, 12], "time": 14,
                "history": "Richard the Lionheart built Château Gaillard on the Seine to guard Normandy, and swore it would hold "
                           "if its walls were made of butter. Richard is dead, and his brother John is no Richard.",
                "briefing": "Storm the Saucy Castle, take Rouen and Caen, and make Normandy French.",
                "victory": "Rouen opens its gates. After three centuries Normandy belongs to the king of France.",
                "defeat_text": "Paris falls, and the Angevins rule from the Somme to the Pyrenees.",
            },
            {
                "name": "The Albigensian Crusade, 1209", "map": "france",
                "factions": [FRANCE, F("toulouse", "County of Toulouse", "", "#c4962c", "defensive")], "rest": "france",
                "owners": {"toulouse": SOUTH + " cahors",
                           "neutral": " ".join([ENG_ISLE, "poitiers la_rochelle limoges perigueux bordeaux bayonne", BRITTANY,
                                                FLANDERS, LOW_LANDS, EMPIRE_WEST])},
                "capitals": {"france": "paris", "toulouse": "toulouse"},
                "walls": {"carcassonne": 2},
                "primary": [{"type": "capture", "regions": ["carcassonne", "toulouse"]}],
                "additional": [{"type": "lose_at_most", "unit_class": "cavalry", "count": 5}],
                "defeat": [{"type": "lose_region", "region": "lyon"}],
                "crowns": [8, 11, 14], "time": 16,
                "history": "The Pope has called a crusade against the Cathars of the south, and the barons of the north have "
                           "gathered at Lyon under Simon de Montfort. Count Raymond of Toulouse protects the heretics.",
                "briefing": "March down the Rhône, take Carcassonne and Toulouse, and bring the south under the crown.",
                "victory": "Carcassonne and Toulouse fall. The south will be French.",
                "defeat_text": "The crusade breaks apart, and the south keeps its counts.",
            },
            {
                "name": "Bouvines, 1214", "map": "france",
                "factions": [FRANCE, F("flanders", "Count of Flanders", "", "#d1a23a", "aggressive"),
                             F("empire", "Emperor Otto IV", "", "#5a5a5a", "aggressive"), F("england", "King John", "anglish", "#b5423a")],
                "rest": "france",
                "owners": {"flanders": " ".join([FLANDERS, LOW_LANDS]), "empire": EMPIRE_WEST,
                           "england": ENG_ISLE + " la_rochelle poitiers bordeaux bayonne", "neutral": BRITTANY + " " + SOUTH},
                "capitals": {"france": "paris", "flanders": "ghent", "empire": "liege", "england": "london"},
                "primary": [{"type": "capture", "regions": ["ghent"]}],
                "additional": [{"type": "capture", "regions": ["liege"], "points": 300}],
                "defeat": [{"type": "lose_region", "region": "paris"}],
                "crowns": [6, 8, 10], "time": 12,
                "events": [{"turn": 2, "type": "reinforcements", "faction": "england", "region": "la_rochelle", "unit": "longbowman",
                            "soldiers": 10, "text": "King John lands at La Rochelle to strike from the south."}],
                "history": "King John, the Emperor Otto and the Count of Flanders have joined against Philip Augustus. Otto "
                           "and the Flemish march from the north while John lands in Poitou.",
                "briefing": "Meet the northern army and break it, then carry the war into Flanders.",
                "victory": "At Bouvines Otto's eagle falls. John loses Anjou, and the king of France is master in his realm.",
                "defeat_text": "Paris falls to the coalition.",
            },
            {
                "name": "Taillebourg, 1242", "map": "france",
                "factions": [FRANCE, F("england", "King Henry III", "anglish", "#b5423a", "aggressive")], "rest": "france",
                "owners": {"england": ENG_ISLE + " " + AQUITAINE, "neutral": " ".join([BRITTANY, FLANDERS, LOW_LANDS, EMPIRE_WEST])},
                "capitals": {"france": "paris", "england": "london"},
                "primary": [{"type": "capture", "regions": ["poitiers", "la_rochelle"]}],
                "additional": [{"type": "capture", "regions": ["bordeaux"], "points": 300}],
                "defeat": [{"type": "lose_region", "region": "tours"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "Hugh of Lusignan has risen in Poitou, and Henry III of England has landed at Royan to help him "
                           "win back his father's lands.",
                "briefing": "Cross the Charente, beat Henry and take Poitou.",
                "victory": "Henry flees from Taillebourg and Saintes. Poitou is French.",
                "defeat_text": "Tours falls, and the Loire is lost.",
            },
            {
                "name": "Mons-en-Pévèle, 1304", "map": "france",
                "factions": [FRANCE, F("flanders", "Flemish Cities", "", "#d1a23a", "aggressive")], "rest": "france",
                "owners": {"flanders": FLANDERS, "neutral": " ".join([ENG_ISLE, "bordeaux bayonne", LOW_LANDS, EMPIRE_WEST])},
                "capitals": {"france": "paris", "flanders": "ghent"},
                "armies": {"ghent": ["pikemen", 20], "brugge": ["pikemen", 18], "antwerp": ["crossbowmen", 15]},
                "primary": [{"type": "capture", "regions": ["ghent", "brugge"]}],
                "additional": [{"type": "destroy_units", "faction": "flanders", "unit_type": "pikemen", "count": 15}],
                "defeat": [{"type": "lose_region", "region": "arras"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "Two years ago the weavers of Flanders cut down the French knights at Courtrai and hung their "
                           "golden spurs in a church. Philip the Fair has come back with a new army.",
                "briefing": "Beat the Flemish militia in the field, then take Ghent and Bruges.",
                "victory": "The Flemish break at Mons-en-Pévèle, and their cities pay for peace.",
                "defeat_text": "Arras falls, and Flanders is lost to the crown.",
            },
            {
                "name": "Du Guesclin, 1370", "map": "france",
                "factions": [FRANCE, ENGLISH_KING, BRITTANY_F], "rest": "france",
                "owners": {"england": ENG_ISLE + " calais " + AQUITAINE, "brittany": BRITTANY,
                           "neutral": " ".join([FLANDERS, LOW_LANDS, EMPIRE_WEST])},
                "capitals": {"france": "paris", "england": "london", "brittany": "nantes"},
                "primary": [{"type": "capture", "regions": ["poitiers", "la_rochelle", "limoges"]}],
                "additional": [{"type": "capture", "regions": ["perigueux"]}],
                "defeat": [{"type": "lose_region", "region": "paris"}],
                "crowns": [8, 11, 14], "time": 16,
                "history": "By the Peace of Brétigny the English hold a third of France. Charles V has made the Breton "
                           "Bertrand du Guesclin Constable of France, and he will not offer them a pitched battle.",
                "briefing": "Win Poitou and the Limousin back town by town.",
                "victory": "Poitiers and La Rochelle are French again, and the English hold little but Bordeaux and Calais.",
                "defeat_text": "Paris falls, and Brétigny becomes a beginning, not an end.",
            },
            {
                "name": "The Siege of Orléans, 1429", "map": "france", "base_history": True,
                "factions": [FRANCE, ENGLISH_KING, F("burgundy", "Duchy of Burgundy", "", "#d1a23a", "balanced"), BRITTANY_F],
                "capitals": {"france": "bourges", "england": "london", "burgundy": "dijon", "brittany": "nantes"},
                "armies": {"orleans": ["pikemen", 20], "chartres": ["longbowman", 15]},
                "primary": [{"type": "hold", "region": "orleans", "turns": 5}],
                "additional": [{"type": "capture", "regions": ["chartres"]}],
                "defeat": [{"type": "lose_region", "region": "bourges"}],
                "crowns": [6, 8, 10], "time": 10,
                "events": [{"turn": 1, "type": "reinforcements", "faction": "france", "region": "chinon", "unit": "sergeant", "soldiers": 10,
                            "text": "A girl from Domrémy, Joan, has come to the Dauphin at Chinon with a relief force for Orléans."}],
                "history": "The English and their Burgundian allies hold Paris and the north, and English forts ring Orléans, "
                           "the last great city on the Loire.",
                "briefing": "Hold Orléans for five turns, until the English give up the siege.",
                "victory": "The English forts burn, and the siege of Orléans is lifted.",
                "defeat_text": "Bourges falls, and the Dauphin has nowhere left to go.",
            },
            {
                "name": "The Road to Reims, 1429", "map": "france", "base_history": True,
                "factions": [FRANCE, ENGLISH_KING, F("burgundy", "Duchy of Burgundy", "", "#d1a23a", "balanced"), BRITTANY_F],
                "capitals": {"france": "bourges", "england": "london", "burgundy": "dijon", "brittany": "nantes"},
                "primary": [{"type": "capture", "regions": ["troyes", "reims"]}],
                "additional": [{"type": "capture", "regions": ["beauvais"]}],
                "defeat": [{"type": "lose_region", "region": "orleans"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "Orléans is free. Joan says the Dauphin must be crowned at Reims, where French kings have always "
                           "been crowned, deep in English and Burgundian country.",
                "briefing": "Take Troyes and Reims so Charles can be crowned.",
                "victory": "Charles VII is crowned in Reims cathedral, with Joan beside him.",
                "defeat_text": "Orléans falls again, and the coronation never happens.",
            },
            {
                "name": "Paris, 1436", "map": "france", "base_history": True,
                "factions": [FRANCE, ENGLISH_KING, F("burgundy", "Duchy of Burgundy", "", "#d1a23a", "defensive"), BRITTANY_F],
                "owners": {"france": "reims troyes beauvais chartres"},
                "capitals": {"france": "bourges", "england": "london", "burgundy": "dijon", "brittany": "nantes"},
                "primary": [{"type": "capture", "regions": ["paris"]}],
                "additional": [{"type": "capture", "regions": ["le_mans"]}],
                "defeat": [{"type": "lose_region", "region": "reims"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "By the Treaty of Arras the Duke of Burgundy has made peace with Charles VII. The English in Paris "
                           "stand alone, and the city is restless.",
                "briefing": "Take Paris back for the king while the English stand alone.",
                "victory": "The Parisians open the gates, and the English garrison marches out.",
                "defeat_text": "Reims falls, and the war turns against France once more.",
            },
            {
                "name": "Formigny, 1450", "map": "france",
                "factions": [FRANCE, ENGLISH_KING, BURGUNDY_F], "rest": "france",
                "owners": {"england": ENG_ISLE + " caen formigny avranches calais bordeaux bayonne",
                           "burgundy": "dijon besancon auxerre macon amiens arras " + FLANDERS + " " + LOW_LANDS,
                           "neutral": EMPIRE_WEST},
                "capitals": {"france": "paris", "england": "london", "burgundy": "dijon"},
                "primary": [{"type": "capture", "regions": ["caen", "formigny", "avranches"]}],
                "additional": [{"type": "destroy_units", "faction": "england", "unit_type": "longbowman", "count": 15}],
                "defeat": [{"type": "lose_region", "region": "rouen"}],
                "crowns": [7, 10, 12], "time": 14,
                "history": "Rouen fell last autumn. Sir Thomas Kyriell has landed at Cherbourg with the last English army in "
                           "Normandy, and the French guns are ready.",
                "briefing": "Destroy Kyriell's army and take the rest of Normandy.",
                "victory": "At Formigny the French cannon break the longbowmen, and Normandy is French for good.",
                "defeat_text": "Rouen falls back to the English.",
            },
            {
                "name": "Castillon, 1453", "map": "france",
                "factions": [FRANCE, ENGLISH_KING, BURGUNDY_F], "rest": "france",
                "owners": {"england": ENG_ISLE + " calais bordeaux bayonne",
                           "burgundy": "dijon besancon auxerre macon amiens arras " + FLANDERS + " " + LOW_LANDS,
                           "neutral": EMPIRE_WEST},
                "capitals": {"france": "paris", "england": "london", "burgundy": "dijon"},
                "primary": [{"type": "capture", "regions": ["bordeaux", "bayonne"]}],
                "additional": [{"type": "destroy_units", "faction": "england", "unit_type": "longbowman", "count": 15}],
                "defeat": [{"type": "lose_region", "region": "perigueux"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "The people of Bordeaux, English for three hundred years, have called back old John Talbot. "
                           "The French have dug in their guns before Castillon.",
                "briefing": "Break Talbot's army and take Bordeaux and Bayonne. Then the Hundred Years' War is over.",
                "victory": "Talbot dies charging the French guns at Castillon. Of all its French lands England keeps only Calais.",
                "defeat_text": "Périgueux falls, and Aquitaine stays English.",
            },
        ],
    },
    {
        "id": "crusader", "civ": "crusader", "order": 3, "name": "Crusades",
        "description": "From Antioch to Jerusalem and back again: two hundred years of war for the Holy Land.",
        "missions": [
            {
                "name": "Antioch, 1098", "map": "levant",
                "factions": [CRUSADERS, SYRIA, FATIMIDS, SELJUKS, BYZANTINES, ARMENIANS], "rest": "syria",
                "owners": {"crusaders": "marash adana tarsus", "fatimids": "beirut sidon tyre acre caesarea jaffa ascalon gaza "
                           "safad nablus jerusalem kerak " + EGYPT, "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia",
                           "armenians": "sis edessa bira", "neutral": "tripoli tortosa krak_des_chevaliers"},
                "capitals": {"crusaders": "marash", "syria": "aleppo", "fatimids": "jerusalem", "seljuks": "konya",
                             "byzantines": "lefkosa", "armenians": "edessa"},
                "walls": {"antioch": 2},
                "primary": [{"type": "capture", "regions": ["antioch", "st_simeon"]}],
                "additional": [{"type": "destroy_units", "faction": "syria", "unit_type": "", "count": 30}],
                "defeat": [{"type": "lose_region", "region": "marash"}],
                "crowns": [6, 8, 10], "time": 12,
                "events": [{"turn": 4, "type": "reinforcements", "faction": "syria", "region": "aleppo", "unit": "mamluk", "soldiers": 15,
                            "text": "Kerbogha of Mosul marches to relieve Antioch with a great army."}],
                "history": "The armies of the First Crusade have crossed Anatolia, through heat, thirst and the Turks' horse "
                           "archers, and come down to the walls of Antioch, the greatest city of Syria.",
                "briefing": "Take Antioch and its port, St Simeon, before Kerbogha arrives.",
                "victory": "Antioch falls, and the crusaders find the Holy Lance under the floor of St Peter's.",
                "defeat_text": "Marash falls, and the crusade dies in the hills.",
            },
            {
                "name": "The County of Edessa, 1098", "map": "levant",
                "factions": [CRUSADERS, ARMENIANS, SYRIA, FATIMIDS, SELJUKS, BYZANTINES], "rest": "syria",
                "owners": {"crusaders": "marash adana tarsus antioch st_simeon", "fatimids": "beirut sidon tyre acre caesarea jaffa "
                           "ascalon gaza safad nablus jerusalem kerak " + EGYPT, "seljuks": RUM,
                           "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis edessa bira",
                           "neutral": "tripoli tortosa krak_des_chevaliers"},
                "capitals": {"crusaders": "antioch", "syria": "aleppo", "fatimids": "jerusalem", "seljuks": "konya",
                             "byzantines": "lefkosa", "armenians": "edessa"},
                "primary": [{"type": "capture", "regions": ["edessa", "bira"]}],
                "additional": [{"type": "lose_at_most", "unit_class": "cavalry", "count": 5}],
                "defeat": [{"type": "lose_region", "region": "antioch"}],
                "crowns": [5, 7, 9], "time": 10,
                "history": "Baldwin of Boulogne has left the main army and ridden east to the Euphrates, where the Armenian "
                           "lord of Edessa has asked for his help.",
                "briefing": "Make Edessa and the Euphrates crossing at Bira the first crusader state.",
                "victory": "Baldwin is Count of Edessa, the first of the crusader states.",
                "defeat_text": "Antioch falls, and Baldwin's adventure ends.",
            },
            {
                "name": "Jerusalem, 1099", "map": "levant",
                "factions": [CRUSADERS, FATIMIDS, SYRIA, SELJUKS, BYZANTINES, ARMENIANS], "rest": "syria",
                "owners": {"crusaders": "marash adana tarsus antioch st_simeon edessa bira tortosa",
                           "fatimids": "beirut sidon tyre acre caesarea jaffa ascalon gaza safad nablus jerusalem kerak " + EGYPT,
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis",
                           "neutral": "tripoli krak_des_chevaliers"},
                "capitals": {"crusaders": "antioch", "syria": "aleppo", "fatimids": "jerusalem", "seljuks": "konya",
                             "byzantines": "lefkosa", "armenians": "sis"},
                "walls": {"jerusalem": 2},
                "primary": [{"type": "capture", "regions": ["jerusalem"]}],
                "additional": [{"type": "capture", "regions": ["jaffa"]}],
                "defeat": [{"type": "lose_region", "region": "antioch"}],
                "crowns": [7, 10, 12], "time": 14,
                "history": "Three years after leaving home, the crusaders march down the coast towards Jerusalem, which the "
                           "Fatimids of Egypt took from the Turks only last year.",
                "briefing": "Take the Holy City before Egypt sends an army to save it.",
                "victory": "On 15 July the crusaders storm the walls of Jerusalem.",
                "defeat_text": "Antioch falls behind you, and the crusade never reaches Jerusalem.",
            },
            {
                "name": "Ascalon, 1099", "map": "levant",
                "factions": [CRUSADERS, FATIMIDS, SYRIA, SELJUKS, BYZANTINES, ARMENIANS], "rest": "syria",
                "owners": {"crusaders": "marash adana tarsus antioch st_simeon edessa bira tortosa jerusalem jaffa nablus",
                           "fatimids": "beirut sidon tyre acre caesarea ascalon gaza safad kerak " + EGYPT,
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis",
                           "neutral": "tripoli krak_des_chevaliers"},
                "capitals": {"crusaders": "jerusalem", "syria": "aleppo", "fatimids": "ascalon", "seljuks": "konya",
                             "byzantines": "lefkosa", "armenians": "sis"},
                "primary": [{"type": "destroy_units", "faction": "fatimids", "unit_type": "", "count": 40}],
                "additional": [{"type": "capture", "regions": ["ascalon"], "points": 300}],
                "defeat": [{"type": "lose_region", "region": "jerusalem"}],
                "crowns": [5, 7, 9], "time": 10,
                "events": [{"turn": 1, "type": "reinforcements", "faction": "fatimids", "region": "ascalon", "unit": "ghazi", "soldiers": 15,
                            "text": "The vizier al-Afdal has landed at Ascalon with the army of Egypt."}],
                "history": "Jerusalem is taken, but the vizier of Egypt is coming to take it back, and most of the crusaders "
                           "want to go home.",
                "briefing": "March out and destroy the Egyptian army before it reaches Jerusalem.",
                "victory": "The Egyptian camp is taken at dawn, and the kingdom of Jerusalem will live.",
                "defeat_text": "Jerusalem falls back to Egypt within the year.",
            },
            {
                "name": "Tripoli, 1109", "map": "levant",
                "factions": [CRUSADERS, F("ammar", "Banu Ammar of Tripoli", "saracen", "#5aa04a", "defensive"), FATIMIDS, SYRIA,
                             SELJUKS, BYZANTINES, ARMENIANS], "rest": "syria",
                "owners": {"crusaders": "marash edessa bira antioch st_simeon tortosa jerusalem jaffa nablus acre caesarea safad",
                           "ammar": "tripoli krak_des_chevaliers", "fatimids": "beirut sidon tyre ascalon gaza kerak " + EGYPT,
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis adana tarsus"},
                "capitals": {"crusaders": "jerusalem", "ammar": "tripoli", "syria": "aleppo", "fatimids": "ascalon", "seljuks": "konya",
                             "byzantines": "lefkosa", "armenians": "sis"},
                "walls": {"tripoli": 2},
                "primary": [{"type": "capture", "regions": ["tripoli"]}],
                "additional": [{"type": "capture", "regions": ["beirut"]}],
                "defeat": [{"type": "lose_region", "region": "antioch"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "Tripoli has held out against the crusaders for five years behind its sea walls. Bertrand of "
                           "Toulouse has come from the West to claim his father's conquest.",
                "briefing": "Take Tripoli and found the fourth crusader state.",
                "victory": "Tripoli surrenders, and the County of Tripoli is born.",
                "defeat_text": "Antioch falls while the army is held before Tripoli.",
            },
            {
                "name": "Tyre, 1124", "map": "levant",
                "factions": [CRUSADERS, FATIMIDS, SYRIA, SELJUKS, BYZANTINES, ARMENIANS], "rest": "syria",
                "owners": {"crusaders": "marash edessa bira antioch st_simeon tortosa tripoli krak_des_chevaliers beirut sidon "
                           "jerusalem jaffa nablus acre caesarea safad",
                           "fatimids": "tyre ascalon gaza kerak " + EGYPT,
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis adana tarsus"},
                "capitals": {"crusaders": "jerusalem", "syria": "aleppo", "fatimids": "ascalon", "seljuks": "konya",
                             "byzantines": "lefkosa", "armenians": "sis"},
                "walls": {"tyre": 2},
                "primary": [{"type": "capture", "regions": ["tyre"]}],
                "additional": [{"type": "destroy_units", "faction": "fatimids", "unit_type": "", "count": 20}],
                "defeat": [{"type": "lose_region", "region": "acre"}],
                "crowns": [5, 7, 9], "time": 10,
                "history": "A Venetian fleet has destroyed the Egyptian navy off Ascalon. Now Venice and the kingdom lay siege "
                           "to Tyre, the strongest city on the coast.",
                "briefing": "Take Tyre while the Venetians hold the sea.",
                "victory": "Tyre surrenders after five months. The whole coast north of Ascalon is in Christian hands.",
                "defeat_text": "Acre falls, and the siege of Tyre is abandoned.",
            },
            {
                "name": "The Fall of Edessa, 1144", "map": "levant",
                "factions": [CRUSADERS, F("zengids", "Zengi of Mosul", "saracen", "#2e6a3a", "aggressive"),
                             F("burids", "Emirate of Damascus", "saracen", "#3d8a4a", "defensive"), FATIMIDS, SELJUKS, BYZANTINES,
                             ARMENIANS], "rest": "zengids",
                "owners": {"crusaders": "marash edessa bira antioch st_simeon tortosa tripoli krak_des_chevaliers beirut sidon tyre "
                           "jerusalem jaffa nablus acre caesarea safad kerak",
                           "burids": DAMASCUS, "fatimids": "ascalon gaza " + EGYPT,
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis adana tarsus"},
                "capitals": {"crusaders": "jerusalem", "zengids": "aleppo", "burids": "damascus", "fatimids": "ascalon",
                             "seljuks": "konya", "byzantines": "lefkosa", "armenians": "sis"},
                "armies": {"edessa": ["crossbowmen", 15], "aleppo": ["mamluk", 20], "raqqa": ["ghazi", 18]},
                "primary": [{"type": "hold", "region": "edessa", "turns": 6}],
                "additional": [{"type": "destroy_units", "faction": "zengids", "unit_type": "", "count": 30}],
                "defeat": [{"type": "lose_region", "region": "edessa"}],
                "crowns": [7, 8, 10], "time": 10,
                "events": [{"turn": 2, "type": "reinforcements", "faction": "zengids", "region": "raqqa", "unit": "mamluk", "soldiers": 10,
                            "text": "Zengi's army crosses the Euphrates."}],
                "history": "Count Joscelin II has taken his army west, and Zengi, atabeg of Mosul and Aleppo, has seized the "
                           "moment to strike at Edessa.",
                "briefing": "Hold Edessa until help comes. History says it falls.",
                "victory": "Zengi's army falls back from the walls, and Edessa stands.",
                "defeat_text": "Edessa falls on Christmas Eve, and Europe takes the cross again.",
            },
            {
                "name": "Damascus, 1148", "map": "levant",
                "factions": [CRUSADERS, F("burids", "Emirate of Damascus", "saracen", "#3d8a4a", "defensive"),
                             F("zengids", "Nur ad-Din", "saracen", "#2e6a3a", "aggressive"), FATIMIDS, SELJUKS, BYZANTINES, ARMENIANS],
                "rest": "zengids",
                "owners": {"crusaders": "antioch st_simeon tortosa tripoli krak_des_chevaliers beirut sidon tyre jerusalem jaffa "
                           "nablus acre caesarea safad kerak",
                           "burids": DAMASCUS, "fatimids": "ascalon gaza " + EGYPT,
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis adana tarsus"},
                "capitals": {"crusaders": "jerusalem", "zengids": "aleppo", "burids": "damascus", "fatimids": "ascalon",
                             "seljuks": "konya", "byzantines": "lefkosa", "armenians": "sis"},
                "walls": {"damascus": 2},
                "primary": [{"type": "capture", "regions": ["damascus"]}],
                "additional": [{"type": "capture", "regions": ["baalbek"]}],
                "defeat": [{"type": "lose_region", "region": "jerusalem"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "The Second Crusade has come, led by the kings of France and Germany. Instead of Edessa, the "
                           "barons have chosen Damascus, the richest city of Syria.",
                "briefing": "Take Damascus before Nur ad-Din comes down from Aleppo.",
                "victory": "Damascus falls, and the Second Crusade is not wasted after all.",
                "defeat_text": "Jerusalem falls while its army is away.",
            },
            {
                "name": "Ascalon, 1153", "map": "levant",
                "factions": [CRUSADERS, FATIMIDS, F("zengids", "Nur ad-Din", "saracen", "#2e6a3a", "aggressive"), SELJUKS, BYZANTINES,
                             ARMENIANS], "rest": "zengids",
                "owners": {"crusaders": "antioch st_simeon tortosa tripoli krak_des_chevaliers beirut sidon tyre jerusalem jaffa "
                           "nablus acre caesarea safad kerak",
                           "fatimids": "ascalon gaza " + EGYPT,
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis adana tarsus"},
                "capitals": {"crusaders": "jerusalem", "zengids": "aleppo", "fatimids": "ascalon", "seljuks": "konya",
                             "byzantines": "lefkosa", "armenians": "sis"},
                "walls": {"ascalon": 2},
                "primary": [{"type": "capture", "regions": ["ascalon"]}],
                "additional": [{"type": "capture", "regions": ["gaza"]}],
                "defeat": [{"type": "lose_region", "region": "jerusalem"}],
                "crowns": [5, 7, 9], "time": 10,
                "history": "Ascalon, the bride of Syria, is the last Egyptian fortress on the coast. Every year its garrison "
                           "raids the kingdom. King Baldwin III has brought siege towers.",
                "briefing": "Take Ascalon and close the road from Egypt.",
                "victory": "Ascalon falls after seven months, and the whole coast is in crusader hands.",
                "defeat_text": "Jerusalem falls while the army is at Ascalon.",
            },
            {
                "name": "Montgisard, 1177", "map": "levant",
                "factions": [CRUSADERS, AYYUBIDS, SELJUKS, BYZANTINES, ARMENIANS], "rest": "ayyubids",
                "owners": {"crusaders": "antioch st_simeon tortosa tripoli krak_des_chevaliers beirut sidon tyre jerusalem jaffa "
                           "nablus acre caesarea safad kerak ascalon gaza",
                           "seljuks": RUM, "byzantines": CYPRUS + " antalya alanya seleucia", "armenians": "sis adana tarsus"},
                "capitals": {"crusaders": "jerusalem", "ayyubids": "damascus", "seljuks": "konya", "byzantines": "lefkosa",
                             "armenians": "sis"},
                "armies": {"al_arish": ["mamluk", 20], "ascalon": ["brother_knight", 15]},
                "primary": [{"type": "destroy_units", "faction": "ayyubids", "unit_type": "mamluk", "count": 15}],
                "additional": [{"type": "capture", "regions": ["al_arish"]}],
                "defeat": [{"type": "lose_region", "region": "jerusalem"}],
                "crowns": [5, 7, 9], "time": 10,
                "events": [{"turn": 1, "type": "reinforcements", "faction": "ayyubids", "region": "al_arish", "unit": "mamluk", "soldiers": 10,
                            "text": "Saladin crosses the Sinai with the army of Egypt."}],
                "history": "King Baldwin IV is sixteen and a leper. Saladin has marched out of Egypt and the king's army is "
                           "shut up in Ascalon, with the road to Jerusalem open.",
                "briefing": "Catch Saladin's army on the march and destroy his Mamluks.",
                "victory": "At Montgisard the boy king's knights scatter Saladin's army.",
                "defeat_text": "Jerusalem falls to Saladin ten years early.",
            },
            {
                "name": "Hattin, 1187", "map": "levant", "base_history": True,
                "factions": [CRUSADERS, AYYUBIDS, SELJUKS, BYZANTINES, ARMENIANS],
                "capitals": {"crusaders": "jerusalem", "ayyubids": "damascus", "seljuks": "konya", "byzantines": "lefkosa",
                             "armenians": "sis"},
                "armies": {"jerusalem": ["brother_knight", 18], "banias": ["mamluk", 20], "damascus": ["ghazi", 20]},
                "walls": {"jerusalem": 2},
                "primary": [{"type": "hold", "region": "jerusalem", "turns": 6}],
                "additional": [{"type": "destroy_units", "faction": "ayyubids", "unit_type": "mamluk", "count": 10}],
                "defeat": [{"type": "lose_region", "region": "jerusalem"}],
                "crowns": [7, 8, 10], "time": 10,
                "events": [{"turn": 2, "type": "reinforcements", "faction": "ayyubids", "region": "banias", "unit": "mamluk", "soldiers": 10,
                            "text": "Saladin's host gathers on the Golan heights above the Sea of Galilee."}],
                "history": "Reynald of Châtillon has broken the truce. Saladin has gathered the largest army the kingdom has "
                           "ever faced, and King Guy is marching to meet it across the waterless hills.",
                "briefing": "History says Jerusalem falls this year. Keep it.",
                "victory": "Saladin's host melts away, and Jerusalem is still a Christian city.",
                "defeat_text": "Jerusalem falls to Saladin, as it did in 1187.",
            },
            {
                "name": "Third Crusade, second half of 1191–1192", "map": "levant",
                "factions": [CRUSADERS, AYYUBIDS, F("cyprus", "Isaac Komnenos of Cyprus", "byzantine", "#7a40a0", "defensive"),
                             SELJUKS, ARMENIANS], "rest": "ayyubids",
                "owners": {"crusaders": "tyre tripoli tortosa krak_des_chevaliers antioch st_simeon", "cyprus": CYPRUS,
                           "seljuks": RUM + " antalya alanya marash", "armenians": "seleucia tarsus adana sis"},
                "capitals": {"crusaders": "tyre", "ayyubids": "damascus", "cyprus": "lefkosa", "seljuks": "konya", "armenians": "sis"},
                "armies": {"tyre": ["brother_knight", 20], "acre": ["ghazi", 15], "jerusalem": ["mamluk", 20]},
                "walls": {"acre": 2, "jerusalem": 2},
                "primary": [{"type": "capture", "regions": ["acre", "jerusalem"]}],
                "additional": [{"type": "hold", "region": "paphos", "turns": 2, "text": "Take Paphos and hold it for 2 turns"},
                               {"type": "hold", "region": "lefkosa", "turns": 2, "text": "Take Lefkosa and hold it for 2 turns"}],
                "defeat": [{"type": "lose_army"}],
                "crowns": [5, 7, 9], "time": 9,
                "history": "The Christian states in the East hang by a thread. The emperor Frederick Barbarossa has drowned on "
                           "the way, and Richard the Lionheart and Philip of France quarrel over Cyprus, but the crusade is "
                           "still strong, and Saladin has lost many men.",
                "briefing": "Take Acre and Jerusalem. Cyprus will keep the crusade supplied.",
                "victory": "Acre and Jerusalem are taken. The Third Crusade has done what the Second could not.",
                "defeat_text": "The crusade melts away, and Richard sails home.",
            },
        ],
    },
    {
        "id": "norse", "civ": "norse", "order": 4, "name": "Vikings",
        "description": "From the first raids on Northumbria to the last great invasion of England.",
        "missions": [
            {
                "name": "Lindisfarne, 793", "map": "british_isles",
                "factions": [VIKINGS, F("northumbria", "Kingdom of Northumbria", "anglish", "#b5423a"),
                             F("mercia", "Kingdom of Mercia", "anglish", "#7a5a2a", "defensive"), SCOTLAND_F, WALES_F, IRELAND_F],
                "rest": "mercia",
                "owners": {"vikings": "lewis caithness dornoch stamford_bridge", "northumbria": NORTHUMBRIA, **CELTS},
                "capitals": {"vikings": "caithness", "northumbria": "york", "mercia": "warwick", **CELT_CAPITALS},
                "armies": {"stamford_bridge": ["berserker", 20], "bamburgh": ["spearmen", 12], "durham": ["militia", 12]},
                "primary": [{"type": "capture", "regions": ["bamburgh", "durham"]}],
                "additional": [{"type": "capture", "regions": ["york"], "points": 300}],
                "defeat": [{"type": "lose_region", "region": "stamford_bridge"}],
                "crowns": [6, 8, 10], "time": 12,
                "history": "Strange ships have been seen off the coast of Northumbria. The monks of Lindisfarne have gold and "
                           "silver on their altars and no swords.",
                "briefing": "Raid the holy island at Bamburgh and the monastery at Durham.",
                "victory": "The church of St Cuthbert is plundered. The Viking Age has begun.",
                "defeat_text": "The Northumbrians burn your camp, and the ships sail home empty.",
            },
            {
                "name": "The Great Heathen Army, 866", "map": "british_isles",
                "factions": [VIKINGS, F("northumbria", "Kingdom of Northumbria", "anglish", "#b5423a"),
                             F("mercia", "Kingdom of Mercia", "anglish", "#7a5a2a", "defensive"),
                             F("wessex", "Kingdom of Wessex", "anglish", "#c46a3a"), SCOTLAND_F, WALES_F, IRELAND_F],
                "rest": "wessex",
                "owners": {"vikings": "norwich colchester cambridge lewis caithness dornoch", "northumbria": NORTHUMBRIA + " stamford_bridge",
                           "mercia": "lincoln nottingham leicester chester shrewsbury warwick hereford gloucester oxford", **CELTS},
                "capitals": {"vikings": "norwich", "northumbria": "york", "mercia": "warwick", "wessex": "winchester", **CELT_CAPITALS},
                "armies": {"norwich": ["huscarl", 20], "cambridge": ["berserker", 18], "colchester": ["archers", 15]},
                "primary": [{"type": "capture", "regions": ["york", "nottingham"]}],
                "additional": [{"type": "capture", "regions": ["london"], "points": 300}],
                "defeat": [{"type": "lose_region", "region": "norwich"}],
                "crowns": [7, 10, 12], "time": 14,
                "history": "The sons of Ragnar Lothbrok have landed in East Anglia with the greatest army England has ever "
                           "seen, sworn to avenge their father.",
                "briefing": "Take York from the quarrelling Northumbrians, then Nottingham in Mercia.",
                "victory": "York is yours, and half of England will be the Danelaw.",
                "defeat_text": "East Anglia rises behind you, and the great army breaks up.",
            },
            {
                "name": "Paris, 845", "map": "france",
                "factions": [VIKINGS, F("france", "West Francia", "frankish", "#3d6fb6"), BRITTANY_F], "rest": "france",
                "owners": {"vikings": "rouen", "brittany": BRITTANY, "neutral": ENG_ISLE},
                "capitals": {"vikings": "rouen", "france": "paris", "brittany": "nantes"},
                "armies": {"rouen": ["huscarl", 20]},
                "gold": {"vikings": 800},
                "primary": [{"type": "capture", "regions": ["paris"]}],
                "additional": [{"type": "capture", "regions": ["beauvais", "chartres"]}],
                "defeat": [{"type": "lose_region", "region": "rouen"}],
                "crowns": [6, 8, 10], "time": 12,
                "events": [{"turn": 3, "type": "message", "text": "King Charles the Bald gathers an army at Saint-Denis."}],
                "history": "A hundred and twenty longships under a chief called Ragnar have rowed up the Seine. Rouen is "
                           "taken, and the road to Paris lies open.",
                "briefing": "Row up the Seine and sack Paris on Easter Sunday.",
                "victory": "Paris is sacked, and Charles the Bald pays seven thousand pounds of silver to see you go.",
                "defeat_text": "The Franks retake Rouen, and the fleet is trapped in the river.",
            },
            {
                "name": "Unification of Norway, 872", "map": "scandinavia",
                "factions": [F("norway", "Harald Fairhair", "norse", "#d1a23a"), F("petty", "Petty Kings of Norway", "norse", "#6a7a8a", "defensive"),
                             F("danes", "Kingdom of Denmark", "norse", "#cfd2e6", "defensive"),
                             F("swedes", "Svear", "norse", "#3d6fb6", "defensive")], "rest": "neutral",
                "owners": {"norway": "oslo tonsberg hamar tanum", "petty": "trondheim borgund bergen stavanger agder",
                           "danes": "ribe slesvik jelling aarhus viborg aalborg funen zealand lolland lund halmstad",
                           "swedes": "uppsala stockholm vasteras nykoping linkoping orebro jonkoping skara lodose kalmar vaxjo karlstad "
                                     "tuna gavle halsingland"},
                "capitals": {"norway": "tonsberg", "petty": "stavanger", "danes": "zealand", "swedes": "uppsala"},
                "primary": [{"type": "capture", "regions": ["stavanger", "bergen", "trondheim"]}],
                "additional": [{"type": "destroy_units", "faction": "petty", "unit_type": "huscarl", "count": 10}],
                "defeat": [{"type": "lose_region", "region": "tonsberg"}],
                "crowns": [8, 11, 14], "time": 16,
                "history": "Harald, king in Vestfold, asked for the hand of Gyda, who said she would not marry a man who ruled "
                           "less than all of Norway. Harald has sworn not to cut his hair until he does.",
                "briefing": "Beat the petty kings of the west at Hafrsfjord and unite Norway.",
                "victory": "The kings of the west fall at Hafrsfjord. Harald cuts his hair, and Norway is one kingdom.",
                "defeat_text": "Tønsberg falls, and Harald's hair grows on.",
            },
            {
                "name": "Rollo, 911", "map": "france",
                "factions": [VIKINGS, F("france", "West Francia", "frankish", "#3d6fb6"), BRITTANY_F], "rest": "france",
                "owners": {"vikings": "rouen caen formigny", "brittany": BRITTANY, "neutral": ENG_ISLE},
                "capitals": {"vikings": "rouen", "france": "paris", "brittany": "nantes"},
                "primary": [{"type": "hold", "region": "rouen", "turns": 5}],
                "additional": [{"type": "capture", "regions": ["chartres"]}],
                "defeat": [{"type": "lose_region", "region": "rouen"}],
                "crowns": [6, 8, 10], "time": 10,
                "history": "Rollo and his Danes have raided the Seine for years. King Charles the Simple, tired of war, may "
                           "give them the land if they can keep it.",
                "briefing": "Hold Rouen until the king comes to terms.",
                "victory": "At Saint-Clair-sur-Epte Charles grants Rollo the land around Rouen. It will be called Normandy.",
                "defeat_text": "The Franks take Rouen, and Rollo's Danes are scattered.",
            },
            {
                "name": "Svolder, 1000", "map": "scandinavia", "base_history": True,
                "factions": [F("norway", "Olaf Tryggvason", "norse", "#d1a23a"), F("danes", "Sweyn Forkbeard", "norse", "#cfd2e6", "aggressive"),
                             F("swedes", "Olof of Sweden", "norse", "#3d6fb6", "aggressive"),
                             F("empire", "Holy Roman Empire", "", "#5a5a5a", "defensive")],
                "capitals": {"norway": "trondheim", "danes": "zealand", "swedes": "uppsala", "empire": "hamburg"},
                "primary": [{"type": "destroy_units", "faction": "danes", "unit_type": "", "count": 40}],
                "additional": [{"type": "capture", "regions": ["lund"]}],
                "defeat": [{"type": "lose_region", "region": "trondheim"}],
                "crowns": [6, 8, 10], "time": 12,
                "events": [{"turn": 2, "type": "reinforcements", "faction": "danes", "region": "zealand", "unit": "huscarl", "soldiers": 10,
                            "text": "Sweyn and Olof of Sweden join their fleets against Olaf."}],
                "history": "Olaf Tryggvason has made Norway Christian with fire and sword. Now the kings of Denmark and Sweden "
                           "and the jarl Eric lie in wait for him off the island of Svolder.",
                "briefing": "Destroy the Danish fleet before the allies close the trap.",
                "victory": "The Long Serpent wins the day, and Olaf's enemies flee.",
                "defeat_text": "Trondheim falls, and Olaf leaps from the Long Serpent into the sea.",
            },
            {
                "name": "Sweyn Forkbeard, 1013", "map": "england",
                "factions": [DENMARK, ENGLAND], "rest": "england",
                "owners": {"denmark": "glamorgan hereford warwick gloucester glastonbury salisbury dorchester winchester guildford "
                                      "rochester hastings", "neutral": "anglesey isle_of_man"},
                "capitals": {"denmark": "winchester", "england": "london"},
                "primary": [{"type": "capture", "regions": ["london", "york"]}],
                "additional": [{"type": "lose_at_most", "unit_class": "cavalry", "count": 3}],
                "defeat": [{"type": "lose_region", "region": "winchester"}],
                "crowns": [7, 10, 12], "time": 14,
                "history": "Sweyn Forkbeard, king of Denmark, has come for the English crown. His fleet holds the Channel, "
                           "and Æthelred the Unready is losing his kingdom town by town.",
                "briefing": "Take London and York, and Sweyn will be king of England.",
                "victory": "London submits, Æthelred flees to Normandy, and Sweyn is king of England.",
                "defeat_text": "Winchester falls, and the Danes go home.",
            },
            {
                "name": "Cnut the Great, 1026", "map": "scandinavia", "base_history": True,
                "factions": [F("danes", "Cnut the Great", "norse", "#cfd2e6"), F("norway", "Olaf of Norway", "norse", "#d1a23a", "aggressive"),
                             F("swedes", "Anund Jacob of Sweden", "norse", "#3d6fb6", "aggressive"),
                             F("empire", "Holy Roman Empire", "", "#5a5a5a", "defensive")],
                "capitals": {"danes": "zealand", "norway": "trondheim", "swedes": "uppsala", "empire": "hamburg"},
                "primary": [{"type": "capture", "regions": ["trondheim", "uppsala"]}],
                "additional": [{"type": "capture", "regions": ["visby"]}],
                "defeat": [{"type": "lose_region", "region": "zealand"}],
                "crowns": [9, 12, 15], "time": 18,
                "history": "Cnut rules England and Denmark. King Olaf of Norway and King Anund Jacob of Sweden have joined "
                           "against him and raid Scania while he is away.",
                "briefing": "Beat the allies and make yourself king of Norway, Denmark and the Swedes.",
                "victory": "Olaf flees to Russia. Cnut is king of England, Denmark, Norway and part of Sweden.",
                "defeat_text": "Zealand falls, and Cnut's North Sea empire is broken.",
            },
            {
                "name": "Harald Hardrada, 1066", "map": "england",
                "factions": [NORWAY, ENGLAND], "rest": "england",
                "owners": {"norway": "stamford_bridge isle_of_man", "neutral": WELSH},
                "capitals": {"norway": "stamford_bridge", "england": "london"},
                "armies": {"stamford_bridge": ["huscarl", 20], "isle_of_man": ["berserker", 15]},
                "gold": {"norway": 900},
                "primary": [{"type": "capture", "regions": ["york", "london"]}],
                "additional": [{"type": "capture", "regions": ["lincoln"]}],
                "defeat": [{"type": "lose_region", "region": "stamford_bridge"}],
                "crowns": [7, 10, 12], "time": 14,
                "events": [{"turn": 2, "type": "reinforcements", "faction": "norway", "region": "stamford_bridge", "unit": "berserker",
                            "soldiers": 10, "text": "Tostig's ships join the fleet in the Humber."}],
                "history": "King Edward is dead, and Harald Hardrada, the last great Viking, claims his throne. Three hundred "
                           "ships have come up the Humber.",
                "briefing": "Take York and then London, and become king of England.",
                "victory": "Harold Godwinson falls, and a Norwegian sits on the English throne.",
                "defeat_text": "At Stamford Bridge the English catch you without your mail, and the Viking Age ends with you.",
            },
        ],
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


def build(campaign, index, spec):
    data, graph = load_map(spec["map"])
    where = f"{campaign['id']} {index + 1} ({spec['name']})"
    if spec.get("base_history"):
        owners = dict(data["history"]["owners"])
    else:
        owners = {r: spec.get("rest", "neutral") for r in graph}
    for faction, regions in spec.get("owners", {}).items():
        for region in regions.split():
            assert region in graph, f"{where}: no region {region}"
            owners[region] = faction
    factions = [dict(f, human=(i == 0)) for i, f in enumerate(spec["factions"])]
    ids = [f["id"] for f in factions]
    for region, owner in owners.items():
        assert owner == "neutral" or owner in ids, f"{where}: {region} goes to unknown {owner}"
    for faction, capital in spec["capitals"].items():
        assert owners[capital] == faction, f"{where}: {faction} doesn't hold its capital {capital}"
    civ_of = {f["id"]: f["civ"] for f in factions}
    armies = {}
    if spec.get("auto", True):
        for faction in factions:
            held = order_from(graph, spec["capitals"][faction["id"]], [r for r, f in owners.items() if f == faction["id"]])
            kinds = ARMIES[faction["civ"]]
            for i, region in enumerate(held[: max(2, (len(held) + 1) // 2)]):
                armies[region] = (kinds[i % len(kinds)], 20 if i == 0 else 15 if i < 3 else 12)
    # Every region an objective names, and every region the player must keep, is held by an army.
    named = []
    for objective in spec["primary"] + spec["additional"]:
        named += objective.get("regions", []) + ([objective["region"]] if "region" in objective else [])
    named += [d["region"] for d in spec["defeat"] if "region" in d]
    for region in named:
        assert region in graph, f"{where}: objective names unknown region {region}"
        if region not in armies and owners[region] != "neutral":
            armies[region] = (ARMIES[civ_of[owners[region]]][1], 15)
    for region, (kind, soldiers) in spec.get("armies", {}).items():
        assert region in graph, f"{where}: army in unknown region {region}"
        if soldiers > 0:
            armies[region] = (kind, soldiers)
        else:
            armies.pop(region, None)
    units = [{"owner": owners[r], "region": r, "type": kind, "soldiers": soldiers}
             for r, (kind, soldiers) in sorted(armies.items()) if owners[r] != "neutral"]
    for region in sorted(r for r, f in owners.items() if f == "neutral"):
        units.append({"owner": "neutral", "region": region, "type": "militia", "soldiers": 10})
    buildings = {}
    for region in list(spec["capitals"].values()) + list(spec.get("walls", {})):
        buildings.setdefault(region, {})["walls"] = spec.get("walls", {}).get(region, 1)
    for region in data["history"].get("buildings", {}):
        if region in owners and "walls" in data["history"]["buildings"][region]:
            buildings.setdefault(region, {})["walls"] = max(buildings.get(region, {}).get("walls", 0), 1)
    mission = {
        "player": ids[0], "primary": spec["primary"], "additional": spec["additional"],
        "defeat": [{"type": "time", "turns": spec["time"]}] + spec["defeat"],
        "crowns": spec["crowns"], "events": spec.get("events", []),
        "history": spec["history"], "briefing": spec["briefing"],
        "victory_text": spec["victory"], "defeat_text": spec["defeat_text"],
    }
    scenario = {
        "id": f"{campaign['id']}_{index + 1}", "name": spec["name"], "map": spec["map"],
        "factions": factions, "owners": owners, "capitals": spec["capitals"],
        "buildings": buildings, "units": units, "mission": mission,
        "campaign": campaign["id"], "mission_index": index,
    }
    if "gold" in spec:
        scenario["resources"] = {f: {"gold": g} for f, g in spec["gold"].items()}
    return scenario


# S&T's tutorial: the north of England, England against the Danes. The Danes
# stand and wait ("passive"); the regions not in play are neutral and empty.
TUTORIAL = {
    "name": "Tutorial", "map": "england",
    "factions": [ENGLAND, F("denmark", "Kingdom of Denmark", "norse", "#cfd2e6", "passive")], "rest": "neutral",
    "owners": {"england": "newcastle cumbria york lancaster stamford_bridge lincoln", "denmark": "doncaster"},
    "capitals": {"england": "york", "denmark": "doncaster"},
    "auto": False,
    "armies": {"york": ["spearmen", 8], "cumbria": ["swordsmen", 6], "lancaster": ["light_cavalry", 4],
               "stamford_bridge": ["swordsmen", 10], "lincoln": ["archers", 6], "doncaster": ["spearmen", 6]},
    "primary": [{"type": "capture", "regions": ["doncaster"], "text": "Conquer all enemy provinces"}],
    "additional": [], "defeat": [], "crowns": [3, 4, 5], "time": 10,
    "history": "", "briefing": "Learn to command an army in the north of England.",
    "victory": "Your training is complete.", "defeat_text": "Even veterans lose a battle. Try again.",
}


def build_tutorial():
    scenario = build({"id": "tutorial"}, -1, TUTORIAL)
    scenario["id"] = "tutorial"
    scenario.pop("campaign")
    scenario.pop("mission_index")
    scenario["units"] = [u for u in scenario["units"] if u["owner"] != "neutral"]
    scenario["mission"]["tutorial"] = True
    scenario["mission"]["defeat"] = []
    with open("data/tutorial/tutorial.json", "w") as f:
        f.write(json.dumps(scenario, indent=1, ensure_ascii=False) + "\n")
    print("tutorial")


def main():
    build_tutorial()
    for campaign in CAMPAIGNS:
        if not campaign["missions"]:
            continue
        out = {k: v for k, v in campaign.items() if k != "missions"}
        out["missions"] = [build(campaign, i, spec) for i, spec in enumerate(campaign["missions"])]
        with open(f"data/campaigns/{campaign['id']}.json", "w") as f:
            f.write(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
        print(campaign["id"], len(out["missions"]), "missions")


if __name__ == "__main__":
    main()
