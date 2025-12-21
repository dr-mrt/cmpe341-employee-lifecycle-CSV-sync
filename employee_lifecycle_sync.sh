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

initialize_workspace

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
    echo "Changes detected" >> "$LOG_FILE"
}

sort_data
detect_changes

awk -F',' '$5 == "terminated" {print}' ./tmp/current.csv > ./tmp/terminated.csv

ADDED_COUNT=$(wc -l < "$ADDED_USERS_LIST")
REMOVED_COUNT=$(wc -l < "$REMOVED_USERS_LIST")
TERMINATED_COUNT=$(wc -l < "$TERMINATED_USERS_LIST")

echo "Added: $ADDED_COUNT | Removed: $REMOVED_COUNT | Terminated: $TERMINATED_COUNT" >> "$LOG_FILE"

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

while IFS=',' read -r emp_id username name department status
do
    if [ "$status" = "active" ]; then
        onboard_user "$username" "$department"
    fi
done < "$ADDED_USERS_LIST"

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

while IFS=',' read -r emp_id username name department status
do
    offboard_user "$username" "removed"
done < ./tmp/removed.csv

while IFS=',' read -r emp_id username name department status
do
    offboard_user "$username" "terminated"
done < ./tmp/terminated.csv

echo "Manager Employee Update" > "$REPORT_FILE"
echo "Timestamp: $DATE" >> "$REPORT_FILE"
echo "Mode: LIVE" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "Summary" >> "$REPORT_FILE"
echo "Added employees (active): $ADDED_COUNT" >> "$REPORT_FILE"
echo "Removed employees: $REMOVED_COUNT" >> "$REPORT_FILE"
echo "Offboarded by status: $TERMINATED_COUNT" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "Added (username, department)" >> "$REPORT_FILE"
if [ "$ADDED_COUNT" -gt 0 ]; then
    awk -F',' '{print $2 ", " $4}' "$ADDED_USERS_LIST" >> "$REPORT_FILE"
else
    echo "None" >> "$REPORT_FILE"
fi
echo "" >> "$REPORT_FILE"

echo "Removed (username, department)" >> "$REPORT_FILE"
if [ "$REMOVED_COUNT" -gt 0 ]; then
    awk -F',' '{print $2 ", " $4}' "$REMOVED_USERS_LIST" >> "$REPORT_FILE"
else
    echo "None" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"

cp ./tmp/current.csv output/last_employees.csv
echo "Snapshot updated." >> "$LOG_FILE"

rm -rf ./tmp
echo "Temporary files cleaned up." >> "$LOG_FILE"
echo "Lifecycle sync completed." >> "$LOG_FILE"

MAIL_TO="iremkeser@stu.khas.edu.tr"

mail -s "Manager Employee Lifecycle Report - $DATE" "$MAIL_TO" < "$REPORT_FILE"

echo "Manager report emailed to $MAIL_TO" >> "$LOG_FILE"