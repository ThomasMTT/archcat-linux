#!/bin/bash
#       _             _      ____      _      ____ _     ___
#      / \   _ __ ___| |__  / ___|__ _| |_   / ___| |   |_ _|
#     / _ \ | '__/ __| '_ \| |   / _` | __| | |   | |    | |
#    / ___ \| | | (__| | | | |__| (_| | |_  | |___| |___ | |
#   /_/   \_\_|  \___|_| |_|\____\__,_|\__|  \____|_____|___|
#
# Downloads, installs and runs the archcat cli tool from https://github.com/ThomasMTT/Archcat-cli

# Define ANSI escape codes for color
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
        echo -e " [$RED*$RESET] This script must be run as root. Use 'sudo archcat'"
        exit 1
fi

FILE_URL="https://github.com/ThomasMTT/Archcat-cli/raw/main/archcat.sh"
DESTINATION="/usr/local/bin/archcat"
TMP_FILE="/tmp/archcat-cli-tmp"

# Download the file
echo -e " [$YELLOW*$RESET] Downloading latest version of archcat..."
curl -sSL -o "$TMP_FILE" "$FILE_URL"

# Check if the download was successful
if [[ $? -ne 0 ]]; then
        echo -e " [$RED*$RESET] Error downloading the archcat"
        exit 1
fi

# Check if file is a script (to avoid downloading the html as archcat)
if [[ $(head -n1 /usr/local/bin/archcat) != "#!/bin/bash" ]]; then
        echo -e " [$RED*$RESET] Error: File must be a bash script" 
        exit 1
fi

# Move the downloaded file to /usr/local/bin
echo -e " [$YELLOW*$RESET] Moving file to $DESTINATION..."
mv "$TMP_FILE" "$DESTINATION"

# Check if the move was successful
if [[ $? -ne 0 ]]; then
        rm "$TMP_FILE" 2>/dev/null
        echo -e " [$RED*$RESET] Error moving the file to /usr/local/bin. Please check permissions."
        exit 1
fi

# Ensure the file is executable
chmod +x "$DESTINATION"

echo -e " [$GREEN*$RESET] Archcat Succesfully installed.\n [$GREEN*$RESET] Running Archcat"

# Run the command
/usr/local/bin/archcat
