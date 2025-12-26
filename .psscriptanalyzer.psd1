@{
    # PSScriptAnalyzer Settings for NL Devices Setup
    # These scripts are user-facing CLI tools, so some rules don't apply

    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Write-Host is intentionally used for colored console output in user-facing scripts
        'PSAvoidUsingWriteHost',

        # These are standalone scripts, not modules - approved verbs don't apply
        'PSUseApprovedVerbs',

        # ShouldProcess is not needed for non-interactive setup scripts
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
        PSAvoidUsingPositionalParameters = @{
            Enable = $true
        }
    }
}
