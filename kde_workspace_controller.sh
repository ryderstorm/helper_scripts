#!/bin/bash

#
# Switch to workspace left, right, up, or down from current for
# workspaces arranged in `$num_rows' rows and `$num_cols'
# columns. Wraps around within the current row for left and right and
# within the current column for up and down.
#
# Can also be used to invoke the Expose, ExposeAll, and DesktopGrid
# effects in KDE Plasma.
#
# Usage: ./this_script.sh (left|right|up|down|expose|exposeall|desktopgrid)
#
# References:
# https://userbase.kde.org/System_Settings/Shortcuts_and_Gestures
# https://forum.xfce.org/viewtopic.php?id=8293
# https://www.reddit.com/r/kde/comments/jx9gh4/exposeall_no_longer_working/


# Configuration
num_rows=3
num_cols=3

# Get the option the user passed in
if [ -z "$1" ]; then
  echo "Usage: $0 (left|right|up|down|expose|exposeall|desktopgrid)"
  exit 1
fi
option="$1"

# Get the current workspace
current=$(wmctrl -d | grep "\*" | cut -d ' ' -f 1)

# Calculate the row and column of the current workspace
row=$((current / num_cols))
col=$((current % num_cols))

# Calculate the row and column of the new workspace
case "$option" in
  left)
    col=$(( (col + num_cols - 1) % num_cols ))
    workspace=$((row * num_cols + col))
    command="wmctrl -s $workspace"
    message="Switching [$option] to workspace [$workspace]"
    ;;
  right)
    col=$(( (col + 1) % num_cols ))
    workspace=$((row * num_cols + col))
    command="wmctrl -s $workspace"
    message="Switching [$option] to workspace [$workspace]"
    ;;
  up)
    row=$(( (row + num_rows - 1) % num_rows ))
    workspace=$((row * num_cols + col))
    command="wmctrl -s $workspace"
    message="Switching [$option] to workspace [$workspace]"
    ;;
  down)
    row=$(( (row + 1) % num_rows ))
    workspace=$((row * num_cols + col))
    command="wmctrl -s $workspace"
    message="Switching [$option] to workspace [$workspace]"
    ;;
  expose)
    command="qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'Expose'"
    message="Invoking [$option] effect"
    ;;

  exposeall)
    command="qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'ExposeAll'"
    message="Invoking [$option] effect"
    ;;

  desktopgrid)
    command="qdbus org.kde.kglobalaccel /component/kwin invokeShortcut 'ShowDesktopGrid'"
    message="Invoking [$option] effect"
    ;;

  *)
    echo "Usage: $0 (left|right|up|down|expose|exposeall|desktopgrid)"
    exit 1
    ;;
esac

# Execute the command
echo "$message"
# notify-send "$message"
eval "$command"
