#!/usr/bin/env bash
#
# Fedora 44 (GNOME 50) post-install setup script
#
# Usage: ./setup.sh
#
set -euo pipefail

log() {
    printf '\n\033[1;32m==>\033[0m %s\n' "$1"
}

require_sudo() {
    log "Requesting sudo access"
    sudo -v
}

configure_dnf() {
    log "Configuring DNF and updating system"
    if ! grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf; then
        echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf
    fi
    sudo dnf update -y
}

remove_unwanted_packages() {
    log "Removing unwanted packages"
    sudo dnf remove -y firefox firefox-langpacks || true
    sudo dnf remove -y 'libreoffice*' || true
    sudo dnf autoremove -y
    sudo dnf clean all
}

enable_rpmfusion() {
    log "Enabling RPM Fusion (free + nonfree)"
    # Required before the "freeworld" mesa swaps and the full ffmpeg swap
    # below — those packages only exist in RPM Fusion, not the default repos.
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
}

swap_to_freeworld() {
    local from="$1"
    local to="$2"

    if rpm -q "$to" &>/dev/null; then
        log "$to already installed, skipping swap"
    else
        sudo dnf swap -y "$from" "$to"
    fi
}

install_graphics_drivers() {
    log "Installing core graphics and Vulkan drivers (RDNA4 / RX 9060 XT)"
    sudo dnf install -y \
        mesa-dri-drivers \
        mesa-dri-drivers.i686 \
        mesa-vulkan-drivers \
        mesa-vulkan-drivers.i686 \
        vulkan-loader \
        vulkan-loader.i686 \
        vulkan-tools

    log "Swapping in RPM Fusion 'freeworld' hardware video acceleration"
    swap_to_freeworld mesa-va-drivers mesa-va-drivers-freeworld
    swap_to_freeworld mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    swap_to_freeworld mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
    swap_to_freeworld mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
    sudo dnf install -y libva-utils
}

configure_multimedia_audio() {
    log "Updating multimedia group and audio stack"
    sudo dnf group upgrade -y multimedia --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin --skip-unavailable

    sudo dnf install -y pipewire-jack-audio-connection-kit

    sudo dnf group upgrade -y sound-and-video --skip-unavailable

    # NOTE: "hw:Generic_1" is a specific ALSA card name — if this errors,
    # confirm the real card name with `amixer -c` or `aplay -l` first.
    amixer -D hw:Generic_1 sset "Auto-Mute Mode" Disabled || true
    sudo alsactl store
}

setup_flatpak() {
    log "Setting up Flatpak and installing apps"
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    flatpak install -y flathub dev.vencord.Vesktop
    flatpak install -y flathub io.gitlab.librewolf-community
    flatpak install -y flathub com.mattjakeman.ExtensionManager
}

install_gaming_stack() {
    log "Installing Steam and game launchers"
    sudo dnf install -y steam

    sudo dnf -y copr enable faugus/faugus-launcher
    sudo dnf -y install faugus-launcher
}

configure_keybindings() {
    log "Configuring custom keybindings"
    gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Control>bracketleft']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-up "['Page_Up']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-down "['Page_Down']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute "['End']"
}

set_sysctl() {
    local key="$1"
    local value="$2"
    local file="/etc/sysctl.d/99-sysctl.conf"

    if ! sudo grep -q "^${key}=" "$file" 2>/dev/null; then
        echo "${key}=${value}" | sudo tee -a "$file" > /dev/null
    else
        sudo sed -i "s/^${key}=.*/${key}=${value}/" "$file"
    fi
}

configure_kernel() {
    log "Applying kernel/sysctl tuning"
    set_sysctl "vm.swappiness" "10"
    set_sysctl "kernel.sysrq" "1"
    sudo sysctl --system
}

configure_ffmpeg() {
    log "Swapping ffmpeg-free for the full ffmpeg build"
    sudo dnf swap -y --allowerasing ffmpeg-free ffmpeg || sudo dnf install -y ffmpeg
}

configure_games_drive() {
    log "Mounting the games drive"
    sudo mkdir -p /mnt/games

    if ! grep -q "LABEL=extradrive" /etc/fstab; then
        echo "LABEL=extradrive   /mnt/games   ext4   defaults,nofail,x-gvfs-show   0   2" | sudo tee -a /etc/fstab
    fi

    if mountpoint -q /mnt/games; then
        log "/mnt/games already mounted, skipping"
    else
        sudo mount -a
    fi
    sudo chown -R "$USER:$USER" /mnt/games
}

configure_shader_cache() {
    log "Configuring Mesa shader cache size"
    mkdir -p ~/.config/environment.d
    local conf=~/.config/environment.d/gaming.conf

    if grep -q '^MESA_SHADER_CACHE_MAX_SIZE=' "$conf" 2>/dev/null; then
        sed -i 's/^MESA_SHADER_CACHE_MAX_SIZE=.*/MESA_SHADER_CACHE_MAX_SIZE=12G/' "$conf"
    else
        echo "MESA_SHADER_CACHE_MAX_SIZE=12G" >> "$conf"
    fi
}

main() {
    require_sudo
    configure_dnf
    remove_unwanted_packages
    enable_rpmfusion
    install_graphics_drivers
    configure_multimedia_audio
    setup_flatpak
    install_gaming_stack
    configure_keybindings
    configure_kernel
    configure_ffmpeg
    configure_games_drive
    configure_shader_cache
    log "Setup complete. A reboot is recommended."
}

main "$@"
