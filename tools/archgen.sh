#!/bin/bash
#     ___                    _        ___
#    /   \     _ _    __    | |_     / __|    ___    _ _
#    | - |    | '_|  / _|   | ' \   | (_ |   / -_)  | ' \
#    |_|_|   _|_|_   \__|_  |_||_|   \___|   \___|  |_||_|
#  _|"""""|_|"""""|_|"""""|_|"""""|_|"""""|_|"""""|_|"""""|
#  "`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'

# Helper function to handle script cancellation
canceled() {
        echo "Canceled. Exiting..."
        exit 1
}

# Function to get a confirmed password
get_confirmed_password() {
        local user="$1"
        while true; do
                password=$(whiptail --title "Set Password" --passwordbox "Enter password for $user:" 8 40 3>&1 1>&2 2>&3)
                if [[ $? -ne 0 ]]; then canceled; fi

                confirm_password=$(whiptail --title "Confirm Password" --passwordbox "Confirm password for $user:" 8 40 3>&1 1>&2 2>&3)
                if [[ $? -ne 0 ]]; then canceled; fi

                if [ -z "$password" ] || [ -z "$confirm_password" ]; then
                        whiptail --title "Empty Password" --msgbox "Password cannot be empty. Please enter a valid password." 8 60 3>&1 1>&2 2>&3
                        if [[ $? -ne 0 ]]; then canceled; fi
                elif [ "$password" == "$confirm_password" ]; then
                        whiptail --title "Confirmed" --msgbox "Password confirmed." 8 40 3>&1 1>&2 2>&3
                        if [[ $? -ne 0 ]]; then canceled; fi
                        echo "$password"
                        return
                else
                        whiptail --title "Mismatch" --msgbox "Passwords do not match. Please try again." 8 60 3>&1 1>&2 2>&3
                        if [[ $? -ne 0 ]]; then canceled; fi
                fi
        done
}

# Detect virtual machine environments
virtual_machine=""
dmidecode | grep -qi "VirtualBox" && virtual_machine="VirtualBox"
dmidecode | grep -qi "VMware" && virtual_machine="VMware"

# Get list of disks
disks=($(lsblk -b -o NAME,SIZE,TYPE | awk '$3 == "disk" {print $1, int($2 / (1024 ** 3))"GB"}'))

# Create menu options for disk selection
available_drives=()
for ((i = 0; i < ${#disks[@]}; i += 2)); do
        available_drives+=("${disks[$i]}" "Size: ${disks[$i + 1]}")
done

# Select drive for installation
selected_drive=$(whiptail --title "Select a Disk" --menu "WARNING: The selected disk will be formatted." 15 50 4 "${available_drives[@]}" 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then canceled; fi


# Ask if the user wants to enable disk encryption and password if so
enable_encryption=$(whiptail --title "Disk Encryption" --yesno "Do you want to enable disk encryption?" 8 45 3>&1 1>&2 2>&3)
if [[ $? -eq 0 ]]; then
        # Get encryption password
        encryption_password=$(get_confirmed_password "full disk encryption")
        if [[ $? -ne 0 ]]; then canceled; fi
        encryption_enabled="true"
fi

# Get root password
root_password=$(get_confirmed_password "root")
if [[ $? -ne 0 ]]; then canceled; fi

# Get username
while true; do
        username=$(whiptail --title "Username" --inputbox "Enter a username:" 8 40 3>&1 1>&2 2>&3)
        if [[ $? -ne 0 ]]; then canceled; fi
        if [ -z "$username" ]; then
                whiptail --title "Invalid Username" --msgbox "Username cannot be empty. Please enter a valid username." 8 60 3>&1 1>&2 2>&3
                if [[ $? -ne 0 ]]; then canceled; fi
        else
                break
        fi
done

# Get user password
user_password=$(get_confirmed_password "$username")
if [[ $? -ne 0 ]]; then canceled; fi

# Get hostname
hostname=$(whiptail --title "Hostname" --inputbox "Enter a hostname:" 8 40 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then canceled; fi

# Check if virtual machine extensions should be installed
virtual_machine_ext="false"
if [ -n "$virtual_machine" ]; then
        whiptail --title "${virtual_machine} Extensions" --yesno "Install ${virtual_machine} extensions for seamless screen and shared clipboard?" 8 45 3>&1 1>&2 2>&3
        if [[ $? -ne 0 ]]; then canceled; fi
        if [[ $? -eq 0 ]]; then
                virtual_machine_ext="true"
        fi
fi

# Configuration file creation
config_file="archgen.cfg"

# Confirm values or exit
clear
echo """
SELECTED_DRIVE: $selected_drive
ENCRYPTION_ENABLED: $encryption_enabled
USERNAME: $username
HOSTNAME: $hostname
VIRTUAL_MACHINE: $virtual_machine
VIRTUAL_MACHINE_EXT: $virtual_machine_ext

ENTER TO CONFIRM THESE VALUES AND WRITE CONFIGURATION FILE
CTRL-C TO CANCEL FILE GENERATION
"""
read -r

# Write ASCII art to configuration file
cat >"$config_file" <<'EOL'
#!/bin/bash
#     ___                    _        ___
#    /   \     _ _    __    | |_     / __|    ___    _ _
#    | - |    | '_|  / _|   | ' \   | (_ |   / -_)  | ' \
#    |_|_|   _|_|_   \__|_  |_||_|   \___|   \___|  |_||_|
#  _|"""""|_|"""""|_|"""""|_|"""""|_|"""""|_|"""""|_|"""""|
#  "`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'

EOL

# Append configuration details to the file
cat >>"$config_file" <<EOL
SELECTED_DRIVE="$selected_drive"
ENCRYPTION_ENABLED="$encryption_enabled"
ENCRYPTION_PASSWORD="$encryption_password"
ROOT_PASSWORD="$root_password"
USERNAME="$username"
USER_PASSWORD="$user_password"
HOSTNAME="$hostname"
VIRTUAL_MACHINE="$virtual_machine"
VIRTUAL_MACHINE_EXT="$virtual_machine_ext"
EOL

# Cleanup trailing whitespace
sed -i 's/[[:space:]]*$//' "$config_file"

# Notify the user of successful completion
whiptail --title "ArchGen" --msgbox "Configuration file '$config_file' created successfully." 8 40 3>&1 1>&2 2>&3

# Clear the screen
clear