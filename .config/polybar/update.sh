#!/bin/bash

echo
echo 'updates.sh: "paru -Syu"'
echo
yay -Syu

echo
bash ~/.config/polybar/checkupdates.sh

read -p "Press enter to close this window..."
