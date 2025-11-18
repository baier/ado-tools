param(
    [Parameter(Mandatory = $true)]
    [int]$ParentId,                  # ID of work item

    [Parameter(Mandatory = $true)]
    [string]$CsvPath,                # Path to CSV file (Title,Description,Tags)

    [string]$Delimiter = ',',        # Default: comma-separated

    [switch]$WhatIf,                 # Dry run - only shows what would happen

    [string]$LogPath                 # Optional: where to store the CSV log of created items
)

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# --------------------------------------------------------
# 1) Get organization/project + auth
# --------------------------------------------------------
. "ado\auth.ps1"
. "ado\orgproj.ps1"

$Organization = GetOrg
$Project      = GetProject
$auth         = GetAuth

$apiVersion = "7.0"
$baseUrlOrg = "https://dev.azure.com/$Organization"
$witBaseUrl = "$baseUrlOrg/$Project/_apis/wit"

# Default log path if not specified
if (-not $LogPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $LogPath = Join-Path $PSScriptRoot "created_children_$timestamp.csv"
}

# --------------------------------------------------------
# 2) Detect parent type (Epic / Feature / User Story )
# --------------------------------------------------------
$parentUrlApi = '{0}/workitems/{1}?api-version={2}&fields=System.Id,System.WorkItemType,System.Title' -f $witBaseUrl, $ParentId, $apiVersion
$parentWi     = Invoke-RestMethod -Uri $parentUrlApi -Headers $auth -Method Get
$parentType  = $parentWi.fields.'System.WorkItemType'
$parentTitle = $parentWi.fields.'System.Title'

Write-Host "Parent $ParentId is of type '$parentType' with title '$parentTitle'."

# Determine child type based on parent type
switch ($parentType) {
    'Epic' {
        $childType = 'Feature'
    }
    'Feature' {
        # Basic/Agile: Feature -> User Story
        $childType = 'User Story'
    }
    'User Story' {
        # Agile: User Story -> Task
        $childType = 'Task'
    }
    default {
        throw "Unsupported parent type '$parentType'. Expected Epic, Feature or User Story."
    }
}

Write-Host "Child items created will be of type '$childType'."

# URL used for establishing the parent-child relationship
$parentUrlRest = "$baseUrlOrg/$Project/_apis/wit/workItems/$ParentId"

# --------------------------------------------------------
# 3) Read CSV: Title, Description, Tags
# --------------------------------------------------------
if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "Could not find CSV file at path: $CsvPath"
}

$rows = Import-Csv -Path $CsvPath -Delimiter $Delimiter
if (-not $rows -or $rows.Count -eq 0) {
    throw "CSV-filen '$CsvPath' contains no rows."
}

Write-Host "Read $($rows.Count) rows from CSV."

# --------------------------------------------------------
# 4) Helper function: build JSON patch body for a new work item
# --------------------------------------------------------
function New-WorkItemPatchBody {
    param(
        [string]$Title,
        [string]$Description,
        [string]$Tags,
        [int]$ParentId,
        [string]$ParentUrlRest
    )

    $ops = @()

    # Tittel (obligatorisk)
    $ops += @{
        op    = "add"
        path  = "/fields/System.Title"
        value = $Title
    }

    # Beskrivelse (valgfri)
    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $ops += @{
            op    = "add"
            path  = "/fields/System.Description"
            value = $Description
        }
    }

    # Tags (valgfri)
    if (-not [string]::IsNullOrWhiteSpace($Tags)) {
        $ops += @{
            op    = "add"
            path  = "/fields/System.Tags"
            value = $Tags
        }
    }

    # Parent-relasjon – ny sak blir child av parent
    $ops += @{
        op   = "add"
        path = "/relations/-"
        value = @{
            rel  = "System.LinkTypes.Hierarchy-Reverse"
            url  = $ParentUrlRest
            attributes = @{
                comment = "Created as child of $ParentId via script"
            }
        }
    }

    return ($ops | ConvertTo-Json -Depth 6)
}

# --------------------------------------------------------
# 5) Create work items in Azure DevOps
# --------------------------------------------------------
$createdItems = @()
$logRows      = @()

# Azure DevOps requires $Type in URL, e.g. .../workitems/$Feature
$childTypeEscaped = [uri]::EscapeDataString($childType)
# Note the use of `${childTypeEscaped}` and backtick before $
$createUrl = '{0}/workitems/${1}?api-version={2}' -f $witBaseUrl, $childTypeEscaped, $apiVersion

foreach ($row in $rows) {

    # Expecting column names Title, Description, Tags
    $title       = $row.Title
    $description = $row.Description
    $tags        = $row.Tags

    if ([string]::IsNullOrWhiteSpace($title)) {
        Write-Warning "Skipping row without a Title."
        continue
    }

    $body = New-WorkItemPatchBody -Title $title `
                                  -Description $description `
                                  -Tags $tags `
                                  -ParentId $ParentId `
                                  -ParentUrlRest $parentUrlRest

    if ($WhatIf) {
        Write-Host "[WHATIF] Would have created ${childType} with title '$title' as child of $parentType $ParentId."
        continue
    }

    Write-Host "Creating ${childType}: '$title' ..."

    try {
        $response = Invoke-RestMethod -Uri $createUrl -Headers $auth -Method Patch -Body $body -ContentType "application/json-patch+json"
        $createdItems += $response

        $newId = $response.id
        $wiUrl = "$baseUrlOrg/$Project/_workitems/edit/$newId"
        Write-Host "  -> Created ${childType} with ID $newId ($wiUrl)"

        # Add to log list
        $logRows += [pscustomobject]@{
            Timestamp      = (Get-Date)
            ParentId       = $ParentId
            ParentType     = $parentType
            ParentTitle    = $parentTitle
            ChildId        = $newId
            ChildType      = $childType
            ChildTitle     = $title
            Description    = $description
            Tags           = $tags
            Url            = $wiUrl
        }
    }
    catch {
        Write-Warning "Error creating '$title': $($_.Exception.Message)"
    }
}

Write-Host ""

if ($WhatIf) {
    Write-Host "WHATIF mode: No work items were actually created."
}
else {
    Write-Host "Done. Created $($createdItems.Count) new '${childType}' under $parentType $ParentId."

    if ($logRows.Count -gt 0) {
        $logRows |
            Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8

        Write-Host "Log of created items saved to: $LogPath"
    }
    else {
        Write-Host "No items were created - no log file written."
    }
}
