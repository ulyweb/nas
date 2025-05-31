<#
.SYNOPSIS
    Copies files to a remote server using SCP with some static/default values and prompted inputs.
.DESCRIPTION
    This script copies files based on a source pattern to a predefined remote server and base directory.
    - Source file path: Prompts the user, with a default of 'c:\yt\*'.
    - Destination server: Statically set to 'root@10.17.76.30'.
    - Base destination directory: Statically set to '/usb8tb/Shared/Public/Media/Movies/'.
    - Year: Prompts the user. If a year is provided, it's appended as a subdirectory.
             If no year is provided (user presses Enter), files are copied to the base destination directory.

    It then uses SCP to transfer the files. After the SCP command, it attempts to verify
    the copy by listing the contents of the target directory on the remote server using SSH.

    Requirements:
    - OpenSSH client (scp.exe and ssh.exe) must be installed and in the system PATH.
    - Network connectivity to the remote server.
    - Appropriate permissions to write to the destination directory on the remote server.
    - SSH access to the remote server for verification (key-based auth recommended, or password will be prompted by ssh.exe).
.EXAMPLE
    .\Copy-FilesWithSCP.ps1
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
$userInputSourcePath = Read-Host "Enter the source file path (default: '$defaultSourcePathPattern')"
$sourcePathPattern = if ([string]::IsNullOrWhiteSpace($userInputSourcePath)) { $defaultSourcePathPattern } else { $userInputSourcePath }

if (-not $sourcePathPattern) { # Should not happen with default, but good practice
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

Show-Message "Final destination: '$($staticDestinationUserHost):'$fullRemotePath''" # Note the single quotes for scp
Show-Message "Attempting to copy files. This may take a while..."

# Execute SCP command
# SCP requires the destination to be quoted if it contains special characters or to ensure the path is treated correctly.
# The path on the remote server should be enclosed in single quotes to prevent shell expansion on the remote side.
$scpArguments = @(
    $sourcePathPattern
    "$($staticDestinationUserHost):'$($fullRemotePath)'" # Single quotes around the remote path for the remote shell
)

try {
    Show-Message "Executing: scp $($scpArguments -join ' ')"
    scp @scpArguments

    # Check SCP exit code
    if ($LASTEXITCODE -eq 0) {
        Show-Message "SCP command completed successfully." -Type Success

        # Verification step: Attempt to list files on the remote server
        Show-Message "Attempting to verify by listing files in the remote directory: $fullRemotePath"
        # The command to be executed on the remote server.
        # Enclose the remote path in single quotes for `ls` to handle spaces/special characters.
        $remoteListCommand = "ls -lah '${fullRemotePath}'"
        
        $sshArguments = @(
            $staticDestinationUserHost
            $remoteListCommand # The command string
        )

        try {
            Show-Message "Executing remote command: ssh $($sshArguments -join ' ')"
            $sshResult = ssh @sshArguments 2>&1 # Capture stdout and stderr
            
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
        Show-Message "SCP command failed with exit code: $LASTEXITCODE. Please check for errors above." -Type Error
    }
} catch {
    Show-Message "An unexpected error occurred during the SCP operation: $($_.Exception.Message)" -Type Error
    Show-Message "Ensure 'scp.exe' is in your PATH and the remote server is accessible." -Type Information
}

Show-Message "Script finished."
