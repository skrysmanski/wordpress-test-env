# Wordpress Test and Development Environment

This repository provides an easy way to spin up and tear down Wordpress environments using Docker.

## Requirements

* Docker
* PowerShell (Core)

## Usage

To use this repository, add it as submodule (under the directory `wordpress-test-env`) to your Wordpress plugin/theme/... repository.

Then create the following 3 files:

### `Start-TestEnv.ps1`

```powershell
#!/usr/bin/env pwsh
& $PSScriptRoot/wordpress-test-env/Start-TestEnv.ps1 -ProjectFile "$PSScriptRoot/wordpress-env.json" @args
```

### `Stop-TestEnv.ps1`

```powershell
#!/usr/bin/env pwsh
& $PSScriptRoot/wordpress-test-env/Stop-TestEnv.ps1 -ProjectFile "$PSScriptRoot/wordpress-env.json" @args
```

### `wordpress-env.json`

The content below is just an example and you need to adjust it to whatever you need.

```json
{
    "ProjectName": "blogtext",

    "Mounts": [
        {
            "Host": "src",
            "Container": "wp-content/plugins/blogtext",
            "ReadOnly": true
        },
        {
            "Host": "tests",
            "Container": "wp-content/plugins/blogtext-tests"
        }
    ],

    "SetupCommands": [
        {
            "Title": "Activating plugin 'BlogText'...",
            "CommandArgs": [ "plugin", "activate", "blogtext" ]
        },
        {
            "Title": "Disabling visual editor for admin...",
            "CommandArgs": [ "user", "meta", "update", "admin", "rich_editing", "false" ]
        },
        {
            "Title": "Installing and activating 'Classic Editor'...",
            "CommandArgs": [ "plugin", "install", "classic-editor", "--activate" ],
            "Condition": "($WordpressVersion -eq '') -or ($WordpressVersion -ge '5.0')"
        }
    ]
}
```
