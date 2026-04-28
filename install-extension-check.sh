#!/bin/bash

# --- Interactive Setup ---
echo "--- Asterisk Extension Monitor ---"
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
FLAG_FILE="/tmp/$(echo $property_name | tr -d ' ' )_is_down"
EMAIL="monitor@famecomputers.com"

# --- Create the Monitoring Script ---
cat << EOF > $INSTALL_PATH
#!/bin/bash

PROPERTY_NAME="$property_name"
MONITORED_EXTS="$EXT_LIST_DISPLAY"
PUBLIC_IP=\$(curl -s --max-time 5 ifconfig.me)
if [ -z "\$PUBLIC_IP" ]; then PUBLIC_IP="No Internet"; fi

# 1. Capture Status
RAW_OUTPUT=\$(/usr/sbin/asterisk -rx 'pjsip show contacts' | grep -E "^\s*Contact:\s*$EXT_PATTERN/")
ONLINE_COUNT=\$(echo "\$RAW_OUTPUT" | grep -c 'Avail')

# 2. Logic Check
# NOTE: We keep the SUBJECT the same for both to force threading in Gmail/Outlook
SUBJECT="MONITOR: \$PROPERTY_NAME (\$PUBLIC_IP)"

if [ "\$ONLINE_COUNT" -eq 0 ]; then
    if [ ! -f "$FLAG_FILE" ]; then
        touch "$FLAG_FILE"
        (
            echo "STATUS: CRITICAL OUTAGE"
            echo "------------------------------------------------"
            echo "Property Name : \$PROPERTY_NAME"
            echo "Public IP     : \$PUBLIC_IP"
            echo "Extensions    : \$MONITORED_EXTS"
            echo "Check Time    : \$(date)"
            echo "------------------------------------------------"
            echo -e "\nAsterisk Status Output:\n\$RAW_OUTPUT"
        ) | mail -s "\$SUBJECT" "$EMAIL"
    fi
else
    if [ -f "$FLAG_FILE" ]; then
        rm "$FLAG_FILE"
        (
            echo "STATUS: RECOVERY DETECTED"
            echo "------------------------------------------------"
            echo "Property Name : \$PROPERTY_NAME"
            echo "Public IP     : \$PUBLIC_IP"
            echo "Status        : All extensions are BACK ONLINE"
            echo "Recovery Time : \$(date)"
            echo "------------------------------------------------"
        ) | mail -s "\$SUBJECT" "$EMAIL"
    fi
fi
EOF

chmod +x $INSTALL_PATH
(crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "*/3 * * * * $INSTALL_PATH > /dev/null 2>&1") | crontab -

echo "-------------------------------------------------------"
echo "Success! Detailed monitoring active for $property_name."
echo "You will receive structured DOWN and RECOVERY emails."
