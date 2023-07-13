#!/bin/bash

# =============================================================================
# This script is a bash script that adjusts the brightness of an external
# display. It takes a parameter of "increase", "decrease", or a number from 30
# to 100 to adjust the brightness. The script uses the ddcutil command to set
# the brightness of the external display.
#
# To run this script, you need to have ddcutil installed on your system.
# Additionally, you need to configure your OS to allow ddcutil to run without
# prompting for a sudo password. This can be done by adding a file to
# /etc/sudoers.d/ with the following contents:
#
# <your_username> ALL=(ALL) NOPASSWD: <path_to_ddcutil>
#
# Replace <your_username> with your actual username. You can find your username
# by running the command "whoami".
#
# Replace <path_to_ddcutil> with the actual path to the ddcutil command. You
# can find the path by running the command "which ddcutil".
# =============================================================================

set_brightness() {
  output=$(sudo ddcutil setvcp 10 "$1" 2>&1)
}

process_input() {
  if [ -z "$user_param" ]; then
    message="You must specify a parameter, one of: \"increase\", \"decrease\", or a number from 30 to 100"
    echo -e "\n${RED}$message${NC}"
    notify-send "Brightness Control - Error" "$message"
    exit 1
  fi
  get_current_brightness
  if [ "$user_param" = "increase" ]; then
    if [ "$current_brightness" -ge 90 ]; then
      new_brightness=100
    else
      new_brightness=$((current_brightness + 10))
    fi
  elif [ "$user_param" = "decrease" ]; then
    if [ "$current_brightness" -le 20 ]; then
      new_brightness=10
    else
      new_brightness=$((current_brightness - 10))
    fi
  elif [[ "$user_param" =~ ^[0-9]+$ ]] && [ "$user_param" -ge 30 ] && [ "$user_param" -le 100 ]; then
    new_brightness="$user_param"
  else
    message="Invalid parameter. It must be either 'increase', 'decrease', or a number from 30 to 100"
    echo -e "\n${RED}$message${NC}"
    notify-send "Brightness Control - Error" "$message"
    exit 1
  fi
  echo "current_brightness: $current_brightness"
  echo "new_brightness: $new_brightness"
  if [ "$current_brightness" = "$new_brightness" ]; then
    notify-send "Brightness Control" "Left brightness as is since it was at $current_brightness% and new brightness was $new_brightness"
    return
  else
    set_brightness "$new_brightness"
  fi

  result=$?
  if [ $result -eq 0 ]; then
    notify-send "Brightness Control" "Adjusted external display brightness from $current_brightness% to $new_brightness%"
  else
    message="Encountered error setting external display brightness to ${new_brightness}%"
    echo -e "$message:\n\n$output"
    notify-send "Brightness Control - Error" "$message\n\n$output"
  fi
}

get_current_brightness() {
  display_info=$(sudo ddcutil getvcp 10 2>&1)
  result=$?
  if [ $result -ne 0 ]; then
    notify-send "Brightness Control - Error"  "$display_info\n\nDo you need to run 'sudo modprobe i2c-dev'?"
    return 1
  fi
  pat='current value =\s+([[:digit:]]+)'
  [[ "$display_info" =~ $pat ]]
  current_brightness="${BASH_REMATCH[1]}"
}

user_param=$1
process_input
