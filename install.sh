#!/bin/bash
# .------..------..------..------..------..------..------.
# |A.--. ||R.--. ||C.--. ||H.--. ||C.--. ||A.--. ||T.--. |
# | :/\: || :/\: || :/\: || (\/) || (\/) || :/\: || (\/) |
# | (__) || (__) || :\/: || :\/: || :\/: || :\/: || :\/: |
# | '--'I|| '--'N|| '--'S|| '--'T|| '--'A|| '--'L|| '--'L|
# `------'`------'`------'`------'`------'`------'`------'

# Define ANSI escape codes for color
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# Log File
LOGFILE=./archcat.log

# Colored logging system
echolog() {
        echo -e " [$1*$RESET] $2" >>"$LOGFILE"
        clear
        cat "$LOGFILE"
        sleep 1.5
}

# Show temporary log, deleted on every echolog
notify() {
        echo -e " [$YELLOW*$RESET] $1"
        sleep 0.5
}

# Function to check internet connection (against quad9 dns servers)
check_internet() {
        ping -c 3 9.9.9.9 &>/dev/null
}

# Function to retry checking internet connection
ensure_internet() {
        retry_count=0
        until check_internet; do
                ((retry_count++))
                if [[ $retry_count -ge 3 ]]; then
                        echo "You don't have internet access... retrying in 3s."
                        retry_count=0
                fi
                sleep 3
        done
}

is_uefi() {
        [ -d /sys/firmware/efi ]
}

# Checks filesystem and mounts partitions if neccesary
check_fs() {

        # Check if the system is UEFI
        is_uefi && efi=/efi

        local drive=$SELECTED_DRIVE
        local root_mount_point="/mnt"
        local boot_mount_point="/mnt/boot$efi"

        # Check if the selected drive has multiple partitions
        if [ "$(lsblk -n -o NAME "/dev/$drive" | wc -l)" -gt 1 ]; then

                # Check if root partition is mounted
                if ! mountpoint -q "$root_mount_point"; then

                        # Mount root
                        mount /dev/"$drive"3 "$root_mount_point" || {
                                notify "Failed to mount /dev/${drive}3 on $root_mount_point."
                                exit 1
                        }
                fi

                # Check if boot partition is mounted
                if ! mountpoint -q "$boot_mount_point"; then

                        # Create /mnt/boot directory if it does not exist
                        mkdir -p "$boot_mount_point"

                        # Mount boot
                        mount /dev/"$drive"1 "$boot_mount_point" || {
                                notify "Failed to mount /dev/${drive}1 on $boot_mount_point."
                                exit 1
                        }
                fi

                # Check if swap is enabled
                if ! grep -q "/dev/${drive}2" /proc/swaps; then

                        # Enable swap
                        swapon /dev/"$drive"2 || {
                                notify "Failed to enable swap on /dev/${drive}2."
                                exit 1
                        }
                fi
        fi
}

# If exitcode of command or function is non-zero display error and exit
exit_code_check() {
        if [ "$1" -ne 0 ]; then
                echolog "$RED" "$2" && exit 1
        fi
}

gsettings_set() {
        local extension=$1
        local extension_name
        local setting=$2
        local value=$3

        # Get extension name from extension path (value after last dot)
        extension_name=$(echo "$extension" | awk -F '.' '{print $NF}')

        apply_setting() {

                # Apply setting
                gsettings set "$extension" "$setting" "$value"

                # Check if it was successfull
                if [[ "$(gsettings get "$extension" "$setting")" == "$value" ]]; then
                        return 0
                else
                        return 1
                fi
        }

        # Run to get return value because gsettings doesn't return error codes
        apply_setting
        exit_code_check $? "Error While configuring extension: $extension_name at setting: $setting" || exit 1
}

# Define all checkpoints for the full installation process
declare -a CHECKPOINTS=(
        "Setup_filesystem" "Install_root_packages" "Generate_fstab" "Prepare_chroot"

        "Setup_system" "Configure_gnome" "Create_accounts" "Configure_hostname"
        "Configure_keyboard" "Configure_timezone" "Configure_network" "Install_grub"
        "Install_base_packages" "Install_gnome" "Install_vm_ext" "Install_aur"
        "Remove_bloatware" "Install_oh_my_zsh" "Configure_zsh_theme"
        "Install_zsh_plugins" "Install_nerd_fonts" "Prepare_gnome"

        "Copy_config_files" "Configure_gnome_keyboard" "Configure_wallpaper"
        "Qol_tweaks" "Configure_default_apps" "Install_gnome_extensions"
        "Configure_gnome_extensions" "Install_gnome_icon_theme" "Cleanup"
)

# Define files
CHECKPOINT_FILE="CHECKPOINT"

# Function to update the checkpoint
update_checkpoint() {
        echo "$1" >$CHECKPOINT_FILE
}

# Function to get the last completed checkpoint
get_last_checkpoint() {

        if [ -f "$CHECKPOINT_FILE" ]; then
                cat $CHECKPOINT_FILE
        else
                # Default to the first one if no checkpoint exists
                echo "${CHECKPOINTS[0]}" 
        fi
}

##CHECKPOINTS BEGIN

setup_filesystem() {
        notify "Setting up filesystem..."

        if lsblk "/dev/$SELECTED_DRIVE" | grep -q "/mnt/boot"; then
                echolog "$GREEN" "Filesystem was already formated and mounted. Skipping..."

        elif [ "$(lsblk "/dev/$SELECTED_DRIVE" | wc -l)" -gt 4 ]; then

                # Mount filesystem
                check_fs || exit 1

        echolog "$GREEN" "Filesystem is already formated. And has now been succesfully mounted"

        else

                # Check if the system is UEFI
                if is_uefi; then

                        # Setup partitions for UEFI
                        parted /dev/"$SELECTED_DRIVE" --script mklabel gpt
                        exit_code_check "$?" "Error while setting up the partition scheme. exiting..." || exit 1

                        parted /dev/"$SELECTED_DRIVE" --script mkpart primary fat32 1MB 513MB
                        exit_code_check "$?" "Error setting up the EFI system partition. exiting..." || exit 1

                        parted /dev/"$SELECTED_DRIVE" --script set 1 boot on
                        exit_code_check "$?" "Error while marking the EFI system partition as bootable. exiting..." || exit 1

                        parted /dev/"$SELECTED_DRIVE" --script set 1 esp on
                        exit_code_check "$?" "Error while marking the EFI system partition as ESP. exiting..." || exit 1

                else
                        # Setup partitions for BIOS
                        parted /dev/"$SELECTED_DRIVE" --script mklabel msdos
                        exit_code_check "$?" "Error while setting up the partition scheme. exiting..." || exit 1

                        parted /dev/"$SELECTED_DRIVE" --script mkpart primary fat32 1MB 513MB
                        exit_code_check "$?" "Error setting up the boot partition. exiting..." || exit 1

                        parted /dev/"$SELECTED_DRIVE" --script set 1 boot on
                        exit_code_check "$?" "Error while marking the boot partition as bootable. exiting..." || exit 1
                fi

                # Common partition setup
                parted /dev/"$SELECTED_DRIVE" --script mkpart primary linux-swap 513MB 5GB
                exit_code_check "$?" "Error while setting up the swap partition. exiting..." || exit 1

                parted /dev/"$SELECTED_DRIVE" --script mkpart primary ext4 5GB 100%
                exit_code_check "$?" "Error while setting up the root partition. exiting..." || exit 1

                mkfs.vfat -F 32 /dev/"$SELECTED_DRIVE"1 
                exit_code_check "$?" "Error while formating boot/EFI partition. exiting..." || exit 1

                mkswap /dev/"$SELECTED_DRIVE"2 
                exit_code_check "$?" "Error while formating swap partition. exiting..." || exit 1

                mkfs.ext4 /dev/"$SELECTED_DRIVE"3 
                exit_code_check "$?" "Error while formating root partition. exiting..." || exit 1

                # Mount filesystem
                check_fs || exit 1

                echolog "$GREEN" "Filesystem created and mounted succesfully"
        fi
}

install_root_packages() {
        update_checkpoint "Install_root_packages"
        notify "Installing root packages..."

        is_uefi && efibootmgr=efibootmgr

        # Download and Install root packages
        pacstrap /mnt linux linux-firmware networkmanager grub wpa_supplicant base base-devel "$efibootmgr"

        # Check if pacstrap was succesfull
        exit_code_check "$?" "Error while installing root packages. exiting..." || exit 1

        echolog "$GREEN" "Root packages installed succesfully"
}

generate_fstab() {
        update_checkpoint "Generate_fstab"
        notify "Generating fstab..."

        # Generte fstab file
        genfstab -U /mnt >/mnt/etc/fstab
        exit_code_check "$?" "Error while Generating fstab. exiting..." || exit 1

        echolog "$GREEN" "Fstab generated succesfully"
}

prepare_chroot() {
        update_checkpoint "Prepare_chroot"
        notify "Preparing chroot..."

        # Check that process is running outsite of chroot
        if [ -d /run/archiso ]; then

                # Create chroot install directory
                mkdir "/mnt/mnt/Archcat"
                exit_code_check "$?" "Error while creating /mnt/Archcat. exiting..." || exit 1

                echolog "$GREEN" "Chroot setup succesfully. Entering chroot..."

                # Copy all necesary files to chroot file system
                cp -r ./* "/mnt/mnt/Archcat"
                exit_code_check "$?" "Error while copying files to chroot /mnt/Archcat. exiting..." || exit 1

                # Execute the script to continue from chroot
                arch-chroot /mnt /mnt/Archcat/install.sh
                local exitcode=$?

                # Update directories
                rsync -av --update ./ /mnt/Archcat &>/dev/null
                rsync -av --update /mnt/Archcat/ ./ &>/dev/null

                # Reboot if neccesary
                [ $exitcode -eq 100 ] && reboot

                exit $exitcode
        fi
}

create_accounts() {
        update_checkpoint "Create_accounts"
        notify "Creating accounts..."

        # Set up root password
        if [ "$(passwd -S root | awk '{print $2}')" != "P" ]; then
                echo "$ROOT_PASSWORD" | passwd --stdin
                exit_code_check $? "Error while assigning root password" || exit 1
        fi

        # Set up user if it doesnt exist already
        if ! id "$USERNAME" &>/dev/null; then
                useradd -m "$USERNAME"
                exit_code_check $? "Error while creating user $USERNAME " || exit 1
        fi

        # Add user to wheel group for sudo permissions unless already in group
        if ! groups "$USERNAME" | grep -q "wheel"; then
                usermod -aG wheel "$USERNAME"
                exit_code_check $? "Error while adding $USERNAME to wheel group for sudo permissions" || exit 1
        fi

        # Add user password unless already set
        if [ "$(passwd -S "$USERNAME" | awk '{print $2}')" != "P" ]; then
                echo "$USER_PASSWORD" | passwd "$USERNAME" --stdin
                exit_code_check $? "Error while assigning password to $USERNAME" || exit 1
        fi

        # Allow users in the wheel group to execute any command (no password required until installation is finished)
        sed -i -e 's/# %wheel ALL=(ALL:ALL)/%wheel ALL=(ALL:ALL)/g' /etc/sudoers
        exit_code_check $? "Error while modifying /etc/sudores file to allow wheel group users sudo permissions" || exit 1

        echolog "$GREEN" "Accounts generated succesfully"
}

configure_hostname() {
        update_checkpoint "Configure_hostname"
        notify "Configuring hostname..."

        # Set Hostname
        echo "$HOSTNAME" >/etc/hostname

        # Check that Hostname was set correctly
        [[ $(cat /etc/hostname) == "$HOSTNAME" ]]
        exit_code_check $? "Error while configuring hostname: $HOSTNAME" || exit 1

        echolog "$GREEN" "Hostname: $HOSTNAME configured" sys
}

configure_keyboard() {
        update_checkpoint "Configure_keyboard"
        notify "Configuring console keyboard..."

        # Modify tty keyboard layout (spanish layout, hardcoded for now)
        sed -i -e 's/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/g' /etc/locale.gen
        exit_code_check $? "Error while modifying /etc/locale.gen to add spanish keyboard layout" || exit 1

        # Generate locale (keyboard layout)
        locale-gen 1>/dev/null
        exit_code_check $? "Error while generating locale (keyboard layout)" || exit 1

        # Make spanish default tty keyboard layout
        echo "KEYMAP=es" >/etc/vconsole.conf

        echolog "$GREEN" "Keyboard configured succesfully"
}

configure_timezone() {
        update_checkpoint "Configure_timezone"
        notify "Configuring timezone..."

        # Set time zone to Madrid (Spain, hardcoded for now)
        ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
        exit_code_check $? "Error while setting time zone to Madrid" || exit 1

        echolog "$GREEN" "Timezone configured succesfully"
}

configure_network() {
        update_checkpoint "Configure_network"
        notify "Configuring Network..."

        # Add local hosts
        echo -e "127.0.0.1   localhost\n::1  localhost" >/etc/hosts

        # Set Quad9 DNS
        echo -e "nameserver 9.9.9.9\nnameserver 149.112.112.112" >/etc/resolv.conf

        # Enable network manager
        systemctl enable NetworkManager.service
        exit_code_check $? "Error while enabling NetworkManager.service" || exit 1

        # Enable wpa_supplicant
        systemctl enable wpa_supplicant.service
        exit_code_check $? "Error while enabling wpa_supplicant.service" || exit 1

        echolog "$GREEN" "Network has been configured"
}

install_grub() {
        update_checkpoint "Install_grub"
        notify "Installing and configuring GRUB..."

        # Change the OS name from "Arch Linux" to "ArchCat"
        sed -i 's/GRUB_DISTRIBUTOR="Arch"/GRUB_DISTRIBUTOR="ArchCat"/' /etc/default/grub

        
        if is_uefi; then
                # For UEFI systems
                grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
                exit_code_check $? "Error while installing GRUB" || exit 1
        else
                # For BIOS systems
                grub-install --target=i386-pc /dev/"$SELECTED_DRIVE"
                exit_code_check $? "Error while installing GRUB" || exit 1
        fi

        # Disable ipv6
        sed -i -e 's/^GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="ipv6.disable=1"/' /etc/default/grub

        # Generate GRUB configuration
        grub-mkconfig -o /boot/grub/grub.cfg 1>/dev/null
        exit_code_check $? "Error while generating GRUB configuration" || exit 1

        echolog "$GREEN" "GRUB installed successfully."
}

install_base_packages() {
        update_checkpoint "Install_base_packages..."
        notify "Installing base packages"

        # Installing base packages
        pacman --noconfirm --quiet -S git wget nano kitty python-pip pacman-contrib zsh dconf-editor lsd bat
        exit_code_check $? "Error while installing base packages" || exit 1

        # Set zsh as default shell
        chsh -s /bin/zsh 
        chsh -s /bin/zsh "$USERNAME" 

        echolog "$GREEN" "Base packages succesfully installed"
}

install_gnome() {
        update_checkpoint "Install_gnome"
        notify "Installing desktop enviroment..."

        # Installing DE
        pacman --noconfirm --quiet -S xorg xorg-server gnome
        exit_code_check $? "Error while installing desktop enviroment" || exit 1

        # Enabling gnome
        systemctl enable gdm.service
        exit_code_check $? "Error while enabling desktop enviroment" || exit 1

        # Install gnome-extensions-cli (gext) to install extensions
        python -m pip install --upgrade gnome-extensions-cli --break-system-packages
        exit_code_check "$?" "Error while installing gnome-extension-cli (Extension manager)" || exit 1

        echolog "$GREEN" "Desktop enviroment succesfully installed"
}

install_vm_ext() {
        update_checkpoint "Install_vm_ext"

        # In case of using virtual machine install extensions

        if [[ $VIRTUAL_MACHINE_EXT == "true" ]]; then

                virtualbox_ext_install() {
                        # Install virtualbox guest additions
                        notify "Installing guest additions..."
                        pacman --noconfirm --quiet -S virtualbox-guest-utils
                        exit_code_check $? "Error while installing virtualbox guest additions" || exit 1

                        # Enable virtualbox guest additions
                        systemctl enable vboxservice.service
                        exit_code_check $? "Error while enabling virtualbox.service" || exit 1

                        # Enable seamless mode (screen adapts to window size)
                        VBoxClient --seamless
                        exit_code_check $? "Error while enabling virtualbox seamless screen mode" || exit 1

                        # Enable vboxsvga mode
                        VBoxClient --vmsvga
                        exit_code_check $? "Error while enabling virtualbox vboxsvga screen mode" || exit 1

                        # Enable shared clipboard between host and client
                        VBoxClient --clipboard
                        exit_code_check $? "Error while enabling virtualbox shared clipboard" || exit 1

                        echolog "$GREEN" "Virtualbox guest additions succesfully installed"
                }

                vmware_ext_install() {
                        # Install vmware tools
                        notify "Installing vmware tools..."
                        pacman --noconfirm --quiet -S open-vm-tools
                        exit_code_check $? "Error while installing vmware tools" || exit 1

                        # Enable vmware tools
                        systemctl enable vmtoolsd.service
                        exit_code_check $? "Error while enabling vmtoolsd.service" || exit 1

                        echolog "$GREEN" "VMware tools succesfully installed"
                }

                case $VIRTUAL_MACHINE in
                "VirtualBox") virtualbox_ext_install || exit 1 ;;
                "VMware") vmware_ext_install || exit 1 ;;
                *) echolog "$GREEN" "No virtual machine detected! skipping vm extensions." ;;
                esac
        fi
}

install_aur() {
        update_checkpoint "Install_aur"
        notify "Downloadning and Installing AUR..."

        # Remove if it was already downloaded
        rm -rf "/home/$USERNAME/paru-bin" 2>/dev/null

        # Download AUR
        sudo -u "$USERNAME" git clone https://aur.archlinux.org/paru-bin.git "/home/$USERNAME/paru-bin"
        exit_code_check $? "Error while cloning AUR (paru-bin)" || exit 1

        # Go to the downloaded directory
        cd "/home/$USERNAME/paru-bin" || exit 1

        # Build AUR
        sudo -u "$USERNAME" makepkg -si --noconfirm

        # Go back to previous directory
        cd - || exit

        # Remove directory
        rm -rf "/home/$USERNAME/paru-bin"

        # Check if paru was installed successfully
        paru --help &>/dev/null
        exit_code_check $? "Error while installing AUR (paru-bin)" || exit 1

        echolog "$GREEN" "AUR repository succesfully installed"
}

remove_bloatware() {
        update_checkpoint "Remove_bloatware"
        notify "Removing bloatware..."

        # Remove bloatware
        pacman --noconfirm -R gnome-tour gnome-user-docs gnome-maps gnome-music gnome-contacts \
        gnome-weather simple-scan epiphany yelp gnome-console

        exit_code_check $? "Error while removing bloatware" || exit 1

        # Remove cached packages
        sudo pacman --noconfirm -Scc
        exit_code_check $? "Error while removing cache" || exit 1

        echolog "$GREEN" "Bloatware removed successfully"
}

install_oh_my_zsh() {
        update_checkpoint "Install_oh_my_zsh"
        notify "Installing Oh My Zsh..."

        # Delete old oh-my-zsh dir if exists
        rm -rf /home/"$USERNAME"/.oh-my-zsh 2>/dev/null

        # Download and install oh my zsh
        sudo -u "$USERNAME" sh -c "$(wget -q -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sed 's/exec zsh -l//g')"
        exit_code_check $? "Error while downloading/installing Oh My Zsh" || exit 1

        # Alias bat as cat and lsd as ls if they arent added already
        grep -q 'alias ls' /home/"$USERNAME"/.zshrc || echo -e "alias ls='lsd'\nalias cat='bat'" >>/home/"$USERNAME"/.zshrc

        echolog "$GREEN" "Oh My Zsh installed successfully"
}

configure_zsh_theme() {
        update_checkpoint "Configure_zsh_theme"
        notify "Installing zsh theme"

        # Download powerlevel10k theme
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /home/"$USERNAME"/.oh-my-zsh/custom/themes/powerlevel10k
        exit_code_check $? "Error while cloning Powerlevel10k theme" || exit 1

        echolog "$GREEN" "Zsh theme installed correctly"
}

install_zsh_plugins() {
        update_checkpoint "Install_zsh_plugins"
        notify "Setting up Zsh plugins..."

        # Install autosuggestions
        git clone https://github.com/zsh-users/zsh-autosuggestions /home/"$USERNAME"/.oh-my-zsh/custom/plugins/zsh-autosuggestions
        exit_code_check $? "Error while cloning zsh-autosuggestions" || exit 1

        # Install syntax highlighting
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git /home/"$USERNAME"/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
        exit_code_check $? "Error while cloning zsh-syntax-highlighting" || exit 1

        # Enable all plugins
        sed -i 's/plugins=.*$/plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting history)/g' /home/"$USERNAME"/.zshrc

        echolog "$GREEN" "Zsh plugins installed correctly"
}

install_nerd_fonts() {
        update_checkpoint "Install_nerd_fonts"
        notify "Installing Nerd fonts..."

        # Download Hack nerd fonts
        wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip
        exit_code_check $? "Error while downloading Nerd Hack fonts" || exit 1

        # Create a directory to store fonts
        mkdir -p /usr/share/fonts/hack
        exit_code_check $? "Error while making directory /usr/share/fonts/hack" || exit 1

        # Unzip to fonts/hack directory
        unzip Hack.zip -d /usr/share/fonts/hack 
        exit_code_check $? "Error while unzipping Nerd Hack fonts to /usr/share/fonts/hack" || exit 1

        # Remove the downloaded file
        rm Hack.zip*

        # Update font cache to enable new fonts
        fc-cache -f -v
        exit_code_check $? "Error while updating font cache" || exit 1

        echolog "$GREEN" "Nerd fonts installed correctly"
}

prepare_gnome() {

        if [ "$DESKTOP_SESSION" != "gnome" ]; then
                update_checkpoint "Prepare_gnome"
                notify "Preparing gnome..."

                # Create autostart dir
                sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.config/autostart/"

                # Give Archcat folder permissions to user
                chown -R "$USERNAME" /mnt/Archcat
                chgrp -R "$USERNAME" /mnt/Archcat

                # Enable auto login for the script to keep running
                echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$USERNAME" | tee /etc/gdm/custom.conf

                # Create the gui installer using the username variable
                echo -e "[Desktop Entry]\nType=Application\nName=ArchCatInstaller\nComment=Continue Installation, will be removed\nExec=/usr/bin/kitty -T 'ArchCat Installer' bash -c \"cd /mnt/Archcat && sleep 2; /mnt/Archcat/install.sh; exec /bin/zsh\"\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true" | tee "/home/$USERNAME/.config/autostart/archcat.desktop"

                # Reboot to execute this script from gnome
                echolog "$GREEN" "Reboot required, remove the installation media and enter"
                read -r
                exit 100
        else
                # Disable auto launch archcat installer
                rm -f "/home/$USERNAME/.config/autostart/archcat.desktop" 2>/dev/null
                echolog "$GREEN" "Gnome is Active"
        fi
}

copy_config_files() {
        update_checkpoint "Copy_config_files"
        notify "Copying configuration files..."

        # Copy kitty config file
        sudo -u "$USERNAME" mkdir -p /home/"$USERNAME"/.config/kitty/
        cp /mnt/Archcat/config/kitty.conf /home/"$USERNAME"/.config/kitty/
        exit_code_check $? "Error while copying Kitty configuration" || exit 1

        # Copy powerlevel10k config file
        cp /mnt/Archcat/config/.p10k.zsh /home/"$USERNAME"/
        exit_code_check $? "Error while copying zsh theme configuration" || exit 1

        # Enable theme
        sed -i 's/^ZSH_THEME=.*$/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' /home/"$USERNAME"/.zshrc

        # Enable powerlevel10k config
        echo -e "\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" >>/home/"$USERNAME"/.zshrc

        # Set home folder permissions completely to user
        chown "$USERNAME" -R /home/"$USERNAME" 
        chgrp "$USERNAME" -R /home/"$USERNAME" 

        echolog "$GREEN" "Config files copied succesfully"
}

configure_gnome_keyboard() {
        update_checkpoint "Configure_gnome_keyboard"
        notify "Configuring keyboard input sources..."

        # Set keyboard input sources (spanish, hardcoded for now)
        gsettings_set org.gnome.desktop.input-sources sources "[('xkb', 'es')]" || exit 1

        echolog "$GREEN" "Keyboard configured in gnome"
}

configure_wallpaper() {
        update_checkpoint "Configure_wallpaper"
        notify "Configuring wallpaper..."

        # Copy Wallpapers
        cp /mnt/Archcat/images/wallpaper* /home/"$USERNAME"/Pictures/
        exit_code_check $? "Error while copying pictures to /home/$USERNAME/Pictures/" || exit 1

        # Set pictures dir variable in correct format
        pictures_dir="'file:///home/$USERNAME/Pictures/"

        # Set light mode wallpaper
        gsettings_set org.gnome.desktop.background picture-uri "$pictures_dir/wallpaper.jpg'" || exit 1

        # Set dark mode wallpaper
        gsettings_set org.gnome.desktop.background picture-uri-dark "$pictures_dir/wallpaper-dark.jpg'" || exit 1

        echolog "$GREEN" "Wallpaper configured in gnome"
}

qol_tweaks() {
        update_checkpoint "Qol_tweaks"
        notify "Configuring quality of life tweaks..."

        # Set max volume to 150
        gsettings_set org.gnome.desktop.sound allow-volume-above-100-percent true || exit 1

        # When in text editor higlight current line
        gsettings_set org.gnome.TextEditor highlight-current-line true || exit 1

        # Show battery percentage
        gsettings_set org.gnome.desktop.interface show-battery-percentage true || exit 1

        # Show weekdate in taskbar
        gsettings_set org.gnome.desktop.calendar show-weekdate true || exit 1

        # Disable clocks and character search-providers
        gsettings_set org.gnome.desktop.search-providers disabled "['org.gnome.clocks.desktop', 'org.gnome.Characters.desktop']" || exit 1

        # Set file explorer icons to small
        gsettings_set org.gnome.nautilus.icon-view default-zoom-level "'small'" || exit 1

        # Set default pinned apps
        gsettings_set org.gnome.shell favorite-apps "['kitty.desktop', 'org.gnome.Nautilus.desktop']" || exit 1

        echolog "$GREEN" "Quality of life changes configured in gnome"
}

configure_default_apps() {
        update_checkpoint "Configure_default_apps"
        notify "Configuring defaut apps..."

        # Set text editor as default compared to nvim
        xdg-mime default org.gnome.TextEditor.desktop text/plain

        echolog "$GREEN" "Default apps configured"
}

install_gnome_extensions() {
        update_checkpoint "Install_gnome_extensions"
        notify "Installing gnome shell extensions..."

        # Install extensions
        gext -F install runcat@kolesnikov.se dash-to-panel@jderose9.github.com arcmenu@arcmenu.com \
        caffeine@patapon.info clipboard-indicator@tudmotu.com arch-update@RaphaelRochet IP-Finder@linxgem33.com
        exit_code_check "$?" "Error while installing extensions" || exit 1

        # Copy configuration schemas
        sudo cp /home/"$USERNAME"/.local/share/gnome-shell/extensions/*/schemas/org.*gschema.xml /usr/share/glib-2.0/schemas/
        exit_code_check "$?" "Error while copying extension schemas" || exit 1

        # Apply schemas
        sudo glib-compile-schemas /usr/share/glib-2.0/schemas/
        exit_code_check "$?" "Error while applying glib schemas, this is required to configure gnome extensions" || exit 1

        echolog "$GREEN" "Gnome Extensions installed succesfully"
}

configure_gnome_extensions() {
        update_checkpoint "Configure_gnome_extensions"
        notify "Configuring gnome shell extensions..."

        # Runcat
        local extension="org.gnome.shell.extensions.runcat"
        gsettings_set $extension displaying-items "'character-and-percentage'" || exit 1
        gsettings_set $extension idle-threshold 15 || exit 1

        # Dash-to-Panel
        extension="org.gnome.shell.extensions.dash-to-panel"
        gsettings_set $extension panel-sizes "'{\"0\":36}'" || exit 1
        gsettings_set $extension window-preview-size 130 || exit 1
        gsettings_set $extension show-window-previews-timeout 100 || exit 1
        gsettings_set $extension appicon-margin 0 || exit 1
        gsettings_set $extension trans-use-custom-opacity true || exit 1
        gsettings_set $extension trans-panel-opacity 0.75 || exit 1
        gsettings_set $extension click-action "'CYCLE-MIN'"
        gsettings_set $extension panel-element-positions "'{\"0\":[{\"element\":\"showAppsButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"activitiesButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"leftBox\",\"visible\":true,\"position\":\"stackedTL\"},{\"element\":\"taskbar\",\"visible\":true,\"position\":\"stackedTL\"},{\"element\":\"centerBox\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"rightBox\",\"visible\":true,\"position\":\"centerMonitor\"},{\"element\":\"systemMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"dateMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"desktopButton\",\"visible\":false,\"position\":\"stackedBR\"}]}'" || exit 1

        # ArcMenu
        extension="org.gnome.shell.extensions.arcmenu"
        gsettings_set $extension menu-layout "'Raven'" || exit 1
        gsettings_set $extension menu-button-fg-color "(true, 'rgb(98,160,234)')" || exit 1
        gsettings_set $extension distro-icon 6 || exit 1
        gsettings_set $extension menu-button-icon "'Distro_Icon'" || exit 1
        gsettings_set $extension hide-overview-on-startup true || exit 1
        gsettings_set $extension disable-recently-installed-apps true || exit 1
        gsettings_set $extension shortcut-icon-type "'Full_Color'" || exit 1
        gsettings_set $extension extra-categories "[(2, true), (0, true), (1, true), (3, false), (4, false)]" || exit 1
        gsettings_set $extension pinned-apps "[{'id': 'org.gnome.Nautilus.desktop'}, {'id': 'kitty.desktop'}, {'id': 'org.gnome.TextEditor.desktop'}, {'id': 'org.gnome.SystemMonitor.desktop'}, {'id': 'org.gnome.Logs.desktop'}, {'id': 'org.gnome.Calculator.desktop'}]" || exit 1
        gsettings_set $extension context-menu-items "[{'id': 'ArcMenu_PowerOptions', 'name': 'Power Options', 'icon': 'system-shutdown-symbolic'}, {'id': 'ArcMenu_ActivitiesOverview', 'name': 'Activities Overview', 'icon': 'view-fullscreen-symbolic'}, {'id': 'ArcMenu_ShowDesktop', 'name': 'Show Desktop', 'icon': 'computer-symbolic'}]" || exit 1

        # Clipboard Indicator
        extension="org.gnome.shell.extensions.clipboard-indicator"
        gsettings_set $extension confirm-clear false || exit 1
        gsettings_set $extension paste-button false || exit 1

        # Arch Update
        extension="org.gnome.shell.extensions.arch-update"
        gsettings_set $extension update-cmd "'/usr/bin/kitty -T \"Archcat Update\" sh -c \"sudo pacman -Syu ; echo Done - Exitting in 3s ; sleep 3\"'" || exit 1
        gsettings_set $extension always-visible false || exit 1

        echolog "$GREEN" "Gnome extensions configured succeessfully"
}

install_gnome_icon_theme() {
        update_checkpoint "Install_gnome_icon_theme"
        notify "Installing papirus icon theme..."

        # Enable user themes
        gext enable user-theme@gnome-shell-extensions.gcampax.github.com
        exit_code_check "$?" "Failed to enable user themes" || exit 1

        # Download papirus theme
        sudo pacman --noconfirm --quiet -S gnome-tweaks papirus-icon-theme
        exit_code_check "$?" "Error while installing Papirus icon theme" || exit 1

        # Enable papirus theme
        gsettings_set org.gnome.desktop.interface icon-theme "'Papirus'" || exit 1

        echolog "$GREEN" "Papirus Theme has been enabled"
}

cleanup() {
        update_checkpoint "Cleanup"

        # Disable auto login
        sudo rm -f /etc/gdm/custom.conf 2>/dev/null
        exit_code_check "$?" "Error while disabling auto login" || exit 1

        # Remove useless file
        sudo rm "/home/$USERNAME/.*pre-oh-my-zsh*" 2>/dev/null
        sudo rm "/home/$USERNAME/.wget-hsts" 2>/dev/null

        # Move archcat.sh to bin to be a regular command
        sudo cp /mnt/Archcat/tools/archcat.sh /usr/local/bin/archcat 2>/dev/null
        exit_code_check "$?" "Error while adding archcat as a system command" || exit 1

        # Remove installer from system
        sudo rm -rf /mnt/Archcat 2>/dev/null
        exit_code_check "$?" "Error while removing installer" || exit 1

        # Make password required for sudo for wheel group users
        sudo sed -i -e 's/%wheel ALL=(ALL:ALL) NOPASSWD/# %wheel ALL=(ALL:ALL) NOPASSWD/g' /etc/sudoers 
        exit_code_check "$?" "Error while enabling user password for sudo" || exit 1

        # Final poweroff to finish installation
        echo -e " [$GREEN*$RESET] Installation Complete! system rebooting in 5s"
        sleep 5
        reboot
}

##CHECKPOINTS END

main() {

        # Check that internet is available
        ensure_internet

        cd "$(dirname -- "$0")" 2>/dev/null || cd "/mnt/Archcat" || exit

        [ -f $LOGFILE ] || printf "\n" >$LOGFILE

        if [ -d /mnt/mnt/Archcat ]; then

                # Update directories
                rsync -av --update ./ /mnt/mnt/Archcat &>/dev/null
                rsync -av --update /mnt/mnt/Archcat/ ./ &>/dev/null

                # Continue script from inside chroot
                arch-chroot /mnt /mnt/Archcat/install.sh
                local exitcode=$?

                # Update directories
                rsync -av --update ./ /mnt/mnt/Archcat &>/dev/null
                rsync -av --update /mnt/mnt/Archcat/ ./ &>/dev/null

                # Reboot if required
                [ $exitcode -eq 100 ] && reboot

                exit $exitcode
        fi

        # Check if .cfg file exists, else generate it
        ls archgen.cfg &>/dev/null || ./tools/archgen.sh || exit 1

        # Import installation config
        source ./archgen.cfg

        # Check filesystem if interacting from iso, mount if necessary
        if [ -d /run/archiso ]; then
                check_fs
        fi

        # Get last checkpoint to continue from (if any)
        last_checkpoint=$(get_last_checkpoint)

        # Determine the starting index based on last checkpoint
        last_checkpoint_index=-1
        for i in "${!CHECKPOINTS[@]}"; do
                if [ "${CHECKPOINTS[$i]}" == "$last_checkpoint" ]; then
                        last_checkpoint_index=$((i - 1))
                        break
                fi
        done

        # Run through the installation sequence from last checkpoint
        for ((i = last_checkpoint_index + 1; i < ${#CHECKPOINTS[@]}; i++)); do
                Checkpoint=${CHECKPOINTS[$i]}

                case $Checkpoint in

                        # Setup system
                        "Setup_filesystem") setup_filesystem || exit 1 ;;
                        "Install_root_packages") install_root_packages || exit 1 ;;
                        "Generate_fstab") generate_fstab || exit 1 ;;
                        "Prepare_chroot") prepare_chroot || exit 1 ;;

                        # Configure system
                        "Create_accounts") create_accounts || exit 1 ;;
                        "Configure_hostname") configure_hostname || exit 1 ;;
                        "Configure_keyboard") configure_keyboard || exit 1 ;;
                        "Configure_timezone") configure_timezone || exit 1 ;;
                        "Install_grub") install_grub || exit 1 ;;
                        "Configure_network") configure_network || exit 1 ;;
                        "Install_base_packages") install_base_packages || exit 1 ;;
                        "Install_gnome") install_gnome || exit 1 ;;
                        "Install_vm_ext") install_vm_ext || exit 1 ;;
                        "Install_aur") install_aur || exit 1 ;;
                        "Remove_bloatware") remove_bloatware || exit 1 ;;
                        "Install_oh_my_zsh") install_oh_my_zsh || exit 1 ;;
                        "Configure_zsh_theme") configure_zsh_theme || exit 1 ;;
                        "Install_zsh_plugins") install_zsh_plugins || exit 1 ;;
                        "Install_nerd_fonts") install_nerd_fonts || exit 1 ;;
                        "Configure_terminal") configure_terminal || exit 1 ;;
                        "Prepare_gnome")
                                prepare_gnome
                                exit_code=$?
                                [ $exit_code -eq 100 ] && exit 100
                                [ $exit_code -ne 0 ] && exit 1
                                ;;

                        # Configure gnome after reboot
                        "Copy_config_files") copy_config_files || exit 1 ;;
                        "Configure_gnome_keyboard") configure_gnome_keyboard || exit 1 ;;
                        "Configure_wallpaper") configure_wallpaper || exit 1 ;;
                        "Qol_tweaks") qol_tweaks || exit 1 ;;
                        "Configure_default_apps") configure_default_apps || exit 1 ;;
                        "Install_gnome_extensions") install_gnome_extensions || exit 1 ;;
                        "Configure_gnome_extensions") configure_gnome_extensions || exit 1 ;;
                        "Install_gnome_icon_theme") install_gnome_icon_theme || exit 1 ;;
                        "Cleanup") cleanup || exit 1 ;;
                esac
        done
}

main "$@"