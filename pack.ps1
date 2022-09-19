[CmdletBinding()]
param (
    [Parameter()]
    $version
)
Remove-Item *.zip
Compress-Archive . -DestinationPath CLM_ReportThis-$version-wrath.zip