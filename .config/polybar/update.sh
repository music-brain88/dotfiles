#!/bin/bash

echo
echo 'updates.sh: "paru -Syu"'
echo
paru -Syu

echo
bash ~/.config/polybar/checkupdates.sh

read -p "Press enter to close this window..."
