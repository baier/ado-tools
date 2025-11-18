# Roadmap

This PowerShell script retrieves **Epics** and **Features** from an Azure DevOps project, resolves their parent–child relationships, and outputs a clean `roadmap.csv` file containing:

* Epic title
* Feature title (or “no features” if none exist)
* Description (HTML removed)
* Status
* Area Path
* Direct link to the work item

The script automatically excludes area paths using your custom filter logic and handles API batching for large datasets.

---

## Features

* Retrieves all **Epics** and **Features** from an Azure DevOps project
* Filters out:

  * Removed items
  * Closed items
  * Area paths defined in `exclude-areapaths.ps1`
* Fetches work items in **batches** to avoid API limits
* Builds a clean relationship map using `System.LinkTypes.Hierarchy`
* Generates `roadmap.csv` sorted by Status → Epic → Feature

---

## Output Format

The generated CSV contains:

| Column                        | Description                        |
| ----------------------------- | ---------------------------------- |
| **Theme**                     | Epic title                         |
| **Measure**                   | Feature title (or `(no features)`) |
| **Description**               | Description (HTML stripped)        |
| **Status**                    | Work item state                    |
| **AreaPath**                  | Work item area path                |
| **Link (Feature)** / **Link** | Direct link to work item           |

Output location:

```
./roadmap.csv
```

---

## Prerequisites

Your environment must provide:

* PowerShell **5+** or **7+**
* Network access to Azure DevOps REST API
* Config-values:

| What                                    | Where                    | Example value        | Description                        |
| --------------------------------------- | ------------------------ | -------------------- | ---------------------------------- |
| Personal access token                   | `.azdo_pat.txt`          | `<guid>`             | Needs read and write permission    |
| Organization and project                | `.azdo_orgproj.txt`      | `your-org`           | First line: organization           |
|                                         |                          | `your-project`       | Second line: project               |
| System area paths to exclude (optional) | `.exclude-areapaths.txt` | `excluded-area-path` | One area path per line             |

---

## How to Run

1. Clone repo
2. Run:

```powershell
.\roadmap.ps1
```

Expected console output:

```
FEATURES FOUND: <number>
EPICS FOUND: <number>
CSV stored to: <path>
```

`roadmap.csv` will appear in the same directory.

---

## Script Overview

### Workflow Summary

1. Load helper scripts
2. Retrieve:

   * Organization
   * Project
   * Authentication headers
3. Fetch all Epic IDs and Feature IDs using WIQL
4. Retrieve work item details in batches
5. Map Epics by ID
6. Link Features to parent Epics
7. Add:

   * Epics with features
   * Epics *without* features
8. Sort results
9. Export to CSV

---

## Customization

### API Version

```powershell
$apiVersion = "7.0"
```

### Fields to Include

```powershell
$featureFields = @("System.Id", "System.Title", ...)
```

### Batch Size

```powershell
-BatchSize 200
```

---

## Troubleshooting

| Issue                        | Cause / Fix                                |
| ---------------------------- | ------------------------------------------ |
| `No Epic/Feature found`      | WIQL filters or area exclusions hide items |
| `401 Unauthorized`           | PAT missing/expired in `GetAuth`           |
| CSV is empty                 | No items matched criteria                  |
| Missing relations            | Features are not linked to Epics           |
| HTML appears in descriptions | Extend the regex stripping rule            |

---

# Create Child Work Items from CSV

This script bulk-creates **child work items** (Features, User Stories, Tasks) under an existing Azure DevOps parent work item, using data from a CSV file.

The script auto-detects the parent type, selects the correct child type, links them correctly, and logs all created items.

---

## Features

* Determines parent work item type automatically (Epic / Feature / User Story / PBI)
* Selects the correct child type:

  * Epic → Feature
  * Feature → User Story
  * User Story → Task
  * Product Backlog Item → Task
* Reads CSV rows as new work items
* Supports Title, Description, Tags
* Supports `-WhatIf` dry-run mode
* Creates a detailed log file of all created work items
* Adds parent-child link using `System.LinkTypes.Hierarchy-Reverse`

---

## CSV Format

The script expects the following headers:

| Column        | Required | Description                      |
| ------------- | -------- | -------------------------------- |
| `Title`       | Yes      | Work item title                  |
| `Description` | No       | Description (HTML allowed)       |
| `Tags`        | No       | Semicolon-separated list of tags |

Example:

```csv
Title,Description,Tags
Login page,"Implement login form","frontend;login"
Registration,"Create registration flow","frontend;registration"
```

---

## Parameters

| Parameter    | Required | Description                                 |
| ------------ | -------- | ------------------------------------------- |
| `-ParentId`  | Yes      | ID of the parent work item                  |
| `-CsvPath`   | Yes      | Path to the CSV file                        |
| `-Delimiter` | No       | CSV delimiter (default: `,`)                |
| `-WhatIf`    | No       | Simulates creation without performing it    |
| `-LogPath`   | No       | Path to log file (auto-generated otherwise) |

---

## How to Run

### Basic usage

```powershell
.\create-children.ps1 -ParentId 12345 -CsvPath .\items.csv
```

### Dry-run simulation

```powershell
.\create-children.ps1 -ParentId 12345 -CsvPath .\items.csv -WhatIf
```

### Custom delimiter

```powershell
.\create-children.ps1 -ParentId 12345 -CsvPath .\items.csv -Delimiter ';'
```

### Custom log path

```powershell
.\create-children.ps1 -ParentId 12345 -CsvPath .\items.csv -LogPath .\mylog.csv
```

---

## Script Workflow

1. Load helper scripts
2. Fetch:

   * Organization
   * Project
   * Authentication
   * Parent work item metadata
3. Determine correct child work item type
4. Read rows from CSV
5. Build JSON Patch payload
6. Create work items through Azure DevOps REST API
7. Output log file

---

## Troubleshooting

| Issue                     | Cause / Fix                                   |
| ------------------------- | --------------------------------------------- |
| Unsupported parent type   | Only Epic, Feature, User Story, PBI supported |
| CSV empty or unreadable   | Check delimiter and header names              |
| Unauthorized / PAT issues | Ensure PAT has Work Item Read/Write           |
| Missing relations         | Check PAT permissions                         |
| No children created       | Try running without `-WhatIf`                 |

