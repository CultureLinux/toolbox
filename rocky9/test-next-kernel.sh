#!/bin/bash

current=$(uname -r)
next=$(basename "$(grubby --default-kernel)" | sed 's/^vmlinuz-//')
latest=$(rpm -q --last kernel | awk 'NR==1{sub(/^kernel-/,"",$1); print $1}')

printf "%-8s : %s\n" "Running" "$current"
printf "%-8s : %s\n" "Next"    "$next"
printf "%-8s : %s\n" "Latest"  "$latest"

status=0

if [[ "$current" != "$latest" ]]; then
    echo "WARNING: reboot pending"
    status=1
fi

if [[ "$next" != "$latest" ]]; then
    echo "WARNING: GRUB not configured on latest kernel"
    status=2
fi

exit $status