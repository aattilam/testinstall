#!/bin/bash

# This script modifies an already installed minimal Debian Stable system.
# It sets up repositories, configures APT pinning, installs packages,
# modifies existing users' themes, sets up automatic updates for major versions,
# and performs other configurations.
# Run this script as root or with sudo privileges.

# Exit immediately if a command exits with a non-zero status
set -e

echo "1. Setting up APT repositories..."

# Backup existing sources.list
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# Configure sources.list to include Testing, Stable, and Backports
cat > /etc/apt/sources.list << EOL
# Debian Testing (Main Repository)
deb http://deb.debian.org/debian testing main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian testing main contrib non-free non-free-firmware

# Debian Stable (Secondary Repository)
deb http://deb.debian.org/debian stable main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian stable main contrib non-free non-free-firmware

# Debian Stable Backports
deb http://deb.debian.org/debian stable-backports main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian stable-backports main contrib non-free non-free-firmware
EOL

echo "2. Configuring APT preferences for package pinning..."

# Create or overwrite /etc/apt/preferences
cat > /etc/apt/preferences << EOL
Package: *
Pin: release a=testing
Pin-Priority: 990

Package: *
Pin: release a=stable-backports
Pin-Priority: 500

Package: *
Pin: release a=stable
Pin-Priority: 400
EOL

# Get current major versions of the kernel and GNOME
echo "Detecting current major versions of the kernel and GNOME..."

CURRENT_KERNEL_MAJOR_VERSION=$(uname -r | cut -d'.' -f1,2)
CURRENT_GNOME_VERSION=$(gnome-shell --version | awk '{print $3}' | cut -d'.' -f1)

# Handle cases where GNOME is not installed yet
if [ -z "$CURRENT_GNOME_VERSION" ]; then
  # Assuming GNOME 3 as default if not installed
  CURRENT_GNOME_VERSION=3
fi

echo "Current Kernel Major Version: $CURRENT_KERNEL_MAJOR_VERSION"
echo "Current GNOME Major Version: $CURRENT_GNOME_VERSION"

# Pin the kernel and GNOME packages to the current major versions
cat >> /etc/apt/preferences << EOL

# Hold current kernel packages
Package: linux-image-*
Pin: version $CURRENT_KERNEL_MAJOR_VERSION*
Pin-Priority: 1001

Package: linux-headers-*
Pin: version $CURRENT_KERNEL_MAJOR_VERSION*
Pin-Priority: 1001

# Hold current GNOME packages
Package: gnome gnome-*
Pin: version $CURRENT_GNOME_VERSION*
Pin-Priority: 1001
EOL

echo "3. Creating update script for major versions..."

# Create the update script
cat > /usr/local/bin/update-major-versions.sh << 'EOF'
#!/bin/bash
# This script updates the major version numbers in /etc/apt/preferences

# Exit immediately if a command exits with a non-zero status
set -e

echo "Updating major versions in /etc/apt/preferences..."

# Get the latest kernel major version available
LATEST_KERNEL_VERSION=$(apt-cache policy linux-image-amd64 | grep Candidate | awk '{print $2}' | cut -d'.' -f1,2)

# Get the latest GNOME major version available
LATEST_GNOME_VERSION=$(apt-cache policy gnome-shell | grep Candidate | awk '{print $2}' | cut -d'.' -f1)

# Update /etc/apt/preferences with the new major versions
sed -i "s/^\(Package: linux-image-\*\)\nPin: version .*/\1\nPin: version $LATEST_KERNEL_VERSION*\nPin-Priority: 1001/" /etc/apt/preferences
sed -i "s/^\(Package: linux-headers-\*\)\nPin: version .*/\1\nPin: version $LATEST_KERNEL_VERSION*\nPin-Priority: 1001/" /etc/apt/preferences
sed -i "s/^\(Package: gnome gnome-\*\)\nPin: version .*/\1\nPin: version $LATEST_GNOME_VERSION*\nPin-Priority: 1001/" /etc/apt/preferences

echo "Major versions updated to Kernel: $LATEST_KERNEL_VERSION, GNOME: $LATEST_GNOME_VERSION"

# Update package lists
apt-get update
EOF

# Make the update script executable
chmod +x /usr/local/bin/update-major-versions.sh

echo "4. Setting up cron job to run the update script weekly..."

# Add a cron job to run the update script every Sunday at midnight
(crontab -l 2>/dev/null; echo "0 0 * * 0 /usr/local/bin/update-major-versions.sh >> /var/log/update-major-versions.log 2>&1") | crontab -

echo "Cron job added to run update-major-versions.sh weekly."

echo "5. Adding i386 architecture..."
dpkg --add-architecture i386

echo "6. Updating and upgrading the system..."
apt-get update && apt-get upgrade -y && apt-get autoremove -y

echo "7. Installing required packages..."
apt-get install -y \
  gnome-core zenity gir1.2-gnomedesktop-3.0 \
  libreoffice libreoffice-gnome \
  sudo gnome-tweaks gnome-initial-setup \
  curl git htop gnome-boxes software-properties-gtk \
  laptop-detect flatpak network-manager \
  gnome-software-plugin-flatpak chrome-gnome-shell \
  adwaita-qt adwaita-qt6 firmware-linux-nonfree firmware-misc-nonfree \
  rar unrar libavcodec-extra gstreamer1.0-libav \
  gstreamer1.0-plugins-ugly gstreamer1.0-vaapi ffmpeg \
  lm-sensors isenkram network-manager-gnome wget

echo "8. Removing Firefox ESR and installing the latest Firefox..."
apt-get purge -y firefox-esr
apt-get install -y firefox

echo "9. Adding Flathub repository..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "10. Installing Linux headers..."
apt-get install -y linux-headers-amd64

echo "11. Detecting graphics card and installing appropriate drivers..."
graphics=$(lspci -nn | egrep -i "3d|display|vga")

# Check if the output contains NVIDIA
if echo "$graphics" | grep -qi "NVIDIA"; then
  echo "NVIDIA graphics card detected. Installing NVIDIA drivers..."
  apt-get install -y nvidia-detect nvidia-driver nvidia-smi \
    mesa-vulkan-drivers libglx-mesa0:i386 \
    mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386
# Check if the output contains AMD
elif echo "$graphics" | grep -qi "AMD"; then
  echo "AMD graphics card detected. Installing AMD drivers..."
  apt-get install -y firmware-amd-graphics libgl1-mesa-dri \
    libvulkan1 vulkan-tools vulkan-validationlayers \
    libdrm-amdgpu1 libglx-mesa0 mesa-vulkan-drivers \
    libglx-mesa0:i386 mesa-vulkan-drivers:i386 \
    libgl1-mesa-dri:i386 radeontop fancontrol
else
  echo "No NVIDIA or AMD graphics card detected. Skipping driver installation."
fi

echo "12. Fixing NetworkManager configuration..."
nmandefault="# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback
"

# Backup existing interfaces file
cp /etc/network/interfaces /etc/network/interfaces.bak
echo "$nmandefault" > /etc/network/interfaces

# Modify NetworkManager.conf
if grep -q "^\[ifupdown\]" /etc/NetworkManager/NetworkManager.conf; then
    if grep -q "^managed=" /etc/NetworkManager/NetworkManager.conf; then
        sed -i '/^\[ifupdown\]/,/^$/ {s/^managed=.*/managed=true/;}' /etc/NetworkManager/NetworkManager.conf
    else
        sed -i '/^\[ifupdown\]/ a managed=true' /etc/NetworkManager/NetworkManager.conf
    fi
else
    echo -e "\n[ifupdown]\nmanaged=true" >> /etc/NetworkManager/NetworkManager.conf
fi

echo "Interface management enabled in /etc/NetworkManager/NetworkManager.conf"

echo "13. Installing Wine and related packages..."
apt-get install -y wine wine32 wine64 libwine libwine:i386 fonts-wine

echo "14. Setting up GTK themes for all users..."

# Install themes to system-wide directory
wget https://github.com/lassekongo83/adw-gtk3/releases/download/v5.3/adw-gtk3v5.3.tar.xz
tar -xf adw-gtk3v5.3.tar.xz -C /usr/share/themes
rm adw-gtk3v5.3.tar.xz

# Install Flatpak themes
flatpak install -y org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark

# Apply theme to existing users
echo "Applying theme to existing users..."
for user in $(ls /home); do
  USER_HOME="/home/$user"
  if [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/.themes"
    cp -r /usr/share/themes/adw-gtk3 "$USER_HOME/.themes/"
    chown -R "$user":"$user" "$USER_HOME/.themes"
    # Optionally set the theme in the user's settings (requires dconf)
    sudo -u "$user" dbus-launch gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3"
    sudo -u "$user" dbus-launch gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
  fi
done

# Also set the theme for new users via /etc/skel
mkdir -p /etc/skel/.themes
cp -r /usr/share/themes/adw-gtk3 /etc/skel/.themes/

echo "15. Installing GRUB2 themes..."
git clone https://github.com/vinceliuice/grub2-themes.git
cd grub2-themes
./install.sh -t tela -s 1080p
cd ..
rm -rf grub2-themes

echo "All tasks have been completed successfully!"
