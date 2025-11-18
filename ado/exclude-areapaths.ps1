function Get-ExcludedAreaFilter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project
    )

    # pathen til brukerens exclude-file
    $excludeFile = Join-Path $env:USERPROFILE ".exclude-areapaths.txt"

    # default: ingen filtrering
    $excludeAreaFilter = ""

    # finnes ikke => return tom
    if (-not (Test-Path -LiteralPath $excludeFile)) {
        return ""
    }

    # les innlinjer
    $areas = Get-Content -LiteralPath $excludeFile |
             Where-Object { $_ -and -not $_.StartsWith("#") }

    # hvis tom => return tom
    if ($areas.Count -eq 0) {
        return ""
    }

    # bygg opp AND-linjer
    $clauses = @()

    foreach ($area in $areas) {
        $trimmed = $area.Trim()
        if (-not $trimmed) { continue }

        $fullPath = "$Project\$trimmed"

        # escape enkeltsitater
        $escaped = $fullPath -replace "'", "''"

        # bygg WIQL-del
        $clauses += "    AND [System.AreaPath] <> '$escaped'"
    }

    if ($clauses.Count -gt 0) {
        $excludeAreaFilter = ($clauses -join "`r`n")
    }

    return $excludeAreaFilter
}
