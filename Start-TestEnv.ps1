#!/usr/bin/env pwsh
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
param(
    [Parameter(Mandatory=$True)]
    [string] $ProjectFile,

    [string] $WordpressVersion = '',

    [string] $PhpVersion = '',

    [int] $Port = 8080,

    [int] $MaxConnectRetries = 20,

    [string] $AdminUserName = 'admin',

    [string] $AdminPassword = 'test1234'
)

# Stop on every error
$script:ErrorActionPreference = 'Stop'

try {
    & $PSScriptRoot/Unload-Modules.ps1

    Import-Module "$PSScriptRoot/WordpressTestEnv.psm1" -DisableNameChecking

    Write-Title 'Spinning up Docker containers...'

    $projectDescriptor = Get-ProjectDescriptor $ProjectFile

    $wordpressTag = Get-DockerWordpressTag -WordpressVersion $WordpressVersion -PhpVersion $PhpVersion

    $composeProjectName = Get-DockerComposeProjectName -ProjectName $projectDescriptor.ProjectName -WordpressTag $wordpressTag

    $volumes = @()

    if ($projectDescriptor.Mounts) {
        foreach ($mount in $projectDescriptor.Mounts) {
            $hostPath = [IO.Path]::GetFullPath($mount.Host)
            $volumeString = "$($hostPath):/var/www/html/$($mount.Container)"
            if ($mount.ReadOnly) {
                $volumeString += ':ro'
            }

            $volumes += $volumeString
        }
    }

    $composeFilePath = New-WordpressTestEnvComposeFile `
        -ComposeProjectName $composeProjectName `
        -WordpressTag $wordpressTag `
        -Port $Port `
        -Volumes $volumes

    & docker-compose --file $composeFilePath --project-name $composeProjectName up --detach
    if (-Not $?) {
        throw '"docker-compose up" failed'
    }

    Write-Title 'Waiting for containers to come up (this may take some time)...'

    for ($i = 0; $i -lt $MaxConnectRetries; $i++) {
        try {
            Invoke-WebRequest -Uri "http://localhost:$Port" | Out-Null
            Write-Host -ForegroundColor Green 'Container is up'
            break
        }
        catch {
            if ($i -lt ($MaxConnectRetries - 1)) {
                Start-Sleep -Seconds 3
                Write-Host -ForegroundColor DarkGray "Attempt: $($i + 2)"
            }
            else {
                Write-Error 'Containers did not come up'
            }
        }
    }

    $containerId = & docker-compose --file $composeFilePath --project-name $composeProjectName ps -q web
    if ((-Not $?) -or (-Not $containerId)) {
        throw 'Could not determine container id of web container'
    }

    # Fix some permissions that are broken due to mounting the plugin.
    & docker exec -t $containerId chown www-data /var/www/html/wp-content /var/www/html/wp-content/plugins
    if (-Not $?) {
        throw 'Could change ownership of certain directories in the container.'
    }

    function Invoke-WordpressCli {
        #
        # Wordpress CLI:
        #  - https://wp-cli.org/
        #  - https://developer.wordpress.org/cli/commands/
        #
        # NOTE: For CLI commands, the PHP version doesn't really matter. Thus we don't use it.
        #
        # IMPORTANT: We need to specify the user id (33) explicitely here because in the CLI image the user id
        #   for www-data is different than in the actual wordpress image (most likely because the cli image is
        #   Alpine while the actual image is Debian). See also: https://github.com/docker-library/wordpress/issues/256
        & docker run -it --rm --user 33 --volumes-from $containerId --network container:$containerId wordpress:cli @args
        if (-Not $?) {
            Write-Error "Wordpress CLI failed: $args"
        }
    }

    Write-Title 'Installing WordPress...'
    Invoke-WordpressCli core install `
        "--url=localhost:$Port" `
        '--title=Wordpress Test Site' `
        "--admin_user=$AdminUserName" `
        "--admin_password=$AdminPassword" `
        '--admin_email=test@test.com' `
        --skip-email `
        --color

    if ($projectDescriptor.SetupCommands) {
        foreach ($setupCommand in $projectDescriptor.SetupCommands) {
            if ($setupCommand.Condition) {
                $conditionMet = Invoke-Expression $setupCommand.Condition
                if (-Not $conditionMet) {
                    continue
                }
            }

            Write-Title $setupCommand.Title

            $commandArgs = $setupCommand.CommandArgs
            Invoke-WordpressCli @commandArgs
        }
    }

    Write-Host
    Write-Host
    Write-Host 'Your Wordpress test env is now available at:'
    Write-Host
    Write-Host -ForegroundColor Cyan "    http://localhost:$Port"
    Write-Host
    Write-Host "Admin Login: "
    Write-Host
    Write-Host -ForegroundColor Cyan "    $AdminUserName // $AdminPassword"
    Write-Host
}
catch {
    function LogError([string] $exception) {
        Write-Host -ForegroundColor Red $exception
    }

    # Type of $_: System.Management.Automation.ErrorRecord

    # NOTE: According to https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/windows-powershell-error-records
    #   we should always use '$_.ErrorDetails.Message' instead of '$_.Exception.Message' for displaying the message.
    #   In fact, there are cases where '$_.ErrorDetails.Message' actually contains more/better information than '$_.Exception.Message'.
    if ($_.ErrorDetails -And $_.ErrorDetails.Message) {
        $unhandledExceptionMessage = $_.ErrorDetails.Message
    }
    elseif ($_.Exception -And $_.Exception.Message) {
        $unhandledExceptionMessage = $_.Exception.Message
    }
    else {
        $unhandledExceptionMessage = 'Could not determine error message from ErrorRecord'
    }

    # IMPORTANT: We compare type names(!) here - not actual types. This is important because - for example -
    #   the type 'Microsoft.PowerShell.Commands.WriteErrorException' is not always available (most likely
    #   when Write-Error has never been called).
    if ($_.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.WriteErrorException') {
        # Print error messages (without stacktrace)
        LogError $unhandledExceptionMessage
    }
    else {
        # Print proper exception message (including stack trace)
        # NOTE: We can't create a catch block for "RuntimeException" as every exception
        #   seems to be interpreted as RuntimeException.
        if ($_.Exception.GetType().FullName -eq 'System.Management.Automation.RuntimeException') {
            LogError "$unhandledExceptionMessage$([Environment]::NewLine)$($_.ScriptStackTrace)"
        }
        else {
            LogError "$($_.Exception.GetType().Name): $unhandledExceptionMessage$([Environment]::NewLine)$($_.ScriptStackTrace)"
        }
    }

    exit 1
}
