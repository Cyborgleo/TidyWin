[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Apply', 'Restore', 'Check')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$TargetSid,

    [Parameter(Mandatory = $true)]
    [string]$StateDirectory,

    [Parameter(Mandatory = $true)]
    [string]$ScriptDirectory,

    [switch]$DisableCapture
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:RegistryRoot = $null
$script:TargetSid = $TargetSid
$script:StatePath = Join-Path $StateDirectory 'GamingMode-State.json'
$script:NvidiaSkipped = $false
$script:HighPerformancePlan = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:NvidiaPowerSettingId = '274197361'
$script:NvidiaProfileName = 'GLOBAL DRIVER PROFILE'

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host ('   ' + $Message) -ForegroundColor $Color
    if ($script:LogFile) {
        $stamp = Get-Date -Format 'HH:mm:ss'
        Add-Content -LiteralPath $script:LogFile -Value ($stamp + '  ' + $Message) -Encoding UTF8
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Save-State {
    param([Parameter(Mandatory = $true)]$State)

    $temporary = $script:StatePath + '.tmp'
    $json = ConvertTo-Json -InputObject $State -Depth 12
    Set-Content -LiteralPath $temporary -Value $json -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $script:StatePath -Force
}

function Get-RegistrySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SubKey,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    $fullSubKey = $script:TargetSid + '\' + $SubKey
    $key = $script:RegistryRoot.OpenSubKey($fullSubKey, $false)
    $keyExisted = $null -ne $key
    $values = @()

    try {
        foreach ($name in $Names) {
            $exists = $false
            $kind = ''
            $data = ''
            if ($keyExisted -and ($key.GetValueNames() -contains $name)) {
                $exists = $true
                $kind = [string]$key.GetValueKind($name)
                $raw = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($kind -eq 'DWord') {
                    $data = ([uint32]$raw).ToString([Globalization.CultureInfo]::InvariantCulture)
                } elseif ($kind -eq 'QWord') {
                    $data = ([uint64]$raw).ToString([Globalization.CultureInfo]::InvariantCulture)
                } elseif ($kind -eq 'Binary') {
                    $data = [Convert]::ToBase64String([byte[]]$raw)
                } elseif ($kind -eq 'MultiString') {
                    $data = ConvertTo-Json -InputObject @($raw) -Compress
                } else {
                    $data = [string]$raw
                }
            }

            $values += [pscustomobject]@{
                Name = $name
                Exists = $exists
                Kind = $kind
                Data = $data
            }
        }
    } finally {
        if ($keyExisted) { $key.Dispose() }
    }

    return [pscustomobject]@{
        SubKey = $SubKey
        KeyExisted = $keyExisted
        Values = @($values)
    }
}

function Set-UserValue {
    param(
        [Parameter(Mandatory = $true)][string]$SubKey,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][Microsoft.Win32.RegistryValueKind]$Kind
    )

    $fullSubKey = $script:TargetSid + '\' + $SubKey
    $key = $script:RegistryRoot.CreateSubKey($fullSubKey, $true)
    if ($null -eq $key) { throw "Could not open the current user's registry key: $SubKey" }
    try {
        $key.SetValue($Name, $Value, $Kind)
        $key.Flush()
    } finally {
        $key.Dispose()
    }
}

function Restore-RegistrySnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $fullSubKey = $script:TargetSid + '\' + [string]$Snapshot.SubKey
    $key = $script:RegistryRoot.OpenSubKey($fullSubKey, $true)
    foreach ($value in @($Snapshot.Values)) {
        if ($value.Exists) {
            if ($null -eq $key) {
                $key = $script:RegistryRoot.CreateSubKey($fullSubKey, $true)
            }
            if ($null -eq $key) { throw "Could not restore registry key: $($Snapshot.SubKey)" }

            $kind = [Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$value.Kind))
            switch ([string]$value.Kind) {
                'DWord' { $data = [int]::Parse([string]$value.Data, [Globalization.CultureInfo]::InvariantCulture) }
                'QWord' { $data = [long]::Parse([string]$value.Data, [Globalization.CultureInfo]::InvariantCulture) }
                'Binary' { $data = [Convert]::FromBase64String([string]$value.Data) }
                'MultiString' { $data = @((ConvertFrom-Json -InputObject ([string]$value.Data))) }
                default { $data = [string]$value.Data }
            }
            $key.SetValue([string]$value.Name, $data, $kind)
        } elseif ($null -ne $key) {
            $key.DeleteValue([string]$value.Name, $false)
        }
    }

    if ($null -ne $key) {
        $key.Flush()
        $key.Dispose()
    }

    if (-not $Snapshot.KeyExisted) {
        $check = $script:RegistryRoot.OpenSubKey($fullSubKey, $false)
        if ($null -ne $check) {
            $empty = ($check.ValueCount -eq 0 -and $check.SubKeyCount -eq 0)
            $check.Dispose()
            if ($empty) { $script:RegistryRoot.DeleteSubKey($fullSubKey, $false) }
        }
    }
}

function Set-MouseAcceleration {
    param([int[]]$Values)

    if (-not ('TidyWinNativeSettings' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class TidyWinNativeSettings {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint uiParam, int[] pvParam, uint flags);
}
'@
    }

    $ok = [TidyWinNativeSettings]::SystemParametersInfo(4, 0, $Values, 2)
    if (-not $ok) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw (New-Object System.ComponentModel.Win32Exception($code))
    }
}

function Get-ActivePowerPlan {
    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    $output = & $powercfg /getactivescheme 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Windows could not read the active power plan.' }
    $match = [regex]::Match(($output -join ' '), '(?i)[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}')
    if (-not $match.Success) { throw 'Windows returned an unrecognized active power plan.' }
    return $match.Value.ToLowerInvariant()
}

function Get-PowerPlanList {
    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    $output = & $powercfg /list 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Windows could not list available power plans.' }
    return ($output -join [Environment]::NewLine)
}

function Test-PowerPlanExists {
    param([string]$Guid)
    if ([string]::IsNullOrWhiteSpace($Guid)) { return $false }
    $plans = Get-PowerPlanList
    return $plans -match [regex]::Escape($Guid)
}

function Set-ActivePowerPlan {
    param([Parameter(Mandatory = $true)][string]$Guid)
    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
    & $powercfg /setactive $Guid 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Windows could not activate power plan $Guid." }
}

function Find-NvidiaInspector {
    $candidates = @(
        (Join-Path $ScriptDirectory 'nvidiaProfileInspector.exe'),
        (Join-Path $ScriptDirectory 'tools\nvidiaProfileInspector\nvidiaProfileInspector.exe'),
        (Join-Path $ScriptDirectory '..\..\tools\nvidiaProfileInspector\nvidiaProfileInspector.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

function Invoke-NvidiaInspector {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$Arguments
    )

    $processName = [IO.Path]::GetFileNameWithoutExtension($Executable)
    $existing = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        throw 'Close NVIDIA Profile Inspector before TidyWin changes or restores the NVIDIA profile.'
    }

    $workingDirectory = Split-Path -Parent $Executable
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $workingDirectory -Wait -PassThru
    return $process.ExitCode
}

function Get-NewestNvidiaExport {
    param([Parameter(Mandatory = $true)][string]$Executable)

    $folder = Split-Path -Parent $Executable
    $existing = @(Get-ChildItem -LiteralPath $folder -Filter 'CustomProfiles_*.nip' -File -ErrorAction SilentlyContinue)
    $beforeFiles = @{}
    foreach ($file in $existing) {
        $beforeFiles[$file.FullName.ToLowerInvariant()] = [pscustomobject]@{
            LastWriteTimeUtcTicks = $file.LastWriteTimeUtc.Ticks
            Length = $file.Length
        }
    }

    $exitCode = Invoke-NvidiaInspector -Executable $Executable -Arguments '-exportCustomized'
    if ($exitCode -ne 0) { throw 'NVIDIA Profile Inspector did not finish its profile export.' }

    $exports = @(Get-ChildItem -LiteralPath $folder -Filter 'CustomProfiles_*.nip' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $name = $_.FullName.ToLowerInvariant()
            if (-not $beforeFiles.ContainsKey($name)) { return $true }
            $prior = $beforeFiles[$name]
            return ($_.LastWriteTimeUtc.Ticks -ne $prior.LastWriteTimeUtcTicks -or $_.Length -ne $prior.Length)
        } |
        Sort-Object LastWriteTimeUtc -Descending)
    if ($exports.Count -eq 0) { throw 'No NVIDIA customized-profile export was created. Check that the Inspector folder is writable.' }
    return $exports[0].FullName
}

function Get-GlobalProfileNode {
    param([Parameter(Mandatory = $true)][System.Xml.XmlDocument]$Document)

    foreach ($node in @($Document.DocumentElement.ChildNodes)) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        $nameNode = $node.SelectSingleNode('ProfileName')
        if ($null -ne $nameNode -and $nameNode.InnerText -eq $script:NvidiaProfileName) {
            return $node
        }
    }
    return $null
}

function Write-GlobalProfileBackup {
    param(
        [Parameter(Mandatory = $true)][string]$ExportFile,
        [Parameter(Mandatory = $true)][string]$BackupFile
    )

    $source = New-Object System.Xml.XmlDocument
    $source.XmlResolver = $null
    $source.Load($ExportFile)
    $profileNode = Get-GlobalProfileNode -Document $source

    $backup = New-Object System.Xml.XmlDocument
    $backup.XmlResolver = $null
    $declaration = $backup.CreateXmlDeclaration('1.0', 'utf-16', $null)
    [void]$backup.AppendChild($declaration)
    $root = $backup.CreateElement('ArrayOfProfile')
    [void]$backup.AppendChild($root)

    if ($null -ne $profileNode) {
        [void]$root.AppendChild($backup.ImportNode($profileNode, $true))
    } else {
        $profile = $backup.CreateElement('Profile')
        $name = $backup.CreateElement('ProfileName')
        $name.InnerText = $script:NvidiaProfileName
        [void]$profile.AppendChild($name)
        [void]$profile.AppendChild($backup.CreateElement('Executeables'))
        [void]$profile.AppendChild($backup.CreateElement('Settings'))
        [void]$root.AppendChild($profile)
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = [Text.Encoding]::Unicode
    $settings.Indent = $true
    $writer = [System.Xml.XmlWriter]::Create($BackupFile, $settings)
    try { $backup.Save($writer) } finally { $writer.Dispose() }
    return $BackupFile
}

function Test-NvidiaPresetApplied {
    param(
        [Parameter(Mandatory = $true)][string]$ExportFile,
        [Parameter(Mandatory = $true)][string]$ExpectedPowerValue
    )

    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.Load($ExportFile)
    $profile = Get-GlobalProfileNode -Document $document
    if ($null -eq $profile) { return $false }
    foreach ($setting in @($profile.SelectNodes('Settings/ProfileSetting'))) {
        $idNode = $setting.SelectSingleNode('SettingID')
        $valueNode = $setting.SelectSingleNode('SettingValue')
        if ($null -ne $idNode -and $null -ne $valueNode -and
            $idNode.InnerText -eq $script:NvidiaPowerSettingId -and
            $valueNode.InnerText -eq $ExpectedPowerValue) {
            return $true
        }
    }
    return $false
}

function Get-NvidiaPresetPath {
    return (Join-Path $ScriptDirectory 'afterburner-nvidia.nip')
}

function Invoke-NvidiaApply {
    param([Parameter(Mandatory = $true)]$State)

    $nvidiaAdapters = @()
    try {
        $nvidiaAdapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -match '(?i)nvidia' })
    } catch {
        $script:NvidiaSkipped = $true
        Write-Status 'Could not query the display adapters; NVIDIA settings will be skipped for safety.' Yellow
        return
    }
    if ($nvidiaAdapters.Count -eq 0) {
        $script:NvidiaSkipped = $true
        Write-Status 'No NVIDIA display adapter was detected; the NVIDIA step is skipped.' Yellow
        return
    }

    $inspector = Find-NvidiaInspector
    $preset = Get-NvidiaPresetPath
    if (-not $inspector) {
        $script:NvidiaSkipped = $true
        Write-Status 'NVIDIA Profile Inspector not found; the NVIDIA step is skipped.' Yellow
        Write-Status 'Windows settings still applied; NVIDIA settings were left unchanged.' Yellow
        Write-Status 'For NVIDIA setup, follow the simple steps in the TidyWin README; do not open the PS1 or NIP files.' Gray
        return
    }
    if (-not (Test-Path -LiteralPath $preset -PathType Leaf)) {
        $script:NvidiaSkipped = $true
        Write-Status 'NVIDIA preset file not found; the NVIDIA step is skipped.' Yellow
        Write-Status 'Restore afterburner-nvidia.nip beside this BAT.' Gray
        return
    }

    $started = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $StateDirectory ('NVIDIA_Global_Before_' + $started + '.nip')
    try {
        $exportFile = Get-NewestNvidiaExport -Executable $inspector
        [void](Write-GlobalProfileBackup -ExportFile $exportFile -BackupFile $backupFile)
    } catch {
        Write-Status ('NVIDIA profile backup could not be created; no NVIDIA settings were changed: ' + $_.Exception.Message) Yellow
        return
    }
    $State.NvidiaInspector = $inspector
    $State.NvidiaBackup = $backupFile
    $State.NvidiaApplied = $true
    Save-State -State $State
    Write-Status 'Saved a restore snapshot of the NVIDIA global profile.' Green

    $quotedPreset = '"' + $preset + '"'
    $importExit = Invoke-NvidiaInspector -Executable $inspector -Arguments ('-silentImport -mergeImport ' + $quotedPreset)
    if ($importExit -ne 0) { throw 'NVIDIA Profile Inspector returned an error while applying the preset.' }

    $verifyExport = Get-NewestNvidiaExport -Executable $inspector
    if (-not (Test-NvidiaPresetApplied -ExportFile $verifyExport -ExpectedPowerValue '1')) {
        Write-Status 'The NVIDIA global preset could not be verified. Restoring its saved global profile now.' Yellow
        $quotedBackup = '"' + $backupFile + '"'
        $restoreExit = Invoke-NvidiaInspector -Executable $inspector -Arguments ('-silentImport -replaceImport ' + $quotedBackup)
        if ($restoreExit -ne 0) { throw 'The NVIDIA import failed and automatic profile rollback returned an error.' }
        $State.NvidiaApplied = $false
        Save-State -State $State
        throw 'The NVIDIA global preset could not be verified; its original global profile was restored.'
    }

    $State.NvidiaApplied = $true
    Save-State -State $State
    Write-Status 'NVIDIA global settings applied and verified.' Green
}

function Invoke-NvidiaRestore {
    param([Parameter(Mandatory = $true)]$State)

    if (-not $State.NvidiaApplied) {
        Write-Status 'No NVIDIA change was recorded for this saved state.' Gray
        return
    }
    if (-not $State.NvidiaInspector -or -not (Test-Path -LiteralPath ([string]$State.NvidiaInspector) -PathType Leaf)) {
        throw 'The NVIDIA restore snapshot exists, but NVIDIA Profile Inspector is not available at its saved path.'
    }
    if (-not $State.NvidiaBackup -or -not (Test-Path -LiteralPath ([string]$State.NvidiaBackup) -PathType Leaf)) {
        throw 'The NVIDIA restore snapshot file is missing.'
    }

    $quotedBackup = '"' + [string]$State.NvidiaBackup + '"'
    $exitCode = Invoke-NvidiaInspector -Executable ([string]$State.NvidiaInspector) -Arguments ('-silentImport -replaceImport ' + $quotedBackup)
    if ($exitCode -ne 0) { throw 'NVIDIA Profile Inspector returned an error while restoring the global profile.' }
    Write-Status 'Restored the saved NVIDIA global profile.' Green
}

function Open-GraphicsSettings {
    try {
        Start-Process -FilePath 'ms-settings:display-advancedgraphics' -ErrorAction Stop
        Write-Status 'Opened Windows Graphics settings for optional HAGS and per-game checks.' Blue
    } catch {
        Write-Status 'Open Settings > System > Display > Graphics for HAGS and per-game GPU options.' Yellow
    }
}

function New-InitialState {
    $registry = @(
        (Get-RegistrySnapshot -SubKey 'Software\Microsoft\GameBar' -Names @('AutoGameModeEnabled')),
        (Get-RegistrySnapshot -SubKey 'Control Panel\Mouse' -Names @('MouseSpeed', 'MouseThreshold1', 'MouseThreshold2'))
    )
    if ($DisableCapture) {
        $registry += (Get-RegistrySnapshot -SubKey 'System\GameConfigStore' -Names @('GameDVR_Enabled'))
        $registry += (Get-RegistrySnapshot -SubKey 'Software\Microsoft\Windows\CurrentVersion\GameDVR' -Names @('AppCaptureEnabled'))
    }

    $powerPlan = ''
    try { $powerPlan = Get-ActivePowerPlan } catch { Write-Status ('Could not read the active power plan: ' + $_.Exception.Message) Yellow }

    return [pscustomobject]@{
        SchemaVersion = 1
        TargetSid = $script:TargetSid
        CreatedAt = (Get-Date).ToString('o')
        IsApplied = $true
        CaptureWasDisabled = [bool]$DisableCapture
        ActivePowerPlanBefore = $powerPlan
        Registry = @($registry)
        NvidiaInspector = ''
        NvidiaBackup = ''
        NvidiaApplied = $false
    }
}

function Invoke-Check {
    Write-Status 'SETUP CHECK (read-only)' Cyan
    Write-Status 'No Windows or NVIDIA configuration settings will be changed.' Gray
    Write-Status 'A report log will be saved in the Gaming Mode Logs folder.' Gray

    if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) {
        Write-Status 'Saved snapshot: none yet; Apply will create one before changing settings.' Gray
    } else {
        try {
            $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            if ($null -eq $state.PSObject.Properties['IsApplied']) {
                Write-Status 'Saved snapshot: unreadable format. Do not Apply until the saved state is reviewed.' Red
            } elseif ([bool]$state.IsApplied) {
                $created = ''
                try { $created = ' (created ' + ([DateTimeOffset]::Parse([string]$state.CreatedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm')) + ')' } catch { }
                Write-Status ('Saved snapshot: ACTIVE' + $created + '; choose Restore before Apply.') Yellow
                if ($state.NvidiaApplied) {
                    Write-Status 'Saved snapshot records an NVIDIA global-profile change.' Yellow
                } else {
                    Write-Status 'Saved snapshot records no NVIDIA profile change.' Gray
                }
            } else {
                Write-Status 'Saved snapshot: already restored; it is safe to Apply again.' Green
            }
        } catch {
            Write-Status ('Saved snapshot: could not be read; do not Apply until it is reviewed. ' + $_.Exception.Message) Red
        }
    }

    try {
        $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
        $powerOutput = & $powercfg /getactivescheme 2>&1
        if ($LASTEXITCODE -eq 0) {
            $powerSummary = ($powerOutput -join ' ').Trim()
            Write-Status ('Power plan: ' + $powerSummary) Blue
            if ($powerSummary -match ('(?i)' + [regex]::Escape($script:HighPerformancePlan))) {
                Write-Status 'The Windows High Performance power plan is active.' Green
            }
        } else {
            Write-Status 'Power plan: Windows could not report the active plan.' Yellow
        }
    } catch {
        Write-Status ('Power plan check failed: ' + $_.Exception.Message) Yellow
    }

    try {
        $gameMode = (Get-RegistrySnapshot -SubKey 'Software\Microsoft\GameBar' -Names @('AutoGameModeEnabled')).Values[0]
        if (-not $gameMode.Exists) {
            Write-Status 'Windows Game Mode: registry preference is not explicitly set; check Windows Settings.' Yellow
        } elseif ($gameMode.Data -eq '1') {
            Write-Status 'Windows Game Mode: enabled for this account.' Green
        } else {
            Write-Status ('Windows Game Mode: preference is ' + $gameMode.Data + '; check Windows Settings.') Yellow
        }
    } catch {
        Write-Status ('Windows Game Mode check failed: ' + $_.Exception.Message) Yellow
    }

    try {
        $mouse = (Get-RegistrySnapshot -SubKey 'Control Panel\Mouse' -Names @('MouseSpeed', 'MouseThreshold1', 'MouseThreshold2')).Values
        if (@($mouse | Where-Object { -not $_.Exists }).Count -eq 0 -and @($mouse | Where-Object { $_.Data -eq '0' }).Count -eq 3) {
            Write-Status "Enhanced Pointer Precision: off according to this account's mouse settings." Green
        } else {
            Write-Status 'Enhanced Pointer Precision: not confirmed off; review Mouse settings if you want consistent raw mouse movement.' Yellow
        }
    } catch {
        Write-Status ('Mouse setting check failed: ' + $_.Exception.Message) Yellow
    }

    try {
        $captureA = (Get-RegistrySnapshot -SubKey 'System\GameConfigStore' -Names @('GameDVR_Enabled')).Values[0]
        $captureB = (Get-RegistrySnapshot -SubKey 'Software\Microsoft\Windows\CurrentVersion\GameDVR' -Names @('AppCaptureEnabled')).Values[0]
        if ($captureA.Exists -and $captureB.Exists -and $captureA.Data -eq '0' -and $captureB.Data -eq '0') {
            Write-Status 'Game Bar capture/background recording: disabled in the checked preferences.' Green
        } elseif ($captureA.Exists -and $captureB.Exists -and $captureA.Data -eq '1' -and $captureB.Data -eq '1') {
            Write-Status 'Game Bar capture/background recording: enabled in the checked preferences.' Gray
        } else {
            Write-Status 'Game Bar capture/background recording: Windows defaults or mixed preferences; check Xbox Game Bar settings.' Gray
        }
    } catch {
        Write-Status ('Game Bar capture check failed: ' + $_.Exception.Message) Yellow
    }

    try {
        $nvidiaAdapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -match '(?i)nvidia' } |
            ForEach-Object { [string]$_.Name })
        if ($nvidiaAdapters.Count -gt 0) {
            Write-Status ('NVIDIA adapter detected: ' + ($nvidiaAdapters -join ', ')) Green
        } else {
            Write-Status 'NVIDIA adapter: none detected; the optional NVIDIA step will be skipped.' Yellow
        }
    } catch {
        Write-Status ('NVIDIA adapter check unavailable: ' + $_.Exception.Message) Yellow
    }

    $inspector = Find-NvidiaInspector
    if ($inspector) {
        Write-Status ('NVIDIA Profile Inspector found: ' + $inspector) Green
    } else {
        Write-Status 'NVIDIA Profile Inspector: not found; NVIDIA settings will remain unchanged.' Gray
    }
    $preset = Get-NvidiaPresetPath
    if (Test-Path -LiteralPath $preset -PathType Leaf) {
        Write-Status 'TidyWin NVIDIA preset: found. Check confirms file readiness only; it does not inspect live driver values.' Gray
    } else {
        Write-Status 'TidyWin NVIDIA preset: missing; the optional NVIDIA step cannot run.' Yellow
    }

    Write-Status 'MANUAL CHECKS' Cyan
    Write-Status 'Windows Graphics: choose High performance for each game on hybrid/laptop PCs, if available.' Gray
    Write-Status 'HAGS: use the Windows Graphics settings switch only if it is offered; restart and compare results.' Gray
    Write-Status 'Display: select the highest refresh rate supported at your chosen resolution.' Gray
    Write-Status 'Windows 11: review windowed-game optimizations for DX10/11 games in windowed or borderless mode.' Gray
    Write-Status 'NVIDIA Reflex: enable it inside supported games; avoid forcing a global Ultra Low Latency override.' Gray
    Write-Status 'NVIDIA Control Panel: use per-game profiles for game-specific tuning; global values affect many 3D apps.' Gray
    Write-Status 'Compare the same game scene and graphics settings a few times before/after; FPS gains are not guaranteed.' Gray
}

function Invoke-Apply {
    if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
        try {
            $oldState = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            if ($oldState.IsApplied) {
        throw 'A Gaming Mode snapshot is already active. No settings were changed. Choose Restore Saved Settings in afterburner.bat, then Apply again.'
            }
        } catch {
            if ($_.Exception.Message -like 'A Gaming Mode snapshot is already active*') { throw }
            throw ('The existing state file could not be read. Restore or move it manually before applying again: ' + $_.Exception.Message)
        }
    }

    $state = New-InitialState
    Save-State -State $state
    Write-Status ('Saved the Windows settings snapshot to ' + $script:StatePath) Green

    $failed = $false
    try {
        if (-not $state.ActivePowerPlanBefore) {
            throw 'The active power plan could not be saved, so TidyWin left the current plan unchanged.'
        } elseif (Test-PowerPlanExists -Guid $script:HighPerformancePlan) {
            if ($state.ActivePowerPlanBefore -ne $script:HighPerformancePlan) {
                Set-ActivePowerPlan -Guid $script:HighPerformancePlan
            }
            Write-Status 'High Performance power plan is active.' Green
        } else {
            Write-Status 'High Performance plan is not available; opening Windows Power settings.' Yellow
            Write-Status 'Select Best performance in Power mode if Windows offers it on this PC.' Yellow
            Start-Process -FilePath 'ms-settings:powersleep'
        }
    } catch {
        $failed = $true
        Write-Status ('Power plan step failed: ' + $_.Exception.Message) Red
    }

    try {
        Set-UserValue -SubKey 'Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
        Write-Status 'Windows Game Mode enabled for this Windows account.' Green
    } catch {
        $failed = $true
        Write-Status ('Game Mode step failed: ' + $_.Exception.Message) Red
    }

    try {
        Set-UserValue -SubKey 'Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Kind ([Microsoft.Win32.RegistryValueKind]::String)
        Set-UserValue -SubKey 'Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Kind ([Microsoft.Win32.RegistryValueKind]::String)
        Set-UserValue -SubKey 'Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Kind ([Microsoft.Win32.RegistryValueKind]::String)
        Set-MouseAcceleration -Values ([int[]]@(0, 0, 0))
        Write-Status 'Enhanced Pointer Precision disabled for consistent mouse input.' Green
    } catch {
        $failed = $true
        Write-Status ('Mouse acceleration step failed: ' + $_.Exception.Message) Red
    }

    if ($DisableCapture) {
        try {
            Set-UserValue -SubKey 'System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
            Set-UserValue -SubKey 'Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0 -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
            Write-Status 'Game Bar capture/background recording disabled as selected.' Green
        } catch {
            $failed = $true
            Write-Status ('Game Bar capture step failed: ' + $_.Exception.Message) Red
        }
    } else {
        Write-Status 'Game Bar capture settings left unchanged.' Gray
    }

    try {
        Invoke-NvidiaApply -State $state
    } catch {
        $failed = $true
        Write-Status ('NVIDIA step needs attention: ' + $_.Exception.Message) Red
        Write-Status 'Use Restore before trying again; the saved snapshot is still available.' Yellow
    }

    Save-State -State $state
    if ($failed) {
        Write-Status 'Gaming Mode finished with one or more warnings; review this log and use Restore if needed.' Yellow
    } elseif ($script:NvidiaSkipped) {
        Write-Status 'Windows settings were applied; the optional NVIDIA step was skipped.' Yellow
    } else {
        Write-Status 'Gaming Mode setup finished. No FPS increase is guaranteed; compare your games before and after.' Green
    }
    Write-Status 'The HAGS switch is left for you to choose in Windows Graphics settings; it depends on GPU and driver support.'
    Write-Status 'For Windows 11, also review windowed-game optimization, each game GPU preference, and your monitor refresh rate.'
    Open-GraphicsSettings
}

function Invoke-Restore {
    if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) {
        throw 'No Gaming Mode snapshot was found. Apply must create a snapshot before Restore can run.'
    }
    $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($state.TargetSid -ne $script:TargetSid) {
        throw 'The saved snapshot belongs to a different Windows account. Run Restore from the account that used Apply.'
    }
    if (-not $state.IsApplied) {
        Write-Status 'The latest Gaming Mode snapshot has already been restored.' Yellow
        return
    }

    $failed = $false
    try { Invoke-NvidiaRestore -State $state } catch {
        $failed = $true
        Write-Status ('NVIDIA restore failed: ' + $_.Exception.Message) Red
    }

    foreach ($snapshot in @($state.Registry)) {
        try {
            Restore-RegistrySnapshot -Snapshot $snapshot
            Write-Status ('Restored user settings under ' + $snapshot.SubKey) Green
        } catch {
            $failed = $true
            Write-Status ('Registry restore failed for ' + $snapshot.SubKey + ': ' + $_.Exception.Message) Red
        }
    }

    try {
        if ($state.ActivePowerPlanBefore -and (Test-PowerPlanExists -Guid ([string]$state.ActivePowerPlanBefore))) {
            Set-ActivePowerPlan -Guid ([string]$state.ActivePowerPlanBefore)
            Write-Status 'Restored the previous active power plan.' Green
        } elseif ($state.ActivePowerPlanBefore) {
            $failed = $true
            Write-Status 'The previous power plan is no longer installed; it could not be restored.' Yellow
        }
    } catch {
        $failed = $true
        Write-Status ('Power plan restore failed: ' + $_.Exception.Message) Red
    }

    try {
        $mouse = $script:RegistryRoot.OpenSubKey($script:TargetSid + '\Control Panel\Mouse', $false)
        if ($null -ne $mouse) {
            try {
                $names = @('MouseSpeed', 'MouseThreshold1', 'MouseThreshold2')
                if (($names | Where-Object { $mouse.GetValueNames() -contains $_ }).Count -eq 3) {
                    $values = @(
                        [int]$mouse.GetValue('MouseSpeed'),
                        [int]$mouse.GetValue('MouseThreshold1'),
                        [int]$mouse.GetValue('MouseThreshold2')
                    )
                    Set-MouseAcceleration -Values ([int[]]$values)
                }
            } finally { $mouse.Dispose() }
        }
    } catch {
        $failed = $true
        Write-Status ('Mouse settings refresh failed: ' + $_.Exception.Message) Yellow
    }

    if (-not $failed) {
        $state.IsApplied = $false
        $state.RestoredAt = (Get-Date).ToString('o')
    } else {
        $state.LastRestoreAttemptAt = (Get-Date).ToString('o')
    }
    Save-State -State $state

    if ($failed) {
        Write-Status 'Restore finished with warnings. The saved state remains active so you can retry after fixing the issue.' Yellow
    } else {
        Write-Status 'Saved Windows and NVIDIA settings restored.' Green
    }
}

try {
    if ($TargetSid -notmatch '^S-1-[0-9]+(-[0-9]+)+$') { throw 'The supplied Windows account SID is invalid.' }
    if (-not (Test-IsAdministrator)) { throw 'Administrator permission is required.' }

    $identitySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($identitySid -ne $TargetSid) {
        throw 'The elevated account differs from the account that launched TidyWin. Run it from the same administrator account so per-user settings are not changed for the wrong person.'
    }

    $StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
    $ScriptDirectory = [IO.Path]::GetFullPath($ScriptDirectory)
    if (-not (Test-Path -LiteralPath $StateDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $StateDirectory -Force)
    }
    $logDirectory = Join-Path $StateDirectory 'Logs'
    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $logDirectory -Force)
    }
    $script:LogFile = Join-Path $logDirectory ('GamingMode_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    Set-Content -LiteralPath $script:LogFile -Value ('TidyWin Gaming Mode v1.0.6 - ' + $Action) -Encoding UTF8

    $script:RegistryRoot = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::Users,
        [Microsoft.Win32.RegistryView]::Default
    )
    $userHive = $script:RegistryRoot.OpenSubKey($TargetSid, $false)
    if ($null -eq $userHive) { throw 'The launching Windows account registry hive is not loaded.' }
    $userHive.Dispose()

    Write-Status ('Log file: ' + $script:LogFile) Blue
    switch ($Action) {
        'Apply' { Invoke-Apply }
        'Restore' { Invoke-Restore }
        'Check' { Invoke-Check }
    }
} catch {
    Write-Status ('ERROR: ' + $_.Exception.Message) Red
    exit 1
} finally {
    if ($script:RegistryRoot) { $script:RegistryRoot.Dispose() }
}

exit 0
