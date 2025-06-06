#!/usr/bin/env bash
languages='echo "python c golang typescript rust lua" | tr ' ' '\n''
core_utils='echo "xargs xrandr find mv sed grep awk" | tr ' ' '\n''



echo "$languages $core_utils"
