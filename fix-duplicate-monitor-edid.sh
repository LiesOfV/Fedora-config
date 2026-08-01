#!/usr/bin/env bash
#
# fix-duplicate-monitor-edid.sh
#
# WHAT THIS FIXES
#   GNOME/Mutter/colord cannot assign independent color profiles to two
#   identical monitors when they report byte-for-byte identical EDIDs
#   (same make/model, no unique serial number burnt in by the vendor).
#   colord builds its device identity from the EDID, so both monitors
#   collide, and you'll see "Failed to create device color profile:
#   Profile generation already in progress" in the journal, plus only
#   one shared color profile in Settings > Displays > Color.
#
# HOW IT'S FIXED
#   A synthetic, unique serial number is patched into a copy of the
#   EDID for each connector, with the checksum recalculated. The kernel
#   is told (via drm.edid_firmware=) to present these patched EDIDs
#   instead of the monitors' real ones. Only the 4-byte serial field
#   and the checksum byte are changed - resolution/timing data (your
#   144Hz mode) is untouched.
#
# THIS SCRIPT IS HARDWARE-SPECIFIC
#   Monitor:    VIE WV24FHD144 (24" 1080p 144Hz) x2, identical units
#   Connectors: DP-2 and HDMI-A-1
#   The two base64 blobs below are patched copies of THIS monitor's
#   real EDID. They are safe to reuse across a distro-hop on the SAME
#   physical machine/ports. Do NOT reuse them if you plug a different
#   monitor model into these ports, or move these monitors to
#   different ports - see CONNECTOR_A/CONNECTOR_B below.
#
# SUPPORTS
#   initramfs: mkinitcpio, dracut, initramfs-tools (Debian/Ubuntu)
#   bootloader: GRUB (incl. Fedora/RHEL grubby+BLS), systemd-boot
#   Not handled: Limine - add the kernel parameter to /boot/limine.conf
#   manually if that's your bootloader (see KPARAM value printed below).
#
# NOTE ON GNOME VERSION
#   This fix works one layer below the display server: drm.edid_firmware
#   is parsed by the kernel's DRM subsystem before Mutter ever starts, so
#   Mutter/colord just see the patched EDID like it was the real thing.
#   That makes this fix independent of GNOME/Mutter version - GNOME 50
#   or any future version reads it the same way. Nothing here touches
#   GNOME config.
#
# NOTE ON FEDORA
#   Verified against Fedora 44's stock toolchain: GRUB2 + BLS with
#   grubby for kernel params, dracut for initramfs, both handled below.
#   SELinux is enforcing by default on Fedora, so this script relabels
#   every file it writes with restorecon so dracut/the kernel can read
#   them without denials.
#   This assumes traditional (dnf-based) Fedora Workstation with a
#   writable /usr. On the atomic variants (Silverblue/Kinoite/Atomic
#   Desktops), /usr is read-only and this script will need to be run
#   via `rpm-ostree usroverlay` first, or adapted to layer the files in.
#
# Safe to re-run: each step checks whether it's already applied.
#
# USAGE: sudo bash fix-duplicate-monitor-edid.sh
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

# ---------- CONFIG (edit these if your ports/hardware change) -----------
CONNECTOR_A="DP-2"
CONNECTOR_B="HDMI-A-1"
FILE_A="wv24fhd144-dp2.bin"
FILE_B="wv24fhd144-hdmi-a-1.bin"
B64_A="AP///////wBZJYAMAQAAABQjAQSiNB94CtelollKliQUUFQtzwDRwLMAAQGBgIFAgcABAQEBAjqAGHE4LUBYLEUADyghAAAeN0WAtHA4LUAwIDUAWMEQAAAeAAAA/QAwkB+0JAAKICAgICAgAAAA/ABXVjI0RkhEMTQ0CiAgAc8CAyyxR5ABAgMEEx/iANXjBcMBZwMMABAAGEhn2F3EAUgAAGgaAAABATCQ5rBtgKBwOC1AMCA1AA8oIQAAHqCDgKBwOC1AGCA1AA8oIQAAHmhbgKBwOC1AMCA1AA8oIQAAHgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAdA=="
B64_B="AP///////wBZJYAMAgAAABQjAQSiNB94CtelollKliQUUFQtzwDRwLMAAQGBgIFAgcABAQEBAjqAGHE4LUBYLEUADyghAAAeN0WAtHA4LUAwIDUAWMEQAAAeAAAA/QAwkB+0JAAKICAgICAgAAAA/ABXVjI0RkhEMTQ0CiAgAc4CAyyxR5ABAgMEEx/iANXjBcMBZwMMABAAGEhn2F3EAUgAAGgaAAABATCQ5rBtgKBwOC1AMCA1AA8oIQAAHqCDgKBwOC1AGCA1AA8oIQAAHmhbgKBwOC1AMCA1AA8oIQAAHgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAdA=="
FW_DIR="/usr/lib/firmware/edid"
KPARAM="drm.edid_firmware=${CONNECTOR_A}:edid/${FILE_A},${CONNECTOR_B}:edid/${FILE_B}"
TS=$(date +%Y%m%d-%H%M%S)

log()  { echo -e "\n\033[1;32m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m!!\033[0m $*" >&2; }

backup() {
  # Always returns 0, even when there's nothing to back up yet (e.g. a
  # config file that doesn't exist until this script creates it - true
  # on a fresh install). Under 'set -e', a bare [[ -f "$f" ]] && cp ...
  # here would silently kill the whole script the moment it hit a file
  # that doesn't exist yet.
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak-${TS}"
  fi
  return 0
}

relabel() {
  # No-op on non-SELinux systems (e.g. CachyOS); restores correct
  # context on SELinux-enforcing systems (e.g. Fedora) so dracut and
  # the kernel aren't blocked from reading files this script wrote.
  local p="$1"
  command -v restorecon >/dev/null 2>&1 && restorecon -RF "$p" 2>/dev/null || true
}

# ---------- 1. Install firmware files -----------------------------------
log "Installing patched EDID firmware files to ${FW_DIR}"
mkdir -p "$FW_DIR"
echo "$B64_A" | base64 -d > "${FW_DIR}/${FILE_A}"
echo "$B64_B" | base64 -d > "${FW_DIR}/${FILE_B}"

for f in "${FW_DIR}/${FILE_A}" "${FW_DIR}/${FILE_B}"; do
  n=$(wc -c < "$f")
  if [[ "$n" -ne 256 ]]; then
    echo "ERROR: $f is $n bytes, expected 256. Aborting." >&2
    exit 1
  fi
done
echo "  OK - both firmware files are 256 bytes"
relabel "$FW_DIR"

# ---------- 2. Embed into initramfs --------------------------------------
log "Detecting initramfs generator"

if command -v mkinitcpio >/dev/null 2>&1; then
  echo "  Found mkinitcpio"
  CONF="/etc/mkinitcpio.conf"
  backup "$CONF"
  python3 - "$CONF" "$FW_DIR/$FILE_A" "$FW_DIR/$FILE_B" << 'PYEOF'
import re, sys
conf_path, fa, fb = sys.argv[1], sys.argv[2], sys.argv[3]
with open(conf_path) as f:
    text = f.read()
m = re.search(r'^FILES=\((.*?)\)', text, re.MULTILINE)
if not m:
    text += f'\nFILES=({fa} {fb})\n'
else:
    existing = m.group(1).split()
    for entry in (fa, fb):
        if entry not in existing:
            existing.append(entry)
    text = text[:m.start()] + f'FILES=({" ".join(existing)})' + text[m.end():]
with open(conf_path, 'w') as f:
    f.write(text)
PYEOF
  echo "  Updated FILES= in $CONF"
  relabel "$CONF"
  mkinitcpio -P
  echo "  Regenerated initramfs (all presets)"

elif command -v dracut >/dev/null 2>&1; then
  echo "  Found dracut"
  CONF="/etc/dracut.conf.d/99-edid-override.conf"
  backup "$CONF"
  echo "install_items+=\" ${FW_DIR}/${FILE_A} ${FW_DIR}/${FILE_B} \"" > "$CONF"
  echo "  Wrote $CONF"
  relabel "$CONF"
  dracut -f --regenerate-all
  echo "  Regenerated initramfs (all kernels)"

elif command -v update-initramfs >/dev/null 2>&1; then
  echo "  Found initramfs-tools (Debian/Ubuntu)"
  HOOK="/etc/initramfs-tools/hooks/zz-edid-override"
  cat > "$HOOK" << HOOKEOF
#!/bin/sh
PREREQ=""
prereqs() { echo "\$PREREQ"; }
case \$1 in prereqs) prereqs; exit 0 ;; esac
. /usr/share/initramfs-tools/hook-functions
mkdir -p "\$DESTDIR${FW_DIR}"
cp "${FW_DIR}/${FILE_A}" "\$DESTDIR${FW_DIR}/"
cp "${FW_DIR}/${FILE_B}" "\$DESTDIR${FW_DIR}/"
HOOKEOF
  chmod +x "$HOOK"
  relabel "$HOOK"
  echo "  Installed hook $HOOK"
  update-initramfs -u -k all
  echo "  Regenerated initramfs (all kernels)"

else
  warn "Could not detect mkinitcpio, dracut, or initramfs-tools."
  warn "You'll need to manually ensure ${FW_DIR}/${FILE_A} and ${FILE_B} are bundled into your initramfs."
fi

# ---------- 3. Set kernel parameter via bootloader ------------------------
log "Detecting bootloader"

if command -v grubby >/dev/null 2>&1 && { [[ -d /boot/loader/entries ]] || [[ -d /boot/grub2 ]]; }; then
  echo "  Found grubby (Fedora/RHEL-style BLS)"
  if grubby --info=ALL 2>/dev/null | grep -q "drm.edid_firmware"; then
    echo "  Parameter already present, skipping"
  else
    grubby --update-kernel=ALL --args="$KPARAM"
    echo "  Added kernel parameter via grubby to all kernels"
  fi

elif [[ -f /etc/default/grub ]] && { command -v update-grub >/dev/null 2>&1 || command -v grub-mkconfig >/dev/null 2>&1 || command -v grub2-mkconfig >/dev/null 2>&1; }; then
  echo "  Found GRUB"
  CONF="/etc/default/grub"
  backup "$CONF"
  if grep -q "drm.edid_firmware" "$CONF"; then
    echo "  Parameter already present in $CONF, skipping"
  else
    sed -i -E "s#^(GRUB_CMDLINE_LINUX_DEFAULT=[\"'])(.*)([\"'])\$#\1\2 ${KPARAM}\3#" "$CONF"
    echo "  Appended parameter to GRUB_CMDLINE_LINUX_DEFAULT"
  fi
  relabel "$CONF"

  if command -v update-grub >/dev/null 2>&1; then
    update-grub
  elif command -v grub2-mkconfig >/dev/null 2>&1; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
  elif [[ -f /boot/grub/grub.cfg ]]; then
    grub-mkconfig -o /boot/grub/grub.cfg
  else
    warn "Found a grub config tool but couldn't determine grub.cfg's path - run it manually."
  fi
  echo "  Regenerated GRUB config"

elif command -v bootctl >/dev/null 2>&1 && bootctl status >/dev/null 2>&1; then
  echo "  Found systemd-boot"
  CMDLINE_FILE="/etc/kernel/cmdline"
  if [[ -f "$CMDLINE_FILE" ]]; then
    backup "$CMDLINE_FILE"
    if grep -q "drm.edid_firmware" "$CMDLINE_FILE"; then
      echo "  Parameter already present in $CMDLINE_FILE, skipping"
    else
      sed -i "s#\$# ${KPARAM}#" "$CMDLINE_FILE"
      echo "  Appended parameter to $CMDLINE_FILE"
    fi
  else
    warn "$CMDLINE_FILE not found - creating it (used by kernel-install for future entries)"
    mkdir -p "$(dirname "$CMDLINE_FILE")"
    echo "$KPARAM" > "$CMDLINE_FILE"
  fi
  relabel "$CMDLINE_FILE"
  # Also patch existing loader entries directly so it works without waiting for a kernel reinstall
  for entry in /boot/loader/entries/*.conf /efi/loader/entries/*.conf /boot/efi/loader/entries/*.conf; do
    [[ -f "$entry" ]] || continue
    backup "$entry"
    if ! grep -q "drm.edid_firmware" "$entry"; then
      sed -i "/^options /s#\$# ${KPARAM}#" "$entry"
      echo "  Patched $entry"
    fi
    relabel "$entry"
  done

else
  warn "Could not detect GRUB, grubby, or systemd-boot."
  warn "Manually add this to your kernel command line: $KPARAM"
fi

log "Done. A reboot is required for this to take effect."
cat <<EOF

After rebooting, verify with:

  for c in ${CONNECTOR_A} ${CONNECTOR_B}; do
    dir=\$(ls /sys/class/drm | grep -- "-\${c}\$" | head -1)
    echo "--- \$c ---"
    cat "/sys/class/drm/\$dir/edid" | base64 -w0 | python3 -c "
import sys, base64
d = base64.b64decode(sys.stdin.read())
print('serial:', d[12:16].hex(), '  checksum ok:', sum(d[0:128]) % 256 == 0)
"
  done
  colormgr get-devices | grep -E 'Serial|Device ID|Model'

Expect ${CONNECTOR_A} -> serial 01000000, ${CONNECTOR_B} -> serial 02000000,
checksum ok: True for both, and two distinct Device ID / Serial lines
from colord.

EOF
