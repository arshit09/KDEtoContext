# Adds/removes "Send to <device>" entries in the Explorer right-click menu for KDE Connect devices.
$ErrorActionPreference = 'Stop'

$KdeBin   = 'C:\Program Files\KDE Connect\bin'
$Cli      = Join-Path $KdeBin 'kdeconnect-cli.exe'
$Icon     = 'C:\Program Files\KDE Connect\icon.ico'
$DataDir  = Join-Path $env:LOCALAPPDATA 'KDEConnectContextMenu'
$Launcher = Join-Path $DataDir 'send.vbs'
$ShellKey = 'HKCU:\Software\Classes\*\shell'
$Prefix   = 'KDEConnect.'
$LogFile  = Join-Path $PSScriptRoot 'KDEConnect-ContextMenu.log'

function Write-Log($Message, $Level = 'INFO') {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')] [$Level] $Message`r`n"
    # The log can be briefly locked (e.g. an editor reloading it); retry, and never let logging crash the script.
    for ($i = 0; $i -lt 40; $i++) {
        try { [IO.File]::AppendAllText($LogFile, $line); return } catch { Start-Sleep -Milliseconds 50 }
    }
}

# Log any unhandled error with its exact location, show it, and exit.
trap {
    Write-Log "$($_.Exception.GetType().FullName): $_" 'ERROR'
    Write-Log "Location: $($_.InvocationInfo.PositionMessage)" 'ERROR'
    Write-Log "Stack:`r`n$($_.ScriptStackTrace)" 'ERROR'
    Write-Host "Error: $_ (logged to $LogFile)" -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}

# Runs kdeconnect-cli, logs the command, exit code, stdout and stderr; returns stdout lines.
function Invoke-Cli {
    # kdeconnect-cli may print harmless Qt warnings to stderr; log them instead of failing.
    $ErrorActionPreference = 'Continue'
    Write-Log "Running: `"$Cli`" $args"
    $out = & $Cli @args 2>&1
    Write-Log "Exit code: $LASTEXITCODE"
    foreach ($line in $out) {
        if ($line -is [System.Management.Automation.ErrorRecord]) { Write-Log "  stderr: $line" 'WARN' }
        else { Write-Log "  stdout: $line"; "$line" }
    }
}

# Hidden launcher so no console window flashes when sending; it logs each send to the same log file.
# The file is handed to kdeconnect-cli first and the log is written afterwards, so logging never delays a send.
function Install-Launcher {
    New-Item -ItemType Directory -Force $DataDir | Out-Null
    @"
Set a = WScript.Arguments
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
logText = ""

' Queues a log line; FlushLog writes the queue to disk.
Sub WriteLog(level, msg)
    d = Now
    ts = Year(d) & "-" & Right("0" & Month(d), 2) & "-" & Right("0" & Day(d), 2) & " " & FormatDateTime(d, 4) & ":" & Right("0" & Second(d), 2)
    logText = logText & "[" & ts & "] [" & level & "] [send] " & msg & vbCrLf
End Sub

' Retries only while another send holds the log open (error 70); any other error, such as the
' log folder having been moved, gives up at once instead of stalling.
Sub FlushLog()
    On Error Resume Next
    For i = 1 To 40
        Err.Clear
        Set f = fso.OpenTextFile("$LogFile", 8, True)
        If Err.Number = 0 Then
            f.Write logText
            f.Close
            Exit Sub
        End If
        If Err.Number <> 70 Then Exit Sub
        WScript.Sleep 50
    Next
End Sub

If a.Count < 2 Then
    WriteLog "ERROR", "Launcher called with " & a.Count & " argument(s); expected device id and file path"
    FlushLog
    WScript.Quit 1
End If
If Not fso.FileExists(a(1)) Then
    WriteLog "ERROR", "File not found or is a folder: " & a(1)
    FlushLog
    WScript.Quit 1
End If

tmp = fso.GetSpecialFolder(2) & "\" & fso.GetTempName()
cmd = "cmd /c """"$Cli"" -d " & a(0) & " --share """ & a(1) & """ > """ & tmp & """ 2>&1"""
WriteLog "INFO", "Sending """ & a(1) & """ to device " & a(0)
WriteLog "INFO", "Command: " & cmd
code = sh.Run(cmd, 0, True)

' The file has been handed off; a failure while collecting output must not lose the queued log.
On Error Resume Next
If fso.FileExists(tmp) Then
    If fso.GetFile(tmp).Size > 0 Then
        For Each line In Split(fso.OpenTextFile(tmp).ReadAll, vbCrLf)
            If Len(Trim(line)) > 0 Then WriteLog "INFO", "  output: " & line
        Next
    End If
    fso.DeleteFile tmp
End If

If code = 0 Then
    WriteLog "INFO", "Exit code 0 (OK)"
Else
    WriteLog "ERROR", "Exit code " & code & " (FAILED)"
End If
FlushLog
"@ | Set-Content -Path $Launcher -Encoding ASCII
    Write-Log "Launcher written: $Launcher"
}

function Get-Devices {
    $known = Invoke-Cli -l --id-name-only
    $reachable = @(Invoke-Cli -a --id-only)
    foreach ($line in $known) {
        if ($line -match '^(\S+)\s+(.+)$') {
            $dev = [pscustomobject]@{ Id = $Matches[1]; Name = $Matches[2]; Reachable = $reachable -contains $Matches[1] }
            Write-Log "Device found: $($dev.Name) [$($dev.Id)] reachable=$($dev.Reachable)"
            $dev
        } else {
            Write-Log "Unparsed device line: '$line'" 'WARN'
        }
    }
}

function Get-Installed {
    Get-ChildItem -LiteralPath $ShellKey -ErrorAction SilentlyContinue |
        Where-Object PSChildName -like "$Prefix*" |
        ForEach-Object {
            [pscustomobject]@{
                Id   = $_.PSChildName.Substring($Prefix.Length)
                Name = (Get-ItemProperty -LiteralPath $_.PSPath).MUIVerb
                Path = $_.PSPath
            }
        }
}

function Add-Entry($dev) {
    Write-Log "Adding device: $($dev.Name) [$($dev.Id)]"
    Install-Launcher
    $key = Join-Path $ShellKey ($Prefix + $dev.Id)
    $command = "wscript.exe //B `"$Launcher`" `"$($dev.Id)`" `"%1`""
    Write-Log "Creating key: $key"
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name 'MUIVerb' -Value "Send to $($dev.Name)" -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name 'Icon' -Value $Icon -Force | Out-Null
    # Keep the entry visible when more than 15 files are selected.
    New-ItemProperty -LiteralPath $key -Name 'MultiSelectModel' -Value 'Player' -Force | Out-Null
    $cmd = New-Item -Path (Join-Path $key 'command') -Force
    Set-ItemProperty -LiteralPath $cmd.PSPath -Name '(default)' -Value $command
    Write-Log "Registry written: MUIVerb='Send to $($dev.Name)' Icon='$Icon' MultiSelectModel='Player' command='$command'"
    Write-Host "Added: Send to $($dev.Name)" -ForegroundColor Green
}

function Pick($items, $label) {
    $sel = Read-Host "Number to $label (Enter to cancel)"
    Write-Log "User entered '$sel' to $label"
    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $items.Count) { return $items[[int]$sel - 1] }
    Write-Log "Selection cancelled or invalid"
}

Write-Log '===== Session start ====='
Write-Log "Script: $PSCommandPath"
Write-Log "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)); OS $([Environment]::OSVersion.VersionString); User $env:USERNAME"
Write-Log "kdeconnect-cli exists: $(Test-Path $Cli) ($Cli)"
Write-Log "KDE Connect processes running: $((Get-Process kdeconnect* -ErrorAction SilentlyContinue).Name -join ', ')"

if (-not (Test-Path $Cli)) {
    Write-Log "kdeconnect-cli not found at $Cli" 'ERROR'
    Write-Host "kdeconnect-cli not found at $Cli" -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1
}

# Rewrite the launcher for existing entries so they pick up script updates and log next to this script, even after it was moved.
if (Get-Installed) { Install-Launcher }

while ($true) {
    $installed = @(Get-Installed)
    Write-Log "Installed entries: $(($installed | ForEach-Object { "$($_.Name) [$($_.Id)]" }) -join '; ')"
    Write-Host "`n=== KDE Connect context menu ===" -ForegroundColor Cyan
    Write-Host 'In context menu:'
    if ($installed) { $installed | ForEach-Object { Write-Host "  - $($_.Name)" } } else { Write-Host '  (none)' }
    Write-Host "`n[A] Add device   [R] Remove device   [Q] Quit"
    $choice = (Read-Host 'Choice').Trim().ToUpper()
    Write-Log "Menu choice: '$choice'"
    switch ($choice) {
        'A' {
            $devices = @(Get-Devices | Where-Object { $installed.Id -notcontains $_.Id })
            if (-not $devices) {
                Write-Log 'No devices available to add' 'WARN'
                Write-Host 'No paired devices left to add (is the KDE Connect app running?).' -ForegroundColor Yellow; break
            }
            for ($i = 0; $i -lt $devices.Count; $i++) {
                $state = if ($devices[$i].Reachable) { 'reachable' } else { 'offline' }
                Write-Host "  [$($i + 1)] $($devices[$i].Name)  ($state)"
            }
            if ($d = Pick $devices 'add') { Add-Entry $d }
        }
        'R' {
            if (-not $installed) { Write-Log 'Nothing to remove' 'WARN'; Write-Host 'Nothing to remove.' -ForegroundColor Yellow; break }
            for ($i = 0; $i -lt $installed.Count; $i++) { Write-Host "  [$($i + 1)] $($installed[$i].Name)" }
            if ($d = Pick $installed 'remove') {
                Write-Log "Removing key: $($d.Path)"
                Remove-Item -LiteralPath $d.Path -Recurse -Force
                Write-Log "Removed: $($d.Name) [$($d.Id)]"
                Write-Host "Removed: $($d.Name)" -ForegroundColor Green
            }
        }
        'Q' { Write-Log '===== Session end ====='; exit 0 }
    }
}
