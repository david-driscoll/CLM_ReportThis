[CmdletBinding()]
param (
    [Parameter()]
    $path
)

if ((Test-Path "$path\CLM_ReportThis\") -and (-not (Get-Item "$path\CLM_ReportThis\").LinkType)) {
    Remove-Item "$path\CLM_ReportThis\" -Recurse -Force
}
New-Item -ItemType Junction -Path "$path\CLM_ReportThis\" -Target ($PWD.Path)