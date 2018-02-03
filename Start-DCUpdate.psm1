Function Start-DCUpdate
{
    <#
        .SYNOPSIS
            Run Dell Command Update to update device drivers.
        .DESCRIPTION
            This script will run Dell Command Update to update device drivers.  The application can also be installed
            through the script.
        .EXAMPLE
            Start-DCUpdate -BitLockerDriveLetter 'C'
    #>
    [cmdletbinding()]
    param (
        # Path to the installation EXE for Dell Command Update
        [string] $DCUtilityInstallerPath = '.\DCU_Setup_2_3_0.exe',

        # Path to log (default is C:\Windows\Temp\DCU)
        [string] $LogPath = 'C:\Windows\Temp\DCU',

        #Arguments to send to the DCU executable.
        [string] $DCUArgs = "/silent /log $LogPath",

        # If BitLocker is enabled, state the volume on which to Suspend BitLocker.
        [ValidateSet("C","D","E","F")]
        [char] $BitLockerDriveLetter = 'C'
    )
    
    Write-Output "Starting driver updates..."

    # Test to see if DCU is installed
    $Architecture = ((Get-CimInstance Win32_OperatingSystem -Property OSArchitecture) | Select-Object OSArchitecture)
    Write-Verbose "Testing OS Architecture..."

    if($Architecture.OSArchitecture -eq "32-bit") 
    {
        # 32-bit OS - Look in C:\Program Files
        Write-Verbose "32-bit OS detcted."
        $DCUtilityLocalPath = $env:ProgramFiles + "\Dell\CommandUpdate"
    }
    else
    {
        # Not 32-bit (read:  64-bit)
        # DCU is a 32-bit only application, so look in Program Files (x86)
        Write-Verbose "64-bit OS detected."
        $DCUtilityLocalPath = ${env:ProgramFiles(x86)} + "\Dell\CommandUpdate"
    }

    # Install DCU
    if((Test-Path $DCUtilityLocalPath) -eq $false)
    {
        Write-Output "Dell Command Update not found.  Installing..."
        if((Test-Path $DCUtilityInstallerPath) -eq $true)
        {
            try
            {
                Write-Verbose "Starting Installation..."
                Write-Debug "Installation source: $DCUtilityInstallerPath (Installation will not execute)"
                if($DebugPreference -eq 'SilentlyContinue')
                {
                    Start-Process -FilePath $DCUtilityInstallerPath -ArgumentList $DCUArgs -Wait -NoNewWindow
                }
                
            }
            catch
            {
                Write-Debug $Error
                Write-Error "An error occured trying to install DCU."
                exit
            }
        }
        else
        {
            Write-Debug $Error
            Write-Error "Cannot find Dell Command Update installation executable.  Make sure it's in the same directory as this script."
        }
    }

    Write-Verbose "Dell Command Successfully Installed."
    Write-Debug "Installed correctly."
    # Get BitLocker status
    Write-Verbose  "Getting BitLocker status..."

    # Need to fix this to test to see if BitLocker commands exist

    $BitLockerEnabled = (Get-Command "*bitlocker*").Count

    if($BitLockerEnabled -gt '0')
    {
        # Cmd-lets for BitLocker are available.
        $BitLockerDrive = ((Get-BitLockerVolume -MountPoint "$BitLockerDriveLetter" -OutVariable "nothing" -ErrorAction SilentlyContinue) | Select-Object ProtectionStatus)
        Write-Debug "BitLockerDrive is $BitLockerDrive."
        
        if($BitLockerDrive.ProtectionStatus -eq "On")
        {
            # BitLocker is "On" for C:
            Write-Warning "BitLocker enabled for drive $($BitLockerDriveLetter):"
            Write-Warning "Suspending BitLocker..."
            try
            {
                if($DebugPreference -eq 'SilentlyContinue')
                {
                    [void] (Suspend-BitLocker -MountPoint "$BitLockerDriveLetter" -ErrorAction Stop -RebootCount 1)
                }
                
                Write-Warning "BitLocker suspended."
                Write-Debug "(not really)"
            }
            catch
            {
                Write-Error "Suspend operation failed for drive $($BitLockerDriveLetter):.  The script will now exit."
                break
            }
        }
        else
        {
            Write-Output "Bitlocker for drive $($BitLockerDriveLetter): is currently off."
        }
    }
    else
    {
        Write-Verbose "No BitLocker cmd-lets found.  BitLocker is not enabled."
    }

    # Set the variable that corresponds to dcu-cli.exe
    if($Architecture.OSArchitecture -eq "32-bit")
    {
        $DCUCLI = $env:ProgramFiles + "\Dell\CommandUpdate\dcu-cli.exe"
    }
    else
    {
        $DCUCLI = ${env:ProgramFiles(x86)} + "\Dell\CommandUpdate\dcu-cli.exe"
    }

    Write-Debug "DCU being executed from $DCUCLI"

    # Run it
    try
    {
        Write-Output "Starting driver updates..."
        Write-Debug "`"$DCUCLI`" with arguments `"$DCUArgs`". (but not really happening)"
        if($DebugPreference -eq 'SilentlyContinue')
        {
            $UpdateResult = (Start-Process -FilePath $DCUCLI -ArgumentList $DCUArgs -Verb runas -ErrorAction Stop -Wait -WindowStyle Hidden -PassThru)
        }
        else
        {
            $UpdateResult = Get-Random -Maximum 5 -Minimum 0
            Write-Debug "Generating random result code:  $($UpdateResult)"    
        }
    }
    catch
    {
        Write-Error "An error has occured starting driver updates. "
        break
    }

    $RebootNeeded = $false

    if($DebugPreference -ne 'SilentlyContinue')
    {
        switch ($UpdateResult)
        {
            0
            {
                $ExitMessage = "Update successful.  No reboot required."
            }
            1
            {
                $ExitMessage = "Update successful.  Reboot required."
                $RebootNeeded = $true
            }
            2
            {
                $ExitMessage = "Driver update unsuccessful.  Please see log in C:\Windows\Temp\DCU.  The computer will now be restarted.  Re-run the script when the reboot is complete." 
                $RebootNeeded = $true
            }
            5
            {
                $ExitMessage = "Reboot required.  Please restart the scan`n
                                when Windows reloads."
                $RebootNeeded = $true
            }
            default
            {
                $ExitMessage = "Unknown error.  Ensure all instances`n
                are closed and try again."
            }
        }
    }
    else 
    {
        switch ($UpdateResult.ExitCode)
        {
            0
            {
                $ExitMessage = "Update successful.  No reboot required."
            }
            1
            {
                $ExitMessage = "Update successful.  Reboot required."
                $RebootNeeded = $true
            }
            2
            {
                $ExitMessage = "Driver update unsuccessful.  Please see log in C:\Windows\Temp\DCU.  The computer will now be restarted.  Re-run the script when the reboot is complete." 
                $RebootNeeded = $true
            }
            5
            {
                $ExitMessage = "Reboot required.  Please restart the scan`n
                                when Windows reloads."
                $RebootNeeded = $true
            }
            default
            {
                $ExitMessage = "Unknown error.  Ensure all instances`n
                are closed and try again."
            }
        }
    }
    
    Write-Output $ExitMessage
    Write-Verbose "$($UpdateResult.Exitcode) / $ExitMessage"

    Write-Debug "Reboot:  $RebootNeeded"
    if($RebootNeeded -and ($DebugPreference -eq 'SilentlyContinue'))
    {
        Write-Debug "Sleeping 5..."
        Start-Sleep 5
        Restart-Computer -Force
    }

}