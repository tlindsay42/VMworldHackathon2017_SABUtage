Function Start-Sabutage {
    Param (
        $Server,
        $Credential,
        $KillCount = 1
    )

    Connect-VIServer -Server $Server -Credential $Credential

    while ($KillCount > 0) {
        Get-VMHost | Get-Random | Stop-VMHost -Force
        $KillCount = $KillCount - 1
    }

}

$server = 192.168.0.10
$cred = Get-Credential
Start-Sabutage -Server $server -Credential $cred
