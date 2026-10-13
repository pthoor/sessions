BeforeAll {
    $sessionRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $sessionRoot 'scripts/modules/MdoDemo.psm1') -Force
    $script:runId = 'MDO-20261012-001'
    $script:goldenText = 'https://northwind-mfa.invalid/r?ref=MDO-20261012-001'
}

Describe 'QR encoder' {
    It 'produces the zxing-verified golden PNG for a fixed URL' {
        $png = ConvertTo-MdoQrPng -Text $script:goldenText
        $hash = (Get-FileHash -InputStream ([IO.MemoryStream]::new($png)) -Algorithm SHA256).Hash

        $hash | Should -Be '169AFF8D3249896EFD254A1EF412AD83CC786E44BAA5C4AC0B2581690F69DFE3'
    }

    It 'returns a 33 by 33 version 4 matrix with three finder patterns and the dark module' {
        $matrix = Get-MdoQrMatrix -Text $script:goldenText

        $matrix.Length | Should -Be 33
        foreach ($row in $matrix) { $row.Length | Should -Be 33 }
        foreach ($corner in @(@(0, 0), @(0, 26), @(26, 0))) {
            $r = $corner[0]; $c = $corner[1]
            $matrix[$r][$c] | Should -BeTrue
            $matrix[$r + 3][$c + 3] | Should -BeTrue
            $matrix[$r + 1][$c + 1] | Should -BeFalse
        }
        $matrix[25][8] | Should -BeTrue
        $matrix[26][26] | Should -BeTrue
        $matrix[25][25] | Should -BeFalse
    }

    It 'writes a valid PNG signature and IHDR for 8-bit grayscale' {
        $png = ConvertTo-MdoQrPng -Text 'A' -ModulePixels 4

        $png[0..7] | Should -Be @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        [Text.Encoding]::ASCII.GetString($png, 12, 4) | Should -Be 'IHDR'
        $png[16..19] | Should -Be @(0, 0, 0, 164)
        $png[24] | Should -Be 8
        $png[25] | Should -Be 0
    }

    It 'rejects text beyond the 78-byte version 4-L capacity' {
        { Get-MdoQrMatrix -Text ('x' * 79) } | Should -Throw '*78*'
    }
}

Describe 'Test-MdoDemoContent' {
    It 'accepts reserved HTTPS destinations, cid images and allowed email domains' {
        $result = Test-MdoDemoContent -Content '<a href="https://a.invalid/x">x</a><img src="cid:qr-1" /> desk@example.invalid' -AllowedDomains @('example.invalid')

        $result.IsSafe | Should -BeTrue
    }

    It 'rejects <Reason>' -ForEach @(
        @{ Reason = 'a reachable host'; Value = 'https://login.example.com/x'; Violation = 'NonReservedUrl' }
        @{ Reason = 'plain HTTP on a reserved host'; Value = 'http://a.invalid/'; Violation = 'NonReservedUrl' }
        @{ Reason = 'a suffix lookalike'; Value = 'https://a.invalid.example.com/'; Violation = 'NonReservedUrl' }
        @{ Reason = 'a data link'; Value = '<a href="data:text/html,x">x</a>'; Violation = 'NonReservedUrl' }
        @{ Reason = 'an outside email domain'; Value = 'ceo@contoso.com'; Violation = 'EmailDomainNotAllowed' }
        @{ Reason = 'script markup'; Value = '<script>x</script>'; Violation = 'ActiveContent' }
    ) {
        $result = Test-MdoDemoContent -Content $Value -AllowedDomains @('example.invalid')

        $result.IsSafe | Should -BeFalse
        $result.Violations | Should -Contain $Violation
    }
}

Describe 'New-MdoDemoMessage' {
    It 'builds <Scenario> with the run tag, scenario header and only reserved destinations' -ForEach @(
        @{ Scenario = 'InvoiceLink'; Header = 'invoicelink' }
        @{ Scenario = 'QrCode'; Header = 'qrcode' }
        @{ Scenario = 'SclBypass'; Header = 'sclbypass' }
    ) {
        $message = New-MdoDemoMessage -Scenario $Scenario -RunId $script:runId -AllowedDomains @('example.invalid')

        $message.Subject | Should -Match "\[$script:runId\]$"
        $message.Headers['x-mdodemo-runid'] | Should -Be $script:runId
        $message.Headers['x-mdodemo-scenario'] | Should -Be $Header
        $message.Body | Should -Not -Match '(?i)synthetic|mock|\btest\b|\blab\b'
        (Test-MdoDemoContent -Content $message.Body -AllowedDomains @('example.invalid')).IsSafe | Should -BeTrue
    }

    It 'gives the invoice exactly one clickable reserved link for Safe Links to wrap' {
        $message = New-MdoDemoMessage -Scenario InvoiceLink -RunId $script:runId -AllowedDomains @()

        @([regex]::Matches($message.Body, 'href="([^"]+)"')).Count | Should -Be 1
        $message.Body | Should -Match ([regex]::Escape("https://northwind-billing.invalid/invoice/48213?ref=$script:runId"))
        @($message.Attachments).Count | Should -Be 0
    }

    It 'hides the only QR URL inside an inline PNG and keeps it out of the HTML' {
        $message = New-MdoDemoMessage -Scenario QrCode -RunId $script:runId -AllowedDomains @()
        $attachment = @($message.Attachments)[0]

        @($message.Attachments).Count | Should -Be 1
        $attachment.IsInline | Should -BeTrue
        $attachment.ContentType | Should -Be 'image/png'
        $message.Body | Should -Match "src=`"cid:$($attachment.ContentId)`""
        $message.Body | Should -Not -Match 'https?://'
        $message.QrText | Should -Be $script:goldenText
        $attachment.ContentBytes | Should -Be ([Convert]::ToBase64String((ConvertTo-MdoQrPng -Text $script:goldenText)))
    }
}

Describe 'ConvertTo-MdoGraphMailRequest' {
    It 'maps headers and inline attachments to the Graph sendMail shape' {
        $message = New-MdoDemoMessage -Scenario QrCode -RunId $script:runId -AllowedDomains @()
        $request = ConvertTo-MdoGraphMailRequest -Message $message -Recipient 'protected@example.invalid'
        $json = $request | ConvertTo-Json -Depth 10 | ConvertFrom-Json

        $json.message.toRecipients[0].emailAddress.address | Should -Be 'protected@example.invalid'
        ($json.message.internetMessageHeaders | Where-Object name -EQ 'x-mdodemo-scenario').value | Should -Be 'qrcode'
        $json.message.attachments[0].isInline | Should -BeTrue
        $json.message.attachments[0].contentId | Should -Be 'mfa-reregistration'
        $json.saveToSentItems | Should -BeTrue
    }
}

Describe 'New-MdoRunId' {
    It 'skips identifiers that already have a run record' {
        New-Item -ItemType File -Path (Join-Path $TestDrive 'MDO-20261012-001.run.local.json') | Out-Null

        New-MdoRunId -ResultsDirectory $TestDrive -Now ([datetime]'2026-10-12T08:00:00Z') | Should -Be 'MDO-20261012-002'
    }
}
