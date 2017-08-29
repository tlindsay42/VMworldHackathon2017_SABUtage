####################################################################################
#                                                                                  #
#     VMware Virtual SAN -- All Flash Automated Deployment for Stretched Cluster   #
#                                                                              	   # 
####################################################################################

####################################################################################
#                                                                                  #
#      The All-in-One and Ultimate Virtual SAN Streched Cluster Config. Script     #
#                                                                                  #
#                        by Alan Renouf and Rawlinson                              #
#                                                                                  #
####################################################################################

# -- Add all VMware PowerCLI modules --

get-module -ListAvailable VMware* | Import-Module | Out-Null

# -- Infrastructure Settings for scripts -- 

	$VCNode = "vcenter-fqdn-or-ip"
	$VCUserName = "administrator@vsphere.local"
	$VCPassword = "password"
	$ESXiUserName = "root"
	$ESXiPassword = 'password'
	$DCName = "octo-sabu"
	$CluName = "hci-stretched-cluster"
	$VDSName = "10G Switch"
	$PrimaryPortGroup = 3001
	$SecondaryPortgroup = 3003
	$WitnessPortgroup = 3002
	$DNS = "10.142.7.21", "10.142.7.22"
	$NTP = "10.132.249.12", "10.132.249.28"
	$VMotionIP = "192.168.21."
	$VSANIP = "192.168."
	$cachingSSD = "S630DC-960"
	$CapacitySSD = "MICRON_M510DC_MT"
	$witness = "VSAN-witness-fqdn-or-ip"
	$witnessIP = "192.168.2.68"
	$WitnessSNM = "255.255.255.0"

# -- Static Routes --

	$PrimarySR = "192.168.1.0"
	$PrimaryGW = "192.168.1.253"

	$SecondarySR = "192.168.3.0"
	$SecondaryGW = "192.168.3.253"

	$WitnessSR = "192.168.2.0"
	$WitnessGW = "192.168.2.253"

# -- Connect to vCenter --

	Connect-viserver $VCNode -user $VCUserName -pass $VCPassword -WarningAction SilentlyContinue

# -- Datacenter/Cluster Configuration --

# -- Create Datacenters --

	Write-Host "Creating Datacenter: $DCName" -ForegroundColor Green
	$DC = New-Datacenter -Name $DCName -Location (Get-Folder Datacenters)

# -- Adding and configuring the Virtual SAN Witness Appliance to vCenter

	Write-Host "Creating Witness Datacenter: witness-$($DCName)" -ForegroundColor Green
	$WDC = New-Datacenter -Name "Witness-$($DCName)" -Location (Get-Folder Datacenters)
	Write-Host "Adding Witness host $Witness" -ForegroundColor Green
	Add-VMHost -Name $witness -Location $WDC -User $ESXiUserName -Password $ESXiPassword -Force | Out-Null
	Write-Host "Adding Witness IP Address" -ForegroundColor Green
	$WVMK = get-vmhost $witness | Get-VMHostNetworkAdapter | Where { $_.dhcpEnabled -eq $true}
	$WVMK | Set-VMHostNetworkAdapter -IP $witnessIP -SubnetMask $WitnessSNM -Confirm:$false | Out-Null

# -- Create Cluster --

	Write-Host "Creating Cluster: $CluName" -ForegroundColor Green
	$CLU = New-Cluster -Name $CluName -Location ($DC) -DrsEnabled

# -- Add Hosts to cluster --

09..16 | Foreach {
    $num = $_ ; 
    $newnum = "{0:D2}" -f $num
    Write-Host "Adding host hostname-$newnum.vmware.com" -ForegroundColor Green
    Add-VMHost -Name "hostname-$newnum.vmware.com" -Location $CluName -User $ESXiUserName -Password $ESXiPassword -Force | Out-Null
}

# -- Host Configuration --

	$VMHosts = Get-VMHost | Sort Name

# -- Add DNS/NTP and Enable iScsi Settings for the hosts --

Foreach ($vmhost in $vmhosts) {
   Write-Host "Configuring DNS and Domain Name on $vmhost" -ForegroundColor Green
   Get-VMHostNetwork -VMHost $vmhost | Set-VMHostNetwork -DNSAddress $DNS -Confirm:$false | Out-Null
    
   Write-Host "Configuring NTP Servers on $VMHost" -ForegroundColor Green
   Add-VMHostNTPServer -NtpServer $NTP -VMHost $VMHost -Confirm:$false -ErrorAction SilentlyContinue | FT | Out-Null
    
   Write-Host "Configuring NTP Client Policy on $VMHost" -ForegroundColor Green
   Get-VMHostService -VMHost $VMHost | where {$_.Key -eq "ntpd"} | Set-VMHostService -policy "on" -Confirm:$false | FT | Out-Null

   Write-Host "Restarting NTP Client on $VMHost" -ForegroundColor Green
   Get-VMHostService -VMHost $VMHost | where {$_.Key -eq "ntpd"} | Restart-VMHostService -Confirm:$false | FT | Out-Null

 }


# -- Network Configuration --


# -- Create DVSwitch --

	Write-Host "Creating VDSwitch: $VDSName" -ForegroundColor Green
	$VDS = New-VDSwitch -Name $VDSName -NumUplinkPorts 2 -Location $DC -Mtu 9000 -Version "6.0.0"

# -- Create Portgroups --

	Write-Host "Creating PortGroup: VSAN Network $PrimaryPortGroup" -ForegroundColor Green
	New-VDPortgroup -Name "VSAN Network $PrimaryPortGroup" -Vds $vds -VlanId $PrimaryPortGroup | Out-Null
	Write-Host "Creating PortGroup: VSAN Network $SecondaryPortGroup" -ForegroundColor Green
	New-VDPortgroup -Name "VSAN Network $SecondaryPortGroup" -Vds $vds -VlanId $SecondaryPortGroup | Out-Null
	Write-Host "Creating PortGroup: VSAN Network $WitnessPortGroup" -ForegroundColor Green
	New-VDPortgroup -Name "VSAN Network $WitnessPortGroup" -Vds $vds -VlanId $WitnessPortGroup | Out-Null
	Write-Host "Creating vMotion Network 3021" -ForegroundColor Green
	New-VDPortgroup -Name "vMotion Network 3021" -VDSwitch $vds -VlanId 3021 | Out-Null


# -- Add Hosts to VDSWitch and Migrate pNIC to VDS (vmnic2/vmnic3) --

	Foreach ($vmhost in ($DC | Get-VmHost)) {
    Write-Host "Adding $VMHost to $VDSName" -ForegroundColor Green
    $vds | Add-VDSwitchVMHost -VMHost $vmhost | Out-Null
    $vmhostNetworkAdapter = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic2
    Write-Host "Adding $VMHostNetworkAdapter to $VDSName" -ForegroundColor Green
    $vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false | Out-Null
    $vmhostNetworkAdapter = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic3
    Write-Host "Adding $VMHostNetworkAdapter to $VDSName" -ForegroundColor Green
    $vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false | Out-Null
}

# -- Set DVUplink2 to standby --

	$TeamingPolicys = $vds | Get-VDPortgroup VSAN* | Get-VDUplinkTeamingPolicy
	Foreach ($Policy in $TeamingPolicys) {
    Write-Host "Setting Standby Uplink for $($Policy.VDPortGroup)" -ForegroundColor Green
    $Policy | Set-VDUplinkTeamingPolicy -StandbyUplinkPort "dvUplink2" | Out-Null
}   


# -- Create vMotion VMKernel Ports for all hosts in DC --

	foreach ($vmhost in ($DC | Get-VmHost)) {
    $HostIP = ($vmhost | Get-VMHostNetworkAdapter -Name vmk0).ip
    $LastO = $HostIP.Split(".")[3]
    $VSANNet = Get-VDPortGroup "VSAN Network $PrimaryPortGroup"
    $3rdO = ($VSANNet.Name).Substring(16)
    $CurrentvMotionIP = $vMotionIP + $LastO
    Write-Host "Adding vMotion Network Adapter to $VMHost with IP of $CurrentvMotionIP" -ForegroundColor Green
    New-vmhostnetworkadapter -VMHost $vmhost -PortGroup "vMotion Network 3021" -VirtualSwitch $vds -VMotionEnabled $true -IP $CurrentvMotionIP -SubnetMask "255.255.255.0" | Out-Null
    
}

#Adding Static Routes for Virtual SAN Streched Cluster

# -- Primary site --

	09..12 | Foreach {
    $num = $_  
    $newnum = "{0:D2}" -f $num
    $VMHost = "hostname-$newnum.vmware.com"
    $HostIP = (Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Name vmk0).ip
    $LastO = $HostIP.Split(".")[3]
    $VSANNet = Get-VDPortGroup "VSAN Network $PrimaryPortGroup"
    $3rdO = ($VSANNet.Name).Substring(16)
    $CurrentVSANIP = $VSANIP + $3rdO + "." + $LastO
    Write-Host "Adding $CurrentVSANIP to $($VSANNet.Name) and enabling VSAN traffic" -ForegroundColor Green
    $VSANVMK = New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $VSANNet.Name -VirtualSwitch $vds -VsanTrafficEnabled $true -IP $CurrentVSANIP -SubnetMask "255.255.255.0"
    Write-Host "Adding Static Routes for primary Site to host hostname-$newnum.vmware.com" -ForegroundColor Green
    New-VMHostRoute -VMHost $VMHost -Destination $SecondarySR -Gateway $PrimaryGW -PrefixLength 24 -Confirm:$false | Out-Null
    New-VMHostRoute -VMHost $VMHost -Destination $WitnessSR -Gateway $PrimaryGW -PrefixLength 24 -Confirm:$false | Out-Null
    if (-not $1PrimaryIP) {
        $1PrimaryIP = (Get-VMHost $VMHost | Get-VMHostNetworkAdapter -Name $VMKnet).IP
    }
 }

# -- Secondary Site --

	13..16 | Foreach {
    $num = $_ ; 
    $newnum = "{0:D2}" -f $num
    $VMHost = "hostname-$newnum.vmware.com"
    $HostIP = (Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Name vmk0).ip
    $LastO = $HostIP.Split(".")[3]
    $VSANNet = Get-VDPortGroup "VSAN Network $SecondaryPortGroup"
    $3rdO = ($VSANNet.Name).Substring(16)
    $CurrentVSANIP = $VSANIP + $3rdO + "." + $LastO
    Write-Host "Adding $CurrentVSANIP to $($VSANNet.Name) and enabling VSAN traffic" -ForegroundColor Green
    $VSANVMK = New-vmhostnetworkadapter -VMHost $vmhost -PortGroup $VSANNet.Name -VirtualSwitch $vds -VsanTrafficEnabled $true -IP $CurrentVSANIP -SubnetMask "255.255.255.0"
    Write-Host "Adding Static Routes for Secondary Site to host hostname-$newnum.vmware.com" -ForegroundColor Green
    New-VMHostRoute -VMHost $VMHost -Destination $PrimarySR -Gateway $SecondaryGW -PrefixLength 24 -Confirm:$false | Out-Null
    New-VMHostRoute -VMHost $VMHost -Destination $WitnessSR -Gateway $SecondaryGW -PrefixLength 24 -Confirm:$false | Out-Null
    if (-not $1SecondaryIP) {
        $1SecondaryIP = (Get-VMHost $VMHost | Get-VMHostNetworkAdapter -Name $VMKnet).IP
    }
}

# -- witness Site --

	Write-Host "Adding Static Routes to Witness" -ForegroundColor Green
	New-VMHostRoute -VMHost $witness -Destination $PrimarySR -Gateway $WitnessGW -PrefixLength 24 -Confirm:$false | Out-Null
	New-VMHostRoute -VMHost $witness -Destination $SecondarySR -Gateway $WitnessGW -PrefixLength 24 -Confirm:$false | Out-Null


# -- communication validation between all Hosts and networks -- 

# -- primary site --
  
	09..12 | Foreach {
    $num = $_ ; 
    $newnum = "{0:D2}" -f $num
    $VMHost = "hostname-$newnum.vmware.com"
    $VMKnet = (Get-VMHostNetworkAdapter -VMHost $vmhost -PortGroup "VSAN*").Name
    Write-Host "Pinging $SecondarySR from $VMHost on $vmknet..." -ForegroundColor Green
    $esxcli = Get-ESXCLI -VMhost $vmhost
    $ping = $esxcli.network.diag.ping(2,$null,$null,$1SecondaryIP,$vmknet,$null,$null,$null,$null,$null,$null,$null,$null) | select -expand Summary
    if ($ping.Recieved -ge 1) {
        Write-Host "Ping of Secondary: $1SecondaryIP Tested OK" -ForegroundColor Yellow
    } Else {
        Write-Host "Ping of Secondary: $1SecondaryIP Failed" -ForegroundColor Red
    }
    Write-Host "Pinging $WitnessSR from $VMHost on $VMKnet..." -ForegroundColor Green
    $ping = $esxcli.network.diag.ping(2,$null,$null,$WitnessIP,$vmknet,$null,$null,$null,$null,$null,$null,$null,$null) | select -expand Summary
    if ($ping.Recieved -ge 1) {
        Write-Host "Ping of Witness: $WitnessSR Tested OK" -ForegroundColor Yellow
    } Else {
        Write-Host "Ping of Witness: $WitnessSR Failed" -ForegroundColor Red
    }
}

# -- secondary site --

	13..16 | Foreach {
    $num = $_ ; 
    $newnum = "{0:D2}" -f $num
    $VMHost = "hostname-$newnum.vmware.com"
    $VMKnet = (Get-VMHostNetworkAdapter -VMHost $vmhost -PortGroup "VSAN*").Name
    Write-Host "Pinging $PrimarySR from $VMHost on $vmknet..." -ForegroundColor Green
    $esxcli = Get-ESXCLI -VMhost $vmhost
    $ping = $esxcli.network.diag.ping(2,$null,$null,$1PrimaryIP,$vmknet,$null,$null,$null,$null,$null,$null,$null,$null) | select -expand Summary
    if ($ping.Recieved -ge 1) {
        Write-Host "Ping of Primary: $1PrimaryIP Tested OK" -ForegroundColor Yellow
    } Else {
        Write-Host "Ping of Primary: $1PrimaryIP Failed" -ForegroundColor Red
    }
    Write-Host "Pinging $WitnessSR from $VMHost on $vmknet..." -ForegroundColor Green
    $ping = $esxcli.network.diag.ping(2,$null,$null,$WitnessIP,$vmknet,$null,$null,$null,$null,$null,$null,$null,$null) | select -expand Summary
    if ($ping.Recieved -ge 1) {
        Write-Host "Ping of Witness: $WitnessSR Tested OK" -ForegroundColor Yellow
    } Else {
        Write-Host "Ping of Witness: $WitnessSR Failed" -ForegroundColor Red
    }
}

# -- witness site --

    $VMKnet = (Get-VMHostNetworkAdapter -VMHost $witness -PortGroup "VSAN*").Name
    Write-Host "Pinging $PrimarySR from $witness on $vmknet..." -ForegroundColor Green
    $esxcli = Get-ESXCLI -VMhost $witness
    $Ping = $esxcli.network.diag.ping(2,$null,$null,$1PrimaryIP,$vmknet,$null,$null,$null,$null,$null,$null,$null,$null) | select -expand Summary
    if ($ping.Recieved -ge 1) {
        Write-Host "Ping of Primary: $1PrimaryIP Tested OK" -ForegroundColor Yellow
    } Else {
        Write-Host "Ping of Primary: $1PrimaryIP Failed" -ForegroundColor Red
    }
    Write-Host "Pinging $SecondarySR from $witness
