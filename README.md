ScriptName : Move-AzAvailabilitySetMembers
Description : This script will move all VM's of an availability set to another availability set
Author : Roelf Zomerman (https://blog.azureinfra.com)
Based on: Samir Farhat (https://buildwindows.wordpress.com) - Set-ArmVmAvailabilitySet.ps1
Version : 1.01

#Usage
    ./Move-AzAvailabilitySetMembers.ps1 -SourceAvailabilitySet SourceAVSET1 -TargetAvailabilitySet TargetAVSET2 -ResourceGroup ResourceGroupName -Login $false/$true -SelectSubscription $false/$true -PauseAfterEachVM $false/$true 

#Options / Required input
  -SourceAvailabilitySet  #Mandatory - the Source AV set to move all the VM's from
  -TargetAvailabilitySet  #Mandatory - the target AV set to move all the VM's to
  -ResourceGroup          #Mandatory - the ResourceGroup containing the VM's and Availability sets (must be same)

Optionally the following attributes can be provided
- VmSize                 # If VM's need to be resized - NOTE THAT HARDWARE COMPATIBILITY IS NOT VALIDATED (#Data Disks, #Accelerated & #NIC's, etc)
- Login                 #Will trigger Add-AzAccount logins
- SelectSubscription    #Will pop-up a subscription selectionbox
- PauseAfterEachVM      #Will pause the script after moving each VM - so manual validation can occur

#Prerequisites#
- Azure Powershell 5.01 or later
- Azure AZ Powershell Commandlet's (Install-Module AZ)
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
    - If specified Resize the VM
    - ReCreate the VM
