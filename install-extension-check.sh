#!/bin/bash

# --- Interactive Setup ---
echo "--- Asterisk Extension Monitor Installer ---"

# 1. New Question: Property Name
read -p "Enter the Property Name (e.g., Sonesta NYC): " property_name

# 2. Existing Question: Extensions
read -p "How many extensions do you wish to monitor? " ext_count

extensions=()
for ((i=1; i<=ext_count; i++)); do
    read -p "Enter extension $i: " ext
    extensions+=("$ext")
done

# Prepare logic variables
EXT_PATTERN="($(IFS="|"; echo "${extensions[*]}"))"
EXT_LIST_DISPLAY="${extensions[*]}"
INSTALL_PATH="/usr/local/bin/extension_monitor.sh"
EMAIL="monitor@famecomputers.com"

echo "Creating monitoring script for $property_name..."

# --- Create the Monitoring Script ---
cat << EOF > $INSTALL_PATH
#!/bin/bash

# Configuration
PROPERTY_NAME="$property_name"
MONITORED_EXTS="$EXT_LIST_DISPLAY"
PUBLIC_IP=\$(curl -s ifconfig.me)

# 1. Capture and Filter PJSIP output (Fail-proofed regex)
RAW_OUTPUT=\$(/usr/sbin/asterisk -rx 'pjsip show contacts' | grep -E "^\s*Contact:\s*$EXT_PATTERN/")

# 2. Check for 'Avail' status
ONLINE_COUNT=\$(echo "\$RAW_OUTPUT" | grep -c 'Avail')

# 3. Alert Logic
if [ "\$ONLINE_COUNT" -eq 0 ]; then
    (
        echo "CRITICAL OUTAGE DETECTED"
        echo "------------------------------------------------"
        echo "Property Name : \$PROPERTY_NAME"
        echo "Public IP     : \$PUBLIC_IP"
        echo "Extensions    : \$MONITORED_EXTS"
        echo "Check Time    : \$(date)"
        echo "------------------------------------------------"
        echo -e "\nAsterisk Status Output:\n"
        echo "\$RAW_OUTPUT"
    ) | mail -s "ALERT: All Extensions Offline - \$PROPERTY_NAME (\$PUBLIC_IP)" "$EMAIL"
fi
EOF

# --- Permissions and Cron ---
chmod +x $INSTALL_PATH

# Update Crontab (removes old entries for this script, adds new 7-min entry)
(crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "*/7 * * * * $INSTALL_PATH > /dev/null 2>&1") | crontab -

echo "-------------------------------------------------------"
echo "Success! $property_name is now being monitored."
echo "Public IP detected as: \$(curl -s ifconfig.me)"
echo "-------------------------------------------------------"
