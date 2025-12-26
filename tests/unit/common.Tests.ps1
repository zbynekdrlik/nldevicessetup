# Unit tests for lib/common.ps1
# Run with: Invoke-Pester -Path tests/unit/common.Tests.ps1

BeforeAll {
    $LibPath = Join-Path $PSScriptRoot '..\..\lib\common.ps1'
    . $LibPath
}

Describe 'Write-LogInfo' {
    It 'Should output message with INFO prefix' {
        $output = Write-LogInfo 'test message' 6>&1
        $output | Should -Match '\[INFO\]'
        $output | Should -Match 'test message'
    }
}

Describe 'Write-LogSuccess' {
    It 'Should output message with OK prefix' {
        $output = Write-LogSuccess 'test message' 6>&1
        $output | Should -Match '\[OK\]'
    }
}

Describe 'Write-LogWarn' {
    It 'Should output message with WARN prefix' {
        $output = Write-LogWarn 'test message' 6>&1
        $output | Should -Match '\[WARN\]'
    }
}

Describe 'Write-LogError' {
    It 'Should output message with ERROR prefix' {
        $output = Write-LogError 'test message' 6>&1
        $output | Should -Match '\[ERROR\]'
    }
}

Describe 'Test-Administrator' {
    It 'Should return a boolean' {
        $result = Test-Administrator
        $result | Should -BeOfType [bool]
    }
}

Describe 'Get-WindowsVersionInfo' {
    It 'Should return version information' {
        $info = Get-WindowsVersionInfo
        $info.Version | Should -Not -BeNullOrEmpty
        $info.BuildNumber | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-RegistryValueIdempotent' {
    BeforeAll {
        $TestPath = 'HKCU:\Software\nldevicessetup-test'
    }

    AfterAll {
        Remove-Item -Path 'HKCU:\Software\nldevicessetup-test' -Recurse -ErrorAction SilentlyContinue
    }

    It 'Should create registry path if not exists' {
        Set-RegistryValueIdempotent -Path $TestPath -Name 'TestValue' -Value 1
        Test-Path $TestPath | Should -Be $true
    }

    It 'Should set registry value' {
        Set-RegistryValueIdempotent -Path $TestPath -Name 'TestValue' -Value 42
        $value = Get-ItemProperty -Path $TestPath -Name 'TestValue'
        $value.TestValue | Should -Be 42
    }

    It 'Should not modify if value already set' {
        Set-RegistryValueIdempotent -Path $TestPath -Name 'TestValue' -Value 42
        Set-RegistryValueIdempotent -Path $TestPath -Name 'TestValue' -Value 42
        $value = Get-ItemProperty -Path $TestPath -Name 'TestValue'
        $value.TestValue | Should -Be 42
    }
}

Describe 'Invoke-CommandWithDryRun' {
    It 'Should execute command when not in dry run' {
        $script:DRY_RUN = $false
        $result = Invoke-CommandWithDryRun -ScriptBlock { 'executed' } -Description 'test'
        $result | Should -Be 'executed'
    }

    It 'Should not execute command in dry run mode' {
        $script:DRY_RUN = $true
        $result = Invoke-CommandWithDryRun -ScriptBlock { 'executed' } -Description 'test'
        $result | Should -BeNullOrEmpty
    }
}
