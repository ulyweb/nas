<#
.SYNOPSIS
    Provides a GUI to copy files to a remote server using SCP with some static/default values.
.DESCRIPTION
    This script presents a Windows Forms interface to:
    - Specify a source file path or pattern (default: 'c:\yt\*').
    - Optionally specify a year for a subdirectory on the remote server.
    - Copy files to a predefined remote server ('root@10.17.76.30') and base directory ('/usb8tb/Shared/Public/Media/Movies/').

    Features:
    - Attempts to create the target directory on the remote server.
    - Uses SCP for file transfer.
    - Attempts to verify the copy by listing files in the remote directory using SSH.
    - Displays status messages and command outputs within the GUI.

    Requirements:
    - OpenSSH client (scp.exe and ssh.exe) must be installed and in the system PATH.
    - Network connectivity to the remote server.
    - Appropriate permissions on the remote server.
.EXAMPLE-2
    .\Copy-FilesWithSCP-GUI.ps1
    (The GUI window will appear. Fill in the fields and click "Start Copy".)
#>

# --- Load Required Assemblies for GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Static Configuration (same as before) ---
$staticDestinationUserHost = "root@10.17.76.30"
$staticRemoteBaseDirectory = "/usb8tb/Shared/Public/Media/Movies/" # Must end with a slash
$defaultSourcePathPattern = "c:\yt\*"

# --- Helper Function to Add Messages to RichTextBox ---
function Add-StatusMessage {
    param (
        [System.Windows.Forms.RichTextBox]$richTextBox,
        [string]$Message,
        [System.Drawing.Color]$Color = ([System.Drawing.Color]::Black), # Default to Black
        [bool]$IsBold = $false
    )
    
    if ($richTextBox.InvokeRequired) {
        # Correctly create a delegate for Invoke
        $action = [Action[System.Windows.Forms.RichTextBox, string, System.Drawing.Color, bool]] {
            param($rtbParam, $messageParam, $colorParam, $isBoldParam)
            # Call the original function by its script scope name, ensuring it's treated as a command
            & $script:Add-StatusMessage -richTextBox $rtbParam -Message $messageParam -Color $colorParam -IsBold $isBoldParam
        }
        $richTextBox.Invoke($action, $richTextBox, $Message, $Color, $IsBold)
    } else {
        $richTextBox.SelectionStart = $richTextBox.TextLength
        $richTextBox.SelectionLength = 0
        $richTextBox.SelectionColor = $Color
        if ($IsBold) {
            $richTextBox.SelectionFont = New-Object System.Drawing.Font($richTextBox.Font, [System.Drawing.FontStyle]::Bold)
        } else {
            $richTextBox.SelectionFont = New-Object System.Drawing.Font($richTextBox.Font, [System.Drawing.FontStyle]::Regular)
        }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $richTextBox.AppendText("[$timestamp] $Message`r`n")
        if ($IsBold) { # Reset font to regular after bolded text
            $richTextBox.SelectionFont = New-Object System.Drawing.Font($richTextBox.Font, [System.Drawing.FontStyle]::Regular)
        }
        $richTextBox.ScrollToCaret()
    }
}

# --- GUI Elements Creation ---

# Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Secure File Copier to $staticDestinationUserHost"
$form.Size = New-Object System.Drawing.Size(700, 550) # Increased size for better layout
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog # Prevent resizing
$form.MaximizeBox = $false

# Font for labels and controls
$defaultFont = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Font = $defaultFont

# Static Info Display
$lblStaticInfo = New-Object System.Windows.Forms.Label
$lblStaticInfo.Text = "Destination Server: $staticDestinationUserHost`nBase Remote Path: $staticRemoteBaseDirectory"
$lblStaticInfo.Location = New-Object System.Drawing.Point(20, 20)
$lblStaticInfo.AutoSize = $true
$form.Controls.Add($lblStaticInfo)

# Source File Path Label
$lblSourcePath = New-Object System.Windows.Forms.Label
$lblSourcePath.Text = "Source File/Pattern:"
$lblSourcePath.Location = New-Object System.Drawing.Point(20, 70)
$lblSourcePath.AutoSize = $true
$form.Controls.Add($lblSourcePath)

# Source File Path TextBox
$txtSourcePath = New-Object System.Windows.Forms.TextBox
$txtSourcePath.Text = $defaultSourcePathPattern
$txtSourcePath.Location = New-Object System.Drawing.Point(20, 95)
$txtSourcePath.Size = New-Object System.Drawing.Size(540, 25)
$txtSourcePath.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($txtSourcePath)

# Browse Button for Source File
$btnBrowseSource = New-Object System.Windows.Forms.Button
$btnBrowseSource.Text = "Browse..."
$btnBrowseSource.Location = New-Object System.Drawing.Point(570, 93)
$btnBrowseSource.Size = New-Object System.Drawing.Size(90, 29)
$btnBrowseSource.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($btnBrowseSource)

# Year Label
$lblYear = New-Object System.Windows.Forms.Label
$lblYear.Text = "Year (optional, for subfolder like '2023'):"
$lblYear.Location = New-Object System.Drawing.Point(20, 135)
$lblYear.AutoSize = $true
$form.Controls.Add($lblYear)

# Year TextBox
$txtYear = New-Object System.Windows.Forms.TextBox
$txtYear.Location = New-Object System.Drawing.Point(20, 160)
$txtYear.Size = New-Object System.Drawing.Size(150, 25)
$txtYear.Text = (Get-Date -Format "yyyy") # Default to current year
$form.Controls.Add($txtYear)

# Start Copy Button
$btnStartCopy = New-Object System.Windows.Forms.Button
$btnStartCopy.Text = "Start Copy"
$btnStartCopy.Location = New-Object System.Drawing.Point(20, 200)
$btnStartCopy.Size = New-Object System.Drawing.Size(150, 35)
$btnStartCopy.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnStartCopy.BackColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($btnStartCopy)

# Status Output RichTextBox
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status & Output:"
$lblStatus.Location = New-Object System.Drawing.Point(20, 245)
$lblStatus.AutoSize = $true
$form.Controls.Add($lblStatus)

$rtbStatus = New-Object System.Windows.Forms.RichTextBox
$rtbStatus.Location = New-Object System.Drawing.Point(20, 270)
$rtbStatus.Size = New-Object System.Drawing.Size(640, 220)
$rtbStatus.ReadOnly = $true
$rtbStatus.Font = New-Object System.Drawing.Font("Consolas", 9)
$rtbStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$rtbStatus.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$form.Controls.Add($rtbStatus)


# --- Event Handlers ---

# Browse Button Click Event
$btnBrowseSource.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Select Source File or Enter Pattern Manually"
    # $openFileDialog.Filter = "All files (*.*)|*.*" # You can specify filters
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSourcePath.Text = $openFileDialog.FileName
    }
})

# Start Copy Button Click Event
$btnStartCopy.Add_Click({
    # Disable button to prevent multiple clicks
    $btnStartCopy.Enabled = $false
    $btnStartCopy.Text = "Copying..."
    $rtbStatus.Clear()

    Add-StatusMessage -richTextBox $rtbStatus -Message "Operation Started." -Color ([System.Drawing.Color]::Blue) -IsBold $true

    $sourcePathPattern = $txtSourcePath.Text
    $yearInput = $txtYear.Text

    if ([string]::IsNullOrWhiteSpace($sourcePathPattern)) {
        Add-StatusMessage -richTextBox $rtbStatus -Message "Source path pattern cannot be empty." -Color ([System.Drawing.Color]::Red) -IsBold $true
        $btnStartCopy.Enabled = $true
        $btnStartCopy.Text = "Start Copy"
        return
    }
    Add-StatusMessage -richTextBox $rtbStatus -Message "Using source: `"$sourcePathPattern`""

    # Construct full remote path
    $fullRemotePath = $staticRemoteBaseDirectory
    if (-not [string]::IsNullOrWhiteSpace($yearInput)) {
        $yearCleaned = $yearInput.Trim('/')
        $fullRemotePath = "$($staticRemoteBaseDirectory.TrimEnd('/'))/$yearCleaned/"
        Add-StatusMessage -richTextBox $rtbStatus -Message "Year subdirectory specified: '$yearCleaned'. Full remote path: '$fullRemotePath'"
    } else {
        Add-StatusMessage -richTextBox $rtbStatus -Message "No year specified. Files will be copied to base: '$fullRemotePath'"
    }
    if (-not $fullRemotePath.EndsWith("/")) { $fullRemotePath += "/" }

    Add-StatusMessage -richTextBox $rtbStatus -Message "Final destination target: $($staticDestinationUserHost):$($fullRemotePath)"

    # Force UI update before long operation
    $form.Update() 

    # 1. Attempt to create remote directory
    Add-StatusMessage -richTextBox $rtbStatus -Message "Attempting to create remote directory (if needed): $fullRemotePath" -Color ([System.Drawing.Color]::DarkCyan)
    $mkdirCommand = "mkdir -p '${fullRemotePath}'" # Single quotes for remote shell
    $sshMkdirArgs = @($staticDestinationUserHost, $mkdirCommand)
    
    try {
        $mkdirOutput = ssh @sshMkdirArgs 2>&1 # Capture stdout and stderr
        if ($LASTEXITCODE -eq 0) {
            Add-StatusMessage -richTextBox $rtbStatus -Message "Remote directory task completed successfully (or directory already existed)." -Color ([System.Drawing.Color]::Green)
            if ($mkdirOutput) { Add-StatusMessage -richTextBox $rtbStatus -Message "mkdir output: $($mkdirOutput -join "`r`n")" }
        } else {
            Add-StatusMessage -richTextBox $rtbStatus -Message "ERROR: Could not create/verify remote directory '$fullRemotePath'. SSH exit code: $LASTEXITCODE" -Color ([System.Drawing.Color]::Red) -IsBold $true
            if ($mkdirOutput) { Add-StatusMessage -richTextBox $rtbStatus -Message "mkdir error output: $($mkdirOutput -join "`r`n")" -Color ([System.Drawing.Color]::Red) }
            $btnStartCopy.Enabled = $true
            $btnStartCopy.Text = "Start Copy"
            return
        }
    } catch {
        Add-StatusMessage -richTextBox $rtbStatus -Message "EXCEPTION during remote directory creation: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red) -IsBold $true
        $btnStartCopy.Enabled = $true
        $btnStartCopy.Text = "Start Copy"
        return
    }
    $form.Update()

    # 2. Execute SCP command
    Add-StatusMessage -richTextBox $rtbStatus -Message "Attempting to copy files via SCP..." -Color ([System.Drawing.Color]::DarkCyan)
    $scpDestinationArgument = "$($staticDestinationUserHost):$($fullRemotePath)"
    # For scp, if sourcePathPattern contains spaces and is a single file, it needs to be quoted.
    # PowerShell's argument parsing for external commands usually handles this if it's a single variable.
    # However, explicit quoting can be safer if wildcards are not intended to be expanded by the local shell first.
    # For simplicity here, we rely on PowerShell's default behavior. If issues arise with spaces in source paths,
    # $sourcePathPattern might need to be explicitly quoted: "`"$sourcePathPattern`""
    $scpArguments = @($sourcePathPattern, $scpDestinationArgument)

    try {
        Add-StatusMessage -richTextBox $rtbStatus -Message "Executing: scp $($scpArguments -join ' ')" # Display purpose
        $scpOutput = scp @scpArguments 2>&1 
        if ($LASTEXITCODE -eq 0) {
            Add-StatusMessage -richTextBox $rtbStatus -Message "SCP command completed successfully." -Color ([System.Drawing.Color]::Green) -IsBold $true
            if ($scpOutput) { Add-StatusMessage -richTextBox $rtbStatus -Message "SCP output: $($scpOutput -join "`r`n")" }
        } else {
            Add-StatusMessage -richTextBox $rtbStatus -Message "ERROR: SCP command failed. Exit code: $LASTEXITCODE." -Color ([System.Drawing.Color]::Red) -IsBold $true
            Add-StatusMessage -richTextBox $rtbStatus -Message "Source: '$sourcePathPattern', Destination: '$scpDestinationArgument'" -Color ([System.Drawing.Color]::Red)
            if ($scpOutput) { Add-StatusMessage -richTextBox $rtbStatus -Message "SCP error output: $($scpOutput -join "`r`n")" -Color ([System.Drawing.Color]::Red) }
            $btnStartCopy.Enabled = $true
            $btnStartCopy.Text = "Start Copy"
            return
        }
    } catch {
        Add-StatusMessage -richTextBox $rtbStatus -Message "EXCEPTION during SCP operation: $($_.Exception.Message)" -Color ([System.Drawing.Color]::Red) -IsBold $true
        $btnStartCopy.Enabled = $true
        $btnStartCopy.Text = "Start Copy"
        return
    }
    $form.Update()

    # 3. Verification step
    Add-StatusMessage -richTextBox $rtbStatus -Message "Attempting to verify copy by listing remote directory..." -Color ([System.Drawing.Color]::DarkCyan)
    $remoteListCommand = "ls -lah '${fullRemotePath}'" # Single quotes for remote shell
    $sshListArgs = @($staticDestinationUserHost, $remoteListCommand)

    try {
        $listOutput = ssh @sshListArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-StatusMessage -richTextBox $rtbStatus -Message "Verification: Remote directory listing successful." -Color ([System.Drawing.Color]::Green)
            Add-StatusMessage -richTextBox $rtbStatus -Message "--- Remote Directory Contents ---" -Color ([System.Drawing.Color]::Black) -IsBold $true
            Add-StatusMessage -richTextBox $rtbStatus -Message ($listOutput -join "`r`n") -Color ([System.Drawing.Color]::DarkSlateGray)
            Add-StatusMessage -richTextBox $rtbStatus -Message "--- End of Directory Contents ---" -Color ([System.Drawing.Color]::Black) -IsBold $true
        } else {
            Add-StatusMessage -richTextBox $rtbStatus -Message "WARNING: Could not list files in remote directory for verification. SSH exit code: $LASTEXITCODE." -Color ([System.Drawing.Color]::OrangeRed)
            if ($listOutput) { Add-StatusMessage -richTextBox $rtbStatus -Message "SSH ls error output: $($listOutput -join "`r`n")" -Color ([System.Drawing.Color]::OrangeRed) }
        }
    } catch {
        Add-StatusMessage -richTextBox $rtbStatus -Message "EXCEPTION during verification listing: $($_.Exception.Message)" -Color ([System.Drawing.Color]::OrangeRed) -IsBold $true
    }

    Add-StatusMessage -richTextBox $rtbStatus -Message "Operation Finished." -Color ([System.Drawing.Color]::Blue) -IsBold $true
    $btnStartCopy.Enabled = $true
    $btnStartCopy.Text = "Start Copy"
})

# --- Show the Form ---
# Set the form to be the topmost window initially, then allow others on top.
$form.TopMost = $true 
$form.ShowDialog() | Out-Null # ShowDialog makes it modal
$form.TopMost = $false

# Dispose of the form object when done (good practice)
$form.Dispose()
