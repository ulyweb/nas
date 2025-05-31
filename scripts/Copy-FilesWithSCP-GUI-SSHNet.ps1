<#
.SYNOPSIS
    Provides a GUI to copy files to a remote server using SSH.NET, featuring a GUI password prompt.
.DESCRIPTION
    This script presents a Windows Forms interface to:
    - Specify a source file path, directory, or pattern (default: 'c:\yt\*').
    - Optionally specify a year for a subdirectory on the remote server.
    - Enter a password via a GUI field.
    - Copy files to a predefined remote server ('root@10.17.76.30') and base directory ('/usb8tb/Shared/Public/Media/Movies/').

    Features:
    - Uses the SSH.NET library (Renci.SshNet.dll) for all SSH and SCP operations.
    - GUI-based password entry.
    - Attempts to create the target directory on the remote server.
    - Handles single file, directory (recursive), and wildcard (*) source uploads.
    - Attempts to verify the copy by listing files in the remote directory.
    - Displays status messages and command outputs within the GUI.

    Requirements:
    - Renci.SshNet.dll: Must be present in the same directory as this script.
    - Network connectivity to the remote server.
    - Appropriate permissions on the remote server.
.EXAMPLE
    .\Copy-FilesWithSCP-GUI-SSHNet.ps1
    (Ensure Renci.SshNet.dll is in the same directory. The GUI window will appear.)
#>

# --- Try to Load SSH.NET Assembly ---
$SshNetDllPath = Join-Path $PSScriptRoot "Renci.SshNet.dll"
try {
    Add-Type -Path $SshNetDllPath -ErrorAction Stop
    Write-Host "[INFO] Renci.SshNet.dll loaded successfully from $SshNetDllPath" -ForegroundColor Cyan
}
catch {
    Write-Error "[FATAL] Renci.SshNet.dll not found or could not be loaded from '$SshNetDllPath'."
    Write-Error "Please download Renci.SshNet.dll and place it in the same directory as this script."
    Write-Error "You can find it on NuGet (package SSH.NET) or the SSH.NET project website."
    
    # Attempt to show a Windows Forms error if possible, then exit
    try { Add-Type -AssemblyName System.Windows.Forms } catch {}
    if ([System.Windows.Forms.Application]::MessageLoop) { # Check if a message loop exists (e.g., if ISE is running)
         [System.Windows.Forms.MessageBox]::Show("Renci.SshNet.dll not found or could not be loaded from '$SshNetDllPath'.`nPlease download it and place it in the same directory as this script.`nScript will now exit.", "Missing DLL", "OK", "Error")
    }
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

# --- Helper Function to Add Messages to RichTextBox (same as before, ensure it's defined) ---
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
        $currentFont = $richTextBox.SelectionFont | Select-Object -First 1 # Ensure we get a single font object
        if ($IsBold) {
            $richTextBox.SelectionFont = New-Object System.Drawing.Font($currentFont.FontFamily, $currentFont.Size, [System.Drawing.FontStyle]::Bold)
        } else {
            $richTextBox.SelectionFont = New-Object System.Drawing.Font($currentFont.FontFamily, $currentFont.Size, [System.Drawing.FontStyle]::Regular)
        }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $richTextBox.AppendText("[$timestamp] $Message`r`n")
        if ($IsBold) { # Reset font
             $richTextBox.SelectionFont = New-Object System.Drawing.Font($currentFont.FontFamily, $currentFont.Size, [System.Drawing.FontStyle]::Regular)
        }
        $richTextBox.ScrollToCaret()
    }
}


# --- GUI Elements Creation ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Secure File Copier (SSH.NET)"
$form.Size = New-Object System.Drawing.Size(700, 600) # Increased height for password
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$defaultFont = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Font = $defaultFont

$yPos = 20

# Static Info Display
$lblStaticInfo = New-Object System.Windows.Forms.Label
$lblStaticInfo.Text = "Host: $sshHost (Port: $sshPort)`nUsername: $sshUsername`nBase Remote Path: $staticRemoteBaseDirectory"
$lblStaticInfo.Location = New-Object System.Drawing.Point(20, $yPos)
$lblStaticInfo.AutoSize = $true
$form.Controls.Add($lblStaticInfo)
$yPos += $lblStaticInfo.Height + 15

# Password Label
$lblPassword = New-Object System.Windows.Forms.Label
$lblPassword.Text = "Password for $sshUsername@$sshHost:"
$lblPassword.Location = New-Object System.Drawing.Point(20, $yPos)
$lblPassword.AutoSize = $true
$form.Controls.Add($lblPassword)
$yPos += $lblPassword.Height + 5

# Password TextBox
$txtPassword = New-Object System.Windows.Forms.TextBox
$txtPassword.Location = New-Object System.Drawing.Point(20, $yPos)
$txtPassword.Size = New-Object System.Drawing.Size(300, 25)
$txtPassword.PasswordChar = '*'
$form.Controls.Add($txtPassword)
$yPos += $txtPassword.Height + 15

# Source File Path Label
$lblSourcePath = New-Object System.Windows.Forms.Label
$lblSourcePath.Text = "Source File/Directory/Pattern:"
$lblSourcePath.Location = New-Object System.Drawing.Point(20, $yPos)
$lblSourcePath.AutoSize = $true
$form.Controls.Add($lblSourcePath)
$yPos += $lblSourcePath.Height + 5

# Source File Path TextBox
$txtSourcePath = New-Object System.Windows.Forms.TextBox
$txtSourcePath.Text = $defaultSourcePathPattern
$txtSourcePath.Location = New-Object System.Drawing.Point(20, $yPos)
$txtSourcePath.Size = New-Object System.Drawing.Size(540, 25)
$form.Controls.Add($txtSourcePath)

# Browse Button for Source File
$btnBrowseSource = New-Object System.Windows.Forms.Button
$btnBrowseSource.Text = "Browse File..."
$btnBrowseSource.Location = New-Object System.Drawing.Point(570, $yPos - 2) # Align with textbox
$btnBrowseSource.Size = New-Object System.Drawing.Size(100, 29)
$form.Controls.Add($btnBrowseSource)
$yPos += $txtSourcePath.Height + 5

# Browse Button for Source Directory
$btnBrowseFolder = New-Object System.Windows.Forms.Button
$btnBrowseFolder.Text = "Browse Folder..."
$btnBrowseFolder.Location = New-Object System.Drawing.Point(570, $yPos -2 + $txtSourcePath.Height - 25) # Below previous browse
$btnBrowseFolder.Size = New-Object System.Drawing.Size(100, 29)
#$form.Controls.Add($btnBrowseFolder) # Re-enable if desired
$yPos += $btnBrowseFolder.Height + 10


# Year Label
$lblYear = New-Object System.Windows.Forms.Label
$lblYear.Text = "Year (optional, for subfolder like '2023'):"
$lblYear.Location = New-Object System.Drawing.Point(20, $yPos)
$lblYear.AutoSize = $true
$form.Controls.Add($lblYear)
$yPos += $lblYear.Height + 5

# Year TextBox
$txtYear = New-Object System.Windows.Forms.TextBox
$txtYear.Location = New-Object System.Drawing.Point(20, $yPos)
$txtYear.Size = New-Object System.Drawing.Size(150, 25)
$txtYear.Text = (Get-Date -Format "yyyy")
$form.Controls.Add($txtYear)
$yPos += $txtYear.Height + 15

# Start Copy Button
$btnStartCopy = New-Object System.Windows.Forms.Button
$btnStartCopy.Text = "Start Copy"
$btnStartCopy.Location = New-Object System.Drawing.Point(20, $yPos)
$btnStartCopy.Size = New-Object System.Drawing.Size(150, 35)
$btnStartCopy.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnStartCopy.BackColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($btnStartCopy)
$yPos += $btnStartCopy.Height + 10

# Status Output RichTextBox
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status & Output:"
$lblStatus.Location = New-Object System.Drawing.Point(20, $yPos)
$lblStatus.AutoSize = $true
$form.Controls.Add($lblStatus)
$yPos += $lblStatus.Height + 5

$rtbStatus = New-Object System.Windows.Forms.RichTextBox
$rtbStatus.Location = New-Object System.Drawing.Point(20, $yPos)
$rtbStatus.Size = New-Object System.Drawing.Size(640, $form.ClientSize.Height - $yPos - 20) # Adjust to fill remaining space
$rtbStatus.ReadOnly = $true
$rtbStatus.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$rtbStatus.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$form.Controls.Add($rtbStatus)

# --- Event Handlers ---
$btnBrowseSource.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Select Source File"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSourcePath.Text = $openFileDialog.FileName
    }
})

# $btnBrowseFolder.Add_Click({ # Re-enable if desired
# $folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
# $folderBrowserDialog.Description = "Select Source Directory"
# if ($folderBrowserDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
# $txtSourcePath.Text = $folderBrowserDialog.SelectedPath
# }
# })


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

    # Construct full remote path
    $fullRemotePathDir = $staticRemoteBaseDirectory
    if (-not [string]::IsNullOrWhiteSpace($yearInput)) {
        $yearCleaned = $yearInput.Trim('/')
        $fullRemotePathDir = "$($staticRemoteBaseDirectory.TrimEnd('/'))/$yearCleaned/"
    }
    if (-not $fullRemotePathDir.EndsWith("/")) { $fullRemotePathDir += "/" }
    Add-StatusMessage -richTextBox $rtbStatus -Message "Target remote directory: '$fullRemotePathDir'"

    try {
        # 1. Create SSH Connection Info
        $connectionInfo = New-Object Renci.SshNet.PasswordConnectionInfo($sshHost, $sshPort, $sshUsername, $password)
        $connectionInfo.Timeout = [TimeSpan]::FromSeconds(20) # Connection timeout

        # 2. Create Remote Directory using SshClient
        Add-StatusMessage -richTextBox $rtbStatus -Message "Connecting to $sshHost to create directory..." -Color ([System.Drawing.Color]::DarkCyan)
        using ($ssh = New-Object Renci.SshNet.SshClient($connectionInfo)) {
            $ssh.Connect()
            Add-StatusMessage -richTextBox $rtbStatus -Message "Connected. Creating remote directory '$fullRemotePathDir' (if not exists)..."
            $mkdirCommand = $ssh.CreateCommand("mkdir -p '${fullRemotePathDir}'") # Use single quotes for remote shell
            $mkdirCommand.Execute()
            if ($mkdirCommand.ExitStatus -ne 0) {
                Add-StatusMessage -richTextBox $rtbStatus -Message "ERROR creating remote directory: $($mkdirCommand.Error)" -Color ([System.Drawing.Color]::Red) -IsBold $true
                throw "Failed to create remote directory. Exit status: $($mkdirCommand.ExitStatus)"
            }
            Add-StatusMessage -richTextBox $rtbStatus -Message "Remote directory task completed." -Color ([System.Drawing.Color]::Green)
            $ssh.Disconnect()
        }
        $form.Update()

        # 3. Upload files/directories using ScpClient
        Add-StatusMessage -richTextBox $rtbStatus -Message "Preparing to upload files..." -Color ([System.Drawing.Color]::DarkCyan)
        using ($scp = New-Object Renci.SshNet.ScpClient($connectionInfo)) {
            $scp.Connect()
            Add-StatusMessage -richTextBox $rtbStatus -Message "SCP client connected. Starting upload(s) to '$fullRemotePathDir'."

            # Resolve source path (file, directory, or wildcard)
            if (Test-Path -Path $sourcePathInput -PathType Container) { # It's a directory
                Add-StatusMessage -richTextBox $rtbStatus -Message "Source is a directory: '$sourcePathInput'. Uploading recursively."
                $dirInfo = Get-Item -Path $sourcePathInput
                $scp.Upload($dirInfo, $fullRemotePathDir) # Uploads directory recursively
                Add-StatusMessage -richTextBox $rtbStatus -Message "Directory '$($dirInfo.Name)' uploaded." -Color ([System.Drawing.Color]::Green)
            } elseif (Test-Path -Path $sourcePathInput -PathType Leaf) { # It's a single file
                 Add-StatusMessage -richTextBox $rtbStatus -Message "Source is a single file: '$sourcePathInput'. Uploading."
                 $fileInfo = Get-Item -Path $sourcePathInput
                 $scp.Upload($fileInfo, $fullRemotePathDir + $fileInfo.Name) # Specify remote file name
                 Add-StatusMessage -richTextBox $rtbStatus -Message "File '$($fileInfo.Name)' uploaded." -Color ([System.Drawing.Color]::Green)
            } elseif ($sourcePathInput.Contains("*") -or $sourcePathInput.Contains("?")) { # It's a wildcard pattern
                Add-StatusMessage -richTextBox $rtbStatus -Message "Source is a wildcard pattern: '$sourcePathInput'. Resolving items..."
                $itemsToUpload = Get-ChildItem -Path $sourcePathInput -ErrorAction SilentlyContinue
                if ($itemsToUpload.Count -eq 0) {
                    Add-StatusMessage -richTextBox $rtbStatus -Message "No items found matching pattern '$sourcePathInput'." -Color ([System.Drawing.Color]::OrangeRed)
                } else {
                    foreach ($item in $itemsToUpload) {
                        Add-StatusMessage -richTextBox $rtbStatus -Message "Uploading '$($item.FullName)'..."
                        if ($item -is [System.IO.DirectoryInfo]) {
                            $scp.Upload($item, $fullRemotePathDir) # Upload directory recursively
                            Add-StatusMessage -richTextBox $rtbStatus -Message "Directory '$($item.Name)' uploaded." -Color ([System.Drawing.Color]::Green)
                        } elseif ($item -is [System.IO.FileInfo]) {
                            $scp.Upload($item, $fullRemotePathDir + $item.Name) # Specify remote file name
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

        # 4. Verification step using SshClient
        Add-StatusMessage -richTextBox $rtbStatus -Message "Verifying by listing remote directory '$fullRemotePathDir'..." -Color ([System.Drawing.Color]::DarkCyan)
        using ($ssh = New-Object Renci.SshNet.SshClient($connectionInfo)) {
            $ssh.Connect()
            $listCommandText = "ls -lah '${fullRemotePathDir}'" # Single quotes for remote shell
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
        # Clear password from memory (TextBox still holds it, but variable is out of scope)
        Clear-Variable -Name password -ErrorAction SilentlyContinue 
    }
})

# --- Show the Form ---
$form.TopMost = $true 
$form.ShowDialog() | Out-Null
$form.TopMost = $false
$form.Dispose()
