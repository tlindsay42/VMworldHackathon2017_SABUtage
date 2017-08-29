Function Set-DrsAndHA {
	Param (
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster
    )

    # VMware's Best Practice values for configuration with a stretched cluster
    $Settings = @{
        "HAEnabled" = $true;
        "HAIsolationResponse" = "PowerOff";
        "HAAdmissionControlEnabled" = $true;
        "DrsEnabled" = $true
        "DrsAutomationLevel" = "PartiallyAutomated";

    }

    # Update Cluster Settings
    Set-Cluster -Cluster $Cluster -HAIsolationResponse

    # Set Admission Control Policy to 50% CPU and Memory and Do not use datastores for heartbeating 
    $spec = New-Object VMware.Vim.ClusterConfigSpecEx
    $spec.dasConfig = New-Object VMware.Vim.ClusterDasConfigInfo
    $spec.dasConfig.HeartbeatDatastore = $null
    $spec.dasConfig.admissionControlPolicy = New-Object VMware.Vim.ClusterFailoverResourcesAdmissionControlPolicy
    $spec.dasConfig.admissionControlPolicy.cpuFailoverResourcesPercent = 50
    $spec.dasConfig.admissionControlPolicy.memoryFailoverResourcesPercent = 50
    $Cluster.ExtensionData.ReconfigureComputeResource_Task($spec, $true)
}

Function Set-IsolationAddress {
    Param (
        [String]$IP1,
        [String]$IP2
    )

    New-AdvancedSetting -Entity $cluster -Type ClusterHA -Name 'das.isolationaddress1' -Value $IP1
    if ($IP2) { New-AdvancedSetting -Entity $cluster -Type ClusterHA -Name 'das.isolationaddress2' -Value $IP2 }

    # Disable Default Isolation Address Check
    New-AdvancedSetting -Entity $cluster -Type ClusterHA -Name 'das.usedefaultisolationaddress' -Value false
}

Function Set-vSanLocalityGroups {
    Param (
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$Location1,
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$Location2
    )
    $PreferredVMHostGroup = New-DrsClusterGroup -Cluster $Cluster -Name "Host Location 1" -VMHost $PreferredFaultDomainHostList
    $SecondaryVMHostGroup = New-DrsClusterGroup -Cluster $Cluster -Name $SecondaryVMHostGroupName -VMHost $SecondaryFaultDomainHostList

}