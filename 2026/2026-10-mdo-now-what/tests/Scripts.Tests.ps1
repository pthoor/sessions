BeforeAll {
    $sessionRoot = Split-Path -Parent $PSScriptRoot
    $script:sendScript = Join-Path $sessionRoot 'scripts/Send-MdoDemoMail.ps1'
    $script:ruleScript = Join-Path $sessionRoot 'scripts/Set-MdoDemoInboxRule.ps1'
    $script:sclScript = Join-Path $sessionRoot 'scripts/Set-MdoDemoSclBypassRule.ps1'
    $script:configPath = Join-Path $sessionRoot '../mdo-prompt-injection/demo/config/lab.example.psd1'
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    function global:Get-TransportRule { [CmdletBinding()] param([string] $Identity) }
    function global:New-TransportRule { [CmdletBinding()] param([string] $Name, [string[]] $From, [string] $HeaderContainsMessageHeader, [string[]] $HeaderContainsWords, [int] $SetSCL, [string] $Comments) }
    function global:Remove-TransportRule { [CmdletBinding(SupportsShouldProcess)] param([string] $Identity) }
    function global:Get-AcceptedDomain { [CmdletBinding()] param() }
}

AfterAll {
    Remove-Item -Path Function:\Get-TransportRule, Function:\New-TransportRule, Function:\Remove-TransportRule, Function:\Get-AcceptedDomain -ErrorAction SilentlyContinue
}

Describe 'Send-MdoDemoMail.ps1' {
    BeforeEach {
        Mock Connect-MgGraph {}
        Mock Disconnect-MgGraph {}
        Mock Get-MgContext { [pscustomobject]@{ Account = 'attacker@example.invalid' } }
        Mock Invoke-MgGraphRequest { [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::Accepted) }
        $script:results = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'renders a local preview and run record without signing in when not acknowledged' {
        $result = & $script:sendScript -Scenario QrCode -ConfigPath $script:configPath -ResultsDirectory $script:results

        $result.TransportStatus | Should -Be 'Preview'
        Test-Path (Join-Path $script:results "$($result.RunId).run.local.json") | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $script:results "$($result.RunId).preview.local.html") -Raw | Should -Match 'data:image/png;base64,'
        Should -Invoke Connect-MgGraph -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
    }

    It 'makes no Graph request under WhatIf even when acknowledged' {
        $result = & $script:sendScript -Scenario InvoiceLink -ConfigPath $script:configPath -ResultsDirectory $script:results -AcknowledgeLabUse -WhatIf

        $result.TransportStatus | Should -Be 'Declined'
        Should -Invoke Connect-MgGraph -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
    }

    It 'sends exactly one message to the protected mailbox from the attacker tenant' {
        $result = & $script:sendScript -Scenario SclBypass -ConfigPath $script:configPath -ResultsDirectory $script:results -AcknowledgeLabUse -Confirm:$false

        $result.TransportStatus | Should -Be 'Accepted'
        $result.SentAtUtc | Should -Not -BeNullOrEmpty
        Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter { $TenantId -eq 'ATTACKER_TENANT_ID' -and $Scopes -contains 'Mail.Send' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
            $request = $Body | ConvertFrom-Json
            $Uri -eq 'https://graph.microsoft.com/v1.0/me/sendMail' -and
            $request.message.toRecipients[0].emailAddress.address -eq 'protected@example.invalid' -and
            ($request.message.internetMessageHeaders | Where-Object name -EQ 'x-mdodemo-scenario').value -eq 'sclbypass'
        }
    }

    It 'passes the device code switch through to the Graph sign-in' {
        $null = & $script:sendScript -Scenario InvoiceLink -ConfigPath $script:configPath -ResultsDirectory $script:results -AcknowledgeLabUse -UseDeviceCode -Confirm:$false

        Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter { $UseDeviceCode -eq $true }
    }

    It 'records a failed send without throwing secrets into the record' {
        Mock Invoke-MgGraphRequest { throw 'Authorization: Bearer PRIVATE_TOKEN' }
        $result = & $script:sendScript -Scenario InvoiceLink -ConfigPath $script:configPath -ResultsDirectory $script:results -AcknowledgeLabUse -Confirm:$false -WarningVariable sendWarnings -WarningAction SilentlyContinue

        $result.TransportStatus | Should -Be 'Failed'
        "$sendWarnings" | Should -Match 'Bearer \[redacted\]'
        "$sendWarnings" | Should -Not -Match 'PRIVATE_TOKEN'
        $result.FailureType | Should -Not -BeNullOrEmpty
        Get-Content -LiteralPath (Join-Path $script:results "$($result.RunId).run.local.json") -Raw | Should -Not -Match 'PRIVATE_TOKEN'
    }
}

Describe 'Set-MdoDemoInboxRule.ps1' {
    BeforeEach {
        Mock Connect-MgGraph {}
        Mock Disconnect-MgGraph {}
        Mock Get-MgContext { [pscustomobject]@{ Account = 'protected@example.invalid' } }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like '*messageRules' } { @{ value = @() } }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like '*mailFolders/conversationhistory' } { @{ id = 'folder-ch'; displayName = 'Conversation History' } }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' } { @{ id = 'rule-1' } }
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'DELETE' } {}
    }

    It 'creates the hiding rule in the protected user mailbox' {
        $result = & $script:ruleScript -ConfigPath $script:configPath -Confirm:$false

        $result.Action | Should -Be 'Created'
        $result.Folder | Should -Be 'Conversation History'
        Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter { $TenantId -eq 'PROTECTED_TENANT_ID' -and $Scopes -contains 'MailboxSettings.ReadWrite' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and ($rule = $Body | ConvertFrom-Json) -and
            $rule.displayName -ceq '.' -and $rule.actions.moveToFolder -eq 'folder-ch' -and
            $rule.actions.markAsRead -and $rule.actions.stopProcessingRules -and
            ($rule.conditions.subjectContains -contains 'invoice')
        }
    }

    It 'refuses to write into a mailbox other than the protected lab user' {
        Mock Get-MgContext { [pscustomobject]@{ Account = 'admin@example.invalid' } }

        { & $script:ruleScript -ConfigPath $script:configPath -Confirm:$false } | Should -Throw '*protected lab user*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'removes only rules named exactly "."' {
        Mock Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -like '*messageRules' } { @{ value = @(@{ id = 'a'; displayName = '.' }, @{ id = 'b'; displayName = 'Newsletters' }) } }
        $result = & $script:ruleScript -ConfigPath $script:configPath -Remove -Confirm:$false

        $result.RuleCount | Should -Be 1
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like '*/a' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like '*/b' }
    }

    It 'signs in to nothing under WhatIf' {
        & $script:ruleScript -ConfigPath $script:configPath -WhatIf

        Should -Invoke Connect-MgGraph -Times 0 -Exactly
    }
}

Describe 'Set-MdoDemoSclBypassRule.ps1' {
    BeforeEach {
        Mock Connect-ExchangeOnline {}
        Mock Disconnect-ExchangeOnline {}
        Mock Get-TransportRule {}
        Mock New-TransportRule {}
        Mock Remove-TransportRule {}
        Mock Get-AcceptedDomain { [pscustomobject]@{ DomainName = 'lab.example.invalid'; Default = $true } }
    }

    It 'refuses to write when the signed-in tenant does not own the organization domain' {
        Mock Get-AcceptedDomain { [pscustomobject]@{ DomainName = 'attacker.example.invalid'; Default = $true } }

        { & $script:sclScript -SenderAddress 'attacker@example.invalid' -Organization 'lab.example.invalid' -Confirm:$false } | Should -Throw '*attacker.example.invalid*does not own lab.example.invalid*'
        Should -Invoke New-TransportRule -Times 0 -Exactly
        Should -Invoke Get-TransportRule -Times 0 -Exactly
    }

    It 'scopes the SCL -1 rule to one sender and the demo header' {
        $result = & $script:sclScript -SenderAddress 'attacker@example.invalid' -Organization 'lab.example.invalid' -Confirm:$false

        $result.Action | Should -Be 'Created'
        Should -Invoke New-TransportRule -Times 1 -Exactly -ParameterFilter {
            $SetSCL -eq -1 -and @($From) -contains 'attacker@example.invalid' -and
            $HeaderContainsMessageHeader -eq 'x-mdodemo-scenario' -and @($HeaderContainsWords) -contains 'sclbypass'
        }
    }

    It 'passes the device code switch through to the Exchange Online sign-in' {
        $null = & $script:sclScript -SenderAddress 'attacker@example.invalid' -Organization 'lab.example.invalid' -UseDeviceCode -Confirm:$false

        Should -Invoke Connect-ExchangeOnline -Times 1 -Exactly -ParameterFilter { $Device -eq $true }
    }

    It 'rejects a sender with a display name before connecting' {
        { & $script:sclScript -SenderAddress 'Eve <attacker@example.invalid>' -Organization 'lab.example.invalid' -Confirm:$false } | Should -Throw '*literal*'
        Should -Invoke Connect-ExchangeOnline -Times 0 -Exactly
    }

    It 'removes the demo rule by its exact name' {
        Mock Get-TransportRule { [pscustomobject]@{ Name = 'MDO demo - SCL -1 bypass (lab only)' } }
        $result = & $script:sclScript -Organization 'lab.example.invalid' -Remove -Confirm:$false

        $result.Action | Should -Be 'Removed'
        Should -Invoke Remove-TransportRule -Times 1 -Exactly -ParameterFilter { $Identity -eq 'MDO demo - SCL -1 bypass (lab only)' }
    }
}
