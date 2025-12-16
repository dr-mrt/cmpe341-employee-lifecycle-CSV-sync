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

tail -n +2 employees.csv | sort > /tmp/current.csv
sort output/last_employees.csv > /tmp/previous.csv

comm -13 /tmp/previous.csv /tmp/current.csv > /tmp/added.csv
comm -23 /tmp/previous.csv /tmp/current.csv > /tmp/removed.csv

awk -F',' '$5 == "terminated" {print}' /tmp/current.csv > /tmp/terminated.csv

ADDED_COUNT=$(wc -l < /tmp/added.csv)
REMOVED_COUNT=$(wc -l < /tmp/removed.csv)
TERMINATED_COUNT=$(wc -l < /tmp/terminated.csv)

echo "Added: $ADDED_COUNT | Removed: $REMOVED_COUNT | Terminated: $TERMINATED_COUNT" >> "$LOG_FILE"
