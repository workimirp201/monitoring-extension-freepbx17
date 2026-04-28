#!/bin/bash

# --- Interactive Setup ---
echo "--- Asterisk Extension Monitor Installer ---"
read -p "How many extensions do you wish to monitor? " ext_count

extensions=()
for ((i=1; i<=ext_count; i++)); do
    read -p "Enter extension $i (e.g. 101): " ext
    extensions+=("$ext")
done

# Create a clean regex pattern for grep
# Example: (101|102)
EXT_PATTERN="($(IFS="|"; echo "${extensions[*]}"))"
EXT_LIST_DISPLAY="${extensions[*]}"

INSTALL_PATH="/usr/local/bin/extension_monitor.sh"
EMAIL="monitor@famecomputers.com"

# --- Create the Monitoring Script ---
cat << EOF > $INSTALL_PATH
#!/bin/bash

# Extensions being monitored: $EXT_LIST_DISPLAY

# 1. Capture the PJSIP contacts output
# 2. Filter for lines that start with our extensions
# 3. Check if any of those lines contain 'Avail'
RAW_OUTPUT=\$(/usr/sbin/asterisk -rx 'pjsip show contacts' | grep -E "^\s*Contact:\s*\$EXT_PATTERN/")

# 4. Count how many monitored extensions are 'Avail'
ONLINE_COUNT=\$(echo "\$RAW_OUTPUT" | grep -c 'Avail')

# 5. If ZERO are available, send the alert
if [ "\$ONLINE_COUNT" -eq 0 ]; then
    (
        echo "CRITICAL ALERT: Total Front Desk Outage"
        echo "None of the monitored extensions ($EXT_LIST_DISPLAY) are available."
        echo "Check Time: \$(date)"
        echo -e "\n--- Asterisk Status ---\n"
        echo "\$RAW_OUTPUT"
    ) | mail -s "ALERT: Front Desk Total Outage" "$EMAIL"
fi
EOF

# --- Permissions and Cron ---
chmod +x $INSTALL_PATH

# Update Crontab: Removes old version of this script if exists, adds new one for every 7 mins
(crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "*/7 * * * * $INSTALL_PATH > /dev/null 2>&1") | crontab -

echo "-------------------------------------------------------"
echo "Installation Complete."
echo "Monitoring: $EXT_LIST_DISPLAY"
echo "Cron Job: Scheduled for every 7 minutes."
