#!/bin/sh
# Downloads the CC0 Quaternius models that tools/render_figures.gd renders into
# assets/figures/. Usage: tools/fetch_figure_models.sh <empty folder>
# The models come from Quaternius (https://quaternius.com, CC0 1.0), through
# the single-model mirror at github.com/trebeljahr/quaternius-showcase, pinned
# to one commit. They are data only: nothing in them is run.
set -eu
DIR="${1:?give an empty folder to download into}"
BASE="https://raw.githubusercontent.com/trebeljahr/quaternius-showcase/722c39e964360beff2728a8ee4d103e2d11d457c/public/glb"
fetch() {
	mkdir -p "$DIR/$1"
	for model in $2; do
		curl -sfL -o "$DIR/$1/$model.glb" "$BASE/$1/$model.glb"
	done
}
fetch modular_men "Farmer King Adventurer"
fetch single_knight_pack "Helmet1 Helmet2 Helmet3"
fetch animals_pack "Horse Horse_White"
fetch medieval_weapons_pack "Spear Bow_Wooden Bow_Wooden2 Sword Sword_2 Axe Axe_Double Axe_Small Shield_Heater Shield_Round Shield_Round_2"
echo "Downloaded to $DIR. Now run:"
echo "  godot --path . --rendering-method forward_plus -s tools/render_figures.gd -- $DIR"
