#!/bin/bash

# --- Interactive Setup ---
echo "--- Asterisk Monitor with Email Threading ---"
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
# Flag file will now store the Message-ID
FLAG_FILE="/tmp/$(echo $property_name | tr -d ' ' )_msgid.txt"
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
if [ "\$ONLINE_COUNT" -eq 0 ]; then
    # --- SYSTEM IS DOWN ---
    if [ ! -f "$FLAG_FILE" ]; then
        # Generate a unique Message-ID for this thread
        MSG_ID="<internal-\$(date +%s)@\$HOSTNAME>"
        echo "\$MSG_ID" > "$FLAG_FILE"

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
        ) | mail -a "Message-ID: \$MSG_ID" -s "DOWN: \$PROPERTY_NAME (\$PUBLIC_IP)" "$EMAIL"
    fi
else
    # --- SYSTEM IS UP ---
    if [ -f "$FLAG_FILE" ]; then
        OLD_MSG_ID=\$(cat "$FLAG_FILE")
        rm "$FLAG_FILE"

        (
            echo "RECOVERY DETECTED"
            echo "------------------------------------------------"
            echo "Property Name : \$PROPERTY_NAME"
            echo "Public IP     : \$PUBLIC_IP"
            echo "Status        : All monitored extensions are BACK ONLINE"
            echo "Recovery Time : \$(date)"
            echo "------------------------------------------------"
        ) | mail -a "In-Reply-To: \$OLD_MSG_ID" -a "References: \$OLD_MSG_ID" -s "Re: DOWN: \$PROPERTY_NAME (\$PUBLIC_IP)" "$EMAIL"
    fi
fi
EOF

chmod +x $INSTALL_PATH
(crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "*/3 * * * * $INSTALL_PATH > /dev/null 2>&1") | crontab -

echo "-------------------------------------------------------"
echo "Success! Recovery emails will now show as a reply to the outage email."
