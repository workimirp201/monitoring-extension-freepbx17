#!/bin/bash

# --- Interactive Setup ---
echo "--- Asterisk Monitor with Recovery Alerts ---"
read -p "Enter Property Name: " property_name
read -p "How many extensions? " ext_count
extensions=()
for ((i=1; i<=ext_count; i++)); do
    read -p "Enter extension $i: " ext
    extensions+=("$ext")
done

EXT_PATTERN="($(IFS="|"; echo "${extensions[*]}"))"
EXT_LIST_DISPLAY="${extensions[*]}"
INSTALL_PATH="/usr/local/bin/extension_monitor.sh"
# This file tracks if we were offline
FLAG_FILE="/tmp/$(echo $property_name | tr -d ' ' )_is_down"
EMAIL="monitor@famecomputers.com"

# --- Create the Monitoring Script ---
cat << EOF > $INSTALL_PATH
#!/bin/bash

PROPERTY_NAME="$property_name"
PUBLIC_IP=\$(curl -s --max-time 5 ifconfig.me)
# Fallback if curl fails due to DNS/Internet issues
if [ -z "\$PUBLIC_IP" ]; then PUBLIC_IP="Unknown/No Internet"; fi

# 1. Capture Status
RAW_OUTPUT=\$(/usr/sbin/asterisk -rx 'pjsip show contacts' | grep -E "^\s*Contact:\s*$EXT_PATTERN/")
ONLINE_COUNT=\$(echo "\$RAW_OUTPUT" | grep -c 'Avail')

# 2. Logic Check
if [ "\$ONLINE_COUNT" -eq 0 ]; then
    # --- SYSTEM IS DOWN ---
    if [ ! -f "$FLAG_FILE" ]; then
        # First time detecting outage
        touch "$FLAG_FILE"
        (
            echo "CRITICAL: All extensions at \$PROPERTY_NAME are OFFLINE."
            echo "IP: \$PUBLIC_IP"
            echo "Time: \$(date)"
            echo -e "\nAsterisk Output:\n\$RAW_OUTPUT"
        ) | mail -s "DOWN: \$PROPERTY_NAME (\$PUBLIC_IP)" "$EMAIL"
    fi
else
    # --- SYSTEM IS UP ---
    if [ -f "$FLAG_FILE" ]; then
        # System was down, but now it's back!
        rm "$FLAG_FILE"
        (
            echo "RECOVERY: Extensions at \$PROPERTY_NAME are back ONLINE."
            echo "IP: \$PUBLIC_IP"
            echo "Recovery Time: \$(date)"
        ) | mail -s "FIXED: \$PROPERTY_NAME (\$PUBLIC_IP)" "$EMAIL"
    fi
fi
EOF

chmod +x $INSTALL_PATH
(crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "*/7 * * * * $INSTALL_PATH > /dev/null 2>&1") | crontab -

echo "Done! You will now receive DOWN alerts and RECOVERY alerts."
