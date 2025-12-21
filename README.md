# Employee Lifecycle Management Script

## Project Summary
This is an automation script that bridges HR systems with IT infrastructure by automatically managing Linux user accounts based on employee data from CSV files. It implements a state synchronization engine that detects employee changes (hires, departures, terminations) and performs corresponding system operations.

* **New Hires** (Active status): system accounts are created and added to groups.
* **Terminated Employees** (Terminated status): are locked out and their home directories are archived.
* **Removed Records** (Deleted from CSV): are offboarded in the same way as terminated employees.
* **Reporting**: Managers receive an automated email report summarizing all changes.

* Submitted by: Serpil Duru Mert, İrem Keser, Ahu Tarasi

## CSV Formatting
The script expects a strictly formatted input file named `employees.csv` in the root directory.

**Format:**
`employee_id,username,name_surname,department,status`

**Example:**
```csv
10001,ayse.aydin,Ayşe Aydın,data,active
10002,mehmet.kaya,Mehmet Kaya,dev,active
10003,elif.demir,Elif Demir,hr,active
```

* **Columns:** Must be exactly 5 columns separated by commas
* **Headers:** The first row is treated as a header and skipped
* **Status:** `active`: Creates the user and adds them to the department group.
    * `terminated`: Locks the user account and archives their home directory.

## Configuration (Email)
The script is configured to send reports via **Gmail SMTP** using `curl`. The variables at the top of `employees_lifecycle_sync.sh` should be configured before running.

```bash
ADMIN_EMAIL="manager@example.com"    # Who receives the report
SMTP_ENABLED="true"
SMTP_USER="your_email@gmail.com"
SMTP_PASS="abcdefghijklmnop"         # Google app password
```

> **Note:** If `SMTP_ENABLED` is set to `"false"`, the script will attempt to use the local `mail` command instead.

## How to Run

### 1. Prerequisites
* Linux environment
* Root privileges (`sudo`) are required to add/remove users
* `curl` is used for sending SMTP emails

### 2. Execution Steps
1.  `employees.csv` should be in the same folder as the script
2.  ```bash
    chmod +x employee_lifecycle_sync.sh
    ```
3. ```bash
    sudo ./employee_lifecycle_sync.sh
    ```

### 3. Output Locations
* **Logs:** `./output/logs/lifecycle_sync.log` (log files)
* **Archives:** `./output/archives/` (user home directories zipped)
* **Reports:** `./output/reports/` (written reports for managment)
* **Snapshot:** `./output/last_employees.csv` (used to track changes between runs)

## Limitations

1.  **CSV Structure:** The script relies on specific column positions
2.  **Local User Management Only:** This script manages local Linux users
4.  **Google App Password:** If using Gmail, you cannot use your login password, you must enable 2FA and generate a specific **App Password** for the `SMTP_PASS` variable