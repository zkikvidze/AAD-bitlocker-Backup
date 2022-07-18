#required modules:
#Microsoft.Graph.Authentication
#Microsoft.Graph.Identity.DirectoryManagement
#Microsoft.Graph.DeviceManagement
#Microsoft.Graph.Identity.SignIns

Connect-MgGraph -Scopes "BitlockerKey.Read.All", "BitlockerKey.ReadBasic.All", "Device.Read.All", "DeviceManagementManagedDevices.Read.All"

$cdate = Get-Date -Format "dd-MM-yyyy"
$tmppath = $pwd
$csvfilename = "bitlocker-backup-$cdate.csv"
$logfilename = "bitlocker-backup-log-$cdate.txt"
$csvfilepath = "$tmppath\$csvfilename"
$logfilepath = "$tmppath\$logfilename"

$devices = @(Get-MgDevice -All -CountVariable CountVar -Filter "approximateLastSignInDateTime ge 1970-01-01T00:00:00.000Z and approximateLastSignInDateTime le 2022-01-08T11:02:15.864Z and startswith(operatingSystem,'Windows')" -Property "DisplayName,DeviceId,Id")

foreach ($device in $devices) 

{
    $deviceid = $device.DeviceID.trim()

    try
    {
        try
        {
            #Get Device Info From MDM
            $deviceinfo = Get-MgDeviceManagementManagedDevice -Filter "azureADDeviceId eq '$deviceid'" -Property "deviceName,id,azureADDeviceId,serialNumber,manufacturer,model,UserPrincipalName" -ErrorAction Stop -ErrorVariable GraphError
            if ($deviceinfo -eq $null)
            {
                Write-Host $deviceid",DeviceID Is Not Managed By MDM"
                Add-Content -Path "$logfilepath" -Value "$deviceid DeviceID Is Not Managed By MDM"
            }
        }
        catch
        {
            if ($_.FullyQualifiedErrorId -eq "BadRequest,Microsoft.Graph.PowerShell.Cmdlets.GetMgDeviceManagementManagedDevice_List1")
            {
                Write-Host $deviceid",DeviceID Is Not Managed By MDM"
                Add-Content -Path "$logfilepath" -Value "$deviceid DeviceID Is Not Managed By MDM"
            }
            else
            {
                Write-Host $deviceid",Unknow ERROR"
                Add-Content -Path "$logfilepath" -Value "$deviceid Unknow ERROR"
            }
            
        }
        #get bitlocker key IDs
        try
        {
            $bitlockerkeys = @(Get-MgInformationProtectionBitlockerRecoveryKey -Filter "DeviceId eq '$deviceid'" -ErrorAction Stop -ErrorVariable GraphError)
            if (!$bitlockerkeys)
            {
                Write-Host $deviceid",DeviceID Have No Bitlocker Key Associated"
                Add-Content -Path "$logfilepath" -Value "$deviceid DeviceID Have No Bitlocker Key Associated"
            }
        }
        catch
        {
            
            if ($_.FullyQualifiedErrorId -eq "invalid_request,Microsoft.Graph.PowerShell.Cmdlets.GetMgInformationProtectionBitlockerRecoveryKey_List1")
            {
                Write-Host $deviceid",DeviceID Have No Bitlocker Key Associated"
                Add-Content -Path "$logfilepath" -Value "$deviceid DeviceID Have No Bitlocker Key Associated"

            }
            else
            {
                Write-Host $deviceid",Unknow ERROR While Getting Bitlocker Keys From Device"
                Add-Content -Path "$logfilepath" -Value "$deviceid Unknow ERROR While Getting Bitlocker Keys From Device"
            }
        }

        foreach ($bitlockerkey in $bitlockerkeys)
        {
            #get bitlocker recovery keys
            try
            {
                $bitlockerrecoverykey = Get-MgInformationProtectionBitlockerRecoveryKey -BitlockerRecoveryKeyId $bitlockerkey.id -Property "Key" -ErrorAction Stop -ErrorVariable GraphError
                $deviceline = New-Object -Type PSObject -Property  @{ deviceid = $deviceid;displayname = $device.DisplayName;objectid = $device.id;deviceserial = $deviceinfo.serialNumber;devicemanufacturer = $deviceinfo.manufacturer;devicemodel = $deviceinfo.model;user = $deviceinfo.UserPrincipalName;bitlockerkeyid = $bitlockerkey.id;bitlockerkey = $bitlockerrecoverykey.key;volumeid = $bitlockerkey.VolumeType }
                write-host $deviceline
                $deviceline | export-csv -Append -noType $csvfilepath -Force
            }
            catch
            {
                Write-Host $device",Unknown Error, Can't grab Bitlocker Recovery Key With Key ID: "$bitlockerkey
                Add-Content -Path "$logfilepath" -Value "$device Unknown Error, Can't grab Bitlocker Recovery Key With Key ID: $bitlockerkey"

            }
        }
     }
    catch
    {
        Write-Host $deviceid",Unknown Error With DeviceID: "$_.FullyQualifiedErrorId
        Add-Content -Path "$logfilepath" -Value "$deviceid Unknown Error With DeviceID: $_.FullyQualifiedErrorId"
    }
}
