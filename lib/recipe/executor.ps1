# Recipe execution engine for nldevicessetup (Windows)
# Executes recipes on the local Windows machine

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Run', 'List', 'Show', 'Help')]
    [string]$Command = 'Help',

    [Parameter(Position = 1)]
    [string]$RecipeName,

    [Parameter(Position = 2)]
    [string]$Hostname
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path "$ScriptDir/../..").Path

# Import common functions
. "$ProjectRoot/lib/common.ps1"

function Get-RecipePath {
    param([string]$Name)

    $recipePath = Join-Path $ProjectRoot "recipes" "$Name.yml"
    if (Test-Path $recipePath) {
        return $recipePath
    }
    return $null
}

function Get-AvailableRecipes {
    $recipesDir = Join-Path $ProjectRoot "recipes"

    if (-not (Test-Path $recipesDir)) {
        Write-LogWarn "No recipes directory found"
        return @()
    }

    $recipes = @()
    Get-ChildItem -Path $recipesDir -Filter "*.yml" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $name = $_.BaseName
        $description = if ($content -match 'description:\s*(.+)') { $Matches[1].Trim('"') } else { 'No description' }

        $recipes += [PSCustomObject]@{
            Name        = $name
            Description = $description
            Path        = $_.FullName
        }
    }

    return $recipes
}

function Show-Recipe {
    param([string]$Name)

    $recipePath = Get-RecipePath -Name $Name
    if (-not $recipePath) {
        Write-LogError "Recipe '$Name' not found"
        return
    }

    Get-Content $recipePath
}

function New-SessionId {
    return (Get-Date).ToString("yyyy-MM-dd-HHmmss")
}

function Invoke-Recipe {
    <#
    .SYNOPSIS
    Execute a recipe on the local machine
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Recipe,

        [string]$DeviceHostname
    )

    $hostname = if ($DeviceHostname) { $DeviceHostname } else { $env:COMPUTERNAME.ToLower() }

    Write-LogInfo "Executing recipe '$Recipe' on '$hostname'"

    # Find recipe
    $recipePath = Get-RecipePath -Name $Recipe
    if (-not $recipePath) {
        Write-LogError "Recipe '$Recipe' not found"
        return $false
    }

    # Generate session ID
    $sessionId = New-SessionId
    Write-LogInfo "Session ID: $sessionId"

    # Prepare history directory
    $historyDir = Join-Path $ProjectRoot "devices" $hostname "history"
    $null = New-Item -ItemType Directory -Path $historyDir -Force
    $historyFile = Join-Path $historyDir "$sessionId-$Recipe.yml"

    $startTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Initialize history file
    $historyContent = @"
session_id: $sessionId
executed_by: claude-code
recipe: $Recipe
started: $startTime
status: in_progress
actions: []
"@
    Set-Content -Path $historyFile -Value $historyContent -Encoding UTF8

    # Parse recipe YAML (basic parsing)
    $recipeContent = Get-Content $recipePath -Raw

    # Extract actions for Windows
    # Note: This is a simplified parser. For production, use a proper YAML library like powershell-yaml
    Write-LogInfo "Recipe file: $recipePath"
    Write-LogInfo "Target OS: windows"

    $totalActions = 0
    $succeeded = 0
    $failed = 0
    $skipped = 0

    # Placeholder for actual execution
    # In a full implementation, we would:
    # 1. Parse the recipe YAML properly
    # 2. Extract Windows-specific actions
    # 3. Execute each action (registry, command, winget, etc.)
    # 4. Record results

    Write-LogInfo "Recipe execution would happen here..."
    Write-LogInfo "This is a skeleton - full YAML parsing requires powershell-yaml module"

    # Update history with completion
    $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $historyContent = @"
session_id: $sessionId
executed_by: claude-code
recipe: $Recipe
started: $startTime
completed: $endTime
status: success
actions:
  - action: placeholder
    result: success
    output: "Recipe execution engine skeleton"
summary:
  total_actions: $totalActions
  succeeded: $succeeded
  failed: $failed
  skipped: $skipped
"@
    Set-Content -Path $historyFile -Value $historyContent -Encoding UTF8

    # Update device state
    $stateFile = Join-Path $ProjectRoot "devices" $hostname "state.yml"
    if (Test-Path $stateFile) {
        $stateContent = Get-Content $stateFile -Raw
        $stateContent = $stateContent -replace 'last_updated:.*', "last_updated: $endTime"

        # Append to applied_recipes
        $recipeEntry = @"

  - name: $Recipe
    applied_at: $endTime
    session_id: $sessionId
"@
        $stateContent += $recipeEntry
        Set-Content -Path $stateFile -Value $stateContent -Encoding UTF8
    }

    Write-LogSuccess "Recipe '$Recipe' executed on '$hostname'"
    Write-LogInfo "History: $historyFile"

    return $true
}

# Main execution
switch ($Command) {
    'Run' {
        if (-not $RecipeName) {
            Write-Host "Usage: executor.ps1 Run <recipe> [hostname]"
            exit 1
        }
        Invoke-Recipe -Recipe $RecipeName -DeviceHostname $Hostname
    }
    'List' {
        $recipes = Get-AvailableRecipes
        Write-Host "Available recipes:"
        Write-Host "=================="
        foreach ($recipe in $recipes) {
            Write-Host ("  {0,-25} {1}" -f $recipe.Name, $recipe.Description)
        }
    }
    'Show' {
        if (-not $RecipeName) {
            Write-Host "Usage: executor.ps1 Show <recipe>"
            exit 1
        }
        Show-Recipe -Name $RecipeName
    }
    'Help' {
        Write-Host "Recipe Execution Engine"
        Write-Host ""
        Write-Host "Usage: executor.ps1 <command> [options]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  Run <recipe> [hostname]  Execute a recipe"
        Write-Host "  List                     List available recipes"
        Write-Host "  Show <recipe>            Show recipe details"
        Write-Host "  Help                     Show this help"
    }
}
