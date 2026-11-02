# Credits

## Unit figures (painted, 3D-rendered)

The unit figures in `assets/figures/` (`<unit>.png` and its faction-colour layer `<unit>_team.png`, 18 unit types)
were rendered for this game by [tools/render_figures.gd](tools/render_figures.gd) from 3D models by
**Quaternius**, released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain; credit
is not required but is given here). The models were posed, given weapons and helmets, recoloured, lit and rendered
at a 3/4 top-down angle; the catapult and the crossbow stock are built from simple boxes in the script. The models
themselves are not in the repository: [tools/fetch_figure_models.sh](tools/fetch_figure_models.sh) downloads them
from the single-model mirror [github.com/trebeljahr/quaternius-showcase](https://github.com/trebeljahr/quaternius-showcase)
(commit `722c39e`).

| Models used | Pack | Author | Source | Licence |
|---|---|---|---|---|
| Farmer, King, Adventurer (bodies and heads) | Ultimate Modular Men Pack | Quaternius | [quaternius.com/packs/ultimatemodularcharacters.html](https://quaternius.com/packs/ultimatemodularcharacters.html) | CC0 1.0 |
| Helmet1, Helmet2, Helmet3 | Animated Knight Pack | Quaternius | [quaternius.com/packs/knightcharacter.html](https://quaternius.com/packs/knightcharacter.html) | CC0 1.0 |
| Horse, Horse_White | Ultimate Animated Animal Pack | Quaternius | [quaternius.com/packs/ultimateanimatedanimals.html](https://quaternius.com/packs/ultimateanimatedanimals.html) | CC0 1.0 |
| Spear, Bow_Wooden, Bow_Wooden2, Sword, Sword_2, Axe, Axe_Double, Axe_Small, Shield_Heater, Shield_Round, Shield_Round_2 | Modular Weapons Pack | Quaternius | [quaternius.com/packs/medievalweapons.html](https://quaternius.com/packs/medievalweapons.html) | CC0 1.0 |

Each unit type is rendered in three poses (`<unit>.png`, `<unit>_v1.png`, `<unit>_v2.png`, each with its `_team`
layer): the same models turned slightly, with the weapon held at another angle.

## Music and sound effects

Every audio file is released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain;
credit is not required but is given here). The files in `assets/audio/` were trimmed, mixed, levelled and
re-encoded as small Ogg Vorbis files by [tools/make_audio.sh](tools/make_audio.sh). For the freesound.org sounds
the high-quality preview of the original upload was used.

| File | Source | Author | Licence |
|---|---|---|---|
| `assets/audio/music/menu_minstrel_dance.ogg` | [Medieval: Minstrel Dance](https://opengameart.org/content/medieval-minstrel-dance) (loop) | RandomMind | CC0 1.0 |
| `assets/audio/music/map_bards_tale.ogg` | [Medieval: The Bard's Tale](https://opengameart.org/content/medieval-the-bards-tale) (loop) | RandomMind | CC0 1.0 |
| `assets/audio/music/map_old_tower_inn.ogg` | [Medieval: The Old Tower Inn](https://opengameart.org/content/medieval-the-old-tower-inn) (loop) | RandomMind | CC0 1.0 |
| `assets/audio/music/victory.ogg` | [Victory Fanfare Short](https://opengameart.org/content/victory-fanfare-short) | cynicmusic | CC0 1.0 |
| `assets/audio/music/defeat.ogg` | [Sad game over](https://opengameart.org/content/sad-game-over) (first 9 seconds, faded) | Emma_MA | CC0 1.0 |
| `assets/audio/sfx/ui_click.ogg` | `click_001` from [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 |
| `assets/audio/sfx/unit_select.ogg` | `beltHandle1` from [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | CC0 1.0 |
| `assets/audio/sfx/order_thunk.ogg` | `impactWood_heavy_001` from [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 |
| `assets/audio/sfx/hourglass.ogg` | [Turning a Small Hour Glass.wav](https://freesound.org/people/el_boss/sounds/625655/) (first 1.8 s) | el_boss | CC0 1.0 |
| `assets/audio/sfx/march.ogg` | `footstep_grass_000`–`003` from [Impact Sounds](https://kenney.nl/assets/impact-sounds), in step | Kenney | CC0 1.0 |
| `assets/audio/sfx/hooves.ogg` | [Horse Gallop - Loopable.mp3](https://freesound.org/people/HebronTheatre/sounds/197212/) | HebronTheatre | CC0 1.0 |
| `assets/audio/sfx/sword_clash.ogg` | `impactMetal_heavy_000`, `impactPlate_medium_002`, `impactMetal_heavy_003` from [Impact Sounds](https://kenney.nl/assets/impact-sounds), mixed | Kenney | CC0 1.0 |
| `assets/audio/sfx/arrow_volley.ogg` | [volley of arrows01.wav](https://freesound.org/people/mcaseydesign/sounds/474121/) | mcaseydesign | CC0 1.0 |
| `assets/audio/sfx/catapult_throw.ogg` | [R01-04-Catapult Launch.wav](https://freesound.org/people/craigsmith/sounds/479922/) (the first launch) | craigsmith | CC0 1.0 |
| `assets/audio/sfx/catapult_impact.ogg` | `impactMining_001` and `impactWood_heavy_003` from [Impact Sounds](https://kenney.nl/assets/impact-sounds), mixed | Kenney | CC0 1.0 |
| `assets/audio/sfx/capture_horn.ogg` | [Horn002.wav](https://freesound.org/people/freefire66/sounds/175946/) | freefire66 | CC0 1.0 |
| `assets/audio/sfx/coins.ogg` | `handleCoins` from [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | CC0 1.0 |
| `assets/audio/sfx/unit_destroyed.ogg` | `impactSoft_heavy_002` from [Impact Sounds](https://kenney.nl/assets/impact-sounds) and `dropLeather` from [RPG Audio](https://kenney.nl/assets/rpg-audio), mixed | Kenney | CC0 1.0 |

## Icons

The icons are from [game-icons.net](https://game-icons.net)
([github.com/game-icons/icons](https://github.com/game-icons/icons)), licensed under
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). The black background square was removed from each SVG
so the white shape can be tinted; the shapes are unchanged.

| File | Icon | Author | Used for | Licence |
|---|---|---|---|---|
| `assets/icons/knight.svg` | [visored-helm](https://game-icons.net/1x1/lorc/visored-helm.html) | Lorc | Reinforcements button | CC BY 3.0 |
| `assets/icons/map_crown.svg` | [crown](https://game-icons.net/1x1/lorc/crown.html) | Lorc | Capital marker | CC BY 3.0 |
| `assets/icons/map_tower.svg` | [tower-flag](https://game-icons.net/1x1/delapouite/tower-flag.html) | Delapouite | Castle (walls) marker | CC BY 3.0 |
| `assets/icons/map_camp.svg` | [camping-tent](https://game-icons.net/1x1/delapouite/camping-tent.html) | Delapouite | Camp marker (reinforcements) | CC BY 3.0 |
| `assets/icons/map_town.svg` | [village](https://game-icons.net/1x1/delapouite/village.html) | Delapouite | Town marker (reinforcements) | CC BY 3.0 |
| `assets/icons/map_ship.svg` | [drakkar](https://game-icons.net/1x1/delapouite/drakkar.html) | Delapouite | Ships on the coast | CC BY 3.0 |
| `assets/icons/ui_coins.svg` | [coins-pile](https://game-icons.net/1x1/delapouite/coins-pile.html) | Delapouite | Gold, region income, prices | CC BY 3.0 |
| `assets/icons/ui_hourglass.svg` | [hourglass](https://game-icons.net/1x1/lorc/hourglass.html) | Lorc | End turn and turn counter | CC BY 3.0 |
| `assets/icons/ui_pause.svg` | [pause-button](https://game-icons.net/1x1/guard13007/pause-button.html) | Guard13007 | Menu button | CC BY 3.0 |
| `assets/icons/ui_swords.svg` | [crossed-swords](https://game-icons.net/1x1/lorc/crossed-swords.html) | Lorc | Melee slider and battles | CC BY 3.0 |
| `assets/icons/ui_check.svg` | [check-mark](https://game-icons.net/1x1/delapouite/check-mark.html) | Delapouite | Confirm buttons | CC BY 3.0 |
| `assets/icons/ui_anvil.svg` | [anvil](https://game-icons.net/1x1/lorc/anvil.html) | Lorc | The Forge | CC BY 3.0 |

## Fonts

| File | Font | Author | Licence |
|---|---|---|---|
| `assets/fonts/Cinzel.ttf` | [Cinzel](https://github.com/google/fonts/tree/main/ofl/cinzel) | The Cinzel Project Authors (Natanael Gama) | [SIL OFL 1.1](assets/fonts/Cinzel-OFL.txt) |
| `assets/fonts/IMFellEnglish-Regular.ttf`, `assets/fonts/IMFellEnglish-Italic.ttf` | [IM FELL English](https://github.com/google/fonts/tree/main/ofl/imfellenglish) | Igino Marini | [SIL OFL 1.1](assets/fonts/IMFellEnglish-OFL.txt) |
| `assets/fonts/NotoSansSymbols2-Symbols.ttf` | [Noto Sans Symbols 2](https://github.com/google/fonts/tree/main/ofl/notosanssymbols2) | The Noto Project Authors | [SIL OFL 1.1](assets/fonts/NotoSansSymbols2-OFL.txt) |
| `assets/fonts/NotoSansMath-Arrows.ttf` | [Noto Sans Math](https://github.com/google/fonts/tree/main/ofl/notosansmath) | The Noto Project Authors | [SIL OFL 1.1](assets/fonts/NotoSansMath-OFL.txt) |

Cinzel and IM FELL English are unmodified copies from the google/fonts repository. The two Noto fonts are
cut down to their symbol blocks, with their line height lowered to IM FELL English's, by
[tools/make_symbol_fonts.sh](tools/make_symbol_fonts.sh); they supply ★ ☆ ✓ ✗ ■ → − where the game fonts have
none.

## Made for this game

The maps (including the tutorial's), region names, campaigns, tutorial and text; the parchment, wood, stone, shield-button and plaque textures
(generated by [tools/make_theme.gd](tools/make_theme.gd)); the map, sea, parchment-stain and vignette shaders; the
banners, heraldic shields, spear arrows, particles and animations; the poses, lighting and rendering of the unit
figures. Nothing is copied from *Strategy & Tactics: Medieval Wars*: its screenshots were used
only as a reference for layout and feel.
