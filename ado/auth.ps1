# -------- PAT-håndtering (kryptert lokalt per bruker) --------
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Global:PatStorePath = Join-Path $env:USERPROFILE ".azdo_pat.txt"

function Ensure-Pat {
  if (Test-Path -LiteralPath $Global:PatStorePath) {
    try {
      $raw = Get-Content -LiteralPath $Global:PatStorePath -Raw
      $raw = $raw.Trim()
      try {
        return ($raw | ConvertTo-SecureString)  # kryptert fra før
      } catch {
        if ([string]::IsNullOrWhiteSpace($raw)) { throw "PAT-filen finnes men er tom." }
        # Klartekst i fil → re-krypter til DPAPI én gang
        $plainSecure = ConvertTo-SecureString $raw -AsPlainText -Force
        ($plainSecure | ConvertFrom-SecureString) | Out-File -FilePath $Global:PatStorePath -Encoding ascii -Force
        return $plainSecure
      }
    } catch {
      throw "Kunne ikke lese/konvertere PAT fra '$Global:PatStorePath': $($_.Exception.Message)"
    }
  } else {
    # Lite GUI for første gangs lagring
    $frm = New-Object Windows.Forms.Form
    $frm.Text = "Azure DevOps PAT"
    $frm.StartPosition = "CenterScreen"
    $frm.Size = New-Object Drawing.Size(520,160)

    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = "Lim inn din Azure DevOps Personal Access Token:"
    $lbl.AutoSize = $true
    $lbl.Location = New-Object Drawing.Point(10,10)

    $txt = New-Object Windows.Forms.TextBox
    $txt.UseSystemPasswordChar = $true
    $txt.Width = 480
    $txt.Location = New-Object Drawing.Point(10,40)

    $btn = New-Object Windows.Forms.Button
    $btn.Text = "Lagre"
    $btn.Location = New-Object Drawing.Point(10,75)
    $btn.Add_Click({
      if ([string]::IsNullOrWhiteSpace($txt.Text)) {
        [Windows.Forms.MessageBox]::Show("PAT kan ikke være tom.","Feil",[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
      }
      $sec = ConvertTo-SecureString $txt.Text -AsPlainText -Force
      ($sec | ConvertFrom-SecureString) | Out-File -FilePath $Global:PatStorePath -Encoding ascii -Force
      $frm.Tag = $sec
      $frm.Close()
    })

    $frm.Controls.AddRange(@($lbl,$txt,$btn))
    [void]$frm.ShowDialog()
    if ($frm.Tag -is [SecureString]) { return $frm.Tag }
    throw "PAT ble ikke satt."
  }
}

function Get-BasicAuthHeader {
  param([SecureString] $Pat)
  $plainPat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Pat))
  try {
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$plainPat"))
    return @{ Authorization = "Basic $token"; Accept = "application/json" }
  } finally { $plainPat = $null }
}

# --------------------------------------------------------
# Autentisering
# --------------------------------------------------------

  
  function GetAuth {
	    $pat  = Ensure-Pat
		Get-BasicAuthHeader -Pat $pat
  }