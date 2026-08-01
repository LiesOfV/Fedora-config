# Enable parallel downloads and update
echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf

sudo dnf update -y

# Uninstall
sudo dnf remove -y firefox firefox-langpacks
sudo dnf remove -y libreoffice*
    
sudo dnf autoremove -y
sudo dnf clean all

#  - Core graphics and Vulkan (RDNA4 / RX 9060 XT)
sudo dnf install -y \
  mesa-dri-drivers \
  mesa-dri-drivers.i686 \
  mesa-vulkan-drivers \
  mesa-vulkan-drivers.i686 \
  vulkan-loader \
  vulkan-loader.i686 \
  vulkan-tools
 

#  - Hardware video acceleration

sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
sudo dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
sudo dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
sudo dnf install -y libva-utils

# Update multimedia and speaker handling
sudo dnf group upgrade -y multimedia --setopt="install_weak_deps=False" \
    --exclude=PackageKit-gstreamer-plugin --skip-unavailable

sudo dnf install -y pipewire-jack-audio-connection-kit

sudo dnf group upgrade -y sound-and-video --skip-unavailable

amixer -D hw:Generic_1 sset "Auto-Mute Mode" Disabled

sudo alsactl store


# Flatpak and apps
flatpak remote-delete --force flathub || true

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install flathub dev.vencord.Vesktop -y

flatpak install flathub io.gitlab.librewolf-community -y

flatpak install flathub com.mattjakeman.ExtensionManager -y


#  Game launchers + prerequisite 
sudo dnf install -y mesa-vulkan-drivers mesa-vulkan-drivers.i686 vulkan-tools

sudo dnf install steam -y

sudo dnf -y copr enable faugus/faugus-launcher
sudo dnf -y install faugus-launcher -y

#  Enable custom keys
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Control>bracketleft']"

gsettings set org.gnome.settings-daemon.plugins.media-keys volume-up "['Page_Up']"

gsettings set org.gnome.settings-daemon.plugins.media-keys volume-down "['Page_Down']"

gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute "['End']"

#  Kernel optimizations
if ! sudo grep -q "^vm.swappiness=" /etc/sysctl.d/99-sysctl.conf; then
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-sysctl.conf
else
    sudo sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.d/99-sysctl.conf
fi

if ! sudo grep -q "^kernel.sysrq=" /etc/sysctl.d/99-sysctl.conf; then
    echo 'kernel.sysrq=1' | sudo tee -a /etc/sysctl.d/99-sysctl.conf
else
    sudo sed -i 's/^kernel.sysrq=.*/kernel.sysrq=1/' /etc/sysctl.d/99-sysctl.conf
fi

sudo sysctl --system

#  Swap to full ffmpeg (best quality)
sudo dnf swap -y --allowerasing ffmpeg-free ffmpeg || sudo dnf install -y ffmpeg

#. Fix steam drive stuff
sudo mkdir -p /mnt/games
 
grep -q "LABEL=extradrive" /etc/fstab || \
  echo "LABEL=extradrive   /mnt/games   ext4   defaults,nofail,x-gvfs-show   0   2" | sudo tee -a /etc/fstab
 
if mountpoint -q /mnt/games; then
  log "/mnt/games already mounted, skipping"
else
  sudo mount -a
fi
sudo chown -R "$USER:$USER" /mnt/games

#. Shader stuff
mkdir -p ~/.config/environment.d
if grep -q '^MESA_SHADER_CACHE_MAX_SIZE=' ~/.config/environment.d/gaming.conf 2>/dev/null; then
  sed -i 's/^MESA_SHADER_CACHE_MAX_SIZE=.*/MESA_SHADER_CACHE_MAX_SIZE=12G/' ~/.config/environment.d/gaming.conf
else
  echo "MESA_SHADER_CACHE_MAX_SIZE=12G" >> ~/.config/environment.d/gaming.conf
fi






