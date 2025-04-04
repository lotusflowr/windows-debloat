# === LOGGING ===
$logDir = "C:\Windows\Temp\Logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Start-Transcript -Path "$logDir\00_SystemSetup.log" -Append -Force
$start = Get-Date

<#
.TITLE
    Script 04 – System-Level Performance, Privacy, and Gaming Optimizations

.SYNOPSIS
    Applies deep system tweaks focused on performance, telemetry reduction, power tuning,
    and gaming responsiveness. Designed to run in SYSTEM context.

.DESCRIPTION
    - Disables telemetry-related scheduled tasks and services
    - Enables the Ultimate Performance power plan
    - Applies CPU and GPU tuning for gaming
    - Blocks unnecessary features like error reporting and Store taskbar pins
    - Removes pinned Start menu tiles and disables taskbar feeds
    - Opens up ICMP traffic for network diagnostics

.NOTES
    ⚠️ Must be run as SYSTEM (e.g. via SetupComplete or Task Scheduler)
    ✅ Safe to run repeatedly (idempotent registry and scheduled task commands)
    📁 Logs actions to $env:TEMP\00_SystemSetup.log
#>

function Write-LoggedOperation {
    param (
        [scriptblock]$Block,
        [string]$Description
    )
    Write-Host "`n[INFO] $Description"
    try {
        & $Block
        Write-Host "[SUCCESS] $Description completed.`n"
    } catch {
        Write-Host "[ERROR] $Description failed: $($_.Exception.Message)`n"
    }
}

# === WINDOWS UPDATE ===
Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" /v SearchOrderConfig /t REG_DWORD /d 1 /f
} "Setting Windows Update to prioritize driver searches"

# === SCHEDULED TASKS: TELEMETRY CLEANUP ===
Write-LoggedOperation {
    $tasks = @(
        "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "Microsoft\Windows\Autochk\Proxy",
        "Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "Microsoft\Windows\Feedback\Siuf\DmClient",
        "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
        "Microsoft\Windows\Windows Error Reporting\QueueReporting",
        "Microsoft\Windows\Application Experience\MareBackup",
        "Microsoft\Windows\Application Experience\StartupAppTask",
        "Microsoft\Windows\Application Experience\PcaPatchDbTask",
        "Microsoft\Windows\Maps\MapsUpdateTask",
        "Microsoft\Windows\Windows Feeds\UpdateFeeds"
    )
    
    $total = $tasks.Count
    $current = 0
    
    foreach ($task in $tasks) {
        $current++
        $progress = [math]::Round(($current / $total) * 100, 2)
        Write-Progress -Activity "Disabling telemetry tasks" -Status "$progress% Complete" -PercentComplete $progress
        
        try {
            schtasks /Change /TN $task /Disable | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARNING] Failed to disable task: $task"
            }
        } catch {
            Write-Host "[WARNING] Error processing task $task : $($_.Exception.Message)"
        }
    }
} "Disabling telemetry and customer experience tasks"

Write-LoggedOperation {
    $taskGUIDs = @(
        "{0600DD45-FAF2-4131-A006-0B17509B9F78}",
        "{4738DE7A-BCC1-4E2D-B1B0-CADB044BFA81}",
        "{6FAC31FA-4A85-4E64-BFD5-2154FF4594B3}",
        "{FC931F16-B50A-472E-B061-B6F79A71EF59}",
        "{0671EB05-7D95-4153-A32B-1426B9FE61DB}",
        "{87BF85F4-2CE1-4160-96EA-52F554AA28A2}",
        "{8A9C643C-3D74-4099-B6BD-9C6D170898B1}",
        "{E3176A65-4E44-4ED3-AA73-3283660ACB9C}"
    )
    
    $total = $taskGUIDs.Count
    $current = 0
    
    foreach ($guid in $taskGUIDs) {
        $current++
        $progress = [math]::Round(($current / $total) * 100, 2)
        Write-Progress -Activity "Clearing task cache" -Status "$progress% Complete" -PercentComplete $progress
        
        try {
            reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\$guid" /f | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[WARNING] Failed to delete task cache: $guid"
            }
        } catch {
            Write-Host "[WARNING] Error processing task cache $guid : $($_.Exception.Message)"
        }
    }
} "Clearing telemetry task cache from registry"

# === POWER & PERFORMANCE ===
Write-LoggedOperation {
    try {
        $result = powercfg.exe /DUPLICATESCHEME e9a42b02-d5df-448d-aa00-03f14749eb61
        if (-not ($result -match '\s([a-f0-9-]{36})\s')) {
            throw "Failed to duplicate power scheme"
        }
        $setResult = powercfg.exe /SETACTIVE $Matches[1]
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set active power scheme: $setResult"
        }
    } catch {
        throw "Power plan configuration failed: $($_.Exception.Message)"
    }
} "Activating Ultimate Performance power plan"

Write-LoggedOperation {
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v IRPStackSize /t REG_DWORD /d 30 /f
} "Increasing IRP Stack Size for better network performance"

Write-LoggedOperation {
    try {
        $ramKB = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB
        if ($ramKB -le 0) {
            throw "Invalid RAM calculation result"
        }
        Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control -Name SvcHostSplitThresholdInKB -Value [int]$ramKB -Force
    } catch {
        throw "RAM optimization failed: $($_.Exception.Message)"
    }
} "Optimizing svchost split threshold based on system RAM"

Write-LoggedOperation { powercfg -hibernate off } "Disabling hibernation"
Write-LoggedOperation { powercfg /change standby-timeout-ac 0 } "Disabling AC standby timeout"
Write-LoggedOperation { powercfg /change standby-timeout-dc 0 } "Disabling DC standby timeout"
Write-LoggedOperation { powercfg /change monitor-timeout-ac 0 } "Disabling monitor timeout (AC)"
Write-LoggedOperation { powercfg /change monitor-timeout-dc 0 } "Disabling monitor timeout (DC)"

# === GAMING PRIORITY ===
Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f
} "Setting GPU priority to 8 for gaming"

Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f
} "Setting CPU scheduling priority to 6 for games"

Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d "High" /f
} "Setting scheduling category to High for gaming tasks"

# === POLICY HARDENING ===
Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled /t REG_DWORD /d 1 /f
} "Disabling Windows Error Reporting"

Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v DisabledByGroupPolicy /t REG_DWORD /d 1 /f
} "Disabling Advertising ID globally"

Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoPinningStoreToTaskbar /t REG_DWORD /d 1 /f
} "Preventing Microsoft Store from being pinned to taskbar"

# === START MENU & FEEDS ===
Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Microsoft\PolicyManager\Current\Device\Start" /v ConfigureStartPins /t REG_SZ /d '{ "pinnedList": [] }' /f
    reg.exe add "HKLM\SOFTWARE\Microsoft\PolicyManager\Current\Device\Start" /v ConfigureStartPins_ProviderSet /t REG_DWORD /d 1 /f
    reg.exe add "HKLM\SOFTWARE\Microsoft\PolicyManager\Current\Device\Start" /v ConfigureStartPins_WinningProvider /t REG_SZ /d B5292708-1619-419B-9923-E5D9F3925E71 /f
} "Clearing Start menu pinned tiles"

Write-LoggedOperation {
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f
} "Disabling News and Interests from taskbar"

# === FIREWALL ALLOW ICMP ===
Write-LoggedOperation {
    New-NetFirewallRule -DisplayName 'ICMPv4' -Profile Any -Protocol ICMPv4
    New-NetFirewallRule -DisplayName 'ICMPv6' -Profile Any -Protocol ICMPv6
} "Allowing ICMP ping (v4 + v6) through the firewall"

# === WRAP UP ===
$runtime = (Get-Date) - $start
Write-Host "`nCompleted in $([math]::Round($runtime.TotalSeconds, 2)) seconds."
Stop-Transcript