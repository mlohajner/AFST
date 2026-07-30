#!/usr/bin/env bash

SRC=$(zenity --file-selection --directory --title="Select SOURCE directory") || exit
DST=$(zenity --file-selection --directory --title="Select DEST directory") || exit

zenity --question --title="AFST AnaliticFileSyncTool" --text="Source:\n$SRC\n\nDestination:\n$DST\n\nStart AFST?" || exit

./afst.sh "$SRC" "$DST" | zenity --progress --title="AFST running" --pulsate --auto-close
