<#
.SYNOPSIS
    Copies files to a remote server using SCP with prompted inputs and attempts verification.
.DESCRIPTION
    This script prompts the user for:
    - Source file path (supports wildcards, e.g., C:\data\file*.txt or .\archive-*.zip)
    - Destination server credentials and address (e.g., user@hostname or user@ip_address)
    - Base destination directory on the remote server (e.g., /srv/uploads/projectX)
    - Year (which will be appended as a subdirectory to the base destination directory)

    It then uses SCP to transfer the files. After the SCP command, it attempts to verify
    the copy by listing the contents of the target directory on the remote server using SSH.

    Requirements:
    - OpenSSH client (scp.exe and ssh.exe) must be installed and in the system PATH.
    - Network connectivity to the remote server.
    - Appropriate permissions to write to the destination directory on the remote server.
    - SSH access to the remote server for verification (key-based auth recommended, or password will be prompted by ssh.exe).
.EXAMPLE
    .\CopyFilesWithSCP.ps1
    (Follow the prompts)
#>

# --- Configuration ---
# No specific configuration here, relies on user input and scp/ssh in PATH.

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

# 1. Prompt for source file path
$sourcePathPattern = Read-Host "Enter the full path to the source files (e.g., C:\data\filename.* or .\localfiles\image-*.jpg)"
if (-not $sourcePathPattern) {
    Show-Message "Source path pattern cannot be empty. Exiting." -Type Error
    exit 1
}

# 2. Prompt for destination server details
$destinationUserHost = Read-Host "Enter the destination server credentials and address (e.g., root@10.17.76.30 or backupuser@server.example.com)"
if (-not $destinationUserHost) {
    Show-Message "Destination server address cannot be empty. Exiting." -Type Error
    exit 1
}

# 3. Prompt for base destination directory on the server
$remoteBaseDirectory = Read-Host "Enter the base destination directory on the server (e.g., /usb8tb/Shared/Public/Media/Movies)"
if (-not $remoteBaseDirectory) {
    Show-Message "Remote base directory cannot be empty. Exiting." -Type Error
    exit 1
}

# 4. Prompt for the year
$year = Read-Host "Enter the year for the subdirectory (e.g., $(Get-Date -Format yyyy))"
if (-not $year) {
    Show-Message "Year cannot be empty. Exiting." -Type Error
    exit 1
}

# Construct the full remote path
# Ensure the base directory ends with a slash if it doesn't have one.
if (-not $remoteBaseDirectory.EndsWith("/")) {
    $remoteBaseDirectory += "/"
}
# Ensure the year does not start with a slash if remoteBaseDirectory already ends with one.
if ($year.StartsWith("/")) {
    $year = $year.Substring(1)
}
$fullRemotePath = "$($remoteBaseDirectory)$year/" # Ensure this also ends with a slash for scp to treat as directory

Show-Message "Source files: '$sourcePathPattern'"
Show-Message "Destination: '$($destinationUserHost):$fullRemotePath'"
Show-Message "Attempting to copy files. This may take a while..."

# Execute SCP command
# SCP requires the destination to be quoted if it contains special characters or to ensure the path is treated correctly.
# The path on the remote server should be enclosed in single quotes to prevent shell expansion on the remote side,
# especially if $fullRemotePath could contain spaces or other special characters (though less common for directory structures).
$scpArguments = @(
    $sourcePathPattern
    "$($destinationUserHost):'$($fullRemotePath)'" # Single quotes around the remote path for the remote shell
)

try {
    Show-Message "Executing: scp $($scpArguments -join ' ')"
    # Using Start-Process to better capture streams if needed, but direct call is simpler for exit code.
    # For scp, direct invocation is fine.
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
            $destinationUserHost
            $remoteListCommand # The command string
        )

        try {
            Show-Message "Executing remote command: ssh $($sshArguments -join ' ')"
            # Invoke ssh and capture output/errors
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
