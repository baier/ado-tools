$configPath = Join-Path $env:USERPROFILE ".azdo_orgproj.txt"

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Fant ikke org/prosjekt-fil på path: $configPath"
}

$configLines = Get-Content -LiteralPath $configPath

if ($configLines.Count -lt 2) {
    throw "Filen '$configPath' må ha minst to linjer: første for Organization, andre for Project."
}

function GetOrg {
	$configLines[0].Trim()
}

function GetProject {
	$configLines[1].Trim()
}