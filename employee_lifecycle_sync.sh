#!/bin/bash

INPUT_FILE="employees.csv"
LOG_DIR="./output/logs"
ARCHIVE_DIR="./output/archives"
REPORT_DIR="./output/reports"
SNAPSHOT_FILE="./output/last_employees.csv"

DATE=$(date "+%Y-%m-%d_%H-%M-%S")
LOG_FILE="./output/logs/lifecycle_sync.log"
REPORT_FILE="./output/reports/manager_update_$DATE.txt"

SORTED_CURRENT="./tmp/current.csv"
SORTED_LAST="./tmp/previous.csv"
ADDED_USERS_LIST="./tmp/added.csv"
REMOVED_USERS_LIST="./tmp/removed.csv"
TERMINATED_USERS_LIST="./tmp/terminated.csv"

ADMIN_EMAIL="uzunzsude@gmail.com"

SMTP_ENABLED="true"
SMTP_SERVER="smtps://smtp.gmail.com:465"
SMTP_USER="durumert11@gmail.com"
SMTP_PASS="lidmlmrhvrwrpluu" 

mkdir -p "$LOG_DIR"
echo "[$DATE] Lifecycle sync started" >> "$LOG_FILE"

function initialize_workspace() {
    mkdir -p "$LOG_DIR" "$ARCHIVE_DIR" "$REPORT_DIR" "./tmp"
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        echo "First run detected. Initializing snapshot." | tee -a "$LOG_FILE"
        touch "$SNAPSHOT_FILE"
        echo "Initial snapshot saved. No changes processed." | tee -a "$LOG_FILE"
    fi
}

if [ ! -f employees.csv ]; then
    echo "employees.csv not found. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

function sort_data() {
    tail -n +2 "$INPUT_FILE" | sort > "$SORTED_CURRENT"
    sort "$SNAPSHOT_FILE" > "$SORTED_LAST"
}

function detect_changes() {
    comm -13 "$SORTED_LAST" "$SORTED_CURRENT" > "$ADDED_USERS_LIST"
    comm -23 "$SORTED_LAST" "$SORTED_CURRENT" > "$REMOVED_USERS_LIST"

    awk -F',' '$5 == "terminated" {print}' "$SORTED_CURRENT" > "$TERMINATED_USERS_LIST"

    echo "Changes detected" >> "$LOG_FILE"
}

function onboard_user() {
    local username="$1"
    local department="$2"

    #adds missing department group
    if ! getent group "$department" > /dev/null; then
        groupadd "$department"
        echo "Group created: $department" >> "$LOG_FILE"
    fi

    #creates missing user or adds existing user to department group
    if ! id "$username" &>/dev/null; then
        useradd -m -G "$department" -s /bin/bash "$username"
        echo "User created: $username and added to department: $department" >> "$LOG_FILE"
    else
        usermod -aG "$department" "$username"
        echo "User $username added to group $department" >> "$LOG_FILE"
    fi
}

function offboard_user() {
    local username="$1"
    local reason="$2"

    local home_dir
    home_dir=$(getent passwd "$username" | cut -d: -f6)

    if [ -n "$home_dir" ] && [ -d "$home_dir" ]; then
        local archive_name="${ARCHIVE_DIR}/${username}_${reason}_${DATE}.tar.gz"

        if [ ! -f "$archive_name" ]; then
            tar -czf "$archive_name" "$home_dir" 2>/dev/null
            echo "Archived home for $username to $archive_name" >> "$LOG_FILE"
        fi
    else 
        echo "Offboard skipped (home dir not found): $username" >> "$LOG_FILE"
    fi

    usermod -L "$username"
    echo "User locked: $username" >> "$LOG_FILE"
}

function process_added() {
    while IFS=',' read -r emp_id username name department status; do
    username=$(echo "$username" | tr -d '\r' | xargs)
    department=$(echo "$department" | xargs)
    status=$(echo "$status" | tr -d '\r' | xargs)

    if [ "$status" = "active" ]; then
        onboard_user "$username" "$department"
    fi
    done < "$ADDED_USERS_LIST"
}

function process_removed() {
    while IFS=',' read -r emp_id username name department status; do
        username=$(echo "$username" | tr -d '\r' | xargs)
        
        if id "$username" &>/dev/null; then
            offboard_user "$username" "removed"
        fi
    done < "$REMOVED_USERS_LIST"
}

function process_terminated() {
    while IFS=',' read -r emp_id username name department status; do
        username=$(echo "$username" | tr -d '\r' | xargs)
        
        if id "$username" &>/dev/null; then
            offboard_user "$username" "terminated"
        fi
    done < "$TERMINATED_USERS_LIST"
}

function generate_report() {
    local added_count=$(wc -l < "$ADDED_USERS_LIST")
    local removed_count=$(wc -l < "$REMOVED_USERS_LIST")
    local terminated_count=$(wc -l < "$TERMINATED_USERS_LIST")

    {
        echo "MANAGER UPDATE REPORT"
        echo "Timestamp: $DATE"
        echo "Mode: LIVE"
        echo ""
        echo "Summary:"
        echo "Added employees (active): $added_count"
        echo "Removed employees: $removed_count"
        echo "Offboarded by status: $terminated_count"
        echo ""

        echo "Added (username, department)"
        if [ "$added_count" -gt 0 ]; then
            awk -F',' '{print $2 ", " $4}' "$ADDED_USERS_LIST"
        else
            echo "None"
        fi
        echo ""

        echo "Removed (username, department):"
        if [ "$removed_count" -gt 0 ]; then
            awk -F',' '{print $2 ", " $4}' "$REMOVED_USERS_LIST"
        else
            echo "None"
        fi
        echo ""

        echo "Added: $added_count | Removed: $removed_count | Terminated: $terminated_count" >> "$LOG_FILE"
    } > "$REPORT_FILE"
}

function cleanup() {
    cp "$SORTED_CURRENT" "$SNAPSHOT_FILE"
    echo "Snapshot updated." >> "$LOG_FILE"
    rm -rf ./tmp
    echo "Temporary files cleaned up." >> "$LOG_FILE"
    echo "Lifecycle sync completed." >> "$LOG_FILE"
}

function mail_report() {
    local report_path=$1 
    local subject="Manager Employee Lifecycle Report"

    if [ "$SMTP_ENABLED" == "true" ]; then
        curl --url "$SMTP_SERVER" \
             --ssl-reqd \
             --mail-from "$SMTP_USER" \
             --mail-rcpt "$ADMIN_EMAIL" \
             --user "$SMTP_USER:$SMTP_PASS" \
             -T <(echo -e "From: $SMTP_USER\nTo: $ADMIN_EMAIL\nSubject: $subject\n\n$(cat $report_path)") \
             --silent
        if [ $? -eq 0 ]; then
            echo "  [SUCCESS] Email sent successfully via SMTP."
        else
            echo "  [ERROR] SMTP send failed. Please check credentials."
        fi
    else
        echo "  [STANDARD] Sending email via local mail command..."
        if command -v mail &> /dev/null; then
            mail -s "$subject" "$ADMIN_EMAIL" < "$report_path"
            echo "  [SUCCESS] Email passed to local mail system."
        else
            echo "  [ERROR] 'mail' command not found. Install mailutils or enable SMTP bonus."
        fi
    fi

    echo "Manager report emailed to $ADMIN_EMAIL" >> "$LOG_FILE"
}

initialize_workspace
sort_data
detect_changes
process_added
process_removed
process_terminated
generate_report
cleanup
mail_report "$REPORT_FILE"

exit 0 
