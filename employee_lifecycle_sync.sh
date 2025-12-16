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
