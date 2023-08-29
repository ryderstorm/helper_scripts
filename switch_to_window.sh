#!/bin/bash
set -e

function log_something() {
  message="$1"
  notify-send -t 2000 "$message"
  echo -e "$message"
}

window_class="$1"
if [[ -z "$window_class" ]]; then
  log_something "You must specify a window class"
  exit 1
fi

log_something "Looking for window with class: $window_class"
window_id=$(wmctrl -lxG | grep "$window_class" | cut -d' ' -f1)

if [[ -z "$window_id" ]]; then
  log_something "Could not find [$window_class] window to switch to."
  exit 1
fi

log_something "Switching to [$window_class] window with ID [$window_id]"
wmctrl -ia "$window_id"
