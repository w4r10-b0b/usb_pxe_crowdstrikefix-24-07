# Created Emanuel Gomes (App logic and method) 2024 with Copilot (functions generation from scenarios)
# Update as required for below
$filePathToDelete = "C:\Windows\System32\drivers\CrowdStrike\C-00000291*.sys"

function Delete-File {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$filePathToDelete
    )
    
    # Find the file(s) with the wildcard pattern
    $files = Get-ChildItem -Path $filePathToDelete -ErrorAction SilentlyContinue
    
    # Check if any files were found
    if ($files) {
        foreach ($file in $files) {
            # Attempt to delete each file
            try {
                Remove-Item -Path $file.FullName -ErrorAction Stop
                Write-Output "Deleted file: $($file.FullName)"
            }
            catch {
                Write-Error "An error occurred while trying to delete $($file.FullName): $_"
            }
        }
    } else {
        Write-Error "No files found matching the pattern: $filePathToDelete"
    }
}

function Connect-AADWithFallback {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InitialUsername,
        [Parameter(Mandatory=$true)]
        [string]$InitialPassword
    )

    $securePassword = ConvertTo-SecureString $InitialPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($InitialUsername, $securePassword)

    try {
        Connect-AzureAD -Credential $credential
        Write-Host "Connected to Azure AD with the initial credentials."
    } catch {
        Write-Host "Failed to connect with the initial credentials. Error: $_"
        $fallbackCredential = Get-Credential -Message "Enter your Azure AD credentials"
        try {
            Connect-AzureAD -Credential $fallbackCredential
            Write-Host "Connected to Azure AD with the fallback credentials."
        } catch {
            Write-Error "Failed to connect with the fallback credentials. Error: $_"
        }
    }
}

function Test-BitLockerStatus {
    [OutputType([boolean])]
    try {
        $bootDrive = (Get-WmiObject -Class Win32_OperatingSystem).SystemDrive
        $status = manage-bde -status $bootDrive
        $isBitLockerEnabled = $status.ProtectionStatus -eq 'Protection On'
        Write-Host "BitLocker is $($isBitLockerEnabled -if 'enabled' -else 'not enabled') on the boot drive $bootDrive."
        return $isBitLockerEnabled
    } catch {
        Write-Error "An error occurred while checking BitLocker status: $_"
        return $false
    }
}

function Get-BitLockerRecoveryKey-AAD {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName
    )
    $results = New-Object PSObject -Property @{
        BitLockerKeys = $null
        LapsPassword = $null
    }
    try {
        $device = Get-AzureADDevice -SearchString $ComputerName
        if ($device) {
            $results.BitLockerKeys = Get-AzureADDeviceBitLockerKey -ObjectId $device.ObjectId
        }
    } catch {
        Write-Warning "An error occurred while retrieving the BitLocker key: $_"
    }
    try {
        $lapsPassword = Get-AzureADDeviceBitLockerKey -ObjectId $device.ObjectId
        if ($lapsPassword) {
            $results.LapsPassword = $lapsPassword
        }
    } catch {
        Write-Warning "An error occurred while retrieving the LAPS password: $_"
    }
    Disconnect-AzureAD
    return $results
}

function Get-BitLockerRecoveryKey-AD {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        [Parameter(Mandatory=$true)]
        [bool]$isBitlockerActive
    )
    $results = New-Object PSObject -Property @{
        BitLockerRecoveryPassword = $null
        LapsPassword = $null
        DriveUnlocked = $false
    }
    if ($isBitlockerActive) {
        try {
            $computer = Get-ADComputer -Identity $ComputerName -Properties *
            $recoveryInfoObjects = $computer | Get-ADObject -Filter 'ObjectClass -eq "msFVE-RecoveryInformation"' -Properties 'msFVE-RecoveryPassword'
            if ($recoveryInfoObjects) {
                $bitLockerRecoveryPassword = ($recoveryInfoObjects | Select-Object -First 1).'msFVE-RecoveryPassword'
                $unlockResult = Unlock-BitLockerDrive -BitLockerKey $bitLockerRecoveryPassword
                if ($unlockResult) {
                    Delete-File -filePathToDelete $filePathToDelete
                    Reboot-System
                    $results.DriveUnlocked = $true
                } else {
                    $results.BitLockerRecoveryPassword = $bitLockerRecoveryPassword
                }
            }
        } catch {
            Write-Warning "An error occurred while retrieving or using the BitLocker key: $_"
        }
    }
    try {
        $lapsPassword = Get-AdmPwdPassword -ComputerName $ComputerName | Select-Object -ExpandProperty Password
        if ($lapsPassword) {
            $results.LapsPassword = $lapsPassword
        }
    } catch {
        Write-Warning "An error occurred while retrieving the LAPS password: $_"
    }
    return $results
}

function Unlock-BitLockerDrive {
    param (
        [Parameter(Mandatory=$true)]
        [string]$BitLockerKey,
        [Parameter(Mandatory=$true)]
        [string]$filePathToDelete
    )
    $unlockResult = manage-bde -unlock -recoverypassword $BitLockerKey -MountPoint "C:"
    if ($unlockResult -match "completed successfully") {
        Delete-File -filePathToDelete $filePathToDelete
        Reboot-System
        return $true
    } else {
        $localCredential = Get-Credential -Message "Enter local admin credentials to unlock the drive"
        $localUsername = $localCredential.UserName
        $localPassword = $localCredential.GetNetworkCredential().Password
        $unlockResultLocal = manage-bde -unlock -recoverypassword $BitLockerKey -MountPoint "C:" -Credential $localCredential
        if ($unlockResultLocal -match "completed successfully") {
            Delete-File -filePathToDelete $filePathToDelete
            Reboot-System
            return $true
        } else {
            Write-Error "Failed to unlock the drive with both AD and local credentials."
            return $false
        }
    }
}

Function Reboot-System {
    shutdown /r /t 0
}

function Invoke-DirectoryFunction {
    $choice = Read-Host "Please choose:
    [A]ctive Directory
    [E]ntra/Azure AD
    [L]ocal"

    switch ($choice.ToUpper()) {
        'A' {
            $ComputerName = Read-Host -Prompt "Enter computer name"
            $isBitLockerActive = Test-BitLockerStatus
            Write-Host "Is BitLocker active: $isBitLockerActive"
            Connect-AADWithFallback -InitialUsername $AADUser -InitialPassword $AADPassword
            $bitLockerKey = Get-BitLockerRecoveryKey-AAD -ComputerName $ComputerName
            if ($bitLockerKey) {
                Unlock-BitLockerDrive -BitLockerKey $bitLockerKey.BitLockerKeys
            }
            Delete-File -filePathToDelete $filePathToDelete
            Reboot-System
        }
        'E' {
            $ComputerName = Read-Host -Prompt "Enter computer name including Domain details"
            $isBitLockerActive = Test-BitLockerStatus
            Write-Host "Is BitLocker active: $isBitLockerActive"
            if ($isBitLockerActive) {
                $bitLockerKey = Get-BitLockerRecoveryKey-AD -ComputerName $ComputerName
                if ($bitLockerKey) {
                    Unlock-BitLockerDrive -BitLockerKey $bitLockerKey.BitLockerKeys
                    Delete-File -filePathToDelete $filePathToDelete
                    Reboot-System
                }
            } else {
                Delete-File -filePathToDelete $filePathToDelete
                Reboot-System
            }
        }
        'L' {
            $ComputerName = Read-Host -Prompt "Enter computer name including Domain details"
            $isBitLockerActive = Test-BitLockerStatus
            Write-Host "Is BitLocker active: $isBitLockerActive"
            if ($isBitLockerActive) {
                $bitLockerKey = Read-Host -Prompt "Enter bitlocker recovery key"
                if ($bitLockerKey) {
                    Unlock-BitLockerDrive -BitLockerKey $bitLockerKey.BitLockerKeys -filePathToDelete $filePathToDelete
                }
            } else {
                $localCredential = Get-Credential -Message "Enter local admin credentials to unlock the drive"
                $localUsername = $localCredential.UserName
                $localPassword = $localCredential.GetNetworkCredential().Password
                Delete-File -filePathToDelete $filePathToDelete
            }
            Reboot-System
        }
        default {
            Write-Host "Invalid choice. Please select A, E, or L."
            Reboot-System
        }
    }
}
