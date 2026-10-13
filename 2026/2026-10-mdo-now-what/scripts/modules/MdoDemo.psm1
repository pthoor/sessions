#requires -Version 7.2

Set-StrictMode -Version Latest

function Get-MdoGfProduct {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)] [int] $X, [Parameter(Mandatory)] [int] $Y)

    $z = 0
    for ($i = 7; $i -ge 0; $i--) {
        $z = (($z -shl 1) -bxor (($z -shr 7) * 0x11D)) -band 0xFF
        if ((($Y -shr $i) -band 1) -eq 1) { $z = $z -bxor $X }
    }
    return $z
}

function Get-MdoReedSolomonRemainder {
    [CmdletBinding()]
    [OutputType([int[]])]
    param([Parameter(Mandatory)] [int[]] $Data, [Parameter(Mandatory)] [int] $Degree)

    $divisor = [int[]]::new($Degree)
    $divisor[$Degree - 1] = 1
    $root = 1
    for ($i = 0; $i -lt $Degree; $i++) {
        for ($j = 0; $j -lt $Degree; $j++) {
            $divisor[$j] = Get-MdoGfProduct -X $divisor[$j] -Y $root
            if ($j + 1 -lt $Degree) { $divisor[$j] = $divisor[$j] -bxor $divisor[$j + 1] }
        }
        $root = Get-MdoGfProduct -X $root -Y 2
    }
    $result = [int[]]::new($Degree)
    foreach ($b in $Data) {
        $factor = $b -bxor $result[0]
        [Array]::Copy($result, 1, $result, 0, $Degree - 1)
        $result[$Degree - 1] = 0
        for ($i = 0; $i -lt $Degree; $i++) {
            $result[$i] = $result[$i] -bxor (Get-MdoGfProduct -X $divisor[$i] -Y $factor)
        }
    }
    return , $result
}

function Get-MdoQrMatrix {
    <#
    .SYNOPSIS
    Encodes text as a QR code module matrix.
    .DESCRIPTION
    Implements QR Model 2, version 4, error correction level L, byte mode and mask 0,
    which holds up to 78 bytes of UTF-8 text in a single Reed-Solomon block. Returns
    a jagged boolean array indexed [row][column] where true is a dark module.
    .PARAMETER Text
    Text to encode, at most 78 UTF-8 bytes.
    .OUTPUTS
    System.Boolean[][]
    .EXAMPLE
    Get-MdoQrMatrix -Text 'https://northwind-pay.invalid/m/48213'
    #>
    [CmdletBinding()]
    [OutputType([bool[][]])]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    if ($bytes.Length -gt 78) { throw 'QR text must be at most 78 UTF-8 bytes for version 4-L.' }
    $size = 33
    $dataCodewords = 80
    $eccCodewords = 20

    $bits = [Collections.Generic.List[int]]::new()
    $appendBits = {
        param([int] $Value, [int] $Length)
        for ($i = $Length - 1; $i -ge 0; $i--) { $bits.Add(($Value -shr $i) -band 1) }
    }
    & $appendBits 4 4
    & $appendBits $bytes.Length 8
    foreach ($b in $bytes) { & $appendBits ([int]$b) 8 }
    $capacity = $dataCodewords * 8
    & $appendBits 0 ([Math]::Min(4, $capacity - $bits.Count))
    & $appendBits 0 ((8 - ($bits.Count % 8)) % 8)
    $data = [Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $bits.Count; $i += 8) {
        $value = 0
        for ($j = 0; $j -lt 8; $j++) { $value = ($value -shl 1) -bor $bits[$i + $j] }
        $data.Add($value)
    }
    $pad = 0xEC
    while ($data.Count -lt $dataCodewords) {
        $data.Add($pad)
        $pad = if ($pad -eq 0xEC) { 0x11 } else { 0xEC }
    }
    $ecc = Get-MdoReedSolomonRemainder -Data $data.ToArray() -Degree $eccCodewords
    $codewords = [int[]]($data.ToArray() + $ecc)

    $modules = [bool[][]]::new($size)
    $isFunction = [bool[][]]::new($size)
    for ($r = 0; $r -lt $size; $r++) { $modules[$r] = [bool[]]::new($size); $isFunction[$r] = [bool[]]::new($size) }
    $set = {
        param([int] $Column, [int] $Row, [bool] $Dark)
        $modules[$Row][$Column] = $Dark
        $isFunction[$Row][$Column] = $true
    }

    for ($i = 0; $i -lt $size; $i++) {
        & $set 6 $i ($i % 2 -eq 0)
        & $set $i 6 ($i % 2 -eq 0)
    }
    foreach ($center in @(@(3, 3), @(($size - 4), 3), @(3, ($size - 4)))) {
        for ($dy = -4; $dy -le 4; $dy++) {
            for ($dx = -4; $dx -le 4; $dx++) {
                $x = $center[0] + $dx
                $y = $center[1] + $dy
                if ($x -ge 0 -and $x -lt $size -and $y -ge 0 -and $y -lt $size) {
                    $distance = [Math]::Max([Math]::Abs($dx), [Math]::Abs($dy))
                    & $set $x $y ($distance -ne 2 -and $distance -ne 4)
                }
            }
        }
    }
    for ($dy = -2; $dy -le 2; $dy++) {
        for ($dx = -2; $dx -le 2; $dx++) {
            & $set (26 + $dx) (26 + $dy) ([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)) -ne 1)
        }
    }

    $formatData = (1 -shl 3) -bor 0
    $remainder = $formatData
    for ($i = 0; $i -lt 10; $i++) { $remainder = ($remainder -shl 1) -bxor (($remainder -shr 9) * 0x537) }
    $format = (($formatData -shl 10) -bor $remainder) -bxor 0x5412
    $formatBit = { param([int] $Index) ((($format -shr $Index) -band 1) -eq 1) }
    for ($i = 0; $i -le 5; $i++) { & $set 8 $i (& $formatBit $i) }
    & $set 8 7 (& $formatBit 6)
    & $set 8 8 (& $formatBit 7)
    & $set 7 8 (& $formatBit 8)
    for ($i = 9; $i -lt 15; $i++) { & $set (14 - $i) 8 (& $formatBit $i) }
    for ($i = 0; $i -lt 8; $i++) { & $set ($size - 1 - $i) 8 (& $formatBit $i) }
    for ($i = 8; $i -lt 15; $i++) { & $set 8 ($size - 15 + $i) (& $formatBit $i) }
    & $set 8 ($size - 8) $true

    $bitIndex = 0
    $totalBits = $codewords.Count * 8
    for ($right = $size - 1; $right -ge 1; $right -= 2) {
        if ($right -eq 6) { $right = 5 }
        for ($vertical = 0; $vertical -lt $size; $vertical++) {
            for ($j = 0; $j -lt 2; $j++) {
                $x = $right - $j
                $upward = (($right + 1) -band 2) -eq 0
                $y = if ($upward) { $size - 1 - $vertical } else { $vertical }
                if (-not $isFunction[$y][$x] -and $bitIndex -lt $totalBits) {
                    $modules[$y][$x] = ((($codewords[$bitIndex -shr 3] -shr (7 - ($bitIndex -band 7))) -band 1) -eq 1)
                    $bitIndex++
                }
            }
        }
    }
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            if (-not $isFunction[$y][$x] -and (($x + $y) % 2 -eq 0)) { $modules[$y][$x] = -not $modules[$y][$x] }
        }
    }
    return , $modules
}

function Get-MdoCrc32 {
    [CmdletBinding()]
    [OutputType([uint32])]
    param([Parameter(Mandatory)] [byte[]] $Bytes)

    [long] $mask = 0xFFFFFFFFL
    [long] $polynomial = 0xEDB88320L
    [long] $crc = $mask
    foreach ($b in $Bytes) {
        $crc = $crc -bxor [long]$b
        for ($k = 0; $k -lt 8; $k++) {
            if (($crc -band 1L) -eq 1L) { $crc = ($crc -shr 1) -bxor $polynomial } else { $crc = $crc -shr 1 }
        }
    }
    return [uint32](($crc -bxor $mask) -band $mask)
}

function ConvertTo-MdoPngChunk {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] [string] $Type, [Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]] $Data)

    $typeBytes = [Text.Encoding]::ASCII.GetBytes($Type)
    $length = [BitConverter]::GetBytes([uint32]$Data.Length)
    [Array]::Reverse($length)
    $crc = [BitConverter]::GetBytes((Get-MdoCrc32 -Bytes ([byte[]]($typeBytes + $Data))))
    [Array]::Reverse($crc)
    return [byte[]]($length + $typeBytes + $Data + $crc)
}

function ConvertTo-MdoQrPng {
    <#
    .SYNOPSIS
    Renders text as a QR code PNG image.
    .DESCRIPTION
    Encodes the text with Get-MdoQrMatrix and writes an 8-bit grayscale PNG with a
    four-module quiet zone. Uses only .NET base libraries, so it runs on Windows,
    macOS and Linux without System.Drawing.
    .PARAMETER Text
    Text to encode, at most 78 UTF-8 bytes.
    .PARAMETER ModulePixels
    Pixel width of one module.
    .OUTPUTS
    System.Byte[]
    .EXAMPLE
    ConvertTo-MdoQrPng -Text 'https://northwind-pay.invalid/m/48213' -ModulePixels 8
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Text,
        [ValidateRange(2, 20)] [int] $ModulePixels = 8
    )

    $matrix = Get-MdoQrMatrix -Text $Text
    $quiet = 4
    $modulesWide = $matrix.Length + 2 * $quiet
    $pixels = $modulesWide * $ModulePixels
    $raw = [IO.MemoryStream]::new()
    for ($py = 0; $py -lt $pixels; $py++) {
        $raw.WriteByte(0)
        $my = [Math]::Floor($py / $ModulePixels) - $quiet
        $row = [byte[]]::new($pixels)
        for ($px = 0; $px -lt $pixels; $px++) {
            $mx = [Math]::Floor($px / $ModulePixels) - $quiet
            $dark = $my -ge 0 -and $my -lt $matrix.Length -and $mx -ge 0 -and $mx -lt $matrix.Length -and $matrix[$my][$mx]
            $row[$px] = if ($dark) { 0 } else { 255 }
        }
        $raw.Write($row, 0, $row.Length)
    }
    $compressed = [IO.MemoryStream]::new()
    $zlib = [IO.Compression.ZLibStream]::new($compressed, [IO.Compression.CompressionLevel]::Optimal, $true)
    try { $raw.Position = 0; $raw.CopyTo($zlib) } finally { $zlib.Dispose() }
    $dimension = [BitConverter]::GetBytes([uint32]$pixels)
    [Array]::Reverse($dimension)
    $header = [byte[]]($dimension + $dimension + [byte[]](8, 0, 0, 0, 0))
    $signature = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    return [byte[]]($signature +
        (ConvertTo-MdoPngChunk -Type 'IHDR' -Data $header) +
        (ConvertTo-MdoPngChunk -Type 'IDAT' -Data $compressed.ToArray()) +
        (ConvertTo-MdoPngChunk -Type 'IEND' -Data ([byte[]]::new(0))))
}

function Test-MdoDemoContent {
    <#
    .SYNOPSIS
    Checks demo message text for destinations that could reach a real host.
    .DESCRIPTION
    Every http(s) URL and link attribute must use HTTPS on a reserved .invalid host;
    inline images may reference cid: content IDs. Email addresses must use an allowed
    domain. Script, form and event-handler markup is rejected.
    .PARAMETER Content
    Subject, body or QR text to inspect.
    .PARAMETER AllowedDomains
    Exact email domains permitted in the content.
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    Test-MdoDemoContent -Content 'https://northwind-pay.invalid/m/1' -AllowedDomains example.invalid
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Content,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AllowedDomains
    )

    $violations = [Collections.Generic.List[string]]::new()
    $decoded = [Net.WebUtility]::HtmlDecode($Content)
    $destinations = [Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($decoded, '(?i)\b[a-z][a-z0-9+.-]*://[^\s<>"'']+')) { $destinations.Add($match.Value) }
    foreach ($match in [regex]::Matches($decoded, '(?i)\b(?:href|src|action)\s*=\s*"([^"]*)"')) { $destinations.Add($match.Groups[1].Value) }
    foreach ($destination in $destinations) {
        if ($destination -match '^cid:[A-Za-z0-9._-]+$') { continue }
        $uri = $null
        if (-not [uri]::TryCreate($destination, [UriKind]::Absolute, [ref] $uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or
            -not $uri.IdnHost.EndsWith('.invalid', [StringComparison]::OrdinalIgnoreCase)) {
            $violations.Add('NonReservedUrl')
        }
    }
    foreach ($match in [regex]::Matches($decoded, '(?i)\b[a-z0-9._%+-]+@([a-z0-9.-]+\.[a-z]{2,})\b')) {
        if ($match.Groups[1].Value -notin $AllowedDomains) { $violations.Add('EmailDomainNotAllowed') }
    }
    if ($decoded -match '(?i)<\s*(?:script|iframe|object|embed|form|meta)\b|\bon[a-z]+\s*=|javascript:') { $violations.Add('ActiveContent') }
    [pscustomobject]@{ IsSafe = $violations.Count -eq 0; Violations = @($violations | Select-Object -Unique) }
}

function New-MdoDemoMessage {
    <#
    .SYNOPSIS
    Builds one staged demo email for the "Now what?" session.
    .DESCRIPTION
    InvoiceLink stages act 1: a supplier invoice with one Safe Links-wrappable link.
    QrCode stages act 3: an MFA re-registration lure whose only URL is inside an inline
    QR image. SclBypass stages act 4: a payment notice carrying the header that the lab
    mail flow rule matches. Every URL points at a reserved .invalid host. The run ID is
    appended to the subject and written to the x-mdodemo-runid header.
    .PARAMETER Scenario
    InvoiceLink, QrCode or SclBypass.
    .PARAMETER RunId
    Identifier in MDO-yyyyMMdd-nnn format.
    .PARAMETER AllowedDomains
    Exact email domains permitted in the content.
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    New-MdoDemoMessage -Scenario QrCode -RunId MDO-20261012-001 -AllowedDomains example.invalid
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory message object and changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateSet('InvoiceLink', 'QrCode', 'SclBypass')] [string] $Scenario,
        [Parameter(Mandatory)] [ValidatePattern('^MDO-[0-9]{8}-[0-9]{3}$')] [string] $RunId,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AllowedDomains
    )

    $attachments = @()
    $headers = [ordered]@{ 'x-mdodemo-runid' = $RunId; 'x-mdodemo-scenario' = $Scenario.ToLowerInvariant() }
    switch ($Scenario) {
        'InvoiceLink' {
            $url = "https://northwind-billing.invalid/invoice/48213?ref=$RunId"
            $subject = 'Updated remittance details for invoice INV-48213'
            $body = @"
<html><body>
<p>Hi,</p>
<p>Our bank details changed this month. The updated remittance advice for invoice INV-48213 (September freight services) is ready in our billing portal.</p>
<p><a href="$url">View invoice INV-48213</a></p>
<p>Please make sure the next payment run uses the new details.</p>
<p>Kind regards,<br />Marta Lindqvist<br />Accounts Receivable, Northwind Logistics</p>
</body></html>
"@
            $qrText = $null
        }
        'QrCode' {
            $qrText = "https://northwind-mfa.invalid/r?ref=$RunId"
            $png = ConvertTo-MdoQrPng -Text $qrText
            $contentId = 'mfa-reregistration'
            $attachments = @([pscustomobject]@{ Name = 'mfa-reregistration.png'; ContentType = 'image/png'; ContentId = $contentId; IsInline = $true; ContentBytes = [Convert]::ToBase64String($png) })
            $subject = 'Action required: re-register your authenticator before Friday'
            $body = @"
<html><body>
<p>Hello,</p>
<p>As part of this quarter's security update, every account must re-register its authenticator app before Friday. Accounts that are not re-registered will be signed out of email and Teams.</p>
<p>Scan the code below with your phone camera to start. The process takes about two minutes.</p>
<p><img src="cid:$contentId" alt="Authenticator re-registration code" width="246" height="246" /></p>
<p>IT Service Desk</p>
</body></html>
"@
        }
        'SclBypass' {
            $url = "https://northwind-billing.invalid/run/2026-10?ref=$RunId"
            $subject = 'Payment run confirmation October'
            $body = @"
<html><body>
<p>Hi,</p>
<p>The October payment run has been confirmed. Review the batch and approve any outstanding items before the cut-off.</p>
<p><a href="$url">Review payment batch</a></p>
<p>Regards,<br />Treasury Operations, Northwind Logistics</p>
</body></html>
"@
            $qrText = $null
        }
    }
    $subject = "$subject [$RunId]"
    foreach ($content in @($subject, $body, $qrText) | Where-Object { $_ }) {
        $safety = Test-MdoDemoContent -Content $content -AllowedDomains $AllowedDomains
        if (-not $safety.IsSafe) { throw "Unsafe demo content: $($safety.Violations -join ', ')." }
    }
    [pscustomobject]@{
        RunId = $RunId
        Scenario = $Scenario
        Subject = $subject
        BodyContentType = 'HTML'
        Body = $body
        QrText = $qrText
        Headers = $headers
        Attachments = @($attachments)
    }
}

function ConvertTo-MdoGraphMailRequest {
    <#
    .SYNOPSIS
    Converts a demo message into a Microsoft Graph sendMail request body.
    .PARAMETER Message
    Object returned by New-MdoDemoMessage.
    .PARAMETER Recipient
    One literal recipient address.
    .OUTPUTS
    System.Collections.Hashtable
    .EXAMPLE
    ConvertTo-MdoGraphMailRequest -Message $message -Recipient protected@example.invalid
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Message,
        [Parameter(Mandatory)] [string] $Recipient
    )

    $attachments = foreach ($attachment in @($Message.Attachments)) {
        @{
            '@odata.type' = '#microsoft.graph.fileAttachment'
            name = $attachment.Name
            contentType = $attachment.ContentType
            contentId = $attachment.ContentId
            isInline = [bool]$attachment.IsInline
            contentBytes = $attachment.ContentBytes
        }
    }
    @{
        message = @{
            subject = $Message.Subject
            body = @{ contentType = $Message.BodyContentType; content = $Message.Body }
            toRecipients = @(@{ emailAddress = @{ address = $Recipient } })
            attachments = @($attachments)
            internetMessageHeaders = @($Message.Headers.GetEnumerator() | ForEach-Object { @{ name = $_.Key; value = $_.Value } })
        }
        saveToSentItems = $true
    }
}

function New-MdoRunId {
    <#
    .SYNOPSIS
    Reserves the next free MDO-yyyyMMdd-nnn identifier in a results directory.
    .PARAMETER ResultsDirectory
    Directory holding <RunId>.run.local.json records.
    .PARAMETER Now
    Clock used for the UTC date component.
    .OUTPUTS
    System.String
    .EXAMPLE
    New-MdoRunId -ResultsDirectory ./results -Now ([datetime]::UtcNow)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns the next free identifier string and writes nothing.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $ResultsDirectory,
        [Parameter(Mandatory)] [datetime] $Now
    )

    $date = $Now.ToUniversalTime().ToString('yyyyMMdd', [cultureinfo]::InvariantCulture)
    for ($sequence = 1; $sequence -le 999; $sequence++) {
        $runId = 'MDO-{0}-{1:D3}' -f $date, $sequence
        if (-not (Test-Path -LiteralPath (Join-Path $ResultsDirectory "$runId.run.local.json"))) { return $runId }
    }
    throw 'All 999 run identifiers for this UTC date are used.'
}

Export-ModuleMember -Function Get-MdoQrMatrix, ConvertTo-MdoQrPng, Test-MdoDemoContent, New-MdoDemoMessage, ConvertTo-MdoGraphMailRequest, New-MdoRunId
