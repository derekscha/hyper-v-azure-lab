#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.KeyVault, Az.Storage

<#
.SYNOPSIS
    Wave 0 bootstrap — creates the Azure Storage Account (Terraform remote state)
    and Key Vault (lab secrets) that all subsequent Terraform waves depend on.

.DESCRIPTION
    This script must run BEFORE any Terraform workspace is initialized. Terraform
    cannot store state in a Storage Account that it creates itself (chicken-and-egg),
    so Wave 0 is handled entirely by the Az PowerShell module.

    Resources created:
    - Resource Group     rg-<code>-<env>-<NNN>
    - Storage Account    st<code><env><NNN>  (Terraform state backend)
    - Storage Container  terraform-state
    - Key Vault          kv-<code>-<env>-<NNN>
    - Four placeholder secrets in Key Vault (fill in real values before Terraform runs)

    Name derivation uses exactly-three-character codes for workload and environment
    so that all generated resource names stay predictable and within platform limits.
    Tag values are supplied separately and have no character restriction.

    Starting from -Instance, the script checks Azure for an instance number where all
    three globally or subscription-scoped names are simultaneously available — including
    soft-deleted Key Vaults — and increments until one is found.

    Storage Account name length is validated locally before any ARM call is made.

    Execution order for the Storage Account deliberately creates the container BEFORE
    applying firewall rules so that data-plane operations (subject to network ACLs) are
    not blocked during initial provisioning.

    A timestamped transcript is written to LogDirectory alongside normal console output.

.PARAMETER SubscriptionId
    Azure subscription ID to target. Required — never assumed from ambient context.

.PARAMETER WorkloadCode
    Exactly three lowercase letters used in all resource names. Must not include hyphens
    or digits — those are added by the naming template. Default: hlb

.PARAMETER EnvironmentCode
    Exactly three lowercase letters identifying the environment in resource names.
    Examples: dev, qas, prd. Default: dev

.PARAMETER Location
    Azure region for all resources. Default: southcentralus

.PARAMETER Instance
    Zero-padded three-digit starting instance number. The script increments this value
    until it finds a combination where the Resource Group, Storage Account, and Key Vault
    names are all simultaneously available. Default: 001

.PARAMETER WorkloadTag
    Human-readable workload label applied to the 'workload' resource tag. No length
    restriction. Default: hyper-v-azure-lab

.PARAMETER EnvironmentTag
    Human-readable environment label applied to the 'environment' resource tag. No
    length restriction. Default: development

.PARAMETER AllowedIpAddress
    Your public IPv4 address. Restricts Storage Account and Key Vault firewall rules.
    Default: 99.6.19.126

.PARAMETER EnablePurgeProtection
    When $true, Key Vault purge protection is enabled — a deleted vault cannot be purged
    for 90 days. Leave $false (default) for dev labs you will tear down repeatedly.
    Set $true before promoting to qa or prod. Once enabled it cannot be turned off.

.PARAMETER LogDirectory
    Directory where the timestamped transcript is written. Created if absent. Defaults
    to the current working directory at script invocation time.

.EXAMPLE
    .\bootstrap.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000'

.EXAMPLE
    .\bootstrap.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -WhatIf

.EXAMPLE
    .\bootstrap.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' `
                    -WorkloadCode 'hlb' -EnvironmentCode 'prd' `
                    -WorkloadTag 'hyper-v-azure-lab' -EnvironmentTag 'production' `
                    -EnablePurgeProtection $true `
                    -LogDirectory 'C:\Logs\bootstrap'
#>

# PSAvoidUsingWriteHost — Write-Host is intentional: this is an interactive terminal script
# using Start-Transcript for capture. -ForegroundColor output requires Write-Host in PS7.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
# PSUseBOMForUnicodeEncodedFile — file is UTF-8 without BOM, valid for PS7+ (default encoding).
# Em-dashes in comments and strings are preserved for readability; no BOM is added.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    # -------------------------------------------------------------------------
    # Name-derivation parameters — all constrained to exactly 3 lowercase letters
    # so that generated resource names are predictable and within platform limits.
    # These must NOT be used for tag values (see tag parameters below).
    # -------------------------------------------------------------------------

    [ValidatePattern('^[a-z]{3}$')]
    [string]$WorkloadCode = 'hlb',

    [ValidatePattern('^[a-z]{3}$')]
    [string]$EnvironmentCode = 'dev',

    [string]$Location = 'southcentralus',

    [ValidatePattern('^\d{3}$')]
    [string]$Instance = '001',

    # -------------------------------------------------------------------------
    # Tag-only parameters — descriptive labels with no character-length restriction.
    # Kept separate from name parameters so resource names stay compact while tags
    # remain human-readable.
    # -------------------------------------------------------------------------

    [string]$WorkloadTag = 'hyper-v-azure-lab',

    [string]$EnvironmentTag = 'development',

    # -------------------------------------------------------------------------
    # Security / operational parameters
    # -------------------------------------------------------------------------

    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}$')]
    [string]$AllowedIpAddress = '99.6.19.126',

    [bool]$EnablePurgeProtection = $false,

    [string]$LogDirectory = $PWD.Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Name prefixes — instance suffix is resolved after Azure connection.
# Resource Group and Key Vault include a hyphen before the instance.
# Storage Account uses no hyphens (Azure enforces lowercase alphanumeric only).
# ---------------------------------------------------------------------------
[string]$resourceGroupPrefix  = "rg-$WorkloadCode-$EnvironmentCode"
[string]$storageAccountPrefix = "st$($WorkloadCode)$($EnvironmentCode)"
[string]$keyVaultPrefix       = "kv-$WorkloadCode-$EnvironmentCode"
[string]$storageContainerName = 'terraform-state'

# ---------------------------------------------------------------------------
# Early Storage Account name length validation — no Azure connection required.
# Azure enforces 3-to-24 lowercase alphanumeric characters for Storage Accounts.
# Validate against the worst-case resolved name (prefix + largest instance '999').
# ---------------------------------------------------------------------------
[string]$storageAccountMaxCheck = "$storageAccountPrefix$Instance"
if ($storageAccountMaxCheck.Length -lt 3) {
    throw "Derived Storage Account name '$storageAccountMaxCheck' is $($storageAccountMaxCheck.Length) character(s) — below Azure's 3-character minimum. Increase -WorkloadCode or -EnvironmentCode length."
}
if ($storageAccountMaxCheck.Length -gt 24) {
    throw "Derived Storage Account name '$storageAccountMaxCheck' is $($storageAccountMaxCheck.Length) characters — exceeds Azure's 24-character maximum. Shorten -WorkloadCode, -EnvironmentCode, or -Instance."
}

# ---------------------------------------------------------------------------
# Tags — use tag parameters (not code parameters) for human-readable values
# ---------------------------------------------------------------------------
[hashtable]$tags = @{
    environment  = $EnvironmentTag
    project      = 'hyper-v-azure-lab'
    workload     = $WorkloadTag
    'managed-by' = 'bootstrap'
}

[string[]]$secretNames = @(
    'domain-admin-password',
    'safe-mode-admin-password',
    'local-admin-password',
    'dsc-registration-key'
)

# ---------------------------------------------------------------------------
# Logging — create directory and start transcript before any output
# ---------------------------------------------------------------------------
[bool]$transcriptStarted = $false
[string]$logFilePath     = [string]::Empty

if (-not (Test-Path -Path $LogDirectory -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    catch {
        Write-Warning "Could not create log directory '$LogDirectory': $($_.Exception.Message). Transcript disabled."
        $LogDirectory = [string]::Empty
    }
}

if (-not [string]::IsNullOrEmpty($LogDirectory)) {
    [string]$logFileName = "bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $logFilePath = Join-Path -Path $LogDirectory -ChildPath $logFileName
    try {
        Start-Transcript -Path $logFilePath -Append
        $transcriptStarted = $true
        Write-Host "Transcript: $logFilePath" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "Could not start transcript at '$logFilePath': $($_.Exception.Message). Continuing without transcript."
    }
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Write-Step {
    param ([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Done {
    param ([string]$Message)
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Skip {
    param ([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

function Find-AvailableInstance {
    <#
    .SYNOPSIS
        Returns the first three-digit instance string (starting at StartInstance)
        where the Resource Group, Storage Account, and Key Vault names are all
        simultaneously available in the current Azure subscription context.

    .NOTES
        Storage Account availability is checked via Get-AzStorageAccountNameAvailability
        which validates global uniqueness and naming rules in one ARM call.

        Key Vault soft-deleted vaults still hold their name globally. This function
        scans the soft-delete inventory for the current subscription. A soft-deleted
        vault in a different subscription would still block the name, but cross-tenant
        enumeration is beyond the scope of a single-subscription bootstrap script.
    #>
    param (
        [string]$RgPrefix,
        [string]$SaPrefix,
        [string]$KvPrefix,
        [string]$StartInstance
    )

    [int]$num = [int]$StartInstance

    while ($num -le 999) {
        [string]$inst   = $num.ToString('D3')
        [string]$rgName = "$RgPrefix-$inst"
        [string]$saName = "$SaPrefix$inst"
        [string]$kvName = "$KvPrefix-$inst"

        [bool]$rgFree        = $false
        [bool]$saFree        = $false
        [bool]$kvFree        = $false
        $saAvailResult       = $null

        try {
            # Resource Group — subscription-scoped
            $rgFree = $null -eq (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue)

            # Storage Account — globally scoped; validates naming rules in one ARM call
            $saAvailResult = Get-AzStorageAccountNameAvailability -Name $saName -ErrorAction Stop
            $saFree        = $saAvailResult.NameAvailable

            # Key Vault — globally scoped; check both active and soft-deleted inventory
            [bool]$kvActiveFree  = $null -eq (Get-AzKeyVault -VaultName $kvName -ErrorAction SilentlyContinue)
            [bool]$kvDeletedFree = $null -eq (
                Get-AzKeyVault -InRemovedState -ErrorAction SilentlyContinue |
                Where-Object { $_.VaultName -eq $kvName }
            )
            $kvFree = $kvActiveFree -and $kvDeletedFree
        }
        catch {
            throw "Error checking name availability for instance '$inst': $($_.Exception.Message)"
        }

        if ($rgFree -and $saFree -and $kvFree) {
            return $inst
        }

        # Build reason string for output
        [System.Collections.Generic.List[string]]$reasons = @()
        if (-not $rgFree)  { $reasons.Add("RG '$rgName' exists in subscription") }
        if (-not $saFree)  { $reasons.Add("SA '$saName' unavailable ($($saAvailResult.Reason))") }
        if (-not $kvFree) {
            if (-not $kvActiveFree)  { $reasons.Add("KV '$kvName' exists") }
            if (-not $kvDeletedFree) { $reasons.Add("KV '$kvName' is soft-deleted") }
        }
        Write-Host "    $inst taken ($($reasons -join '; ')) — trying $(($num + 1).ToString('D3'))..." -ForegroundColor Yellow

        $num++
    }

    throw "No available instance found in the range 001-999 for prefixes '$RgPrefix', '$SaPrefix', '$KvPrefix'. Review existing Azure resources."
}

# ---------------------------------------------------------------------------
# Main body — wrapped in try/finally so the transcript always closes cleanly
# ---------------------------------------------------------------------------
try {

    # -----------------------------------------------------------------------
    # Pre-flight summary (name prefixes shown; final names resolved after login)
    # -----------------------------------------------------------------------
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host '  Hyper-V Lab Bootstrap — Wave 0'                             -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Parameters:'                                                 -ForegroundColor White
    Write-Host ''
    Write-Host "  Subscription    : $SubscriptionId"                          -ForegroundColor White
    Write-Host "  Location        : $Location"                                -ForegroundColor White
    Write-Host "  WorkloadCode    : $WorkloadCode (names)  |  WorkloadTag: $WorkloadTag (tags)" -ForegroundColor White
    Write-Host "  EnvironmentCode : $EnvironmentCode (names)  |  EnvironmentTag: $EnvironmentTag (tags)" -ForegroundColor White
    Write-Host "  Starting Instance: $Instance (auto-incremented if any name is taken)" -ForegroundColor White
    Write-Host "  IP Restriction  : $AllowedIpAddress"                        -ForegroundColor White
    Write-Host "  Purge Protection: $EnablePurgeProtection"                   -ForegroundColor White
    Write-Host ''
    Write-Host '  Name prefixes (instance suffix resolved after login):'      -ForegroundColor White
    Write-Host "  Resource Group  : $resourceGroupPrefix-<NNN>"               -ForegroundColor White
    Write-Host "  Storage Account : $storageAccountPrefix<NNN>"               -ForegroundColor White
    Write-Host "  Container       : $storageContainerName"                    -ForegroundColor White
    Write-Host "  Key Vault       : $keyVaultPrefix-<NNN>"                    -ForegroundColor White
    Write-Host ''
    Write-Host '  Tags:'                                                       -ForegroundColor White
    foreach ($tagKey in $tags.Keys) {
        Write-Host "    $tagKey = $($tags[$tagKey])"                           -ForegroundColor White
    }
    Write-Host ''

    if ($WhatIfPreference) {
        Write-Host '  [WhatIf] No changes will be made.' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    # -----------------------------------------------------------------------
    # Azure connection
    # -----------------------------------------------------------------------
    Write-Step 'Verifying Azure connection'

    $currentContext = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $currentContext -or [string]::IsNullOrEmpty($currentContext.Account.Id)) {
        Write-Host '    No active Az session — launching Connect-AzAccount...' -ForegroundColor Yellow
        Connect-AzAccount -ErrorAction Stop | Out-Null
    }

    Write-Step "Setting subscription context: $SubscriptionId"
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        Write-Done "Subscription set."
    }
    catch {
        throw "Failed to set subscription '$SubscriptionId': $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Instance resolution — find the first NNN where all three names are free
    # -----------------------------------------------------------------------
    Write-Step "Resolving available instance (starting at $Instance)"
    [string]$resolvedInstance = Find-AvailableInstance `
        -RgPrefix      $resourceGroupPrefix `
        -SaPrefix      $storageAccountPrefix `
        -KvPrefix      $keyVaultPrefix `
        -StartInstance $Instance

    # Derive final resource names now that the instance is known
    [string]$resourceGroupName  = "$resourceGroupPrefix-$resolvedInstance"
    [string]$storageAccountName = "$storageAccountPrefix$resolvedInstance"
    [string]$keyVaultName       = "$keyVaultPrefix-$resolvedInstance"
    [string]$ipCidr             = "$AllowedIpAddress/32"

    Write-Done "Instance $resolvedInstance selected."
    Write-Host ''
    Write-Host '  Resolved resource names:'                                   -ForegroundColor White
    Write-Host "    Resource Group  : $resourceGroupName"                     -ForegroundColor White
    Write-Host "    Storage Account : $storageAccountName"                    -ForegroundColor White
    Write-Host "    Container       : $storageContainerName"                  -ForegroundColor White
    Write-Host "    Key Vault       : $keyVaultName"                          -ForegroundColor White
    Write-Host ''

    # Confirmation is shown after names are known so the user sees exactly what will be created
    Read-Host -Prompt '  Confirm the above. Press Enter to proceed or Ctrl+C to abort'

    # -----------------------------------------------------------------------
    # Deploying principal — object ID resolved once and reused by all RBAC assignments
    # -----------------------------------------------------------------------
    Write-Step 'Resolving deploying principal'
    [string]$accountId   = [string]::Empty
    [string]$accountType = [string]::Empty
    [string]$objectId    = [string]::Empty
    try {
        $azContext   = Get-AzContext -ErrorAction Stop
        $accountId   = $azContext.Account.Id
        $accountType = $azContext.Account.Type

        if ($accountType -eq 'User') {
            $adUser = Get-AzADUser -UserPrincipalName $accountId -ErrorAction SilentlyContinue

            if ($null -eq $adUser) {
                $adUser = Get-AzADUser -Filter "mail eq '$($accountId)'" -ErrorAction SilentlyContinue
            }

            if ($null -ne $adUser) {
                if ([string]::IsNullOrEmpty($adUser.Id)) {
                    throw "Get-AzADUser returned an object for '$($accountId)' but the Id property is empty. Check Az.Resources module version."
                }
                $objectId = $adUser.Id
            }
            else {
                # Fallback: /me endpoint via Microsoft Graph REST. Works for any account type
                # (including personal Microsoft accounts) as long as the session has a valid
                # Graph token, which Connect-AzAccount provides automatically.
                Write-Host "    UPN/mail lookup returned no result — querying Graph /me endpoint..." -ForegroundColor Yellow
                $meResponse = Invoke-AzRestMethod -Uri 'https://graph.microsoft.com/v1.0/me' -Method GET -ErrorAction SilentlyContinue
                if ($null -ne $meResponse -and $meResponse.StatusCode -eq 200) {
                    $objectId = ($meResponse.Content | ConvertFrom-Json).id
                }
            }
        }
        elseif ($accountType -eq 'ServicePrincipal') {
            $adSp = Get-AzADServicePrincipal -ApplicationId $accountId -ErrorAction SilentlyContinue
            if ($null -ne $adSp) {
                $objectId = $adSp.Id
            }
        }
        else {
            throw "Account type '$accountType' is not supported. For managed identities, assign roles manually in the Azure portal."
        }

        if ([string]::IsNullOrEmpty($objectId)) {
            throw "Could not resolve an Object ID for '$($accountId)' (type: $($accountType)). All lookup strategies failed (UPN, mail filter, Graph /me). Assign roles manually in the Azure portal."
        }

        Write-Done "Principal resolved: $accountId (Object ID: $objectId)"
    }
    catch {
        throw "Failed to resolve deploying principal: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Resource Group
    # -----------------------------------------------------------------------
    Write-Step "Resource Group: $resourceGroupName"
    try {
        if ($null -ne (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
            Write-Skip "Already exists — skipping."
        }
        else {
            New-AzResourceGroup -Name $resourceGroupName -Location $Location -Tag $tags -ErrorAction Stop | Out-Null
            Write-Done "Created."
        }
    }
    catch {
        throw "Failed to create Resource Group '$resourceGroupName': $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Storage Account
    # -----------------------------------------------------------------------
    Write-Step "Storage Account: $storageAccountName"
    try {
        if ($null -ne (Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue)) {
            Write-Skip "Already exists — applying security settings."
            Set-AzStorageAccount `
                -ResourceGroupName            $resourceGroupName `
                -Name                         $storageAccountName `
                -AllowSharedKeyAccess         $false `
                -ErrorAction                  Stop | Out-Null
            Write-Done "Security settings applied."
        }
        else {
            New-AzStorageAccount `
                -ResourceGroupName            $resourceGroupName `
                -Name                         $storageAccountName `
                -Location                     $Location `
                -SkuName                      'Standard_LRS' `
                -Kind                         'StorageV2' `
                -MinimumTlsVersion            'TLS1_2' `
                -AllowBlobPublicAccess        $false `
                -AllowSharedKeyAccess         $false `
                -Tag                          $tags `
                -ErrorAction                  Stop | Out-Null
            Write-Done "Created."
        }
    }
    catch {
        throw "Failed to create Storage Account '$storageAccountName': $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Storage Blob Data Contributor role — immediately after Storage Account creation.
    # Shared key access is disabled; the container (data-plane) must be created via
    # OAuth, which requires this role to be active before the container step runs.
    # -----------------------------------------------------------------------
    Write-Step "Storage Account RBAC: 'Storage Blob Data Contributor' -> $accountId"
    try {
        [string]$saScope    = "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName"
        $existingSaRole = Get-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName 'Storage Blob Data Contributor' -Scope $saScope -ErrorAction SilentlyContinue
        if ($null -ne $existingSaRole) {
            Write-Skip "Role already assigned — skipping."
        }
        else {
            try {
                New-AzRoleAssignment `
                    -ObjectId           $objectId `
                    -RoleDefinitionName 'Storage Blob Data Contributor' `
                    -Scope              $saScope `
                    -ErrorAction        Stop | Out-Null
                Write-Done "Role assigned."
            }
            catch {
                if ($_.Exception.Message -match 'RoleAssignmentExists') {
                    Write-Skip "Role assignment already exists."
                }
                else {
                    throw
                }
            }
        }

        Write-Host "    Waiting for RBAC role to propagate to the data plane..." -ForegroundColor Yellow
        [int]$saRbacMaxWait  = 120
        [int]$saRbacInterval = 10
        [int]$saRbacElapsed  = 0
        [bool]$saRbacVisible = $false

        while ($saRbacElapsed -lt $saRbacMaxWait) {
            $saRoleCheck = Get-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName 'Storage Blob Data Contributor' -Scope $saScope -ErrorAction SilentlyContinue
            if ($null -ne $saRoleCheck) {
                $saRbacVisible = $true
                break
            }
            Write-Host "    Role not yet visible ($saRbacElapsed/$saRbacMaxWait s) — checking again in $saRbacInterval s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $saRbacInterval
            $saRbacElapsed += $saRbacInterval
        }

        if (-not $saRbacVisible) {
            Write-Warning "Storage Blob Data Contributor role not confirmed within $saRbacMaxWait s. Container creation may fail — verify in the Azure portal before re-running."
        }
        else {
            Write-Done "Role confirmed active ($saRbacElapsed s elapsed)."
        }
    }
    catch {
        throw "Failed to assign Storage Blob Data Contributor role: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Storage Container — created BEFORE firewall rules are applied.
    # New-AzStorageContainer is a data-plane call subject to network ACLs.
    # Shared key access is disabled; an OAuth context (current user token) is
    # used — requires the Storage Blob Data Contributor role above to be active.
    # -----------------------------------------------------------------------
    Write-Step "Storage Container: $storageContainerName"
    try {
        $storageContext = New-AzStorageContext `
            -StorageAccountName $storageAccountName `
            -UseConnectedAccount

        if ($null -ne (Get-AzStorageContainer -Name $storageContainerName -Context $storageContext -ErrorAction SilentlyContinue)) {
            Write-Skip "Already exists — skipping."
        }
        else {
            New-AzStorageContainer `
                -Name        $storageContainerName `
                -Context     $storageContext `
                -Permission  'Off' `
                -ErrorAction Stop | Out-Null
            Write-Done "Created."
        }
    }
    catch {
        throw "Failed to create Storage Container '$storageContainerName': $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Storage Account firewall rules — applied AFTER the container exists.
    # -----------------------------------------------------------------------
    Write-Step "Storage Account firewall (allow $AllowedIpAddress, deny all else)"
    try {
        Add-AzStorageAccountNetworkRule `
            -ResourceGroupName $resourceGroupName `
            -Name              $storageAccountName `
            -IPAddressOrRange  @($AllowedIpAddress) `
            -ErrorAction       Stop | Out-Null

        Update-AzStorageAccountNetworkRuleSet `
            -ResourceGroupName $resourceGroupName `
            -Name              $storageAccountName `
            -DefaultAction     'Deny' `
            -Bypass            'AzureServices' `
            -ErrorAction       Stop | Out-Null

        Write-Done "Firewall configured."
    }
    catch {
        throw "Failed to configure Storage Account firewall rules: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Key Vault
    # -----------------------------------------------------------------------
    Write-Step "Key Vault: $keyVaultName"
    try {
        if ($null -ne (Get-AzKeyVault -VaultName $keyVaultName -ErrorAction SilentlyContinue)) {
            Write-Skip "Already exists — skipping creation."
        }
        else {
            # EnablePurgeProtection is a [SwitchParameter]. Add it to the
            # splatting hashtable only when $true — once enabled it is permanent.
            [hashtable]$kvParams = @{
                Name                         = $keyVaultName
                ResourceGroupName            = $resourceGroupName
                Location                     = $Location
                EnabledForDeployment         = $true
                EnabledForTemplateDeployment = $true
                EnabledForDiskEncryption     = $true
                Tag                          = $tags
                ErrorAction                  = 'Stop'
            }
            if ($EnablePurgeProtection) {
                $kvParams['EnablePurgeProtection'] = $true
            }

            New-AzKeyVault @kvParams | Out-Null
            Write-Done "Created (purge protection: $EnablePurgeProtection)."
        }
    }
    catch {
        throw "Failed to create Key Vault '$keyVaultName': $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Key Vault Secrets Officer role — immediately after Key Vault creation.
    # -----------------------------------------------------------------------
    Write-Step "Key Vault RBAC: 'Key Vault Secrets Officer' -> $accountId"
    try {
        [string]$kvScope    = "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.KeyVault/vaults/$keyVaultName"
        $existingKvRole = Get-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName 'Key Vault Secrets Officer' -Scope $kvScope -ErrorAction SilentlyContinue
        if ($null -ne $existingKvRole) {
            Write-Skip "Role already assigned — skipping."
        }
        else {
            try {
                New-AzRoleAssignment `
                    -ObjectId           $objectId `
                    -RoleDefinitionName 'Key Vault Secrets Officer' `
                    -Scope              $kvScope `
                    -ErrorAction        Stop | Out-Null
                Write-Done "Role assigned."
            }
            catch {
                if ($_.Exception.Message -match 'RoleAssignmentExists') {
                    Write-Skip "Role assignment already exists."
                }
                else {
                    throw
                }
            }
        }

        Write-Host "    Waiting for RBAC role to propagate to the data plane..." -ForegroundColor Yellow
        [int]$kvRbacMaxWait  = 120
        [int]$kvRbacInterval = 10
        [int]$kvRbacElapsed  = 0
        [bool]$kvRbacVisible = $false

        while ($kvRbacElapsed -lt $kvRbacMaxWait) {
            $kvRoleCheck = Get-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName 'Key Vault Secrets Officer' -Scope $kvScope -ErrorAction SilentlyContinue
            if ($null -ne $kvRoleCheck) {
                $kvRbacVisible = $true
                break
            }
            Write-Host "    Role not yet visible ($kvRbacElapsed/$kvRbacMaxWait s) — checking again in $kvRbacInterval s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $kvRbacInterval
            $kvRbacElapsed += $kvRbacInterval
        }

        if (-not $kvRbacVisible) {
            Write-Warning "Key Vault Secrets Officer role not confirmed within $kvRbacMaxWait s. Secret creation may fail — verify in the Azure portal before re-running."
        }
        else {
            Write-Done "Role confirmed active ($kvRbacElapsed s elapsed)."
        }
    }
    catch {
        throw "Failed to assign Key Vault Secrets Officer role: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Key Vault network rules — Update-AzKeyVaultNetworkRuleSet is the correct
    # cmdlet for adding IP ranges. Add-AzKeyVaultNetworkRule does not exist in
    # the Az.KeyVault module. Passing -IpAddressRange replaces the full IP rule
    # set, which makes this call idempotent on re-runs.
    # -----------------------------------------------------------------------
    Write-Step "Key Vault firewall (allow $ipCidr, deny all else)"
    try {
        Update-AzKeyVaultNetworkRuleSet `
            -VaultName      $keyVaultName `
            -DefaultAction  'Deny' `
            -Bypass         'AzureServices' `
            -IpAddressRange @($ipCidr) `
            -ErrorAction    Stop | Out-Null

        Write-Done "Firewall configured."
    }
    catch {
        throw "Failed to configure Key Vault firewall rules: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Placeholder secrets — Set-AzKeyVaultSecret is a data-plane call subject
    # to network ACLs and RBAC role propagation. Each secret is retried up to
    # $secretMaxAttempts times on Forbidden/403 to absorb any remaining lag.
    # -----------------------------------------------------------------------
    Write-Step 'Creating placeholder secrets'
    try {
        # Build SecureString char-by-char to avoid PSAvoidUsingConvertToSecureStringWithPlainText.
        # These are intentional placeholder values — not real secrets.
        [System.Security.SecureString]$placeholderValue = [System.Security.SecureString]::new()
        'PLACEHOLDER-CHANGE-ME'.ToCharArray() | ForEach-Object { $placeholderValue.AppendChar($_) }
        $placeholderValue.MakeReadOnly()

        [int]$secretMaxAttempts = 6
        [int]$secretRetryDelay  = 10   # seconds between retries

        foreach ($secretName in $secretNames) {
            [bool]$secretSet = $false

            for ([int]$attempt = 1; $attempt -le $secretMaxAttempts; $attempt++) {
                try {
                    Set-AzKeyVaultSecret `
                        -VaultName   $keyVaultName `
                        -Name        $secretName `
                        -SecretValue $placeholderValue `
                        -ErrorAction Stop | Out-Null

                    Write-Done "Secret set: $secretName"
                    $secretSet = $true
                    break
                }
                catch {
                    if ($_.Exception.Message -match 'Forbidden|Access Denied|403' -and $attempt -lt $secretMaxAttempts) {
                        Write-Host "    Access denied on attempt $attempt/$secretMaxAttempts for '$secretName' — waiting $($secretRetryDelay)s for role propagation..." -ForegroundColor Yellow
                        Start-Sleep -Seconds $secretRetryDelay
                    }
                    else {
                        throw
                    }
                }
            }

            if (-not $secretSet) {
                throw "Failed to set secret '$secretName' after $secretMaxAttempts attempts. Verify the Key Vault network rules allow your IP ($AllowedIpAddress) and that the 'Key Vault Secrets Officer' role for '$($objectId)' is active."
            }
        }
    }
    catch {
        throw "Failed to create placeholder secrets: $($_.Exception.Message)"
    }

    # -----------------------------------------------------------------------
    # Completion summary
    # -----------------------------------------------------------------------
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host '  Bootstrap complete.'                                         -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Resources created/verified:'                                -ForegroundColor White
    Write-Host "    Resource Group  : $resourceGroupName"                     -ForegroundColor White
    Write-Host "    Storage Account : $storageAccountName"                    -ForegroundColor White
    Write-Host "    Container       : $storageContainerName"                  -ForegroundColor White
    Write-Host "    Key Vault       : $keyVaultName"                          -ForegroundColor White
    Write-Host "    Log             : $logFilePath"                           -ForegroundColor White
    Write-Host ''
    Write-Host '  Paste this block into environments/dev/main.tf as the Terraform backend:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '    terraform {'                                               -ForegroundColor White
    Write-Host '      backend "azurerm" {'                                    -ForegroundColor White
    Write-Host "        resource_group_name  = `"$resourceGroupName`""        -ForegroundColor White
    Write-Host "        storage_account_name = `"$storageAccountName`""       -ForegroundColor White
    Write-Host "        container_name       = `"$storageContainerName`""     -ForegroundColor White
    Write-Host '        key                  = "wave1.terraform.tfstate"'    -ForegroundColor White
    Write-Host '      }'                                                      -ForegroundColor White
    Write-Host '    }'                                                        -ForegroundColor White
    Write-Host ''
    Write-Host '  Next steps:'                                                -ForegroundColor Yellow
    Write-Host "    1. Open Key Vault '$keyVaultName' and replace placeholder secrets:" -ForegroundColor White
    foreach ($secretName in $secretNames) {
        Write-Host "         $secretName"                                     -ForegroundColor White
    }
    Write-Host '    2. Copy the backend block above into environments/dev/main.tf.' -ForegroundColor White
    Write-Host '    3. Run: terraform init   (inside environments/dev/)'      -ForegroundColor White
    Write-Host '    4. Proceed to Wave 1: modules/network.'                   -ForegroundColor White
    Write-Host ''

}
finally {
    if ($transcriptStarted) { Stop-Transcript }
}
