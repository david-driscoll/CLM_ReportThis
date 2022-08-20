[CmdletBinding()]
param (
    [Parameter()]
    $version
)
Remove-Item *.zip
Compress-Archive . -DestinationPath $version-bcc.zip