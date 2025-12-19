#!/bin/bash

DATE=$(date "+%Y-%m-%d_%H-%M-%S")
LOG_FILE="./output/logs/lifecycle_sync.log"
REPORT_FILE="./output/reports/manager_update_$DATE.txt"

echo "[$DATE] Lifecycle sync started" >> "$LOG_FILE"

mkdir -p output/logs output/reports output/archives

if [ ! -f employees.csv ]; then
    echo "employees.csv not found. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

if [ ! -s output/last_employees.csv ]; then
    echo "First run detected. Initializing snapshot." | tee -a "$LOG_FILE"
    tail -n +2 employees.csv | sort > output/last_employees.csv
    echo "Initial snapshot saved. No changes processed." | tee -a "$LOG_FILE"
    exit 0
fi

mkdir -p ./tmp

tail -n +2 employees.csv | sort > ./tmp/current.csv
sort output/last_employees.csv > ./tmp/previous.csv

comm -13 ./tmp/previous.csv ./tmp/current.csv > ./tmp/added.csv
comm -23 ./tmp/previous.csv ./tmp/current.csv > ./tmp/removed.csv

awk -F',' '$5 == "terminated" {print}' ./tmp/current.csv > ./tmp/terminated.csv

ADDED_COUNT=$(wc -l < ./tmp/added.csv)
REMOVED_COUNT=$(wc -l < ./tmp/removed.csv)
TERMINATED_COUNT=$(wc -l < ./tmp/terminated.csv)

echo "Added: $ADDED_COUNT | Removed: $REMOVED_COUNT | Terminated: $TERMINATED_COUNT" >> "$LOG_FILE"

onboard_user() {
    local username="$1"
    local department="$2"


    if ! getent group "$department" > /dev/null; then
        groupadd "$department"
        echo "Group created: $department" >> "$LOG_FILE"
    fi

    if ! id "$username" > /dev/null 2>&1; then
        useradd -m "$username"
        echo "User created: $username" >> "$LOG_FILE"
    fi

    usermod -aG "$department" "$username"
    echo "User $username added to group $department" >> "$LOG_FILE"
}

while IFS=',' read -r emp_id username name department status
do
    if [ "$status" = "active" ]; then
        onboard_user "$username" "$department"
    fi
done < ./tmp/added.csv

offboard_user() {
    local username="$1"

    if ! id "$username" > /dev/null 2>&1; then
        echo "Offboard skipped (user not found): $username" >> "$LOG_FILE"
        return
    fi

    home_dir=$(getent passwd "$username" | cut -d: -f6)

    if [ -d "$home_dir" ]; then
        tar -czf "output/archives/${username}_${DATE}.tar.gz" "$home_dir"
        echo "Archived home for $username" >> "$LOG_FILE"
    fi

    usermod -L "$username"
    echo "User locked: $username" >> "$LOG_FILE"
}

while IFS=',' read -r emp_id username name department status
do
    offboard_user "$username"
done < ./tmp/removed.csv

while IFS=',' read -r emp_id username name department status
do
    offboard_user "$username"
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
    awk -F',' '{print $2 ", " $4}' ./tmp/added.csv >> "$REPORT_FILE"
else
    echo "None" >> "$REPORT_FILE"
fi
echo "" >> "$REPORT_FILE"

echo "Removed (username, department)" >> "$REPORT_FILE"
if [ "$REMOVED_COUNT" -gt 0 ]; then
    awk -F',' '{print $2 ", " $4}' ./tmp/removed.csv >> "$REPORT_FILE"
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
