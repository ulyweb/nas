<#
.SYNOPSIS
    Copies files to a remote server using SCP with some static/default values and prompted inputs.
.DESCRIPTION
    This script copies files based on a source pattern to a predefined remote server and base directory.
    - Source file path: Prompts the user, with a default of 'c:\yt\*'. User can input relative or absolute paths.
                      If a filename with spaces is entered, it should be handled correctly.
    - Destination server: Statically set to 'root@10.17.76.30'.
    - Base destination directory: Statically set to '/usb8tb/Shared/Public/Media/Movies/'.
    - Year: Prompts the user. If a year is provided, it's appended as a subdirectory.
             If no year is provided (user presses Enter), files are copied to the base destination directory.

    Before copying, it attempts to create the target directory on the remote server if it doesn't exist using 'ssh mkdir -p'.
    It then uses SCP to transfer the files. After the SCP command, it attempts to verify
    the copy by listing the contents of the target directory on the remote server using SSH.

    Requirements:
    - OpenSSH client (scp.exe and ssh.exe) must be installed and in the system PATH.
    - Network connectivity to the remote server.
    - Appropriate permissions to write to the destination directory on the remote server.
    - SSH access to the remote server for verification and directory creation (key-based auth recommended, or password will be prompted).
.EXAMPLE
    .\Copy-FilesWithSCP-Updated.ps1
    (Follow the prompts for source path and year)
#>

# --- Static Configuration ---
$staticDestinationUserHost = "root@10.17.76.30"
$staticRemoteBaseDirectory = "/usb8tb/Shared/Public/Media/Movies/" # Must end with a slash
$defaultSourcePathPattern = "c:\yt\*" # Default source, user can override

# --- Functions ---
function Show-Message {
    param (
        [string]$Message,
        [string]$Type = "Information" # Information, Warning, Error, Success
    )
    switch ($Type) {
        "Information" { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
        "Warning"   { Write-Warning "[WARN] $Message" }
        "Error"     { Write-Error "[ERROR] $Message" }
        "Success"   { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
        default     { Write-Host $Message }
    }
}

# --- Main Script ---
Show-Message "Starting file copy script..."
Show-Message "Remote server: '$staticDestinationUserHost'" -Type Information
Show-Message "Base remote directory: '$staticRemoteBaseDirectory'" -Type Information

# 1. Prompt for source file path with a default
$userInputSourcePath = Read-Host "Enter the source file path (default: '$defaultSourcePathPattern'). For current dir, use '.\filename.ext'"
$sourcePathPattern = if ([string]::IsNullOrWhiteSpace($userInputSourcePath)) { $defaultSourcePathPattern } else { $userInputSourcePath }

if (-not $sourcePathPattern) { 
    Show-Message "Source path pattern cannot be empty. Exiting." -Type Error
    exit 1
}
Show-Message "Using source path: '$sourcePathPattern'"

# 2. Prompt for the year (optional)
$yearInput = Read-Host "Enter the year for the subdirectory (e.g., $(Get-Date -Format "yyyy")). Press ENTER to use base directory only."

# 3. Construct the full remote path
$fullRemotePath = $staticRemoteBaseDirectory # Start with the base directory

if (-not [string]::IsNullOrWhiteSpace($yearInput)) {
    $yearCleaned = $yearInput.Trim('/') # Remove any leading/trailing slashes from user input for year
    # Ensure base directory part ends with a slash, and append cleaned year and a final slash
    $fullRemotePath = "$($staticRemoteBaseDirectory.TrimEnd('/'))/$yearCleaned/"
    Show-Message "Year subdirectory specified: '$yearCleaned'. Full remote path will be: '$fullRemotePath'"
} else {
    Show-Message "No year specified. Files will be copied to: '$fullRemotePath'"
}

# Ensure the final path for scp always ends with a slash to denote it as a directory
if (-not $fullRemotePath.EndsWith("/")) {
    $fullRemotePath += "/"
}

Show-Message "Final destination will be: $($staticDestinationUserHost):$($fullRemotePath)"

# 3.5. Attempt to create the remote directory
Show-Message "Attempting to create remote directory (if it doesn't exist): $fullRemotePath"
# The command to be executed on the remote server. Enclose the remote path in single quotes for the remote shell.
$mkdirCommand = "mkdir -p '${fullRemotePath}'" 
$sshMkdirArgs = @(
    $staticDestinationUserHost
    $mkdirCommand
)
try {
    Show-Message "Executing remote command: ssh $($sshMkdirArgs -join ' ')"
    ssh @sshMkdirArgs
    if ($LASTEXITCODE -ne 0) {
        Show-Message "Warning: Could not create or verify remote directory '$fullRemotePath' (ssh mkdir -p exit code: $LASTEXITCODE). SCP might fail if the directory doesn't exist or permissions are incorrect." -Type Warning
        # Allow script to continue; scp will provide the final error if it fails.
    } else {
        Show-Message "Remote directory path '$fullRemotePath' should now exist or was already present." -Type Success
    }
} catch {
    Show-Message "An error occurred while trying to create the remote directory via SSH: $($_.Exception.Message). SCP might fail." -Type Warning
}


Show-Message "Attempting to copy files. This may take a while..."

# 4. Execute SCP command
# Construct the destination argument for scp. No extra quotes around $fullRemotePath here.
$scpDestinationArgument = "$($staticDestinationUserHost):$($fullRemotePath)"

$scpArguments = @(
    $sourcePathPattern          # Source files/pattern
    $scpDestinationArgument     # Destination
)

try {
    Show-Message "Executing: scp $($scpArguments -join ' ')" # For display, join arguments
    # When calling external commands like scp.exe, PowerShell handles quoting of arguments if they contain spaces.
    # So, $sourcePathPattern (if it has spaces and is a single variable) and $scpDestinationArgument will be passed correctly.
    scp @scpArguments

    # Check SCP exit code
    if ($LASTEXITCODE -eq 0) {
        Show-Message "SCP command completed successfully." -Type Success

        # 5. Verification step: Attempt to list files on the remote server
        Show-Message "Attempting to verify by listing files in the remote directory: $fullRemotePath"
        # The command to be executed on the remote server.
        # Enclose the remote path in single quotes for `ls` to handle spaces/special characters on the remote shell.
        $remoteListCommand = "ls -lah '${fullRemotePath}'"
        
        $sshListArgs = @(
            $staticDestinationUserHost
            $remoteListCommand # The command string
        )

        try {
            Show-Message "Executing remote command: ssh $($sshListArgs -join ' ')"
            $sshResult = ssh @sshListArgs 2>&1 # Capture stdout and stderr
            
            if ($LASTEXITCODE -eq 0) {
                Show-Message "Verification: Remote directory listing successful." -Type Success
                Write-Host "Remote directory contents:"
                Write-Host ($sshResult | Out-String)
            } else {
                Show-Message "Verification: Could not list files in the remote directory. `ssh` exit code: $LASTEXITCODE" -Type Warning
                Show-Message "SCP command itself reported success, but listing files for verification failed." -Type Warning
                if ($sshResult) {
                    Show-Message "SSH command output/error: $($sshResult | Out-String)" -Type Warning
                }
            }
        } catch {
            Show-Message "Verification: An error occurred while trying to list files on the remote server via SSH: $($_.Exception.Message)" -Type Warning
            Show-Message "SCP command itself reported success, but the verification step encountered an exception." -Type Warning
        }
    } else {
        Show-Message "SCP command failed with exit code: $LASTEXITCODE. Please check for errors above. Ensure the source path ('$sourcePathPattern') is correct, files exist, and the remote path ('$fullRemotePath') is accessible with correct permissions." -Type Error
    }
} catch {
    Show-Message "An unexpected error occurred during the SCP operation: $($_.Exception.Message)" -Type Error
    Show-Message "Ensure 'scp.exe' is in your PATH, the remote server is accessible, and you have appropriate permissions." -Type Information
}

Show-Message "Script finished."
