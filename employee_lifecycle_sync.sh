#!/bin/bash

#CONFIGURATION
INPUT_FILE="employees.csv"
LOG_DIR="./output/logs"
ARCHIVE_DIR="./output/archives"
REPORT_DIR="./output/reports"
#snapshot tracks the state of employees from last run
SNAPSHOT_FILE="./output/last_employees.csv"

DATE=$(date "+%Y-%m-%d_%H-%M-%S")
LOG_FILE="./output/logs/lifecycle_sync.log"
REPORT_FILE="./output/reports/manager_update_$DATE.txt"

#temporary files for data processing 
SORTED_CURRENT="./tmp/current.csv"
SORTED_LAST="./tmp/previous.csv"
ADDED_USERS_LIST="./tmp/added.csv"
REMOVED_USERS_LIST="./tmp/removed.csv"
TERMINATED_USERS_LIST="./tmp/terminated.csv"

#email recipient address
ADMIN_EMAIL="durumert@stu.khas.edu.tr"

#SMTP configuration 
SMTP_ENABLED="true"
SMTP_SERVER="smtps://smtp.gmail.com:465"
SMTP_USER="durumert11@gmail.com"
SMTP_PASS="lidmlmrhvrwrpluu"

#FUNCTIONS

#creates or checks the existence of required directories, including the first-run case
function initialize_workspace() {
    mkdir -p "$LOG_DIR"
    echo "[$DATE] Lifecycle sync started" >> "$LOG_FILE"

    #checks that the input employees.csv exists
    if [ ! -f $INPUT_FILE ]; then
        echo "$INPUT_FILE not found. Exiting." | tee -a "$LOG_FILE"
        exit 1
    fi

    mkdir -p "$ARCHIVE_DIR" "$REPORT_DIR" "./tmp"

    #creates a snapshot (last_employees.csv) in first-run case
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        echo "First run detected. Initializing snapshot." | tee -a "$LOG_FILE"
        touch "$SNAPSHOT_FILE"
        echo "Initial snapshot saved. No changes processed." | tee -a "$LOG_FILE"
    fi
}

#prepares the input .csv for the comm command since it requires sorted input
function sort_data() {
    #skips header row in the csv file, sorts into temp current.csv
    tail -n +2 "$INPUT_FILE" | sort > "$SORTED_CURRENT"
    sort "$SNAPSHOT_FILE" > "$SORTED_LAST"
}

#compares the current file with last snapshot to find added or removed users 
function detect_changes() {
    #shows lines that exist in current (second file), but not in previous (first file) -> added
    comm -13 "$SORTED_LAST" "$SORTED_CURRENT" > "$ADDED_USERS_LIST"
    #shows lines that exist in previous (first file), but not in current (second file) -> removed
    comm -23 "$SORTED_LAST" "$SORTED_CURRENT" > "$REMOVED_USERS_LIST"
    #finds anyone with status "terminated" and adds to terminated.csv
    awk -F',' '$5 == "terminated" {print}' "$SORTED_CURRENT" > "$TERMINATED_USERS_LIST"

    echo "Changes detected" >> "$LOG_FILE"
}

#creates system groups and users
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

#archives users home directory and locks their account
function offboard_user() {
    local username="$1"
    local reason="$2"

    local home_dir
    home_dir=$(getent passwd "$username" | cut -d: -f6)

    #archives home directory if it exists
    if [ -n "$home_dir" ] && [ -d "$home_dir" ]; then
        local archive_name="${ARCHIVE_DIR}/${username}_${reason}_${DATE}.tar.gz"

        if [ ! -f "$archive_name" ]; then
            tar -czf "$archive_name" "$home_dir" 2>/dev/null
            echo "Archived home for $username to $archive_name" >> "$LOG_FILE"
        fi
    else 
        echo "Offboard skipped (home dir not found): $username" >> "$LOG_FILE"
    fi

    #locks the user account
    usermod -L "$username"
    echo "User locked: $username" >> "$LOG_FILE"
}

#iterates through added.csv and onboards active users
function process_added() {
    while IFS=',' read -r emp_id username name department status; do
    if [ "$status" = "active" ]; then
        onboard_user "$username" "$department"
    fi
    done < "$ADDED_USERS_LIST"
}

#locks users if they are removed from the file entirely
function process_removed() {
    while IFS=',' read -r emp_id username name department status; do
        #checks if the user actually exists on the system  
        if id "$username" &>/dev/null; then
            offboard_user "$username" "removed"
        fi
    done < "$REMOVED_USERS_LIST"
}

#locks users with status "terminated"
function process_terminated() {
    while IFS=',' read -r emp_id username name department status; do
        if id "$username" &>/dev/null; then
            offboard_user "$username" "terminated"
        fi
    done < "$TERMINATED_USERS_LIST"
}

#calculates the number of added, removed and terminated users and writes a text report
function generate_report() {
    #counts lines for each category
    local added_count=$(grep ",active" "$ADDED_USERS_LIST" | wc -l)
    local removed_count=$(wc -l < "$REMOVED_USERS_LIST")
    local terminated_count=$(wc -l < "$TERMINATED_USERS_LIST")

    #written portion of the report
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

        echo "Terminated processed (username, department):"
        if [ "$terminated_count" -gt 0 ]; then
            awk -F',' '{print $2 ", " $4}' "$TERMINATED_USERS_LIST"
        else
            echo "None"
        fi
        echo ""

        echo "Artifacts:"
        echo "Archives folder: $ARCHIVE_DIR" 
        echo "Snapshot file: $SNAPSHOT_FILE"
        echo "Log file: $LOG_FILE"

        #add the information to the log file also 
        echo "Added: $added_count | Removed: $removed_count | Terminated: $terminated_count" >> "$LOG_FILE"
    } > "$REPORT_FILE"
}

#updates snapshot for the next run and removes temporary files
function cleanup() {
    cp "$SORTED_CURRENT" "$SNAPSHOT_FILE"
    echo "Snapshot updated." >> "$LOG_FILE"
    rm -rf ./tmp
    echo "Temporary files cleaned up." >> "$LOG_FILE"
    echo "Lifecycle sync completed." >> "$LOG_FILE"
}

#sends generated report via SMTP if enabled, or through mailutils if not enabled
function mail_report() {
    local report_path=$1 
    local subject="Manager Employee Lifecycle Report"

    #Gmail SMTP using curl
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
    #if SMTP is not enabled, use mailutils
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

#MAIN EXECUTION
function main() {
    initialize_workspace
    sort_data
    detect_changes
    process_added
    process_removed
    process_terminated
    generate_report
    cleanup
    mail_report "$REPORT_FILE"
}

main
exit 0 