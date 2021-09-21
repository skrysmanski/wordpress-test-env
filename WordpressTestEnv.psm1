# Stop on every error
$script:ErrorActionPreference = 'Stop'

function Write-Title($Text) {
    Write-Host
    Write-Host -ForegroundColor Cyan $Text
}

# Tests whether Docker is running. Note that this check takes about 3 seconds
# if Docker is not running. So you should not use it frequently.
function Test-DockerIsRunning() {
    & docker info | Out-Null
    return $?
}

function Get-ProjectDescriptor([string] $ProjectFile) {
    if ([string]::IsNullOrWhiteSpace($ProjectFile)) {
        Write-Error 'No project file has been specified.'
    }

    $projectDescriptor = Get-Content $ProjectFile -Encoding 'utf8' | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace($projectDescriptor.ProjectName)) {
        Write-Error "Missing property 'ProjectName' in '$ProjectFile'."
    }

    return $projectDescriptor
}

function Get-DockerWordpressTag([string] $WordpressVersion, [string] $PhpVersion) {
    # NOTE: Instead of using the "latest" tag we obtain the newest Wordpress version
    #   using a REST API. "latest" won't always point to the newest version if cached
    #   locally (see https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375).
    if ($WordpressVersion -eq '') {
        $WordpressVersion = Get-LatestWordpressVersion
    }

    if (($WordpressVersion -ne '') -and ($PhpVersion -ne '')) {
        return "$WordpressVersion-php$PhpVersion"
    }
    elseif ($WordpressVersion -ne '') {
        return $WordpressVersion
    }
    elseif ($PhpVersion -ne '') {
        return "php$PhpVersion"
    }
    else {
        throw 'We should not get here.'
    }
}

function Get-DockerComposeProjectName([string] $ProjectName, [string] $WordpressTag) {
    return "$ProjectName-wp-$WordpressTag"
}

function Get-ComposeFilePath([string] $ComposeProjectName) {
    New-Item "$PSScriptRoot/envs" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    return "$PSScriptRoot/envs/docker-compose.$($ComposeProjectName).yml"
}

function New-WordpressTestEnvComposeFile([string] $ComposeProjectName, [string] $WordpressTag, [string] $MySqlTag, [int] $Port, [string[]] $volumes) {
    $DB_NAME = 'wpdb'
    $DB_USER = 'wordpress'
    $DB_PASSWORD = 'insecure-password123'

    $volumesString = ''

    if ($volumes) {
        foreach ($volume in $volumes) {
            $volumesString += @"
            - $volume`n
"@
        }

        $volumesString = $volumesString.TrimEnd("`n")
    }

    $contents = @"
# Docker images:
#
# * https://hub.docker.com/_/wordpress
# * https://hub.docker.com/_/mysql
#
version: '3.1'

services:

    web:
        image: wordpress:$WordpressTag
        container_name: $($ComposeProjectName)_web
        depends_on:
            - db
        ports:
            - 127.0.0.1:$($Port):80
        volumes:
            - wordpress:/var/www/html
$volumesString
        environment:
            WORDPRESS_DB_HOST: db
            WORDPRESS_DB_NAME: $DB_NAME
            WORDPRESS_DB_USER: $DB_USER
            WORDPRESS_DB_PASSWORD: $DB_PASSWORD
            WORDPRESS_DEBUG: '1'

    db:
        image: mysql:$MySqlTag
        container_name: $($ComposeProjectName)_db
        volumes:
            - db:/var/lib/mysql
        environment:
            MYSQL_DATABASE: $DB_NAME
            MYSQL_USER: $DB_USER
            MYSQL_PASSWORD: $DB_PASSWORD
            MYSQL_RANDOM_ROOT_PASSWORD: '1'

volumes:
    wordpress:
    db:
"@

    $composeFilePath = Get-ComposeFilePath -ComposeProjectName $ComposeProjectName
    $contents | Out-File $composeFilePath -Encoding 'utf8'

    return $composeFilePath
}

function Get-LatestWordpressVersion() {
    if ($script:LatestWordpressVersion) {
        return $script:LatestWordpressVersion
    }

    Write-Host -ForegroundColor DarkGray -NoNewline 'Determining latest Wordpress version...'

    # For reference, see:
    # * https://codex.wordpress.org/WordPress.org_API#Version_Check
    # * https://developer.wordpress.org/reference/functions/wp_version_check/
    $httpResponse = Invoke-WebRequest -Uri "https://api.wordpress.org/core/version-check/1.7/?version=5.0.2"

    if ($httpResponse.StatusCode -ne 200) {
        Write-Error "Could not determine newest Wordpress version. Got HTTP status code $($httpResponse.StatusCode)"
    }

    $response = $httpResponse.Content | ConvertFrom-Json

    $version = $response.offers[0].version

    if ([string]::IsNullOrWhiteSpace($version)) {
        Write-Error 'Could not determine newest Wordpress version. Received unexpected JSON.'
    }

    Write-Host -ForegroundColor DarkCyan $version

    # Cache this for the duration of the script.
    $script:LatestWordpressVersion = $version

    return $version
}
