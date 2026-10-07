#!/bin/bash
# Install dependencies on a running Pi, or validate an offline image's packages.
# Never run the build host's apt against dependencies missing from a target image.
set -eu

target_root=${1:-/}
packages=(python3 python3-serial python3-rpi.gpio)

dependencies_present() {
  local package status
  for package in "${packages[@]}"; do
    status=$(dpkg-query --admindir="${target_root%/}/var/lib/dpkg" \
      --show --showformat='${Status}' "$package" 2>/dev/null) || return 1
    [[ "$status" == "install ok installed" ]] || return 1
  done
  local serial_version
  serial_version=$(dpkg-query --admindir="${target_root%/}/var/lib/dpkg" \
    --show --showformat='${Version}' python3-serial) || return 1
  dpkg --compare-versions "$serial_version" ge 3.0
}

if dependencies_present; then
  exit 0
fi

if [[ "$target_root" != / ]]; then
  echo "ERROR: The target image needs python3, python3-serial (>= 3.0), and python3-rpi.gpio." >&2
  echo "Install these packages inside the target OS before running the image installer." >&2
  exit 1
fi

apt-get update
apt-get install -y "${packages[@]}"
dependencies_present
