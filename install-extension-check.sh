#!/bin/bash

# --- Interactive Setup ---
echo "--- Multi-Property Asterisk Extension Monitor ---"
read -p "How many properties are hosted on this server? " prop_count

# Arrays to hold generated configuration code
PROP_NAMES=()
PROP_PATTERNS=()
PROP_DISPLAYS=()

for ((p=1; p<=prop_count; p++)); do
    echo ""
    echo "--- Configuring Property $p of $prop_count ---"
    read -p "Enter Property Name: " p_name
    read -p "How many extensions for $p_name? " ext_count
    
    p_exts=()
    for ((i=1; i<=ext_count; i++)); do
        read -p "  Enter extension $i: " ext
        p_exts+=("$ext")
    done

    # Prepare regex pattern and clean display list
    pattern="($(IFS="|"; echo "${p_exts[*]}"))"
    display="${p_exts[*]}"

    PROP_NAMES+=("$p_name")
    PROP_PATTERNS+=("$pattern")
    PROP_DISPLAYS+=("$display")
done

INSTALL_PATH="/usr/local/bin/extension_monitor.sh"
EMAIL="monitor@famecomputers.com"

# --- Create the Single Monitoring Script ---
cat << 'EOF' > $INSTALL_PATH
#!/bin/bash

EMAIL="monitor@famecomputers.com"
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me)
if [ -z "$PUBLIC_IP" ]; then PUBLIC_IP="No Internet"; fi

# Fetch Asterisk contact status once to save execution time
RAW_PJSIP=$(/usr/sbin/asterisk -rx 'pjsip show contacts')

# Function to check a single property
check_property() {
    local prop_name="$1"
    local ext_pattern="$2"
    local ext_display="$3"

    # Unique flag file per property
    local clean_id=$(echo "$prop_name" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    local flag_file="/tmp/${clean_id}_is_down.flag"

    # Filter Asterisk output for this property's extensions
    local prop_output=$(echo "$RAW_PJSIP" | grep -E "^\s*Contact:\s*$ext_pattern/")
    local online_count=$(echo "$prop_output" | grep -c 'Avail')

    local subject="MONITOR: $prop_name ($PUBLIC_IP)"

    if [ "$online_count" -eq 0 ]; then
        # --- PROPERTY IS DOWN ---
        if [ ! -f "$flag_file" ]; then
            touch "$flag_file"
            (
                echo "STATUS: CRITICAL OUTAGE"
                echo "------------------------------------------------"
                echo "Property Name : $prop_name"
                echo "Public IP     : $PUBLIC_IP"
                echo "Extensions    : $ext_display"
                echo "Check Time    : $(date)"
                echo "------------------------------------------------"
                echo -e "\nAsterisk Status Output:\n$prop_output"
            ) | mail -s "$subject" "$EMAIL"
        fi
    else
        # --- PROPERTY IS UP ---
        if [ -f "$flag_file" ]; then
            rm -f "$flag_file"
            (
                echo "STATUS: RECOVERY DETECTED"
                echo "------------------------------------------------"
                echo "Property Name : $prop_name"
                echo "Public IP     : $PUBLIC_IP"
                echo "Status        : All monitored extensions are BACK ONLINE"
                echo "Recovery Time : $(date)"
                echo "------------------------------------------------"
            ) | mail -s "$subject" "$EMAIL"
        fi
    fi
}

EOF

# Append the property loop definitions into the generated script
for ((idx=0; idx<prop_count; idx++)); do
    cat << EOF >> $INSTALL_PATH
check_property "${PROP_NAMES[$idx]}" "${PROP_PATTERNS[$idx]}" "${PROP_DISPLAYS[$idx]}"
EOF
done

# Permissions and Cron
chmod +x $INSTALL_PATH
(crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "*/3 * * * * $INSTALL_PATH > /dev/null 2>&1") | crontab -

echo "-------------------------------------------------------"
echo "Success! Configured $prop_count property check(s) in $INSTALL_PATH."
