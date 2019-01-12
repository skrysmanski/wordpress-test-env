#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory=$True)]
    [string] $ProjectFile,

    [string] $WordpressVersion = '',

    [string] $PhpVersion = '',

    [switch] $KeepVolumes
)

# Stop on every error
$script:ErrorActionPreference = 'Stop'

try {
    & $PSScriptRoot/Unload-Modules.ps1

    Import-Module "$PSScriptRoot/WordpressTestEnv.psm1" -DisableNameChecking

    Write-Title 'Stopping Docker containers...'

    $projectDescriptor = Get-ProjectDescriptor $ProjectFile

    $wordpressTag = Get-DockerWordpressTag -WordpressVersion $WordpressVersion -PhpVersion $PhpVersion

    $composeProjectName = Get-DockerComposeProjectName -ProjectName $projectDescriptor.ProjectName -WordpressTag $wordpressTag

    $composeFilePath = Get-ComposeFilePAth -ComposeProjectName $ComposeProjectName

    & docker-compose --file $composeFilePath --project-name $ComposeProjectName down
    if (-Not $?) {
        Write-Error '"docker-compose down" failed'
    }

    if (-Not $KeepVolumes) {
        Write-Title 'Deleting volumes...'

        # NOTE: Apparently, volume names don't allow for '.' in their names.
        #   They're simply stripped.
        $projectNameForVolumes = $composeProjectName.Replace('.', '')

        & docker volume remove "$($projectNameForVolumes)_wordpress" "$($projectNameForVolumes)_db"
        if (-Not $?) {
            # NOTE: We don't need to stop the script here with "Write-Error".
            Write-Host -ForegroundColor Red 'Some errors while deleting volumes.'
        }
    }

    # Delete compose file
    Remove-Item $composeFilePath | Out-Null
}
catch {
    # IMPORTANT: We compare type names(!) here - not actual types. This is important because - for example -
    #   the type 'Microsoft.PowerShell.Commands.WriteErrorException' is not always available (most likely
    #   when Write-Error has never been called).
    if ($_.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.WriteErrorException') {
        # Print error messages (without stacktrace)
        Write-Host -ForegroundColor Red $_.Exception.Message
    }
    else {
        # Print proper exception message (including stack trace)
        # NOTE: We can't create a catch block for "RuntimeException" as every exception
        #   seems to be interpreted as RuntimeException.
        if ($_.Exception.GetType().FullName -eq 'System.Management.Automation.RuntimeException') {
            Write-Host -ForegroundColor Red $_.Exception.Message
        }
        else {
            Write-Host -ForegroundColor Red "$($_.Exception.GetType().Name): $($_.Exception.Message)"
        }
        Write-Host -ForegroundColor Red $_.ScriptStackTrace
    }

    exit 1
}
