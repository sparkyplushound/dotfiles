#!/usr/bin/env bash 

read -p "What Word Would You Like Defined? " word

dict "$word" | sed 1,7p | fzf


# I stole this line from https://github.com/BreadOnPenguins/scripts/blob/master/define_word. I'm new to bash scripting and didn't feel like figure out how to write this myself. Sorry not sorry. (it checks for special characters)
[[ -z "$word" || "$word" =~ [\/] ]] && notify-send -h string:bgcolor:#bf616a -t 3000 "Invalid input." && exit 0


