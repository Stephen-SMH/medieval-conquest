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

The music is licensed under [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/)
(CC BY 4.0): free to use with credit, which is given here and in the game's Credits screen. Most sound effects are
released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain; credit is not required
but is given here); the battle clash and the victory cheer are CC BY 4.0, credited here and in the Credits screen too. Everything in `assets/audio/` was trimmed, mixed, levelled and re-encoded as Ogg Vorbis by
[tools/make_audio.sh](tools/make_audio.sh): music at quality 4 (about 128 kbps), levelled to -16 LUFS on the map and
-14 LUFS for the menu and battles; sound effects small. For the freesound.org sounds the high-quality preview of the
original upload was used.

| File | Source | Author | Licence |
|---|---|---|---|
| `assets/audio/music/menu_rise_of_kingdoms.ogg` | [Rise of Kingdoms](https://creatorchords.com/music/rise-of-kingdoms/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/map_medieval_chateau.ogg` | [Medieval Chateau](https://creatorchords.com/music/medieval-chateau/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/map_towards_the_horizon.ogg` | [Towards the Horizon](https://creatorchords.com/music/towards-the-horizon/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/map_gates_of_glory.ogg` | [Gates of Glory](https://creatorchords.com/music/gates-of-glory/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/map_tavern_tales.ogg` | [Tavern Tales](https://creatorchords.com/music/tavern-tales/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/map_the_vikings.ogg` | [The Vikings](https://creatorchords.com/music/the-vikings/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/battle_loop.ogg` | [Battle Loop](https://creatorchords.com/music/battle-loop/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/battle_the_great_battle.ogg` | [The Great Battle](https://creatorchords.com/music/the-great-battle/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/victory_superepic.ogg` | [Superepic](https://creatorchords.com/music/superepic/) | Alexander Nakarada (CreatorChords) | CC BY 4.0 |
| `assets/audio/music/defeat_for_the_fallen.ogg` | [For the Fallen](https://incompetech.com/music/royalty-free/music.html) (first 48 seconds, faded) | Kevin MacLeod (incompetech.com) | CC BY 4.0 |
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
| `assets/audio/sfx/battle_charge.ogg` | [MedievalCombatLoop.mp3](https://freesound.org/people/Yap_Audio_Production/sounds/218522/) (1.8 s to 4.8 s, faded) | Yap_Audio_Production | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `assets/audio/sfx/battle_won.ogg` | [VICTORY CRY REVERB 1.wav](https://freesound.org/people/chripei/sounds/165492/) | chripei | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `assets/audio/sfx/battle_lost.ogg` | [Taiko Drum Sequence for Looping (The Sacrifice)](https://freesound.org/people/Infinita08/sounds/459561/) (24.1 s to 28.6 s, faded) | Infinita08 | CC0 1.0 |

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
| `assets/forge/pavilion.svg` | [medieval-pavilion](https://game-icons.net/1x1/delapouite/medieval-pavilion.html) | Delapouite | Forge: Field Training, Winter Quarters | CC BY 3.0 |
| `assets/forge/swordman.svg` | [swordman](https://game-icons.net/1x1/cathelineau/swordman.html) | Cathelineau | Forge: Drill | CC BY 3.0 |
| `assets/forge/crossed_swords.svg` | [crossed-swords](https://game-icons.net/1x1/lorc/crossed-swords.html) | Lorc | Forge: Swordsmanship | CC BY 3.0 |
| `assets/forge/fist.svg` | [fist](https://game-icons.net/1x1/lorc/fist.html) | Lorc | Forge: gauntlets and bracers | CC BY 3.0 |
| `assets/forge/shaking_hands.svg` | [shaking-hands](https://game-icons.net/1x1/delapouite/shaking-hands.html) | Delapouite | Forge: Brothers in Arms | CC BY 3.0 |
| `assets/forge/bow_arrow.svg` | [bow-arrow](https://game-icons.net/1x1/delapouite/bow-arrow.html) | Delapouite | Forge: Yew Bows | CC BY 3.0 |
| `assets/forge/archer.svg` | [archer](https://game-icons.net/1x1/delapouite/archer.html) | Delapouite | Forge: Archery Butts | CC BY 3.0 |
| `assets/forge/bow_string.svg` | [bow-string](https://game-icons.net/1x1/delapouite/bow-string.html) | Delapouite | Forge: Heavy Draw | CC BY 3.0 |
| `assets/forge/saddle.svg` | [saddle](https://game-icons.net/1x1/delapouite/saddle.html) | Delapouite | Forge: War Saddles | CC BY 3.0 |
| `assets/forge/cavalry.svg` | [cavalry](https://game-icons.net/1x1/delapouite/cavalry.html) | Delapouite | Forge: Remounts | CC BY 3.0 |
| `assets/forge/horse_head.svg` | [horse-head](https://game-icons.net/1x1/delapouite/horse-head.html) | Delapouite | Forge: Destriers | CC BY 3.0 |
| `assets/forge/charged_arrow.svg` | [charged-arrow](https://game-icons.net/1x1/lorc/charged-arrow.html) | Lorc | Forge: Breakthrough | CC BY 3.0 |
| `assets/forge/hand_saw.svg` | [hand-saw](https://game-icons.net/1x1/delapouite/hand-saw.html) | Delapouite | Forge: Carpenters | CC BY 3.0 |
| `assets/forge/trebuchet.svg` | [trebuchet](https://game-icons.net/1x1/delapouite/trebuchet.html) | Delapouite | Forge: Counterweights | CC BY 3.0 |
| `assets/forge/palisade.svg` | [palisade](https://game-icons.net/1x1/delapouite/palisade.html) | Delapouite | Forge: Mantlets | CC BY 3.0 |
| `assets/forge/catapult.svg` | [catapult](https://game-icons.net/1x1/heavenly-dog/catapult.html) | HeavenlyDog | Forge: Siege Crews | CC BY 3.0 |
| `assets/forge/siege_ram.svg` | [siege-ram](https://game-icons.net/1x1/skoll/siege-ram.html) | Skoll | Forge: Iron-shod Rams | CC BY 3.0 |
| `assets/forge/house.svg` | [house](https://game-icons.net/1x1/delapouite/house.html) | Delapouite | Forge: houses | CC BY 3.0 |
| `assets/forge/family_house.svg` | [family-house](https://game-icons.net/1x1/delapouite/family-house.html) | Delapouite | Forge: Guild Hall | CC BY 3.0 |
| `assets/forge/crown_coin.svg` | [crown-coin](https://game-icons.net/1x1/lorc/crown-coin.html) | Lorc | Forge: Mint | CC BY 3.0 |
| `assets/forge/two_coins.svg` | [two-coins](https://game-icons.net/1x1/delapouite/two-coins.html) | Delapouite | Forge: Tolls | CC BY 3.0 |
| `assets/forge/coins.svg` | [coins](https://game-icons.net/1x1/delapouite/coins.html) | Delapouite | Forge: Markets | CC BY 3.0 |
| `assets/forge/swap_bag.svg` | [swap-bag](https://game-icons.net/1x1/lorc/swap-bag.html) | Lorc | Forge: Tithes | CC BY 3.0 |
| `assets/forge/coins_pile.svg` | [coins-pile](https://game-icons.net/1x1/delapouite/coins-pile.html) | Delapouite | Forge: Royal Treasury | CC BY 3.0 |
| `assets/forge/broadsword.svg` | [broadsword](https://game-icons.net/1x1/lorc/broadsword.html) | Lorc | Forge: armouries | CC BY 3.0 |
| `assets/forge/bordered_shield.svg` | [bordered-shield](https://game-icons.net/1x1/lorc/bordered-shield.html) | Lorc | Forge: Royal Armoury | CC BY 3.0 |
| `assets/forge/windmill.svg` | [windmill](https://game-icons.net/1x1/delapouite/windmill.html) | Delapouite | Forge: economy tab | CC BY 3.0 |
| `assets/forge/archery_target.svg` | [archery-target](https://game-icons.net/1x1/lorc/archery-target.html) | Lorc | Forge: army tab | CC BY 3.0 |
| `assets/forge/claw_hammer.svg` | [claw-hammer](https://game-icons.net/1x1/lorc/claw-hammer.html) | Lorc | Forge: the buy button and price | CC BY 3.0 |
| `assets/forge/eye.svg` | Our own | — | Forge: Keen Eyes | Same licence as the game |

The Forge's card sketches (`assets/forge/`, fetched by `tools/fetch_forge_icons.sh`) are drawn from these shapes in pencil by `shaders/sketch.gdshader`.

## Fonts

| File | Font | Author | Licence |
|---|---|---|---|
| `assets/fonts/Cinzel.ttf` | [Cinzel](https://github.com/google/fonts/tree/main/ofl/cinzel) | The Cinzel Project Authors (Natanael Gama) | [SIL OFL 1.1](assets/fonts/Cinzel-OFL.txt) |
| `assets/fonts/IMFellEnglish-Regular.ttf`, `assets/fonts/IMFellEnglish-Italic.ttf` | [IM FELL English](https://github.com/google/fonts/tree/main/ofl/imfellenglish) | Igino Marini | [SIL OFL 1.1](assets/fonts/IMFellEnglish-OFL.txt) |
| `assets/fonts/NotoSansSymbols2-Symbols.ttf` | [Noto Sans Symbols 2](https://github.com/google/fonts/tree/main/ofl/notosanssymbols2) | The Noto Project Authors | [SIL OFL 1.1](assets/fonts/NotoSansSymbols2-OFL.txt) |
| `assets/fonts/NotoSansMath-Arrows.ttf` | [Noto Sans Math](https://github.com/google/fonts/tree/main/ofl/notosansmath) | The Noto Project Authors | [SIL OFL 1.1](assets/fonts/NotoSansMath-OFL.txt) |
| `assets/fonts/GrenzeGotisch.ttf` | [Grenze Gotisch](https://github.com/google/fonts/tree/main/ofl/grenzegotisch) | The Grenze Gotisch Project Authors (Omnibus-Type) | [SIL OFL 1.1](assets/fonts/GrenzeGotisch-OFL.txt) |

Cinzel, IM FELL English and Grenze Gotisch (the variable font) are unmodified copies from the google/fonts repository. The two Noto fonts are
cut down to their symbol blocks, with their line height lowered to IM FELL English's, by
[tools/make_symbol_fonts.sh](tools/make_symbol_fonts.sh); they supply ★ ☆ ✓ ✗ ■ → − where the game fonts have
none.

## Made for this game

The maps (including the tutorial's), region names, campaigns, tutorial and text; the parchment, wood, stone, shield-button and plaque textures
(generated by [tools/make_theme.gd](tools/make_theme.gd)); the map, sea, parchment-stain and vignette shaders; the
banners, heraldic shields, spear arrows, particles and animations; the poses, lighting and rendering of the unit
figures. Nothing is copied from *Strategy & Tactics: Medieval Wars*: its screenshots were used
only as a reference for layout and feel.
