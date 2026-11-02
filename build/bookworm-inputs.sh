# shellcheck shell=bash
# Pinned inputs for build-bookworm-image.sh. Change these deliberately, then
# rebuild and re-test on the spare card; the manifest records each one.
# shellcheck disable=SC2034  # read by build-bookworm-image.sh

# Raspberry Pi OS (Legacy, 32-bit) Lite, Bookworm, released 2026-10-06
BASE_URL="https://downloads.raspberrypi.com/raspios_oldstable_lite_armhf/images/raspios_oldstable_lite_armhf-2026-10-06/2026-10-06-raspios-bookworm-armhf-lite.img.xz"
BASE_SHA256="6332f7a232acd7d05f9499273e9a28783bbf1d23e3b1053784167793159044dd"

# Space added to the root filesystem for the Wi-Fi driver build (headers,
# compiler) and the HUD userland. The card's first boot expands it further.
GROW_ROOT_BYTES=$((2 * 1024 * 1024 * 1024))

# The RTL8723BS driver commit is pinned in bookworm/install-rtl8723bs-dkms.sh.
