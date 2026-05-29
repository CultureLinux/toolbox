#!/bin/bash

# Verify script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root" >&2
   exit 1
fi

current=$(uname -r)
next=$(basename "$(grubby --default-kernel)" | sed 's/^vmlinuz-//')
latest=$(rpm -q kernel --last | head -1 | awk '{print $1}' | sed 's/^kernel-//')

echo "Running : $current"
echo "Next    : $next"
echo "Latest  : $latest"
echo

if [[ "$current" == "$latest" ]]; then
  echo "Status  : OK - latest kernel running"
  echo "CVEs    : none pending from newer installed kernel"
else
  echo "Status  : WARNING - reboot pending"
  echo
  echo "CVEs present in installed kernel changelog:"
  rpm -q --changelog "kernel-$latest" | grep -i 'CVE-' | sort -u
fi

[[ "$next" == "$latest" ]] \
  && echo "GRUB    : OK - next boot uses latest kernel" \
  || echo "GRUB    : WARNING - next boot is not latest kernel"