#!/bin/sh
# Builds assets/audio/ from the downloaded sources listed in CREDITS.md.
# Usage: tools/make_audio.sh <download dir> assets/audio
# Trims, mixes and levels with ffmpeg to WAV, then encodes Ogg Vorbis files
# with oggenc (brew install ffmpeg vorbis-tools). <download dir> holds:
#   kenney_rpg-audio/x, kenney_interface-sounds/x, kenney_impact-sounds/x  (unzipped Kenney packs)
#   fs_gallop, fs_volley, fs_catapult1, fs_hourglass, fs_horn1: a.mp3 each (freesound HQ previews)
#   music/: the music MP3s as their composers' sites give them (CC BY 4.0):
#     Rise_of_Kingdoms.mp3, Medieval_Chateau.mp3, Towards_the_Horizon.mp3, Gates_of_Glory.mp3,
#     Tavern_Tales.mp3, The_Vikings.mp3, Battle_Loop.mp3, The_Great_Battle.mp3, Superepic.mp3
#     (Alexander Nakarada, free downloads on creatorchords.com/music/<name>/) and
#     For_the_Fallen.mp3 (Kevin MacLeod, incompetech.com).
set -eu
D="$1"; OUT="$2"
O="$D/wav"
mkdir -p "$OUT/music" "$OUT/sfx" "$O/music" "$O/sfx"
K="$D/kenney_rpg-audio/x/Audio"
I="$D/kenney_interface-sounds/x/Audio"
M="$D/kenney_impact-sounds/x/Audio"
F="-y -hide_banner -loglevel error"
SFX="-ac 1 -ar 32000 -c:a pcm_s16le"
MUS="-ac 2 -ar 44100 -c:a pcm_s16le"
LIMIT="alimiter=limit=0.95:attack=5:release=50"

# Music, levelled by ear-loudness (EBU R128): map tracks to -16 LUFS so they sit under the
# planning, the menu and battles to -14, the victory to -13 and the defeat to -15.
level() {  # level <source> <out name> <target LUFS> [extra filters,]
  gain=$(ffmpeg -hide_banner -nostats -i "$1" -af "${4:-}ebur128" -f null - 2>&1 | awk '/I:/{i=$2} END{print '"$3"' - i}')
  ffmpeg $F -i "$1" -af "${4:-}volume=${gain}dB,$LIMIT" $MUS "$O/music/$2.wav"
}
level "$D/music/Rise_of_Kingdoms.mp3" menu_rise_of_kingdoms -14
level "$D/music/Medieval_Chateau.mp3" map_medieval_chateau -16
level "$D/music/Towards_the_Horizon.mp3" map_towards_the_horizon -16
level "$D/music/Gates_of_Glory.mp3" map_gates_of_glory -16
level "$D/music/Tavern_Tales.mp3" map_tavern_tales -16
level "$D/music/The_Vikings.mp3" map_the_vikings -16
level "$D/music/Battle_Loop.mp3" battle_loop -14
level "$D/music/The_Great_Battle.mp3" battle_the_great_battle -14
level "$D/music/Superepic.mp3" victory_superepic -13
level "$D/music/For_the_Fallen.mp3" defeat_for_the_fallen -15 "atrim=0:48,afade=t=out:st=42:d=6,"

# Effects
ffmpeg $F -i "$I/click_001.ogg" $SFX "$O/sfx/ui_click.wav"
ffmpeg $F -i "$K/beltHandle1.ogg" -af "volume=6dB" $SFX "$O/sfx/unit_select.wav"
ffmpeg $F -i "$M/impactWood_heavy_001.ogg" $SFX "$O/sfx/order_thunk.wav"
ffmpeg $F -i "$D/fs_hourglass/a.mp3" -af "atrim=0:1.8,afade=t=out:st=1.2:d=0.6,loudnorm=I=-18" $SFX "$O/sfx/hourglass.wav"
ffmpeg $F -i "$M/footstep_grass_000.ogg" -i "$M/footstep_grass_001.ogg" -i "$M/footstep_grass_002.ogg" -i "$M/footstep_grass_003.ogg" \
  -filter_complex "[1]adelay=220|220[b];[2]adelay=440|440[c];[3]adelay=660|660[d];[0][b][c][d]amix=inputs=4:normalize=0" $SFX "$O/sfx/march.wav"
ffmpeg $F -i "$D/fs_gallop/a.mp3" -af "atrim=0:2.2,afade=t=in:d=0.1,afade=t=out:st=1.7:d=0.5" $SFX "$O/sfx/hooves.wav"
ffmpeg $F -i "$M/impactMetal_heavy_000.ogg" -i "$M/impactPlate_medium_002.ogg" -i "$M/impactMetal_heavy_003.ogg" \
  -filter_complex "[1]adelay=140|140[b];[2]adelay=330|330[c];[0][b][c]amix=inputs=3:normalize=0" $SFX "$O/sfx/sword_clash.wav"
ffmpeg $F -i "$D/fs_volley/a.mp3" -af "afade=t=out:st=2.2:d=0.5" $SFX "$O/sfx/arrow_volley.wav"
ffmpeg $F -i "$D/fs_catapult1/a.mp3" -af "atrim=1.15:2.75,afade=t=out:st=1.3:d=0.3,volume=12dB" $SFX "$O/sfx/catapult_throw.wav"
ffmpeg $F -i "$M/impactMining_001.ogg" -i "$M/impactWood_heavy_003.ogg" -filter_complex "[1]adelay=40|40[b];[0][b]amix=inputs=2:normalize=0" $SFX "$O/sfx/catapult_impact.wav"
ffmpeg $F -i "$D/fs_horn1/a.mp3" -af "atrim=0.9:3.4,afade=t=out:st=2.0:d=0.5" $SFX "$O/sfx/capture_horn.wav"
ffmpeg $F -i "$K/handleCoins.ogg" $SFX "$O/sfx/coins.wav"
ffmpeg $F -i "$M/impactSoft_heavy_002.ogg" -i "$K/dropLeather.ogg" -filter_complex "[1]adelay=120|120[b];[0][b]amix=inputs=2:normalize=0" $SFX "$O/sfx/unit_destroyed.wav"

for f in "$O"/music/*.wav; do oggenc -Q -q 4 -o "$OUT/music/$(basename "$f" .wav).ogg" "$f"; done
for f in "$O"/sfx/*.wav; do oggenc -Q -q 2 -o "$OUT/sfx/$(basename "$f" .wav).ogg" "$f"; done
echo encoded
