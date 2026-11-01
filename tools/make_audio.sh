#!/bin/sh
# Builds assets/audio/ from the downloaded CC0 sources listed in CREDITS.md.
# Usage: tools/make_audio.sh <download dir> assets/audio
# Trims, mixes and levels with ffmpeg to WAV, then encodes small Ogg Vorbis
# files with oggenc (brew install ffmpeg vorbis-tools). <download dir> holds:
#   kenney_rpg-audio/x, kenney_interface-sounds/x, kenney_impact-sounds/x  (unzipped Kenney packs)
#   oga_minstrel/loop.wav, oga_bards/loop.wav, oga_tower/loop.wav           (RandomMind's loop WAVs)
#   oga_victory/a.wav (cynicmusic), oga_sad/a.wav (Emma_MA)
#   fs_gallop, fs_volley, fs_catapult1, fs_hourglass, fs_horn1: a.mp3 each (freesound HQ previews)
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

# Music
ffmpeg $F -i "$D/oga_minstrel/loop.wav" $MUS "$O/music/menu_minstrel_dance.wav"
ffmpeg $F -i "$D/oga_bards/loop.wav" $MUS "$O/music/map_bards_tale.wav"
ffmpeg $F -i "$D/oga_tower/loop.wav" $MUS "$O/music/map_old_tower_inn.wav"
ffmpeg $F -i "$D/oga_victory/a.wav" -af "afade=t=out:st=10.3:d=1.5" $MUS "$O/music/victory.wav"
ffmpeg $F -i "$D/oga_sad/a.wav" -af "atrim=0:9,afade=t=out:st=7:d=2" $MUS "$O/music/defeat.wav"

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

for f in "$O"/music/*.wav; do oggenc -Q -q 1 -o "$OUT/music/$(basename "$f" .wav).ogg" "$f"; done
for f in "$O"/sfx/*.wav; do oggenc -Q -q 2 -o "$OUT/sfx/$(basename "$f" .wav).ogg" "$f"; done
echo encoded
