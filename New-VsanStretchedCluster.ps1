#Requires -Module NetTCPIP
#Requires -Module VMware.VimAutomation.Core
#Requires -Module VMware.VimAutomation.Storage
#Requires -Module VMware.VimAutomation.Vds

Function New-VsanStretchedCluster
{
  [CmdletBinding()]
  Param (
    [string] $ConfigFilePath,
    [PSCredential] $VcenterCredentials = ( Get-Credential -Message 'Please enter the vCenter Server SSO credentials' -UserName 'administrator@vsphere.local' -ErrorAction Stop )
  )

  Begin
  {
    If ( ( Get-PowerCLIConfiguration -Scope Session ).DefaultVIServerMode -ne 'Single' )
    {
      Set-PowerCLIConfiguration -DefaultVIServerMode Single -Scope Session -Confirm:$false

      Write-Host
    }

    If ( $global:DefaultVIServer.Length -gt 0 )
    {
      Disconnect-VIServer -Server * -Force -Confirm:$false
    }
  }

  Process
  {
    If ( $ConfigFilePath.Length -eq 0 )
    {
      $config = @{}

      $config.VcenterName = ( Read-Host -Prompt 'Please enter the vCenter Server IP or FQDN' -ErrorAction Stop ).ToString()
      If ( ( Test-NetConnection -ComputerName $config.VcenterName -Port 443 -InformationLevel Quiet -ErrorAction Stop ) -eq $false )
      {
        Write-Error -Message ( 'Invalid vCenter Server address "{0}".' -f $config.VcenterName )
        Return
      }

      Connect-VIServer -Server $config.VcenterName -Credential $VcenterCredentials -ErrorAction Stop
      If ( $global:DefaultVIServer.Length -eq 0 ) { Return }

      $config.DatacenterName = Read-Host -Prompt 'Please enter the datacenter name' -ErrorAction Stop
      $config.DatacenterObject = Get-Datacenter -Name $config.DatacenterName -ErrorAction Stop | 
        Select-Object -First 1
	    If ( $config.DatacenterObject.Count -ne 1 ) { Return }

      $config.ClusterName = Read-Host -Prompt 'Please enter the cluster name' -ErrorAction Stop
      $config.ClusterObject = Get-Cluster -Name $config.ClusterName -ErrorAction Stop |
        Select-Object -First 1
	    If ( $config.ClusterObject.Count -ne 1 ) { Return }
	
      $config.DistributedVswitchName = Read-Host -Prompt 'Please enter the distributed vSwitch name' -ErrorAction Stop
      $config.DistributedVswitchObject = Get-VDSwitch -Name $config.DistributedVswitchName -ErrorAction Stop | 
        Select-Object -First 1
	    If ( $config.DistributedVswitchObject.Count -ne 1 ) { Return }
	
      $config.PrimarySitePortGroupName = Read-Host -Prompt 'Please enter the primary site portgroup name' -ErrorAction Stop
      $config.PrimarySitePortGroupObject = $config.DistributedVswitchObject | 
        Get-VDPortgroup -Name $config.PrimarySitePortGroupName -ErrorAction Stop | 
        Select-Object -First 1
	    If ( $config.PrimarySitePortGroupObject.Count -ne 1 ) { Return }

      $config.SecondarySitePortGroupName = Read-Host -Prompt 'Please enter the secondary site portgroup name' -ErrorAction Stop
      $config.SecondarySitePortGroupObject = $config.DistributedVswitchObject | 
        Get-VDPortgroup -Name $config.SecondarySitePortGroupName -ErrorAction Stop | 
        Select-Object -First 1
	    If ( $config.SecondarySitePortGroupObject.Count -ne 1 ) { Return }

      $config.WitnessSitePortGroupName = Read-Host -Prompt 'Please enter the witness site portgroup name' -ErrorAction Stop
      $config.WitnessSitePortGroupObject = $config.DistributedVswitchObject | 
        Get-VDPortgroup -Name $config.WitnessSitePortGroupName -ErrorAction Stop | 
        Select-Object -First 1
	    If ( $config.WitnessSitePortGroupObject.Count -ne 1 ) { Return }

      $config.VsanIpv4 = ( Read-Host -Prompt 'Please enter one or more VSAN IPv4 addresses (comma-delimited)' -ErrorAction Stop ).Split( ',' ) | 
        ForEach-Object -Process { 
          If ( $_ -match '^(?:(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])|\w+\.\w+.*)$' ) { $_ }
          Else { Write-Error -Message ( 'Invalid IPv4 DNS address: "{0}"' -f $_ ) }
        }
      
      <#
      $config.DnsServer = ( Read-Host -Prompt 'Please enter the DNS Server (comma-delimited, IPv4 only)' -ErrorAction Stop ).Split( ',' ) | 
        ForEach-Object -Process { 
          If ( $_ -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])$' ) { $_ }
          Else { Write-Error -Message ( 'Invalid IPv4 DNS address: "{0}"' -f $_ ) }
        }

      $config.NtpServer = ( Read-Host -Prompt 'Please enter one or more NTP servers (comma-delimited)' -ErrorAction Stop ).Split( ',' ) | 
        ForEach-Object -Process { 
          If ( $_ -match '^(?:(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])|\w+\.\w+.*)$' ) { $_ }
          Else { Write-Error -Message ( 'Invalid IPv4 DNS address: "{0}"' -f $_ ) }
        }

      $config.VmotionIpv4 = ( Read-Host -Prompt 'Please enter one or more vMotion IPv4 addresses (comma-delimited)' -ErrorAction Stop ).Split( ',' ) | 
        ForEach-Object -Process { 
          If ( $_ -match '^(?:(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])|\w+\.\w+.*)$' ) { $_ }
          Else { Write-Error -Message ( 'Invalid IPv4 DNS address: "{0}"' -f $_ ) }
        }

	    $VMotionIP = "192.168.21."
	    $VSANIP = "192.168."
	    $cachingSSD = "S630DC-960"
	    $CapacitySSD = "MICRON_M510DC_MT"
	    $witness = "VSAN-witness-fqdn-or-ip"
	    $witnessIP = "192.168.2.68"
	    $WitnessSNM = "255.255.255.0"
      #>
    }
    ElseIf ( Test-Path -Path $ConfigFilePath )
    {
      $config = Get-Content -Path $ConfigFilePath | 
        ConvertFrom-Json -ErrorAction Stop
    }
    Else
    {
      Write-Error -Message ( 'Invalid config file path: "{0}"' -f $ConfigFilePath ) -ErrorAction Stop
    }
  }
}
