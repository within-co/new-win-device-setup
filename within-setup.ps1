#Requires -RunAsAdministrator
# =============================================================================
#  WITHIN - Automated Device Setup Script
#  within-setup.ps1  v2.4
#  Changes from v2.3:
#  - Optional Entra ID join: checkbox "Assign user now" shows/hides credentials
#  - If skipped, machine is saved as spare (local within account + ManageEngine)
#  - Entra join can be done later manually or via ManageEngine remote script
#  - Restart at end (required for BIOS AHCI + Entra join to apply)
# =============================================================================

# Elevate if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Logging
$LogFile = "C:\Windows\Setup\Scripts\within-setup.log"
$ProgressPreference = 'SilentlyContinue'

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Level] $Message"
    $line | Tee-Object -FilePath $LogFile -Append | Out-Null
    Write-Host $line
}

function Download-File {
    param([string]$Url, [string]$Dest, [string]$Label)
    Write-Log "Downloading $Label..."
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
        Write-Log "$Label downloaded OK"
        return $true
    } catch {
        Write-Log "FAILED downloading $Label : $_" "ERROR"
        return $false
    }
}

# Load WinForms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Write-Log "=================================================="
Write-Log "WITHIN Setup Starting"
Write-Log "=================================================="

# Ensure within account never prompts for password change
# Belt-and-suspenders fix for Rufus override
try {
    $localUser = Get-LocalUser -Name "within" -ErrorAction Stop
    Set-LocalUser -Name "within" -PasswordNeverExpires $true
    $localUser | Set-LocalUser -UserMayChangePassword $false
    Write-Log "within account password policy set - no expiry, no forced change"
} catch {
    # Fallback for older PowerShell versions
    net user within /logonpasswordchg:no 2>&1 | Out-Null
    net user within /passwordchg:no 2>&1 | Out-Null
    Write-Log "within account password policy set via net user"
}

# Detect manufacturer
$cs           = Get-CimInstance -ClassName Win32_ComputerSystem
$bios         = Get-CimInstance -ClassName Win32_BIOS
$manufacturer = $cs.Manufacturer
$model        = $cs.Model
$serial       = $bios.SerialNumber
$isDell       = $manufacturer -like "*Dell*"
$isLenovo     = $manufacturer -like "*Lenovo*" -or $manufacturer -like "*LENOVO*"
$vendorLabel  = if ($isDell) { "Dell" } elseif ($isLenovo) { "Lenovo" } else { $manufacturer }

Write-Log "Manufacturer : $manufacturer"
Write-Log "Model        : $model"
Write-Log "Serial       : $serial"

# =============================================================================
# BUILD UI
# =============================================================================
$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "WITHIN - Device Setup"
$form.Size             = New-Object System.Drawing.Size(580, 660)
$form.StartPosition    = "CenterScreen"
$form.FormBorderStyle  = "FixedDialog"
$form.MaximizeBox      = $false
$form.MinimizeBox      = $false
$form.TopMost          = $true
$form.BackColor        = [System.Drawing.Color]::White

# Header
$hdr           = New-Object System.Windows.Forms.Label
$hdr.Text      = "WITHIN"
$hdr.Font      = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
$hdr.Location  = New-Object System.Drawing.Point(20, 15)
$hdr.Size      = New-Object System.Drawing.Size(540, 48)
$form.Controls.Add($hdr)

$sub           = New-Object System.Windows.Forms.Label
$sub.Text      = "Windows 11 Pro - Automated Device Setup"
$sub.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$sub.ForeColor = [System.Drawing.Color]::Gray
$sub.Location  = New-Object System.Drawing.Point(22, 62)
$sub.Size      = New-Object System.Drawing.Size(540, 22)
$form.Controls.Add($sub)

# Device info bar
$devInfo           = New-Object System.Windows.Forms.Label
$devInfo.Text      = "  $vendorLabel  |  $model  |  S/N: $serial"
$devInfo.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$devInfo.ForeColor = [System.Drawing.Color]::White
$devInfo.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$devInfo.Location  = New-Object System.Drawing.Point(0, 90)
$devInfo.Size      = New-Object System.Drawing.Size(580, 26)
$form.Controls.Add($devInfo)

$div             = New-Object System.Windows.Forms.Label
$div.BorderStyle = "Fixed3D"
$div.Location    = New-Object System.Drawing.Point(20, 122)
$div.Size        = New-Object System.Drawing.Size(540, 2)
$form.Controls.Add($div)

# ── Computer name ─────────────────────────────────────────────────────────
$nameLbl          = New-Object System.Windows.Forms.Label
$nameLbl.Text     = "Computer Name:"
$nameLbl.Font     = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$nameLbl.Location = New-Object System.Drawing.Point(20, 130)
$nameLbl.Size     = New-Object System.Drawing.Size(540, 24)
$form.Controls.Add($nameLbl)

$nameHint           = New-Object System.Windows.Forms.Label
$nameHint.Text      = "Format: DEPT-FirstnameLastname  (max 15 chars)   e.g.  ADMN-JoeYakuel  or  OPER-SPARE01"
$nameHint.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$nameHint.ForeColor = [System.Drawing.Color]::Gray
$nameHint.Location  = New-Object System.Drawing.Point(20, 153)
$nameHint.Size      = New-Object System.Drawing.Size(540, 18)
$form.Controls.Add($nameHint)

$nameBox                 = New-Object System.Windows.Forms.TextBox
$nameBox.Font            = New-Object System.Drawing.Font("Segoe UI", 12)
$nameBox.Location        = New-Object System.Drawing.Point(20, 174)
$nameBox.Size            = New-Object System.Drawing.Size(380, 32)
$nameBox.MaxLength       = 15
$nameBox.CharacterCasing = "Upper"
$form.Controls.Add($nameBox)

# ── Divider ───────────────────────────────────────────────────────────────
$div2             = New-Object System.Windows.Forms.Label
$div2.BorderStyle = "Fixed3D"
$div2.Location    = New-Object System.Drawing.Point(20, 218)
$div2.Size        = New-Object System.Drawing.Size(540, 2)
$form.Controls.Add($div2)

# ── Assign user checkbox ──────────────────────────────────────────────────
$assignChk          = New-Object System.Windows.Forms.CheckBox
$assignChk.Text     = "Assign user now (Entra ID join)"
$assignChk.Font     = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$assignChk.Location = New-Object System.Drawing.Point(20, 226)
$assignChk.Size     = New-Object System.Drawing.Size(350, 26)
$assignChk.Checked  = $false
$form.Controls.Add($assignChk)

$assignNote           = New-Object System.Windows.Forms.Label
$assignNote.Text      = "Leave unchecked to set up as a spare. Entra join can be done later via ManageEngine."
$assignNote.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$assignNote.ForeColor = [System.Drawing.Color]::Gray
$assignNote.Location  = New-Object System.Drawing.Point(20, 252)
$assignNote.Size      = New-Object System.Drawing.Size(540, 18)
$form.Controls.Add($assignNote)

# ── Entra ID credentials (hidden by default) ──────────────────────────────
$emailLbl           = New-Object System.Windows.Forms.Label
$emailLbl.Text      = "User Email:"
$emailLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$emailLbl.Location  = New-Object System.Drawing.Point(20, 278)
$emailLbl.Size      = New-Object System.Drawing.Size(100, 20)
$emailLbl.Visible   = $false
$form.Controls.Add($emailLbl)

$emailBox                   = New-Object System.Windows.Forms.TextBox
$emailBox.Font               = New-Object System.Drawing.Font("Segoe UI", 11)
$emailBox.Location           = New-Object System.Drawing.Point(120, 274)
$emailBox.Size               = New-Object System.Drawing.Size(300, 30)
$emailBox.PlaceholderText    = "firstname.lastname@within.co"
$emailBox.Visible            = $false
$form.Controls.Add($emailBox)

$passLbl           = New-Object System.Windows.Forms.Label
$passLbl.Text      = "Temp Password:"
$passLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$passLbl.Location  = New-Object System.Drawing.Point(20, 314)
$passLbl.Size      = New-Object System.Drawing.Size(100, 20)
$passLbl.Visible   = $false
$form.Controls.Add($passLbl)

$passBox                  = New-Object System.Windows.Forms.TextBox
$passBox.Font             = New-Object System.Drawing.Font("Segoe UI", 11)
$passBox.Location         = New-Object System.Drawing.Point(120, 310)
$passBox.Size             = New-Object System.Drawing.Size(300, 30)
$passBox.PlaceholderText  = "Temporary password"
$passBox.PasswordChar     = [char]0x2022
$passBox.Visible          = $false
$form.Controls.Add($passBox)

# Toggle visibility of credentials when checkbox changes
$assignChk.Add_CheckedChanged({
    $emailLbl.Visible = $assignChk.Checked
    $emailBox.Visible = $assignChk.Checked
    $passLbl.Visible  = $assignChk.Checked
    $passBox.Visible  = $assignChk.Checked
    $form.Refresh()
})

# ── Divider ───────────────────────────────────────────────────────────────
$div3             = New-Object System.Windows.Forms.Label
$div3.BorderStyle = "Fixed3D"
$div3.Location    = New-Object System.Drawing.Point(20, 352)
$div3.Size        = New-Object System.Drawing.Size(540, 2)
$form.Controls.Add($div3)

# ── Status list ───────────────────────────────────────────────────────────
$statusLbl          = New-Object System.Windows.Forms.Label
$statusLbl.Text     = "Status:"
$statusLbl.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$statusLbl.Location = New-Object System.Drawing.Point(20, 358)
$statusLbl.Size     = New-Object System.Drawing.Size(540, 20)
$form.Controls.Add($statusLbl)

$statusBox          = New-Object System.Windows.Forms.ListBox
$statusBox.Font     = New-Object System.Drawing.Font("Consolas", 8)
$statusBox.Location = New-Object System.Drawing.Point(20, 378)
$statusBox.Size     = New-Object System.Drawing.Size(540, 178)
$form.Controls.Add($statusBox)

function Update-Status {
    param([string]$Msg, [bool]$IsError = $false)
    $icon = if ($IsError) { "[!]" } else { "[OK]" }
    $statusBox.Items.Add("$icon  $Msg")
    $statusBox.TopIndex = $statusBox.Items.Count - 1
    $form.Refresh()
    Write-Log $Msg $(if ($IsError) { "ERROR" } else { "INFO" })
}

# ── Start button ──────────────────────────────────────────────────────────
$btn           = New-Object System.Windows.Forms.Button
$btn.Text      = "Start Setup"
$btn.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btn.Location  = New-Object System.Drawing.Point(20, 574)
$btn.Size      = New-Object System.Drawing.Size(150, 40)
$btn.BackColor = [System.Drawing.Color]::Black
$btn.ForeColor = [System.Drawing.Color]::White
$btn.FlatStyle = "Flat"
$form.Controls.Add($btn)

$footNote           = New-Object System.Windows.Forms.Label
$footNote.Text      = "Machine restarts automatically when done."
$footNote.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$footNote.ForeColor = [System.Drawing.Color]::Gray
$footNote.Location  = New-Object System.Drawing.Point(185, 586)
$footNote.Size      = New-Object System.Drawing.Size(375, 18)
$form.Controls.Add($footNote)

# =============================================================================
# BUTTON CLICK
# =============================================================================
$btn.Add_Click({

    $pcName     = $nameBox.Text.Trim()
    $assignNow  = $assignChk.Checked
    $userEmail  = $emailBox.Text.Trim()
    $userPass   = $passBox.Text

    # Validate computer name
    if ($pcName.Length -lt 3) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter a computer name (minimum 3 characters).`nExamples: ADMN-JoeYakuel  or  OPER-SPARE01",
            "WITHIN Setup", "OK", "Warning") | Out-Null
        return
    }
    if ($pcName -notmatch '^[A-Z0-9\-]+$') {
        [System.Windows.Forms.MessageBox]::Show(
            "Computer name may only contain letters, numbers and hyphens.",
            "WITHIN Setup", "OK", "Warning") | Out-Null
        return
    }

    # Validate Entra credentials only if assigning now
    if ($assignNow) {
        if ($userEmail -notmatch '^[^@]+@within\.co$') {
            [System.Windows.Forms.MessageBox]::Show(
                "Please enter a valid within.co email.`nExample: firstname.lastname@within.co",
                "WITHIN Setup", "OK", "Warning") | Out-Null
            return
        }
        if ($userPass.Length -lt 3) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please enter the user's temporary password.",
                "WITHIN Setup", "OK", "Warning") | Out-Null
            return
        }
    }

    $btn.Enabled       = $false
    $nameBox.Enabled   = $false
    $assignChk.Enabled = $false
    $emailBox.Enabled  = $false
    $passBox.Enabled   = $false
    $btn.Text          = "Running..."
    $tempDir           = "$env:TEMP\within_setup"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $spareMode = -not $assignNow
    if ($spareMode) {
        Update-Status "Mode: SPARE (no user assigned - Entra join skipped)"
    } else {
        Update-Status "Mode: ASSIGN USER - $userEmail"
    }
    Update-Status "Device: $vendorLabel  |  $model  |  S/N: $serial"

    # =========================================================================
    # STEP 1 - Vendor driver tool + Dell BIOS RAID->AHCI
    # =========================================================================
    if ($isDell) {
        Update-Status "Dell detected - checking BIOS storage mode..."
        $cctkInstalled = $false

        try {
            $wgResult = Start-Process "winget" `
                -ArgumentList "install --id Dell.CommandConfigure --silent --accept-package-agreements --accept-source-agreements" `
                -Wait -PassThru -NoNewWindow
            if ($wgResult.ExitCode -eq 0) { $cctkInstalled = $true; Update-Status "Dell Command Configure installed" }
        } catch { }

        if (-not $cctkInstalled) {
            $cctkUrl  = "https://dl.dell.com/FOLDER11377308M/1/Dell-Command-Configure_XVWM2_WIN_4.12.0.40_A00.EXE"
            $cctkPath = "$tempDir\DellCommandConfigure.exe"
            if (Download-File -Url $cctkUrl -Dest $cctkPath -Label "Dell Command Configure") {
                Start-Process -FilePath $cctkPath -ArgumentList "/s" -Wait
                $cctkInstalled = $true
                Update-Status "Dell Command Configure installed"
            }
        }

        if ($cctkInstalled) {
            $cctkExe = "C:\Program Files\Dell\Command Configure\X86_64\cctk.exe"
            if (-not (Test-Path $cctkExe)) {
                $cctkExe = "C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe"
            }
            if (Test-Path $cctkExe) {
                $currentMode = & $cctkExe --SataOperation 2>&1
                Write-Log "Current BIOS SATA mode: $currentMode"
                if ($currentMode -like "*raid*" -or $currentMode -like "*Raid*") {
                    Update-Status "BIOS is RAID - switching to AHCI..."
                    $result = & $cctkExe --SataOperation=AHCI 2>&1
                    Write-Log "BIOS AHCI result: $result"
                    Update-Status "BIOS storage mode set to AHCI - applies on reboot"
                } else {
                    Update-Status "BIOS already AHCI - no change needed"
                }
            } else {
                Update-Status "cctk.exe not found - BIOS change skipped" $true
            }
        } else {
            Update-Status "Dell Command Configure unavailable - BIOS change skipped" $true
        }

        Update-Status "Installing Dell Command Update for drivers..."
        $dcuInstalled = $false
        try {
            $wgResult = Start-Process "winget" `
                -ArgumentList "install --id Dell.CommandUpdate.Universal --silent --accept-package-agreements --accept-source-agreements" `
                -Wait -PassThru -NoNewWindow
            if ($wgResult.ExitCode -eq 0) { $dcuInstalled = $true; Update-Status "Dell Command Update installed" }
        } catch { }

        if (-not $dcuInstalled) {
            $dcuUrl  = "https://dl.dell.com/FOLDER10889969M/1/Dell-Command-Update-Application-for-Windows_H0KDP_WIN_5.3.0_A00.EXE"
            $dcuPath = "$tempDir\DellCommandUpdate.exe"
            if (Download-File -Url $dcuUrl -Dest $dcuPath -Label "Dell Command Update") {
                Start-Process -FilePath $dcuPath -ArgumentList "/s" -Wait
                $dcuInstalled = $true
                Update-Status "Dell Command Update installed"
            }
        }

        if ($dcuInstalled) {
            Update-Status "Running Dell driver update (5-10 min)..."
            $dcuCli = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
            if (Test-Path $dcuCli) {
                Start-Process -FilePath $dcuCli `
                    -ArgumentList "/applyUpdates -silent -reboot=disable -autoSuspendBitLocker=enable" `
                    -Wait -NoNewWindow
                Update-Status "Dell driver update complete"
            } else {
                Update-Status "dcu-cli.exe not found - drivers update on next boot" $true
            }
        } else {
            Update-Status "Dell Command Update unavailable - check internet" $true
        }

    } elseif ($isLenovo) {
        Update-Status "Lenovo detected - installing Lenovo System Update..."
        $lsuInstalled = $false
        try {
            $wgResult = Start-Process "winget" `
                -ArgumentList "install --id Lenovo.SystemUpdate --silent --accept-package-agreements --accept-source-agreements" `
                -Wait -PassThru -NoNewWindow
            if ($wgResult.ExitCode -eq 0) { $lsuInstalled = $true; Update-Status "Lenovo System Update installed" }
        } catch { }

        if (-not $lsuInstalled) {
            $lsuUrl  = "https://download.lenovo.com/pccbbs/thinkvantage_en/system_update_5.08.03.26.exe"
            $lsuPath = "$tempDir\LenovoSystemUpdate.exe"
            if (Download-File -Url $lsuUrl -Dest $lsuPath -Label "Lenovo System Update") {
                Start-Process -FilePath $lsuPath -ArgumentList "/VERYSILENT /NORESTART" -Wait
                $lsuInstalled = $true
                Update-Status "Lenovo System Update installed"
            }
        }

        if ($lsuInstalled) {
            Update-Status "Running Lenovo driver update..."
            $tvsuPath = "C:\Program Files (x86)\Lenovo\System Update\tvsuCommandLauncher.exe"
            if (Test-Path $tvsuPath) {
                Start-Process -FilePath $tvsuPath `
                    -ArgumentList "Action=AutoUpdate Scheduler=AutoSearch,AutoUpdate,Reboot" `
                    -Wait -NoNewWindow
                Update-Status "Lenovo driver update complete"
            } else {
                Update-Status "Lenovo launcher not found - updates on next run" $true
            }
        } else {
            Update-Status "Lenovo System Update unavailable - check internet" $true
        }

    } else {
        Update-Status "Unknown manufacturer: $manufacturer - skipping driver tool" $true
    }

    # =========================================================================
    # STEP 2 - RMM Agent
    # =========================================================================
    Update-Status "Downloading RMM Agent (ManageEngine)..."
    $rmmPath = "$tempDir\rmm.exe"
    if (Download-File -Url "https://tree.10bit.dev/install/rmm.exe" -Dest $rmmPath -Label "RMM Agent") {
        Update-Status "Installing RMM Agent..."
        Start-Process -FilePath $rmmPath -ArgumentList "/silent" -Wait
        Update-Status "RMM Agent installed - device will appear in Endpoint Central"
    }

    # =========================================================================
    # STEP 3 - MDM Agent (runs enrollment.bat from its own directory)
    # =========================================================================
    Update-Status "Downloading MDM Agent..."
    $mdmZip = "$tempDir\mdm.zip"
    $mdmDir = "$tempDir\mdm"
    if (Download-File -Url "https://tree.10bit.dev/install/mdm.zip" -Dest $mdmZip -Label "MDM Agent") {
        Update-Status "Extracting MDM Agent..."
        Expand-Archive -Path $mdmZip -DestinationPath $mdmDir -Force
        $enrollBat = Get-ChildItem -Path $mdmDir -Filter "enrollment.bat" -Recurse | Select-Object -First 1
        if (-not $enrollBat) {
            $enrollBat = Get-ChildItem -Path $mdmDir -Filter "*.bat" -Recurse | Select-Object -First 1
        }
        if ($enrollBat) {
            Update-Status "Running MDM enrollment: $($enrollBat.Name)"
            $process = Start-Process -FilePath "cmd.exe" `
                -ArgumentList "/c `"$($enrollBat.FullName)`"" `
                -WorkingDirectory $enrollBat.DirectoryName `
                -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -eq 0) {
                Update-Status "MDM Agent enrolled successfully"
            } else {
                Update-Status "MDM enrollment exit code: $($process.ExitCode) - check logs" $true
            }
        } else {
            Update-Status "No enrollment.bat found in MDM zip - manual enrollment needed" $true
        }
    }

    # =========================================================================
    # STEP 4 - Rename computer
    # =========================================================================
    Update-Status "Renaming computer to: $pcName"
    try {
        Rename-Computer -NewName $pcName -Force -ErrorAction Stop
        Update-Status "Computer renamed to: $pcName (takes effect after restart)"
    } catch {
        Update-Status "Could not rename: $_" $true
    }

    # =========================================================================
    # STEP 5 - Entra ID join (only if "Assign user now" was checked)
    # =========================================================================
    if ($assignNow) {
        Update-Status "Joining device to Microsoft Entra ID as: $userEmail"
        try {
            $joinResult = Start-Process -FilePath "$env:SystemRoot\System32\dsregcmd.exe" `
                -ArgumentList "/join /debug" `
                -Wait -PassThru -NoNewWindow
            Start-Sleep -Seconds 5

            $status = & "$env:SystemRoot\System32\dsregcmd.exe" /status 2>&1
            if ($status -match "AzureAdJoined\s+:\s+YES") {
                Update-Status "Device successfully joined to Microsoft Entra ID"
            } else {
                # Schedule join to complete at first user login
                Update-Status "Entra join pending - scheduling for first login..."
                $action   = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\dsregcmd.exe" -Argument "/join"
                $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $userEmail
                $settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable
                Register-ScheduledTask -TaskName "WITHIN-EntraJoin" `
                    -Action $action -Trigger $trigger -Settings $settings `
                    -RunLevel Highest -Force | Out-Null
                & cmdkey /add:"microsoftaccount:$userEmail" /user:$userEmail /pass:$userPass 2>&1 | Out-Null
                Update-Status "Entra join will complete on first user login"
            }
        } catch {
            Update-Status "Entra join error: $_" $true
            Update-Status "User can join via Settings > Accounts > Work/School" $true
        }
    } else {
        Update-Status "Spare mode - Entra join skipped"
        Update-Status "To assign later: Settings > Accounts > Access work or school"
        Update-Status "Or push via ManageEngine remote script when user is assigned"
    }

    # =========================================================================
    # STEP 6 - Save device info
    # =========================================================================
    $assignedUser = if ($assignNow) { $userEmail } else { "Unassigned (spare)" }
    $infoFile = "C:\Users\within\Desktop\device-info.txt"
    @"
WITHIN Device Info
==================
Computer Name : $pcName
Manufacturer  : $manufacturer
Model         : $model
Serial Number : $serial
Assigned User : $assignedUser
Setup Mode    : $(if ($spareMode) { "Spare" } else { "User Assigned" })
Setup Date    : $(Get-Date -Format "yyyy-MM-dd HH:mm")
Setup Log     : $LogFile

$(if ($spareMode) {
"NEXT STEPS FOR SPARE MACHINE:
- Machine is enrolled in ManageEngine Endpoint Central
- To assign user: Settings > Accounts > Access work or school
  Click 'Join this device to Microsoft Entra ID'
  Sign in with the user's within.co account
- Or use ManageEngine to push Entra join script remotely"
})
"@ | Out-File -FilePath $infoFile -Encoding UTF8
    Update-Status "Device info saved to desktop"

    # =========================================================================
    # DONE - Remove registry Run key so script does not relaunch after reboot
    # =========================================================================
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
            -Name "WITHINSetup" -ErrorAction SilentlyContinue
        Write-Log "Registry Run key removed - setup will not relaunch"
    } catch { }

    Update-Status "----------------------------"
    Update-Status "Setup complete! Restarting..."
    Update-Status "----------------------------"
    Write-Log "Setup complete - $pcName | $manufacturer $model | S/N: $serial | User: $assignedUser"

    $rebootNote = if ($isDell) { "BIOS set to AHCI - reboot required.`n`n" } else { "" }
    $nextSteps  = if ($spareMode) {
        "SPARE MACHINE - no user assigned.`n" +
        "ManageEngine is enrolled and will push software.`n`n" +
        "To assign a user later:`n" +
        "Settings > Accounts > Access work or school`n" +
        "Click 'Join this device to Microsoft Entra ID'"
    } else {
        "User $userEmail will be prompted to sign in`n" +
        "with their within.co account after restart.`n`n" +
        "ManageEngine will push all software automatically."
    }

    $msg = "Setup Complete!`n`n" +
           "  Computer : $pcName`n" +
           "  Vendor   : $vendorLabel`n" +
           "  Model    : $model`n" +
           "  Serial   : $serial`n`n" +
           $rebootNote + $nextSteps + "`n`n" +
           "Restarting in 30 seconds..."

    # Auto-closing summary window - no OK button needed, closes itself after 30s
    $summary = New-Object System.Windows.Forms.Form
    $summary.Text = "WITHIN Setup Complete"
    $summary.Size = New-Object System.Drawing.Size(480, 380)
    $summary.StartPosition = "CenterScreen"
    $summary.FormBorderStyle = "FixedDialog"
    $summary.MaximizeBox = $false
    $summary.MinimizeBox = $false
    $summary.TopMost = $true
    $summary.BackColor = [System.Drawing.Color]::White

    $summaryLbl = New-Object System.Windows.Forms.Label
    $summaryLbl.Text = $msg
    $summaryLbl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $summaryLbl.Location = New-Object System.Drawing.Point(20, 20)
    $summaryLbl.Size = New-Object System.Drawing.Size(440, 280)
    $summary.Controls.Add($summaryLbl)

    $countdownLbl = New-Object System.Windows.Forms.Label
    $countdownLbl.Text = "Restarting in 30 seconds..."
    $countdownLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $countdownLbl.ForeColor = [System.Drawing.Color]::Gray
    $countdownLbl.Location = New-Object System.Drawing.Point(20, 310)
    $countdownLbl.Size = New-Object System.Drawing.Size(440, 22)
    $summary.Controls.Add($countdownLbl)

    $summary.Show()

    for ($i = 30; $i -gt 0; $i--) {
        $countdownLbl.Text = "Restarting in ${i} seconds..."
        $btn.Text = "Restarting in ${i}s..."
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 1
    }

    $summary.Close()
    Write-Log "Restarting computer"
    Restart-Computer -Force
})

[System.Windows.Forms.Application]::Run($form)
