<#
.SYNOPSIS
    Provides a GUI to copy files to a remote server using SSH.NET,
    featuring a GUI password prompt and automatic download of Renci.SshNet.dll if missing.
.DESCRIPTION
    This script presents a Windows Forms interface to:
    - Specify a source file path, directory, or pattern (default: 'c:\yt\*').
    - Optionally specify a year for a subdirectory on the remote server.
    - Enter a password via a GUI field.
    - Copy files to a predefined remote server ('root@10.17.76.30') and base directory ('/usb8tb/Shared/Public/Media/Movies/').

    Features:
    - Attempts to automatically download and place Renci.SshNet.dll if not found in the script's directory.
    - Uses the SSH.NET library for all SSH and SCP operations.
    - GUI-based password entry.
    - Attempts to create the target directory on the remote server.
    - Handles single file, directory (recursive), and wildcard (*) source uploads.
    - Attempts to verify the copy by listing files in the remote directory.
    - Displays status messages and command outputs within the GUI.

    Requirements:
    - PowerShell 5.0 or newer (for Expand-Archive).
    - Internet access if Renci.SshNet.dll needs to be downloaded.
    - Network connectivity to the remote server.
    - Appropriate permissions on the remote server.
.EXAMPLE
    .\Copy-FilesWithSCP-GUI-AutoDownload.ps1
    (If Renci.SshNet.dll is missing, the script will attempt to download it.)
#>

# --- Function to Ensure Renci.SshNet.dll is Available ---
function Ensure-SshNetDll {
    param (
        [string]$ScriptRootPath
    )

    $dllName = "Renci.SshNet.dll"
    $dllFullPath = Join-Path $ScriptRootPath $dllName
    $nuGetPackageId = "SSH.NET"
    # Try to get the latest stable version. If this fails, fallback to a known recent version.
    $nuGetPackageVersion = "2024.1.0" # Fallback version

    if (Test-Path $dllFullPath) {
        Write-Host "[INFO] Found $dllName at $dllFullPath." -ForegroundColor Green
        return $dllFullPath
    }

    Write-Warning "[WARN] $dllName not found. Attempting to download from NuGet..."

    try {
        # Attempt to find the latest version from NuGet API
        $versionsUrl = "https://api.nuget.org/v3-flatcontainer/$($nuGetPackageId.ToLower())/index.json"
        $versionsResponse = Invoke-RestMethod -Uri $versionsUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($versionsResponse -and $versionsResponse.versions) {
            # Filter out pre-release versions if any, take the last one (usually latest stable)
            $latestStable = $versionsResponse.versions | Where-Object { $_ -notmatch "-"} | Select-Object -Last 1
            if ($latestStable) {
                $nuGetPackageVersion = $latestStable
                Write-Host "[INFO] Determined latest stable version of $nuGetPackageId to be $nuGetPackageVersion." -ForegroundColor Cyan
            }
        } else {
            Write-Warning "[WARN] Could not dynamically determine latest version. Using fallback: $nuGetPackageVersion."
        }
    } catch {
        Write-Warning "[WARN] Error fetching latest version info for $nuGetPackageId: $($_.Exception.Message). Using fallback: $nuGetPackageVersion."
    }

    $nupkgFileName = "$($nuGetPackageId.ToLower()).$nuGetPackageVersion.nupkg"
    $nupkgUrl = "https://api.nuget.org/v3-flatcontainer/$($nuGetPackageId.ToLower())/$nuGetPackageVersion/$nupkgFileName"
    $nupkgTempPath = Join-Path $ScriptRootPath $nupkgFileName
    $extractionPath = Join-Path $ScriptRootPath "_temp_$nuGetPackageId"

    try {
        Write-Host "[INFO] Downloading $nupkgUrl to $nupkgTempPath..."
        Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgTempPath -TimeoutSec 180 # 3 min timeout for download
        Write-Host "[INFO] Download complete."

        if (Test-Path $extractionPath) {
            Remove-Item -Path $extractionPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $extractionPath -Force | Out-Null

        Write-Host "[INFO] Extracting $nupkgTempPath to $extractionPath..."
        Expand-Archive -Path $nupkgTempPath -DestinationPath $extractionPath -Force
        Write-Host "[INFO] Extraction complete."

        # Common paths for the DLL within the nupkg structure. Prioritize netstandard2.0.
        $possibleDllPathsInNupkg = @(
            "lib/netstandard2.0/$dllName",
            "lib/netstandard2.1/$dllName",
            "lib/net462/$dllName", # .NET Framework 4.6.2, good fallback for WinPS 5.1
            "lib/net40/$dllName"   # Older .NET Framework
        )

        $foundDllInNupkg = $null
        foreach ($pathSuffix in $possibleDllPathsInNupkg) {
            $potentialPath = Join-Path $extractionPath $pathSuffix
            if (Test-Path $potentialPath) {
                $foundDllInNupkg = $potentialPath
                Write-Host "[INFO] Found $dllName at $foundDllInNupkg inside package." -ForegroundColor Cyan
                break
            }
        }

        if ($foundDllInNupkg) {
            Copy-Item -Path $foundDllInNupkg -Destination $dllFullPath -Force
            Write-Host "[SUCCESS] $dllName copied to $dllFullPath." -ForegroundColor Green
            return $dllFullPath
        } else {
            throw "$dllName not found within the extracted NuGet package in expected lib folders."
        }
    }
    catch {
        Write-Error "[FATAL] Failed to download or process $nuGetPackageId: $($_.Exception.Message)"
        Write-Error "Please manually download Renci.SshNet.dll and place it in $ScriptRootPath."
        Write-Error "You can find it on NuGet (package SSH.NET) or the SSH.NET project website."
        return $null
    }
    finally {
        if (Test-Path $nupkgTempPath) { Remove-Item -Path $nupkgTempPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $extractionPath) { Remove-Item -Path $extractionPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# --- Attempt to Ensure and Load SSH.NET Assembly ---
$SshNetDllFullPath = Ensure-SshNetDll -ScriptRootPath $PSScriptRoot
if (-not $SshNetDllFullPath -or -not (Test-Path $SshNetDllFullPath)) {
    # Error message already shown by Ensure-SshNetDll
    # Attempt to show a Windows Forms error if possible, then exit
    try { Add-Type -AssemblyName System.Windows.Forms } catch {}
    if ([System.Windows.Forms.Application]::MessageLoop) {
         [System.Windows.Forms.MessageBox]::Show("Renci.SshNet.dll is required but could not be automatically obtained.`nPlease ensure it's in the script directory: $PSScriptRoot `nScript will now exit.", "Missing Critical DLL", "OK", "Error")
    } else {
        Write-Host "If a GUI is intended, it may not appear due to the missing DLL."
    }
    exit 1
}

try {
    Add-Type -Path $SshNetDllFullPath -ErrorAction Stop
    Write-Host "[INFO] Renci.SshNet.dll loaded successfully." -ForegroundColor Green
}
catch {
    Write-Error "[FATAL] Failed to load $SshNetDllFullPath even after ensuring its presence: $($_.Exception.Message)"
    exit 1
}


# --- Load Required Assemblies for GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Static Configuration ---
$staticDestinationUserHostFull = "root@10.17.76.30"
$staticRemoteBaseDirectory = "/usb8tb/Shared/Public/Media/Movies/" # Must end with a slash
$defaultSourcePathPattern = "c:\yt\*"

# Parse Username and Host
$sshUsername = $staticDestinationUserHostFull.Split('@')[0]
$sshHost = $staticDestinationUserHostFull.Split('@')[1]
$sshPort = 22 # Default SSH port

# --- Helper Function to Add Messages to RichTextBox ---
function Add-StatusMessage {
    param (
        [System.Windows.Forms.RichTextBox]$richTextBox,
        [string]$Message,
        [System.Drawing.Color]$Color = ([System.Drawing.Color]::Black),
        [bool]$IsBold = $false
    )
    if ($richTextBox.InvokeRequired) {
        $action = [Action[System.Windows.Forms.RichTextBox, string, System.Drawing.Color, bool]] {
            param($rtbParam, $messageParam, $colorParam, $isBoldParam)
            & $script:Add-StatusMessage -richTextBox $rtbParam -Message $messageParam -Color $colorParam -IsBold $isBoldParam
        }
        $richTextBox.Invoke($action, $richTextBox, $Message, $Color, $IsBold)
    } else {
        $richTextBox.SelectionStart = $richTextBox.TextLength
        $richTextBox.SelectionLength = 0
        $richTextBox.SelectionColor = $Color
        $currentFont = $richTextBox.SelectionFont | Select-Object -First 1
        if ($IsBold) {
            $richTextBox.SelectionFont = New-Object System.Drawing.Font($currentFont.FontFamily, $currentFont.Size, [System.Drawing.FontStyle]::Bold)
        } else {
            $richTextBox.SelectionFont = New-Object System.Drawing.Font($currentFont.FontFamily, $currentFont.Size, [System.Drawing.FontStyle]::Regular)
        }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $richTextBox.AppendText("[$timestamp] $Message`r`n")
        if ($IsBold) {
             $richTextBox.SelectionFont = New-Object System.Drawing.Font($currentFont.FontFamily, $currentFont.Size, [System.Drawing.FontStyle]::Regular)
        }
        $richTextBox.ScrollToCaret()
    }
}

# --- GUI Elements Creation (Identical to previous version) ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Secure File Copier (SSH.NET - Auto)"
$form.Size = New-Object System.Drawing.Size(700, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$defaultFont = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Font = $defaultFont

$yPos = 20
$lblStaticInfo = New-Object System.Windows.Forms.Label
$lblStaticInfo.Text = "Host: $sshHost (Port: $sshPort)`nUsername: $sshUsername`nBase Remote Path: $staticRemoteBaseDirectory"
$lblStaticInfo.Location = New-Object System.Drawing.Point(20, $yPos)
$lblStaticInfo.AutoSize = $true
$form.Controls.Add($lblStaticInfo)
$yPos += $lblStaticInfo.Height + 15

$lblPassword = New-Object System.Windows.Forms.Label
$lblPassword.Text = "Password for $sshUsername@$sshHost:"
$lblPassword.Location = New-Object System.Drawing.Point(20, $yPos)
$lblPassword.AutoSize = $true
$form.Controls.Add($lblPassword)
$yPos += $lblPassword.Height + 5

$txtPassword = New-Object System.Windows.Forms.TextBox
$txtPassword.Location = New-Object System.Drawing.Point(20, $yPos)
$txtPassword.Size = New-Object System.Drawing.Size(300, 25)
$txtPassword.PasswordChar = '*'
$form.Controls.Add($txtPassword)
$yPos += $txtPassword.Height + 15

$lblSourcePath = New-Object System.Windows.Forms.Label
$lblSourcePath.Text = "Source File/Directory/Pattern:"
$lblSourcePath.Location = New-Object System.Drawing.Point(20, $yPos)
$lblSourcePath.AutoSize = $true
$form.Controls.Add($lblSourcePath)
$yPos += $lblSourcePath.Height + 5

$txtSourcePath = New-Object System.Windows.Forms.TextBox
$txtSourcePath.Text = $defaultSourcePathPattern
$txtSourcePath.Location = New-Object System.Drawing.Point(20, $yPos)
$txtSourcePath.Size = New-Object System.Drawing.Size(540, 25)
$form.Controls.Add($txtSourcePath)

$btnBrowseSource = New-Object System.Windows.Forms.Button
$btnBrowseSource.Text = "Browse File..."
$btnBrowseSource.Location = New-Object System.Drawing.Point(570, $yPos - 2)
$btnBrowseSource.Size = New-Object System.Drawing.Size(100, 29)
$form.Controls.Add($btnBrowseSource)
$yPos += $txtSourcePath.Height + 15 # Adjusted spacing

$lblYear = New-Object System.Windows.Forms.Label
$lblYear.Text = "Year (optional, for subfolder like '2023'):"
$lblYear.Location = New-Object System.Drawing.Point(20, $yPos)
$lblYear.AutoSize = $true
$form.Controls.Add($lblYear)
$yPos += $lblYear.Height + 5

$txtYear = New-Object System.Windows.Forms.TextBox
$txtYear.Location = New-Object System.Drawing.Point(20, $yPos)
$txtYear.Size = New-Object System.Drawing.Size(150, 25)
$txtYear.Text = (Get-Date -Format "yyyy")
$form.Controls.Add($txtYear)
$yPos += $txtYear.Height + 15

$btnStartCopy = New-Object System.Windows.Forms.Button
$btnStartCopy.Text = "Start Copy"
$btnStartCopy.Location = New-Object System.Drawing.Point(20, $yPos)
$btnStartCopy.Size = New-Object System.Drawing.Size(150, 35)
$btnStartCopy.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnStartCopy.BackColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($btnStartCopy)
$yPos += $btnStartCopy.Height + 10

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status & Output:"
$lblStatus.Location = New-Object System.Drawing.Point(20, $yPos)
$lblStatus.AutoSize = $true
$form.Controls.Add($lblStatus)
$yPos += $lblStatus.Height + 5

$rtbStatus = New-Object System.Windows.Forms.RichTextBox
$rtbStatus.Location = New-Object System.Drawing.Point(20, $yPos)
$rtbStatus.Size = New-Object System.Drawing.Size(640, $form.ClientSize.Height - $yPos - 20)
$rtbStatus.ReadOnly = $true
$rtbStatus.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$rtbStatus.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$form.Controls.Add($rtbStatus)

# --- Event Handlers (Identical to previous version) ---
$btnBrowseSource.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Select Source File"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSourcePath.Text = $openFileDialog.FileName
    }
})

$btnStartCopy.Add_Click({
    $btnStartCopy.Enabled = $false
    $btnStartCopy.Text = "Processing..."
    $rtbStatus.Clear()
    $form.Update()

    Add-StatusMessage -richTextBox $rtbStatus -Message "Operation Started." -Color ([System.Drawing.Color]::Blue) -IsBold $true

    $password = $txtPassword.Text
    $sourcePathInput = $txtSourcePath.Text
    $yearInput = $txtYear.Text

    if ([string]::IsNullOrWhiteSpace($password)) {
        Add-StatusMessage -richTextBox $rtbStatus -Message "Password cannot be empty." -Color ([System.Drawing.Color]::Red) -IsBold $true
        $btnStartCopy.Enabled = $true; $btnStartCopy.Text = "Start Copy"; return
    }
    if ([string]::IsNullOrWhiteSpace($sourcePathInput)) {
        Add-StatusMessage -richTextBox $rtbStatus -Message "Source path cannot be empty." -Color ([System.Drawing.Color]::Red) -IsBold $true
        $btnStartCopy.Enabled = $true; $btnStartCopy.Text = "Start Copy"; return
    }

    $fullRemotePathDir = $staticRemoteBaseDirectory
    if (-not [string]::IsNullOrWhiteSpace($yearInput)) {
        $yearCleaned = $yearInput.Trim('/')
        $fullRemotePathDir = "$($staticRemoteBaseDirectory.TrimEnd('/'))/$yearCleaned/"
    }
    if (-not $fullRemotePathDir.EndsWith("/")) { $fullRemotePathDir += "/" }
    Add-StatusMessage -richTextBox $rtbStatus -Message "Target remote directory: '$fullRemotePathDir'"

    try {
        $connectionInfo = New-Object Renci.SshNet.PasswordConnectionInfo($sshHost, $sshPort, $sshUsername, $password)
        $connectionInfo.Timeout = [TimeSpan]::FromSeconds(20)

        Add-StatusMessage -richTextBox $rtbStatus -Message "Connecting to $sshHost to create directory..." -Color ([System.Drawing.Color]::DarkCyan)
        using ($ssh = New-Object Renci.SshNet.SshClient($connectionInfo)) {
            $ssh.Connect()
            Add-StatusMessage -richTextBox $rtbStatus -Message "Connected. Creating remote directory '$fullRemotePathDir' (if not exists)..."
            $mkdirCommand = $ssh.CreateCommand("mkdir -p '${fullRemotePathDir}'")
            $mkdirCommand.Execute()
            if ($mkdirCommand.ExitStatus -ne 0) {
                Add-StatusMessage -richTextBox $rtbStatus -Message "ERROR creating remote directory: $($mkdirCommand.Error)" -Color ([System.Drawing.Color]::Red) -IsBold $true
                throw "Failed to create remote directory. Exit status: $($mkdirCommand.ExitStatus)"
            }
            Add-StatusMessage -richTextBox $rtbStatus -Message "Remote directory task completed." -Color ([System.Drawing.Color]::Green)
            $ssh.Disconnect()
        }
        $form.Update()

        Add-StatusMessage -richTextBox $rtbStatus -Message "Preparing to upload files..." -Color ([System.Drawing.Color]::DarkCyan)
        using ($scp = New-Object Renci.SshNet.ScpClient($connectionInfo)) {
            $scp.Connect()
            Add-StatusMessage -richTextBox $rtbStatus -Message "SCP client connected. Starting upload(s) to '$fullRemotePathDir'."

            if (Test-Path -Path $sourcePathInput -PathType Container) {
                Add-StatusMessage -richTextBox $rtbStatus -Message "Source is a directory: '$sourcePathInput'. Uploading recursively."
                $dirInfo = Get-Item -Path $sourcePathInput
                $scp.Upload($dirInfo, $fullRemotePathDir)
                Add-StatusMessage -richTextBox $rtbStatus -Message "Directory '$($dirInfo.Name)' uploaded." -Color ([System.Drawing.Color]::Green)
            } elseif (Test-Path -Path $sourcePathInput -PathType Leaf) {
                 Add-StatusMessage -richTextBox $rtbStatus -Message "Source is a single file: '$sourcePathInput'. Uploading."
                 $fileInfo = Get-Item -Path $sourcePathInput
                 $scp.Upload($fileInfo, ($fullRemotePathDir + $fileInfo.Name))
                 Add-StatusMessage -richTextBox $rtbStatus -Message "File '$($fileInfo.Name)' uploaded." -Color ([System.Drawing.Color]::Green)
            } elseif ($sourcePathInput.Contains("*") -or $sourcePathInput.Contains("?")) {
                Add-StatusMessage -richTextBox $rtbStatus -Message "Source is a wildcard pattern: '$sourcePathInput'. Resolving items..."
                $itemsToUpload = Get-ChildItem -Path $sourcePathInput -ErrorAction SilentlyContinue
                if ($itemsToUpload.Count -eq 0) {
                    Add-StatusMessage -richTextBox $rtbStatus -Message "No items found matching pattern '$sourcePathInput'." -Color ([System.Drawing.Color]::OrangeRed)
                } else {
                    foreach ($item in $itemsToUpload) {
                        Add-StatusMessage -richTextBox $rtbStatus -Message "Uploading '$($item.FullName)'..."
                        if ($item -is [System.IO.DirectoryInfo]) {
                            $scp.Upload($item, $fullRemotePathDir)
                            Add-StatusMessage -richTextBox $rtbStatus -Message "Directory '$($item.Name)' uploaded." -Color ([System.Drawing.Color]::Green)
                        } elseif ($item -is [System.IO.FileInfo]) {
                            $scp.Upload($item, ($fullRemotePathDir + $item.Name))
                            Add-StatusMessage -richTextBox $rtbStatus -Message "File '$($item.Name)' uploaded." -Color ([System.Drawing.Color]::Green)
                        }
                        $form.Update()
                    }
                }
            } else {
                 Add-StatusMessage -richTextBox $rtbStatus -Message "Source path '$sourcePathInput' not found or type not recognized." -Color ([System.Drawing.Color]::Red) -IsBold $true
                 throw "Source path not found or invalid."
            }
            $scp.Disconnect()
        }
        Add-StatusMessage -richTextBox $rtbStatus -Message "All SCP uploads completed." -Color ([System.Drawing.Color]::Green) -IsBold $true
        $form.Update()

        Add-StatusMessage -richTextBox $rtbStatus -Message "Verifying by listing remote directory '$fullRemotePathDir'..." -Color ([System.Drawing.Color]::DarkCyan)
        using ($ssh = New-Object Renci.SshNet.SshClient($connectionInfo)) {
            $ssh.Connect()
            $listCommandText = "ls -lah '${fullRemotePathDir}'"
            $listCommand = $ssh.CreateCommand($listCommandText)
            $listCommand.Execute()
            if ($listCommand.ExitStatus -eq 0) {
                Add-StatusMessage -richTextBox $rtbStatus -Message "Verification: Remote directory listing successful." -Color ([System.Drawing.Color]::Green)
                Add-StatusMessage -richTextBox $rtbStatus -Message "--- Remote Directory Contents ($fullRemotePathDir) ---" ([System.Drawing.Color]::Black) -IsBold $true
                Add-StatusMessage -richTextBox $rtbStatus -Message ($listCommand.Result) -Color ([System.Drawing.Color]::DarkSlateGray)
                Add-StatusMessage -richTextBox $rtbStatus -Message "--- End of Directory Contents ---" ([System.Drawing.Color]::Black) -IsBold $true
            } else {
                Add-StatusMessage -richTextBox $rtbStatus -Message "WARNING: Could not list files for verification. Exit: $($listCommand.ExitStatus). Error: $($listCommand.Error)" -Color ([System.Drawing.Color]::OrangeRed)
            }
            $ssh.Disconnect()
        }

    } catch [Renci.SshNet.Common.SshAuthenticationException] {
        Add-StatusMessage -richTextBox $rtbStatus -Message "SSH AUTHENTICATION FAILED: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red) -IsBold $true
        Add-StatusMessage -richTextBox $rtbStatus -Message "Please check your username and password." -Color ([System.Drawing.Color]::Red)
    } catch [Renci.SshNet.Common.SshConnectionException] {
        Add-StatusMessage -richTextBox $rtbStatus -Message "SSH CONNECTION FAILED: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red) -IsBold $true
        Add-StatusMessage -richTextBox $rtbStatus -Message "Ensure the host is reachable and SSH service is running." -Color ([System.Drawing.Color]::Red)
    } catch [System.Net.Sockets.SocketException] {
        Add-StatusMessage -richTextBox $rtbStatus -Message "NETWORK ERROR (Socket): $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red) -IsBold $true
        Add-StatusMessage -richTextBox $rtbStatus -Message "Check host address and network connectivity." -Color ([System.Drawing.Color]::Red)
    } catch {
        Add-StatusMessage -richTextBox $rtbStatus -Message "UNEXPECTED ERROR: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red) -IsBold $true
        Add-StatusMessage -richTextBox $rtbStatus -Message "Stack Trace: $($_.Exception.StackTrace)" -Color ([System.Drawing.Color]::DarkRed)
    } finally {
        Add-StatusMessage -richTextBox $rtbStatus -Message "Operation Finished." ([System.Drawing.Color]::Blue) -IsBold $true
        $btnStartCopy.Enabled = $true
        $btnStartCopy.Text = "Start Copy"
        Clear-Variable -Name password -ErrorAction SilentlyContinue 
    }
})

# --- Show the Form ---
# Check if DLL was loaded before trying to show a GUI that depends on it (implicitly)
if ($Global:SshNetDllFullPath -and (Test-Path $Global:SshNetDllFullPath)) { # Check if variable is set and path exists
    $form.TopMost = $true 
    $form.ShowDialog() | Out-Null
    $form.TopMost = $false
    $form.Dispose()
} else {
    Write-Error "SSH.NET DLL is not available. GUI cannot be launched. Please check console messages."
    # Potentially show a basic WinForms message box if Add-Type System.Windows.Forms worked
    try {
        if (-not ([System.Windows.Forms.Application]::MessageLoop)) { # Avoid error if already exited due to no GUI
            [System.Windows.Forms.MessageBox]::Show("SSH.NET DLL (Renci.SshNet.dll) is not available and could not be downloaded. The application cannot start.`nPlease check console messages for details and ensure internet connectivity if downloading, or place the DLL manually in the script's directory: $PSScriptRoot", "Critical Error - Missing DLL", "OK", "Error")
        }
    } catch {
        # If even WinForms isn't available, this will be caught. Console message is the fallback.
    }
}
