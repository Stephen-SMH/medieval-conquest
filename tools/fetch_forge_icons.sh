#!/bin/sh
# Downloads the game-icons.net shapes the Forge's cards are sketched from
# (ForgeCard draws them in pencil on parchment) into assets/forge/, with the
# black background square removed. Usage: tools/fetch_forge_icons.sh
# The icons are CC BY 3.0 (see CREDITS.md), pinned to one commit of
# github.com/game-icons/icons. assets/forge/eye.svg is our own and stays.
set -eu
cd "$(dirname "$0")/.."
BASE="https://raw.githubusercontent.com/game-icons/icons/82d948812bfe3f269ef8f731dcdb07b08160edc4"
mkdir -p assets/forge
while read -r name path; do
	curl -sfL "$BASE/$path.svg" | sed 's#<path d="M0 0h512v512H0z"/>##' > "assets/forge/$name.svg"
done <<'EOF'
pavilion delapouite/medieval-pavilion
swordman cathelineau/swordman
crossed_swords lorc/crossed-swords
fist lorc/fist
shaking_hands delapouite/shaking-hands
bow_arrow delapouite/bow-arrow
archer delapouite/archer
bow_string delapouite/bow-string
saddle delapouite/saddle
cavalry delapouite/cavalry
horse_head delapouite/horse-head
charged_arrow lorc/charged-arrow
hand_saw delapouite/hand-saw
trebuchet delapouite/trebuchet
palisade delapouite/palisade
catapult heavenly-dog/catapult
siege_ram skoll/siege-ram
house delapouite/house
family_house delapouite/family-house
crown_coin lorc/crown-coin
two_coins delapouite/two-coins
coins delapouite/coins
swap_bag lorc/swap-bag
coins_pile delapouite/coins-pile
crested_helmet lorc/crested-helmet
windmill delapouite/windmill
archery_target lorc/archery-target
claw_hammer lorc/claw-hammer
EOF
echo "Done. Run godot --headless --import to import them."
