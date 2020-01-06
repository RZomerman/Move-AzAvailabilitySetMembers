<#

 
ScriptName : Move-AzAvailabilitySetMembers
Description : This script will move all VM's of an availability set to another availability set
Author : Roelf Zomerman (https://blog.azureinfra.com)
Based on: Samir Farhat (https://buildwindows.wordpress.com) - Set-ArmVmAvailabilitySet.ps1
Version : 1.01

#Usage
    ./Move-AzAvailabilitySetMembers.ps1 -SourceAvailabilitySet SourceAVSET1 -TargetAvailabilitySet TargetAVSET2 -ResourceGroup ResourceGroupName -Login $false/$true -SelectSubscription $false/$true -PauseAfterEachVM $false/$true 

#Prerequisites#
- Azure Powershell 1.01 or later
- An Azure Subscription and an account which have the proviliges to : Remove a VM, Create a VM
- An existing Availability Set part of the same Resource Group as the VM

#How it works#
- Get the Source AV Set, grab all VirtualMachinesReferences 
- Grab AZObject -object VirtualMachinesReferences
- For each VM in the VirtualMachinesReferences
    - Get the VM object (JSON)
    - Save the JSON configuration to a file (To rebuild the VM wherever it goes wrong)
    - Remove the VM (Only the configuration, all dependencies are kept ) 
    - Modify the VM object (change the AS)
    - Change the Storage config because the recration needs the disk attach option
    - ReCreate the VM
#>


[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,Position=1)]
   [string]$SourceAvailabilitySet,

   [Parameter(Mandatory=$True,Position=3)]
   [string]$TargetAvailabilitySet,
   
   [Parameter(Mandatory=$True,Position=2)]
   [string]$ResourceGroup,
   [Parameter(Mandatory=$True,Position=3)]
   [string]$VmSize,

   [Parameter(Mandatory=$False)]
   [boolean]$Login,
   [Parameter(Mandatory=$False)]
   [boolean]$SelectSubscription,
   [Parameter(Mandatory=$False)]
   [boolean]$PauseAfterEachVM

)

If (!($VMsize)){$VMsize = $False} #Need to specify $false for the resizing is no new size is given

Import-Module .\Move-AzAvailabilitySetMembers.psm1

write-host ""
write-host ""

#Cosmetic stuff
write-host ""
write-host ""
write-host "                               _____        __                                " -ForegroundColor Green
write-host "     /\                       |_   _|      / _|                               " -ForegroundColor Yellow
write-host "    /  \    _____   _ _ __ ___  | |  _ __ | |_ _ __ __ _   ___ ___  _ __ ___  " -ForegroundColor Red
write-host "   / /\ \  |_  / | | | '__/ _ \ | | | '_ \|  _| '__/ _' | / __/ _ \| '_ ' _ \ " -ForegroundColor Cyan
write-host "  / ____ \  / /| |_| | | |  __/_| |_| | | | | | | | (_| || (_| (_) | | | | | |" -ForegroundColor DarkCyan
write-host " /_/    \_\/___|\__,_|_|  \___|_____|_| |_|_| |_|  \__,_(_)___\___/|_| |_| |_|" -ForegroundColor Magenta
write-host "     "
write-host " This script moves all VM's in an Availability Set to another Availability set" -ForegroundColor "Green"


#Importing the functions module and primary modules for AAD and AD

If (!((LoadModule -name AzureAD))){
    Write-host "Functions Module was not found - cannot continue - please make sure Set-AzAvailabilitySet.psm1 is available in the same directory"
    Exit
}
If (!((LoadModule -name Az.Compute))){
    Write-host "Az.Compute Module was not found - cannot continue - please install the module using install-module AZ"
    Exit
}

##Setting Global Paramaters##
$ErrorActionPreference = "Stop"
$date = Get-Date -UFormat "%Y-%m-%d-%H-%M"
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$logFile = $workfolder+'\AVSetMove'+$date+'.log'
Write-Output "Steps will be tracked on the log file : [ $logFile ]" 

##Login to Azure##
If ($Login) {
    $Description = "Connecting to Azure"
    $Command = {LogintoAzure}
    $AzureAccount = RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"
}


##Select the Subscription##
##Login to Azure##
If ($SelectSubscription) {
    $Description = "Selecting the Subscription : $Subscription"
    $Command = {Get-AZSubscription | Out-GridView -PassThru | Select-AZSubscription}
    RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"
}

#Validate Existence of AVSets
$ValidateSourceAs = Validate-AsExistence -ASName $SourceAvailabilitySet -VmRG $ResourceGroup -LogFile $logFile
$ValidateTargetAs = Validate-AsExistence -ASName $TargetAvailabilitySet -VmRG $ResourceGroup -LogFile $logFile

$TargetAVSetObjectID=(Get-AzAvailabilitySet -ResourceGroupName $ResourceGroup -Name $TargetAvailabilitySet).Id

If (!($ValidateSourceAs) -and $ValidateTargetAs){
    WriteLog "Source AV Set does not exist, please create it" -LogFile $LogFile -Color "Red" 
    #Exit
    
}Elseif ($ValidateSourceAs -and (!$ValidateTargetAs)){
    WriteLog "Target AV Set does not exist, please create it" -LogFile $LogFile -Color "Red" 
    #Exit
}Elseif ($ValidateSourceAs -and $ValidateTargetAs){
    #Can Continue
    #Grab all the VM's in the set - get their power status and move them
    $AllVMObjects = New-Object System.Collections.ArrayList
    $AllMembers=GetAVSetMembers -AvSetName $SourceAvailabilitySet -ResourceGroupName $ResourceGroup
    If (!($AllMembers)) {
        #No members returned, nothing do to 
        WriteLog "No members on Source AV Set found, exiting" -LogFile $LogFile -Color "Red"
        Exit
    }Else{
        Write-host ""
        $totalCount=$AllMembers.count
        $Description = "The source AV Set has $totalCount VM's, migrating all of them to $TargetAvailabilitySet " 
        WriteLog -Description $Description -LogFile $LogFile -Color "Green"
        $i=0
        
        #Running export on all VM configurations
        $Description = "Exporting the configuration of all VM's "
        WriteLog -Description $Description -LogFile $LogFile
        ForEach ($VM in $AllMembers) {
            $i++
            #Get to the VM and check power-status
            $VMDetails=Get-AzResource -ResourceId $VM.id
            $VMname=$VMDetails.Name
            $VMObject=Get-AzVM -ResourceGroupName $VMDetails.ResourceGroupName -Name $VMDetails.Name
            #$Description = "Moving VM $i with name $VMname"
            #WriteLog -Description $Description -LogFile $LogFile
            #Exporting VM details
            $ResourceGroupName=$VMDetails.ResourceGroupName
            $Description = "  -Exporting the VM Config to a file : $ResourceGroupName-$VMName.json "
            $Command = {ConvertTo-Json -InputObject $VmObject -Depth 100 | Out-File -FilePath $workfolder'\'$ResourceGroupName-$VMName'.json'}
            RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"

            #Adding the VM to an Array for bulk change if required
            $void=$AllVMObjects.add($VMObject)
        

        }
    write-host ""
    }
}


If (!($Parallel)){
    #Actually moving the VM
    
    $Description = "Migrating VM's 1-by-1 " 
    WriteLog -Description $Description -LogFile $LogFile -Color 'Green'
    $i=0
        ForEach ($VMObject in $AllVMObjects) {
            $i++
            $VMname=$VMObject.Name
            $Description = "* Moving VM $i with name $VMname"
            WriteLog -Description $Description -LogFile $LogFile 
            
            StopAZVM -VMObject $VMObject -LogFile $LogFile
            If ($VMSize) {
                If (ValidateVMSize -Vmsize $VMSize -location $VMObject.location) {
                    WriteLog "  -Resizing VM to new size: $VMSize" -LogFile $LogFile -Color "Yellow" 
                }else{
                    $Location=$VMObject.location
                    WriteLog "!! Resizing VM to new size: $VMSize failed !! Manual resizing required after deployment !!" -LogFile $LogFile -Color "Red" 
                    WriteLog "!! Possible entry error or size not available in location: $Location" -LogFile $LogFile -Color "Red" 
                }
            }
            Set-AsSetting -VmObject $VmObject -TargetASObject $TargetAVSetObjectID -LogFile $LogFile -vmSize $VmSize
            Write-host "  -Validating if VM exists" -ForegroundColor Yellow -NoNewline
        Do {
            Write-host "." -NoNewline -ForegroundColor Yellow
            Start-Sleep 1
        }
        While (!(Validate-VmExistence -VmName $VMObject.Name -VmRG $VMObject.ResourceGroupName -logFile $logFile)){
        }
       $Description = "  -VM Migration Completed"
        WriteLog -Description $Description -LogFile $LogFile -Color 'Green'
        Write-host "...  ----------------------  ..."
        if ($PauseAfterEachVM -and $VMObjects.count -ne $i) {
            write-host "Next migration has been paused as per PauseAfterEachVM option" -ForegroundColor CYAN
            write-host "            ...Press any key to continue..."  -ForegroundColor CYAN
            [void][System.Console]::ReadKey($true)
        }

    }
    Write-host "** All VM's have been migrated to $TargetAvailabilitySet **" -ForegroundColor "Green"

}

If ($Parallel) {
    #this is an experimental feature that is only available in PShell 7 Preview 3
    Write-host "AS Move in Parallel is available only for Powershell 7.3 and newer" -ForegroundColor Green
    Write-host "It will move a maximum 5 VM's at a time"
        WriteLog -Description $Description -LogFile $LogFile
    If ($Host.Version.Major -eq 7 -and $Host.Version.Minor -gt 2 ) {
        $AllVMObjects | ForEach-Object  -Parallel {
            Import-Module .\Move-AzAvailabilitySetMembers.psm1
            StopAZVM -VMObject $_ -LogFile $using:LogFile
            Set-AsSetting -VmObject $_ -TargetASObject $using:TargetAVSetObjectID -LogFile $using:LogFile
        }
    }
}



