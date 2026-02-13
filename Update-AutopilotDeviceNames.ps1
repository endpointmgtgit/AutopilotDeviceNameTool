<#PSScriptInfo

.VERSION 0.3.0

.GUID c1300cd2-5402-45c4-88e1-c7ee99f95d9a

.AUTHOR Chris Sellar

.COMPANYNAME EndpointMgt

.COPYRIGHT (c) 2026 Chris Sellar. All rights reserved.

.TAGS Autopilot Intune Graph DeviceNaming

.LICENSEURI https://opensource.org/licenses/MIT

.PROJECTURI https://github.com/endpointmgtgit/AutopilotDeviceNameTool

.EXTERNALMODULEDEPENDENCIES Microsoft.Graph.Authentication

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
Added configurable report output location, removed dependency on script root and updated Project URL.

#>

<#
.SYNOPSIS
Autopilot Device Name Tool
- Default: Updates Autopilot displayName from CSV (SerialNumber -> DeviceName OR DisplayName)
- Optional: Export current Autopilot devices (Serial + current displayName) only

.DESCRIPTION
Exports or updates Windows Autopilot device displayName values using Microsoft Graph.

Typical workflow:
1. Run -ExportCurrent to generate a baseline CSV.
2. Edit the DisplayName (or DeviceName) column.
3. Run the script with -CsvPath to apply updates.

Supports -WhatIf to simulate changes without updating Autopilot while still producing a report CSV.

.PARAMETER CsvPath
Path to CSV containing SerialNumber and DeviceName or DisplayName columns.
Used during Update mode.

.PARAMETER ForceUpdate
Overwrite existing displayName values instead of skipping devices that are already named.

.PARAMETER ExportCurrent
Exports current Autopilot devices without making changes.
Creates a baseline CSV which can be edited and reused for updates.

.PARAMETER ReportOutputPath
Optional output location for the generated CSV report.
- If you pass a folder path, the script will generate a timestamped CSV name in that folder.
- If you pass a full *.csv file path, it will write exactly to that file.
Defaults to C:\Temp.

.EXAMPLE
# Export current Autopilot devices (baseline CSV) to default output folder (C:\Temp)
.\Update Autopilot Device Names.ps1 -ExportCurrent

.EXAMPLE
# Export current Autopilot devices to a custom folder (auto filename)
.\Update Autopilot Device Names.ps1 -ExportCurrent -ReportOutputPath "C:\Reports\Autopilot"

.EXAMPLE
# Export current Autopilot devices to an explicit file
.\Update Autopilot Device Names.ps1 -ExportCurrent -ReportOutputPath "C:\Temp\Autopilot-Current.csv"

.EXAMPLE
# Preview changes without making updates (WhatIf) and write report to a folder
.\Update Autopilot Device Names.ps1 -CsvPath ".\NewDeviceNames.csv" -WhatIf -ReportOutputPath "C:\Reports\Autopilot"

.EXAMPLE
# Update Autopilot display names using DeviceName column and write report to Desktop
.\Update Autopilot Device Names.ps1 -CsvPath ".\NewDeviceNames.csv" -ReportOutputPath "$env:USERPROFILE\Desktop"

.NOTES
CSV REQUIRED HEADERS (Update mode)
- Option A: SerialNumber,DeviceName
- Option B: SerialNumber,DisplayName

You can run -ExportCurrent to generate a baseline CSV, edit the DisplayName column,
then feed it back into update mode.

Uses Microsoft Graph Beta endpoint for Autopilot device properties.
#>

[CmdletBinding(DefaultParameterSetName = 'Update', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    # --- Update mode ---
    [Parameter(Mandatory = $true, ParameterSetName = 'Update')]
    [string]$CsvPath,

    [Parameter(Mandatory = $false, ParameterSetName = 'Update')]
    [switch]$ForceUpdate,

    # --- Export mode ---
    [Parameter(Mandatory = $true, ParameterSetName = 'Export')]
    [switch]$ExportCurrent,

    # --- Shared ---
    [Parameter(Mandatory = $false)]
    [Alias("ReportPath")] # Backwards compatible: old -ReportPath still works
    [string]$ReportOutputPath = "C:\Temp"
)

# -------------------------
# Report path handling
# -------------------------
function Resolve-ReportCsvPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PathOrFolder,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Export","Update")]
        [string]$Mode
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $defaultFileName = if ($Mode -eq "Export") {
        "Autopilot-Current-{0}.csv" -f $timestamp
    }
    else {
        "Autopilot-Results-{0}.csv" -f $timestamp
    }

    # If a full CSV file path was provided, use it as-is; otherwise treat as a folder.
    $isCsvFile = $PathOrFolder.TrimEnd('\') -match '\.csv$'

    if ($isCsvFile) {
        $csvPath = $PathOrFolder
        $folder  = Split-Path -Path $csvPath -Parent
        if ([string]::IsNullOrWhiteSpace($folder)) {
            throw "Invalid ReportOutputPath value: $PathOrFolder"
        }
    }
    else {
        $folder  = $PathOrFolder
        $csvPath = Join-Path $folder $defaultFileName
    }

    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    return $csvPath
}

# ---- Graph prerequisites ----
function Initialize-GraphModule {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName
    )

    $available = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue
    if (-not $available) {
        throw "Required module '$ModuleName' not found. Install it with: Install-Module $ModuleName -Scope CurrentUser"
    }

    try {
        Import-Module $ModuleName -ErrorAction Stop
    }
    catch {
        throw "Failed to import module '$ModuleName'. Error: $($_.Exception.Message)"
    }
}

Initialize-GraphModule -ModuleName "Microsoft.Graph.Authentication"

# ---- Connect to Graph ----
try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes 'DeviceManagementServiceConfig.ReadWrite.All' -NoWelcome -ErrorAction Stop
    $connected = Get-MgContext
    Write-Host ("Connected as: {0}" -f $connected.Account) -ForegroundColor Green
}
catch {
    throw ("Graph connection failed. Ensure you have the required permissions/consent. " +
           "Error: {0}" -f $_.Exception.Message)
}

function Get-AutopilotDevice {
    $graphApiVersion = 'Beta'
    $resource = 'deviceManagement/windowsAutopilotDeviceIdentities'
    $uri = "https://graph.microsoft.com/$graphApiVersion/$resource"

    try {
        $graphResults = Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject -ErrorAction Stop
        $results = @()
        if ($graphResults.value) { $results += $graphResults.value }

        $next = $graphResults.'@odata.nextLink'
        while ($null -ne $next) {
            $additional = Invoke-MgGraphRequest -Uri $next -Method Get -OutputType PSObject -ErrorAction Stop
            if ($additional.value) { $results += $additional.value }
            $next = $additional.'@odata.nextLink'
        }

        return $results
    }
    catch {
        throw "Failed to retrieve Autopilot devices. Error: $($_.Exception.Message)"
    }
}

function Set-AutopilotDevice {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][hashtable]$Body
    )

    $graphApiVersion = 'Beta'
    $resource = "deviceManagement/windowsAutopilotDeviceIdentities/$Id/microsoft.graph.updateDeviceProperties"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$resource"

    $payloadJson = $Body | ConvertTo-Json -Depth 5

    $target = "AutopilotDeviceIdentity Id=$Id"
    $action = "Update device properties (POST updateDeviceProperties)"

    if ($PSCmdlet.ShouldProcess($target, $action)) {
        Invoke-MgGraphRequest -Uri $uri -Method Post -Body $payloadJson -ContentType 'application/json' -ErrorAction Stop | Out-Null
        return $true
    }

    return $false
}

# ---- Pull Autopilot devices (used by both modes) ----
Write-Host "Getting all Windows Autopilot devices..." -ForegroundColor Cyan
$apDevices = Get-AutopilotDevice
Write-Host ("Found {0} Windows Autopilot devices." -f $apDevices.Count) -ForegroundColor Green

# =========================
# EXPORT CURRENT MODE ONLY
# =========================
if ($ExportCurrent) {

    $ReportPath = Resolve-ReportCsvPath -PathOrFolder $ReportOutputPath -Mode "Export"

    $export = foreach ($ap in $apDevices) {
        $sn = ([string]$ap.serialNumber).Trim()
        $dn = ([string]$ap.displayName).Trim()

        [pscustomobject]@{
            SerialNumber    = $sn
            DisplayName     = $dn
            Id              = $ap.id
            Manufacturer    = $ap.manufacturer
            Model           = $ap.model
            GroupTag        = $ap.groupTag
            PurchaseOrder   = $ap.purchaseOrderIdentifier
            EnrollmentState = $ap.enrollmentState
        }
    }

    $export | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8 -Force -ErrorAction Stop -WhatIf:$false

    if (-not (Test-Path -LiteralPath $ReportPath)) {
        throw "Export-Csv completed but file not found at: $ReportPath"
    }

    Write-Host "Export complete: $ReportPath" -ForegroundColor Green
    return
}

# =========================
# UPDATE MODE
# =========================

$ReportPath = Resolve-ReportCsvPath -PathOrFolder $ReportOutputPath -Mode "Update"

# Resolve CSV path
$CsvPath = (Resolve-Path -Path $CsvPath -ErrorAction Stop).Path

# Load CSV
$csv = Import-Csv -Path $CsvPath -ErrorAction Stop
if (-not $csv -or $csv.Count -eq 0) {
    throw "CSV is empty: $CsvPath"
}

# Validate CSV headers
$headers = $csv[0].PSObject.Properties.Name

$hasSerial      = $headers -contains "SerialNumber"
$hasDeviceName  = $headers -contains "DeviceName"
$hasDisplayName = $headers -contains "DisplayName"

if (-not $hasSerial -or (-not $hasDeviceName -and -not $hasDisplayName)) {

    $detectedHeaders = if ($headers -and $headers.Count -gt 0) {
        ($headers -join ", ")
    }
    else {
        "(No headers detected)"
    }

    $message = @"
CSV validation failed.

Detected headers:
    $detectedHeaders

Expected CSV headers:

Option A:
    SerialNumber,DeviceName

Option B:
    SerialNumber,DisplayName
"@

    Write-Error $message
    exit 1
}

# Build CSV lookup: Serial -> DesiredName
$csvLookup = @{}
foreach ($row in $csv) {
    $sn = ([string]$row.SerialNumber).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($sn)) { continue }

    $desiredRaw = if ($hasDeviceName) { [string]$row.DeviceName } else { [string]$row.DisplayName }
    $desired = $desiredRaw.Trim()

    if ([string]::IsNullOrWhiteSpace($desired)) { continue }
    $csvLookup[$sn] = $desired
}
Write-Host ("Loaded {0} serials with desired names from CSV." -f $csvLookup.Count) -ForegroundColor Cyan

# Check for duplicate desired names (case-insensitive)
$desiredNames = $csvLookup.Values | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$uniqueNames  = $desiredNames | ForEach-Object { $_.ToUpperInvariant() } | Select-Object -Unique

$duplicateNameSet = @{}
if ($desiredNames.Count -ne $uniqueNames.Count) {
    # Identify duplicates
    $dupGroups = $desiredNames | Group-Object { $_.ToUpperInvariant() } | Where-Object { $_.Count -gt 1 }
    foreach ($g in $dupGroups) { $duplicateNameSet[$g.Name] = $true }

    Write-Warning ("Duplicate desired device names detected in CSV. " +
                   "Those entries will be skipped and flagged in the report. " +
                   "Duplicates: {0}" -f (($dupGroups | ForEach-Object { $_.Group[0] }) -join ", "))
}

# Build Autopilot lookup: Serial -> Record
$apLookup = @{}
foreach ($ap in $apDevices) {
    $sn = ([string]$ap.serialNumber).Trim().ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($sn) -and -not $apLookup.ContainsKey($sn)) {
        $apLookup[$sn] = $ap
    }
}

# Process CSV serials
$results = [System.Collections.Generic.List[object]]::new()

foreach ($serial in $csvLookup.Keys) {

    $desired = $csvLookup[$serial]
    $desiredKey = $desired.ToUpperInvariant()

    # Skip duplicates (flag in report)
    if ($duplicateNameSet.ContainsKey($desiredKey)) {
        $results.Add([pscustomobject]@{
            SerialNumber       = $serial
            DesiredDisplayName = $desired
            Status             = "DuplicateName"
            Reason             = "Desired displayName is duplicated in CSV. Resolve duplicates and re-run."
            Error              = $null
        })
        continue
    }

    if (-not $apLookup.ContainsKey($serial)) {
        $results.Add([pscustomobject]@{
            SerialNumber       = $serial
            DesiredDisplayName = $desired
            Status             = "NoDeviceFound"
            Reason             = "Serial not present in Autopilot"
            Error              = $null
        })
        continue
    }

    $ap = $apLookup[$serial]
    $current = ([string]$ap.displayName).Trim()

    # If not forcing, skip already named devices
    if (-not $ForceUpdate -and -not [string]::IsNullOrWhiteSpace($current)) {
        $results.Add([pscustomobject]@{
            SerialNumber       = $serial
            DesiredDisplayName = $desired
            Status             = "AlreadyNamed"
            Reason             = "Current displayName is '$current'. Use -ForceUpdate to overwrite."
            Error              = $null
        })
        continue
    }

    # If forcing OR current is blank: only update when the value would actually change
    if ($current -eq $desired) {
        $results.Add([pscustomobject]@{
            SerialNumber       = $serial
            DesiredDisplayName = $desired
            Status             = "NoChange"
            Reason             = "Current displayName already equals desired value."
            Error              = $null
        })
        continue
    }

    try {
        $didUpdate = Set-AutopilotDevice -Id $ap.id -Body @{ displayName = $desired }

        if ($didUpdate) {
            $results.Add([pscustomobject]@{
                SerialNumber       = $serial
                DesiredDisplayName = $desired
                Status             = "Updated"
                Reason             = "Updated displayName"
                Error              = $null
            })
        }
        else {
            $results.Add([pscustomobject]@{
                SerialNumber       = $serial
                DesiredDisplayName = $desired
                Status             = "WhatIf"
                Reason             = "Would update displayName (WhatIf/Confirm prevented change)"
                Error              = $null
            })
        }
    }
    catch {
        $results.Add([pscustomobject]@{
            SerialNumber       = $serial
            DesiredDisplayName = $desired
            Status             = "Failed"
            Reason             = "Attempted update but failed"
            Error              = $_.Exception.Message
        })
    }
}

# Export results
$results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8 -Force -ErrorAction Stop -WhatIf:$false

if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "Export-Csv completed but file not found at: $ReportPath"
}

if ($WhatIfPreference) {
    Write-Host "WhatIf: Report generated showing what WOULD happen: $ReportPath" -ForegroundColor Yellow
}
else {
    Write-Host "Report exported OK: $ReportPath" -ForegroundColor Green
}

Write-Host "Summary:" -ForegroundColor Cyan
$results | Group-Object -Property Status | ForEach-Object {
    Write-Host ("{0}: {1}" -f $_.Name, $_.Count) -ForegroundColor Yellow
}

Write-Host "Tip: re-run with -ExportCurrent to confirm Autopilot displayName values after propagation." -ForegroundColor DarkCyan
