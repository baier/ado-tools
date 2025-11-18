. "ado\auth.ps1"
. "ado\orgproj.ps1"
. "ado\exclude-areapaths.ps1"

$Organization = GetOrg
$Project      = GetProject
$auth = GetAuth

$apiVersion = "7.0"
$baseUrlOrg = "https://dev.azure.com/$Organization"
$witBaseUrl = "$baseUrlOrg/$Project/_apis/wit"
$excludeAreaFilter = Get-ExcludedAreaFilter -Project $Project


function Get-WorkItemIds {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkItemType,      # i.e. 'Epic' or 'Feature'

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$WitBaseUrl,        # i.e. "https://dev.azure.com/org/proj/_apis/wit"

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [string]$ApiVersion = "7.0"
    )

    $wiql = @"
SELECT
    [System.Id]
FROM workitems
WHERE
    [System.TeamProject] = '$Project'
    AND [System.WorkItemType] = '$WorkItemType'
    AND [System.State] <> 'Removed'
	AND [System.State] <> 'Closed'
	$excludeAreaFilter
ORDER BY
    [System.Title]
"@

    $body   = @{ query = $wiql } | ConvertTo-Json
    $wiqlUrl = "$WitBaseUrl/wiql?api-version=$ApiVersion"

    $wiqlResult = Invoke-RestMethod -Uri $wiqlUrl -Headers $Headers -Method Post -Body $body -ContentType "application/json"

    if (-not $wiqlResult.workItems) {
        Write-Host "No $WorkItemType found in project '$Project'."
        return @()
    }

    return @($wiqlResult.workItems.id)
}

# --------------------------------------------------------
# Helper for batch retrieval
# --------------------------------------------------------
function Get-WorkItemsInBatches {
    param(
        [int[]]$Ids,
        [int]$BatchSize = 200,
        [string[]]$Fields,
        [switch]$ExpandRelations
    )

    $allItems = @()

    for ($i = 0; $i -lt $Ids.Count; $i += $BatchSize) {

        $batchIds = $Ids[$i..([Math]::Min($i + $BatchSize - 1, $Ids.Count - 1))]
        $idsParam = ($batchIds -join ",")

        # only use ?fields= if we're not expadning relations
        $fieldsParam = ""
        if ($Fields -and -not $ExpandRelations) {
            $fieldsParam = "&fields=" + ($Fields -join ",")
        }

        $expandParam = ""
        if ($ExpandRelations) { $expandParam = "&`$expand=Relations" }

        $url = "$witBaseUrl/workitems?ids=$idsParam$expandParam&api-version=$apiVersion$fieldsParam"

        $result = Invoke-RestMethod -Uri $url -Headers $auth -Method Get
        $allItems += $result.value
    }

    return $allItems
}


$featureIds = Get-WorkItemIds -WorkItemType 'Feature' `
                              -Project $Project `
                              -WitBaseUrl $witBaseUrl `
                              -Headers $auth `
                              -ApiVersion $apiVersion

# Get Epics
$epicIds = Get-WorkItemIds -WorkItemType 'Epic' `
                           -Project $Project `
                           -WitBaseUrl $witBaseUrl `
                           -Headers $auth `
                           -ApiVersion $apiVersion

# --------------------------------------------------------
# Get Features + Epics
# --------------------------------------------------------
$featureFields = @("System.Id","System.Title","System.Description","System.State", "System.AreaPath")
$features = Get-WorkItemsInBatches -Ids $featureIds -Fields $featureFields -ExpandRelations
Write-Host "FEATURES FOUND: $($features.Count)"

$epicFields = @("System.Id","System.Title","System.Description","System.State", "System.AreaPath")
$epics = Get-WorkItemsInBatches -Ids $epicIds -Fields $epicFields
Write-Host "EPICS FOUND: $($epics.Count)"


$epicById = @{}
foreach ($epic in $epics) { $epicById[$epic.id] = $epic }

# --------------------------------------------------------
# Build table
# --------------------------------------------------------
$result = @()
# Keeps track of which epic that has at least one feature
$epicsWithFeatures = New-Object System.Collections.Generic.HashSet[int]

foreach ($feature in $features) {

    if (-not $feature.relations) { continue }

    $parentLinks = $feature.relations | Where-Object { $_.rel -like "System.LinkTypes.Hierarchy*" }
    if (-not $parentLinks) { continue }

    foreach ($link in $parentLinks) {
        $epicIdString = ($link.url -replace '\?.*$', '' -replace '.*/', '')
        if (-not ($epicIdString -match '^\d+$')) { continue }

        [int]$epicId = $epicIdString

        if (-not $epicById.ContainsKey($epicId)) { continue }
		
        [void]$epicsWithFeatures.Add($epicId)

        $epic = $epicById[$epicId]

        $result += [pscustomobject]@{
            'Theme'       = $epic.fields.'System.Title'
            'Measure'  = $feature.fields.'System.Title'
            'Description'       = ($feature.fields.'System.Description' -replace '<[^>]+>', '')
            'Status'            = $feature.fields.'System.State'
			'Link (Feature)' = "$baseUrlOrg/$Project/_workitems/edit/$($feature.id)"
			'AreaPath'        = $feature.fields.'System.AreaPath'
        }
    }
}

foreach ($epic in $epics) {
    [int]$epicId = $epic.id
    if ($epicsWithFeatures.Contains($epicId)) {
        continue  # this epic already has feature(s), is in $result
    }

    # Epic without Feature -> fill inn values for epic where applicable
    $result += [pscustomobject]@{
        'Theme'            = $epic.fields.'System.Title'
        'Measure'          = '(no features)'
        'Desription'     = ($epic.fields.'System.Description' -replace '<[^>]+>', '')
        'Status'          = $epic.fields.'System.State'
		'AreaPath' = $epic.fields.'System.AreaPath'
		'Link'    = "$baseUrlOrg/$Project/_workitems/edit/$epicId"
		
    }
}

# --------------------------------------------------------
# Show table
# --------------------------------------------------------

$csvPath = Join-Path $PSScriptRoot "roadmap.csv"

 $result |
     Sort-Object 'Status', 'Theme', 'Measure' |
     Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 

 Write-Host "CSV stored to: $csvPath"


