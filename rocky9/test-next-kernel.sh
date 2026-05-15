#!/bin/bash

current=$(uname -r)
next=$(basename "$(grubby --default-kernel)" | sed 's/^vmlinuz-//')
latest=$(rpm -q kernel --last | head -1 | awk '{print $1}' | sed 's/kernel-//')

echo "Running : $current"
echo "Next    : $next"
echo "Latest  : $latest"

[[ "$current" != "$latest" ]] && echo "REBOOT PENDING"
[[ "$next" != "$latest" ]] && echo "GRUB NOT USING LATEST KERNEL"