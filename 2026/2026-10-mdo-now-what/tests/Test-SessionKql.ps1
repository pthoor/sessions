#requires -Version 7.2
<#
.SYNOPSIS
Parses every session hunting query against the documented Advanced hunting schemas.
.DESCRIPTION
Downloads the Microsoft.Azure.Kusto.Language package from NuGet into a git-ignored
cache on first use, defines the tables the session queries use with the columns
documented on Microsoft Learn, and reports every syntax error and unknown column or
table. It cannot prove a query returns rows; it proves the query will parse and bind
in Advanced hunting when the documented schema holds.
.PARAMETER Path
Query files to check; defaults to every .kql file in the session kql folder and the
prompt-injection lab's matrix scorecard.
.OUTPUTS
System.Management.Automation.PSCustomObject
.EXAMPLE
./tests/Test-SessionKql.ps1
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [string[]] $Path = @(
        (Get-ChildItem -Path (Join-Path $PSScriptRoot '../kql/*.kql')).FullName
        (Join-Path $PSScriptRoot '../../mdo-prompt-injection/kql/matrix-scorecard.kql')
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$cache = Join-Path $PSScriptRoot 'kusto.local.cache'
$assembly = Join-Path $cache 'lib/net6.0/Kusto.Language.dll'
if (-not (Test-Path -LiteralPath $assembly)) {
    [void][IO.Directory]::CreateDirectory($cache)
    $package = Join-Path $cache 'kusto.language.nupkg'
    Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.Azure.Kusto.Language' -OutFile $package
    Expand-Archive -LiteralPath $package -DestinationPath $cache -Force
}
Add-Type -Path $assembly

$tables = [ordered]@{
    EmailEvents = '(Timestamp:datetime, NetworkMessageId:string, InternetMessageId:string, SenderMailFromAddress:string, SenderFromAddress:string, SenderDisplayName:string, SenderObjectId:string, SenderMailFromDomain:string, SenderFromDomain:string, SenderIPv4:string, SenderIPv6:string, RecipientEmailAddress:string, RecipientObjectId:string, Subject:string, EmailClusterId:long, EmailDirection:string, DeliveryAction:string, DeliveryLocation:string, ThreatTypes:string, ThreatNames:string, DetectionMethods:string, ConfidenceLevel:string, BulkComplaintLevel:int, EmailAction:string, EmailActionPolicy:string, EmailActionPolicyGuid:string, AuthenticationDetails:string, AttachmentCount:int, UrlCount:int, EmailLanguage:string, Connectors:string, OrgLevelAction:string, OrgLevelPolicy:string, UserLevelAction:string, UserLevelPolicy:string, ReportId:string, AdditionalFields:string, LatestDeliveryLocation:string, LatestDeliveryAction:string, OriginalThreatTypes:string, OriginalDetectionMethods:string, OriginalConfidenceLevel:string, DistributionList:string, ExchangeTransportRule:string, ForwardingInformation:string, Context:string, To:string, Cc:string, ThreatClassification:string, RecipientDomain:string, EmailSize:long, IsFirstContact:int, Topics:string)'
    EmailUrlInfo = '(Timestamp:datetime, NetworkMessageId:string, Url:string, UrlDomain:string, UrlLocation:string, UrlChainId:string, UrlChainPosition:int, ReportId:string)'
    UrlClickEvents = '(Timestamp:datetime, Url:string, ActionType:string, AccountUpn:string, Workload:string, NetworkMessageId:string, ThreatTypes:string, DetectionMethods:string, IPAddress:string, IsClickedThrough:bool, UrlChain:string, ReportId:string, AppName:string, AppVersion:string, SourceId:string)'
    EntraIdSignInEvents = '(Timestamp:datetime, Application:string, ApplicationId:string, LogonType:string, ErrorCode:int, CorrelationId:string, SessionId:string, AccountDisplayName:string, AccountObjectId:string, AccountUpn:string, IsExternalUser:int, IsGuestUser:bool, IPAddress:string, Country:string, State:string, City:string, UserAgent:string, ClientAppUsed:string, Browser:string, RiskLevelAggregated:int, ReportId:string)'
    CloudAppEvents = '(Timestamp:datetime, ActionType:string, Application:string, ApplicationId:int, AccountObjectId:string, AccountId:string, AccountDisplayName:string, IsAdminOperation:bool, DeviceType:string, OSPlatform:string, IPAddress:string, IsAnonymousProxy:bool, CountryCode:string, City:string, ISP:string, UserAgent:string, ActivityType:string, ActivityObjects:dynamic, ObjectName:string, ObjectType:string, ObjectId:string, ReportId:string, RawEventData:dynamic, AdditionalFields:dynamic, AccountType:string, IsExternalUser:bool, IsImpersonated:bool)'
    MessageEvents = '(Timestamp:datetime, LastEditedTime:string, TeamsMessageId:string, SenderEmailAddress:string, SenderDisplayName:string, SenderObjectId:string, SenderType:string, RecipientDetails:dynamic, IsOwnedThread:bool, MessageId:string, ParentMessageId:string, GroupId:string, GroupName:string, ThreadId:string, ThreadSubtype:string, IsExternalThread:bool, MessageFormatType:string, MessageFormatSubtype:string, MessageVersion:string, MessageSubject:string, ThreatTypes:string, DetectionMethods:dynamic, ConfidenceLevel:dynamic, DeliveryAction:string, DeliveryLocation:string, ReportId:string, SafetyTip:string)'
    MessagePostDeliveryEvents = '(Timestamp:datetime, TeamsMessageId:string, Action:string, ActionType:string, ActionTrigger:string, ActionResult:string, SenderEmailAddress:string, RecipientDetails:dynamic, ThreatTypes:string, ConfidenceLevel:dynamic, DetectionMethods:string, LatestDeliveryLocation:string, ReportId:string, IsExternalThread:bool, SafetyTip:string)'
    MessageUrlInfo = '(Timestamp:datetime, TeamsMessageId:string, Url:string, UrlDomain:string, ThreatTypes:string, ReportId:string)'
}
$symbols = foreach ($name in $tables.Keys) { [Kusto.Language.Symbols.TableSymbol]::new($name, $tables[$name]) }
$database = [Kusto.Language.Symbols.DatabaseSymbol]::new('hunting', [Kusto.Language.Symbols.Symbol[]]@($symbols))
$globals = [Kusto.Language.GlobalState]::Default.WithDatabase($database)

foreach ($file in @($Path | Where-Object { Test-Path -LiteralPath $_ })) {
    $text = [IO.File]::ReadAllText($file)
    $code = [Kusto.Language.KustoCode]::ParseAndAnalyze($text, $globals)
    $errors = @($code.GetDiagnostics() | Where-Object { $_.Severity -eq 'Error' })
    [pscustomobject]@{
        Query = [IO.Path]::GetFileName($file)
        Valid = $errors.Count -eq 0
        Errors = @($errors | ForEach-Object { '{0} at offset {1}' -f $_.Message, $_.Start })
    }
}
