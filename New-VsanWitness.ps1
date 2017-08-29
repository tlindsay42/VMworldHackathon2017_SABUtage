# 192.168.4.9 witness IP
# TODO
# untag VK1 and tag VK0


Function New-VsanWitness {
    [cmdletbinding()]
    Param(
        $VIServer = "192.168.0.10", # vCenter Server we're using
        $VIUsername = "team4", # user for vCenter
        $VIPassword = "VMware1!", # password for vCenter user

        # Full Path to the vSAN Witness Appliance & Cluster
        $vSANWitnessApplianceOVA = "C:\VMware-VirtualSAN-Witness-6.5.0-4564106.ova", # vSAN Witness Appliance OVA location
        $TargetCluster = "Hackathon-Cluster", # Cluster the OVA will be deployed to
        $NtpHost1 = "time.windows.com", # NTP Host 1
        $NtpHost2 = "time.windows.com", # NTP Host 2

        # Management Network Properties
        $WitVmName = "Witness", # Name of the Witness VM
        $WitVmPass = "VMware1!", # Witness VM root password
        $WitVmDNS1 = "10.10.10.1", # DNS Server1
        $WitVmDNS2 = "10.10.10.2", # DNS Server2
        $WitVmFQDN = "witnessname.demo.com", # DNS Address of the Witness VM
        $WitVMK0IP = "192.168.4.9", # IP address of VMK0, the Management VMK
        $WitVMK0NM = "255.255.255.0", # Netmask of VMK0
        $WitVMK0GW = "192.168.1.1", # Default System Gateway
        $WitVMK0NW = "vSAN Network", # The network name that the Managment VMK will reside on

        # Witness Network Properties
        $WitVMK1IP = "172.16.1.12", # IP address of VMK1, the WitnessPg VMK
        $WitVMK1NM = "255.255.255.0", # Netmask of VMK1
        $WitVMK1NW = "VM Network", # The network name that the Witness VMK will reside on
        $WitDeploymentSize = "tiny", # The OVA deployment size. Options are "tiny","normal", and "large"
        $WitDataCenter = "Witness-DC", # The Datacenter that the Witness Host will be added to 

        # Witness Static Routes
        $WitVMK1R1IP = "172.16.2.0", # IP/Range of Site A vSAN IP addresses
        $WitVMK1R1GW = "172.16.1.1", # Gateway to Site A that VMK1 will use
        $WitVMK1R1PFX = "24", # Network Prefix

        $WitVMK1R2IP = "172.16.3.0", # IP/Range of Site B vSAN IP addresses
        $WitVMK1R2GW = "172.16.1.1", # Gateway to Site B that VMK1 will use
        $WitVMK1R2PFX = "24"         # Network Prefix
    )

    # TODO check no existing witness
    if (Get-VsanWitnessExists -Cluster $TargetCluster -eq $true) {
        return false
    }

    # Run Configuration functions

    # Grab the OVA properties from the vSAN Witness Appliance OVA
    $ovfConfig = Get-OvfConfiguration -Ovf $vSANWitnessApplianceOVA

    # Set the Network Port Groups to use, the deployment size, and the root password for the vSAN Witness Appliance
    $ovfconfig.NetworkMapping.Management_Network.Value = $WitVMK0NW
    $ovfconfig.NetworkMapping.Witness_Network.Value = $WitVMK1NW
    $ovfconfig.DeploymentOption.Value = $WitDeploymentSize
    $ovfconfig.vsan.witness.root.passwd.value = $WitVmPass

    # Grab a random host in the cluster to deploy to
    $TargetHost = Get-Cluster  $TargetCluster | Get-VMHost | where {$_.PowerState -eq "PoweredOn" -and $_.ConnectionState -eq "Connected"} |Get-Random

    # Grab a random datastore
    $TargetDatastore = $TargetHost | Get-Datastore | Get-Random

    # Import the vSAN Witness Appliance 
    $ResourcePool = $TargetCluster | Get-ResourcePool
    Import-VApp -Source $vSANWitnessApplianceOVA -OvfConfiguration $ovfConfig -Name $WitVmName -VMHost $TargetHost -Datastore $TargetDatastore -DiskStorageFormat Thin

    # Power on the vSAN Witness Appliance
    Get-VM $WitVmName | Start-VM 

    # Set the $WitVM variable, and guestos credentials
    $WitVM = Get-VM $WitVmName
    $esxi_username = "root"
    $esxi_password = $WitVmPass

    # Wait until the tools are running because we'll need them to set the IP
    write-host "Waiting for VM Tools to Start"
    do {
        $toolsStatus = (Get-VM $WitVmName | Get-View).Guest.ToolsStatus
        write-host $toolsStatus
        sleep 5
    } until ( $toolsStatus -eq 'toolsOk' )

    # Setup our commands to set IP/Gateway information
    $Command_Path = '/bin/python'

    # CMD to set Management Network Settings
    $CMD_MGMT = '/bin/esxcli.py network ip interface ipv4 set -i vmk0 -I ' + $WitVMK0IP + ' -N ' + $WitVMK0NM + ' -t static;/bin/esxcli.py network ip route ipv4 add -N defaultTcpipStack -n default -g ' + $WitVMK0GW
    # CMD to set DNS & Hostname Settings
    $CMD_DNS = '/bin/esxcli.py network ip dns server add --server=' + $WitVmDNS2 + ';/bin/esxcli.py network ip dns server add --server=' + $WitVmDNS1 + ';/bin/esxcli.py system hostname set --fqdn=' + $WitVmFQDN

    # CMD to set the IP address of VMK1
    $CMD_VMK1_IP = '/bin/esxcli.py network ip interface ipv4 set -i vmk1 -I ' + $WitVMK1IP + ' -N ' + $WitVMK1NM + ' -t static'

    # CMD to set the Gateway of VMK1
    $CMD_VMK1_GW = '/bin/esxcli.py network ip route ipv4 add -N defaultTcpipStack -n default -g ' + $WitVMK1GW
 
    # Setup the Management Network
    Write-Host "Setting the Management Network"
    Write-Host
    runGuestOpInESXiVM -vm_moref $WitVM.ExtensionData.MoRef -guest_username $esxi_username -guest_password $esxi_password -guest_command_path $command_path -guest_command_args $CMD_MGMT
    runGuestOpInESXiVM -vm_moref $WitVM.ExtensionData.MoRef -guest_username $esxi_username -guest_password $esxi_password -guest_command_path $command_path -guest_command_args $CMD_DNS

    # Setup the Witness Portgroup
    Write-Host "Setting the WitnessPg Network"
    runGuestOpInESXiVM -vm_moref $WitVM.ExtensionData.MoRef -guest_username $esxi_username -guest_password $esxi_password -guest_command_path $command_path -guest_command_args $CMD_VMK1_IP

    # For good measure, we'll wait 1 minute before trying to add the guest to vCenter
    Write-Host "Going to wait 60s for the host to become available before attempting to add it to vCenter"
    Start-Sleep -Seconds 30
    Write-Host "Halfway there"
    Start-Sleep -Seconds 30

    # Grab the Datacenter that Witnesses will reside in
    $WitnessDC = Get-Datacenter -Name $WitDataCenter

    # Grab the DNS entry for the guest
    $DnsName = Resolve-DnsName -Name $WitVMK0IP | Select-Object NameHost

    # If the DNS names match, add by DNS, if they don't add by IP
    if ($DnsName.NameHost -eq $WitVmFQDN) {
        Write-Host "Witness IP & Hostname Match"
        $NewWitnessName = $WitVmFQDN 
    }
    else {
        Write-Host "Witness IP & Hostname Don't Match"
        $NewWitnessName = $WitVMK0IP
    }

    # Add the new Witness host to vCenter 
    Add-VMHost $NewWitnessName -Location $WitnessDC -user root -password $WitVmPass -Force

    # Grab the host, so we can set Static Routes and NTP
    $WitnessHost = Get-VMhost -Name $NewWitnessName

    $vmk = $WitnessHost | Get-VMHostNetworkAdapter -Name vmk* | Sort Name
    Set-VMHostNetworkAdapter -VirtualNic $vmk[1] -VsanTrafficEnabled $false
    Set-VMHostNetworkAdapter -VirtualNic $vmk[0] -VsanTrafficEnabled $true
    
    #$witness = Import-VsanWitness -Name $WitVmName -Cluster $TargetCluster -vSANWitnessApplianceOVA $vSANWitnessApplianceOVA `
    #    -ManagementNetwork $WitVMK0NW -WitnessNetwork $WitVMK1NW -WitnessDeploymentSize $WitDeploymentSize -WitnessPass $WitVmPass


    # New-VsanWitnessStaticRoutes -WitnessHost $WitnessHost `
    #    -Route1Destination $WitVMK1R1IP -Route1Gateway $WitVMK1R1GW -Route1PrefixLength $WitVMK1R1PFX `
    #    -Route2Destination $WitVMK1R2IP -Route1Gateway $WitVMK1R2GW -Route1PrefixLength $WitVMK1R2PFX

    # Set-VsanWitnessNTP -WitnessHost $WitnessHost -NtpHost1 $NtpHost1 -NtpHost2 $NtpHost2
}

Function Import-VsanWitness {
    Param(
        $Name,
        $Cluster,
        $vSANWitnessApplianceOVA,
        $ManagementNetwork,
        $WitnessNetwork,
        $WitnessPass,
        $WitnessDeploymentSize = "tiny"
    )

    # Grab the OVA properties from the vSAN Witness Appliance OVA
    $ovfConfig = Get-OvfConfiguration -Ovf $vSANWitnessApplianceOVA

    # Set the Network Port Groups to use, the deployment size, and the root password for the vSAN Witness Appliance
    $ovfconfig.NetworkMapping.Management_Network.Value = $ManagementNetwork
    $ovfconfig.NetworkMapping.Witness_Network.Value = $WitnessNetwork
    $ovfconfig.DeploymentOption.Value = $WitDeploymentSize
    $ovfconfig.vsan.witness.root.passwd.value = $WitnessPass

    # Grab a random host in the cluster to deploy to
    $TargetHost = Get-Cluster  $Cluster | Get-VMHost | where {$_.PowerState -eq "PoweredOn" -and $_.ConnectionState -eq "Connected"} | Get-Random

    # Grab a random datastore
    $TargetDatastore = $TargetHost | Get-Datastore | Get-Random

    # Import the vSAN Witness Appliance 
    Import-VApp -Source $vSANWitnessApplianceOVA -OvfConfiguration $ovfConfig -Name $Name -VMHost $TargetHost -Datastore $TargetDatastore -DiskStorageFormat Thin

    # Power on the vSAN Witness Appliance
    $witness = Get-VM $Name
    $witness | Start-VM
    return $witness
}


Function New-VsanWitnessStaticRoutes {
    Param(
        $WitnessHost,
        $Route1Destination,
        $Route1Gateway,
        $Route1PrefixLength,
        $Route2Destination,
        $Route2Gateway,
        $Route2PrefixLength
    )

    # Set Static Routes
    Write-Host "Setting Static Routes for the Witness Network"
    New-VMHostRoute $WitnessHost -Destination $Route1Destination -Gateway $Route1Gateway -PrefixLength $Route1PrefixLength -Confirm:$False
    New-VMHostRoute $WitnessHost -Destination $Route2Destination -Gateway $Route2Gateway -PrefixLength $Route2PrefixLength -Confirm:$False
}

Function Set-VsanWitnessNTP {
    Param(
        $WitnessHost,
        $NtpHost1,
        $NtpHost2
    )

    Write-Host "Configuring NTP" 
    #Configure NTP server & allow NTP queries outbound through the firewall
    Add-VmHostNtpServer -VMHost $WitnessHost -NtpServer $NtpHost1
    Add-VmHostNtpServer -VMHost $WitnessHost -NtpServer $NtpHost2
    
    # Get the state of the NTP client
    Get-VMHostFirewallException -VMHost $WitnessHost | where {$_.Name -eq "NTP client"} | Set-VMHostFirewallException -Enabled:$true
    
    Write-Host "Starting NTP Client"
    #Start NTP client service and set to automatic
    Get-VmHostService -VMHost $WitnessHost | Where-Object {$_.key -eq "ntpd"} | Start-VMHostService
    Get-VmHostService -VMHost $WitnessHost | Where-Object {$_.key -eq "ntpd"} | Set-VMHostService -policy "automatic"

}

Function runGuestOpInESXiVM() {
    param(
        $vm_moref,
        $guest_username, 
        $guest_password,
        $guest_command_path,
        $guest_command_args
    )
        
    # Guest Ops Managers
    $guestOpMgr = Get-View $session.ExtensionData.Content.GuestOperationsManager
    $authMgr = Get-View $guestOpMgr.AuthManager
    $procMgr = Get-View $guestOpMgr.processManager
        
    # Create Auth Session Object
    $auth = New-Object VMware.Vim.NamePasswordAuthentication
    $auth.username = $guest_username
    $auth.password = $guest_password
    $auth.InteractiveSession = $false
        
    # Program Spec
    $progSpec = New-Object VMware.Vim.GuestProgramSpec
    # Full path to the command to run inside the guest
    $progSpec.programPath = "$guest_command_path"
    $progSpec.workingDirectory = "/tmp"
    # Arguments to the command path, must include "++goup=host/vim/tmp" as part of the arguments
    $progSpec.arguments = "++group=host/vim/tmp $guest_command_args"
        
    # Issue guest op command
    $cmd_pid = $procMgr.StartProgramInGuest($vm_moref, $auth, $progSpec)
}

Function Get-VsanWitnessExists{
    Param(
        $Cluster
    )

    $vSANClusterConfig = Get-VsanClusterConfiguration -Cluster $Cluster
    $exists = $vSANClusterConfig.VsanEnabled -and $vSANClusterConfig.WitnessHost -ne $null

    return $exists
}