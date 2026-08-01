# Enable parallel downloads and update
echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf

sudo dnf update -y


# Flatpak and apps

flatpak remote-delete --force flathub || true

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install flathub dev.vencord.Vesktop -y

flatpak install flathub io.gitlab.librewolf-community


# Update multimedia and speaker handling

sudo dnf group upgrade -y multimedia --setopt="install_weak_deps=False" \
    --exclude=PackageKit-gstreamer-plugin --skip-unavailable

sudo dnf install -y pipewire-jack-audio-connection-kit

sudo dnf group upgrade -y sound-and-video --skip-unavailable

amixer -D hw:Generic_1 sset "Auto-Mute Mode" Disabled

sudo alsactl store
