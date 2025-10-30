#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configures Easy Auth on Azure Function App and grants AI Foundry project Managed Identity access.

.DESCRIPTION
    This script automates the setup of Azure AD authentication (Easy Auth) on an Azure Function App
    and grants the AI Foundry project's Managed Identity the necessary permissions to invoke the function.

.PARAMETER ResourceGroupName
    The name of the resource group containing the Function App.

.PARAMETER FunctionAppName
    The name of the Azure Function App to configure.

.PARAMETER AIFoundryProjectName
    The name of the AI Foundry project (or AI Hub/Workspace).

.PARAMETER AIFoundryResourceGroup
    The resource group containing the AI Foundry project (if different from Function App RG).

.PARAMETER TenantId
    Optional: Azure AD Tenant ID. If not provided, uses current subscription's tenant.

.PARAMETER AllowedAudiences
    Optional: Custom allowed token audiences. Defaults to Function App URL.

.PARAMETER SkipRoleAssignment
    Skip granting role assignment (useful if already granted).

.EXAMPLE
    .\deploy-auth.ps1 -ResourceGroupName "rg-ai-content" -FunctionAppName "func-aicu-wrapper" -AIFoundryProjectName "ai-foundry-project"

.EXAMPLE
    .\deploy-auth.ps1 -ResourceGroupName "rg-functions" -FunctionAppName "my-function" -AIFoundryProjectName "my-ai-project" -AIFoundryResourceGroup "rg-ai-foundry"

.NOTES
    Requires Azure PowerShell module (Az) and appropriate permissions:
    - Owner or User Access Administrator role on Function App
    - Reader role on AI Foundry project
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory = $true)]
    [string]$AIFoundryProjectName,

    [Parameter(Mandatory = $false)]
    [string]$AIFoundryResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$AIFoundryResourceType,

    [Parameter(Mandatory = $false)]
    [string[]]$AllowedAudiences,

    [Parameter(Mandatory = $false)]
    [string]$AppRegistrationClientId,

    [Parameter(Mandatory = $false)]
    [string]$AppRegistrationAudience,

    [Parameter(Mandatory = $false)]
    [switch]$SkipRoleAssignment
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to write section headers
function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "========================================" "Cyan"
    Write-ColorOutput $Title "Cyan"
    Write-ColorOutput "========================================" "Cyan"
}

# Main script
try {
    Write-Section "Azure Function App Easy Auth Setup"
    Write-ColorOutput "Configuration:" "Yellow"
    Write-ColorOutput "  Resource Group: $ResourceGroupName" "Gray"
    Write-ColorOutput "  Function App: $FunctionAppName" "Gray"
    Write-ColorOutput "  AI Foundry Project: $AIFoundryProjectName" "Gray"
    
    # Check if Azure PowerShell module is installed
    Write-Section "Step 1: Checking Prerequisites"
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "Azure PowerShell module (Az) is not installed. Install it with: Install-Module -Name Az -AllowClobber -Scope CurrentUser"
    }
    Write-ColorOutput "[OK] Azure PowerShell module found" "Green"

    # Check if logged in
    $context = Get-AzContext
    if (-not $context) {
        Write-ColorOutput "Not logged in to Azure. Initiating login..." "Yellow"
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-ColorOutput "[OK] Logged in as: $($context.Account.Id)" "Green"
    Write-ColorOutput "  Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" "Gray"
    
    if (-not $TenantId) {
        $TenantId = $context.Tenant.Id
    }
    Write-ColorOutput "  Tenant ID: $TenantId" "Gray"

    # Get Function App details using Azure CLI (more reliable than Az PowerShell for this operation)
    Write-Section "Step 2: Retrieving Function App Details"
    Write-ColorOutput "Fetching Function App information..." "Yellow"
    
    # Check if Azure CLI is available
    $azCliAvailable = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCliAvailable) {
        throw "Azure CLI is required but not found. Install from: https://aka.ms/InstallAzureCLI"
    }
    
    # Ensure logged in to Azure CLI
    $azAccount = az account show 2>&1 | ConvertFrom-Json
    if (-not $azAccount) {
        Write-ColorOutput "Logging in to Azure CLI..." "Yellow"
        az login --tenant $TenantId | Out-Null
        $azAccount = az account show 2>&1 | ConvertFrom-Json
    }

    if ($SubscriptionId -and ($azAccount.id -ne $SubscriptionId -and $azAccount.subscriptionId -ne $SubscriptionId)) {
        Write-ColorOutput "Setting Azure CLI subscription context to $SubscriptionId" "Yellow"
        az account set --subscription $SubscriptionId
        $azAccount = az account show 2>&1 | ConvertFrom-Json
        if ($azAccount.id -ne $SubscriptionId -and $azAccount.subscriptionId -ne $SubscriptionId) {
            throw "Failed to set Azure CLI subscription to $SubscriptionId"
        }
        Write-ColorOutput "[OK] Subscription context set" "Green"
    }
    
    # Get Function App details using Azure CLI
    # Note: az webapp show provides more complete properties than az functionapp show
    # This is critical for Flex Consumption plans where hostnames have unique suffixes
    $functionAppJson = az webapp show --name $FunctionAppName --resource-group $ResourceGroupName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Function App '$FunctionAppName' not found in resource group '$ResourceGroupName'"
    }
    
    $functionApp = $functionAppJson | ConvertFrom-Json
    if (-not $functionApp) {
        throw "Function App '$FunctionAppName' not found in resource group '$ResourceGroupName'"
    }
    
    $functionAppId = $functionApp.id
    $rawHostName = $functionApp.defaultHostName
    if (-not $rawHostName -or $rawHostName.Trim() -eq '') {
        # Fallback pattern for Azure Function Apps (traditional naming)
        $rawHostName = "$FunctionAppName.azurewebsites.net"
        Write-ColorOutput "[WARN] defaultHostName missing; using fallback '$rawHostName'" "Yellow"
    }
    $functionAppUrl = "https://$rawHostName"
    
    Write-ColorOutput "[OK] Function App found" "Green"
    Write-ColorOutput "  Resource ID: $functionAppId" "Gray"
    Write-ColorOutput "  URL: $functionAppUrl" "Gray"
    Write-ColorOutput "  Location: $($functionApp.location)" "Gray"

    # Determine allowed audiences
    if (-not $AllowedAudiences) {
        # If an explicit AppRegistrationAudience is provided, prefer it
        if ($AppRegistrationAudience) {
            $AllowedAudiences = @($AppRegistrationAudience)
            Write-ColorOutput "  Using App Registration Audience: $AppRegistrationAudience" "Gray"
        } else {
            $AllowedAudiences = @($functionAppUrl)
            Write-ColorOutput "  Default Audience: $functionAppUrl" "Gray"
        }
    }

    # Enable System-assigned Managed Identity on Function App (if not already enabled)
    Write-Section "Step 3: Enabling Managed Identity on Function App"
    $identityType = $functionApp.identity.type
    if ($identityType -ne "SystemAssigned" -and $identityType -ne "SystemAssigned, UserAssigned") {
        Write-ColorOutput "Enabling System-assigned Managed Identity..." "Yellow"
        az functionapp identity assign --name $FunctionAppName --resource-group $ResourceGroupName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to enable Managed Identity on Function App"
        }
        # Refresh function app details
        $functionAppJson = az functionapp show --name $FunctionAppName --resource-group $ResourceGroupName
        $functionApp = $functionAppJson | ConvertFrom-Json
        Write-ColorOutput "[OK] Managed Identity enabled" "Green"
    } else {
        Write-ColorOutput "[OK] Managed Identity already enabled" "Green"
    }

    # Configure Easy Auth (Azure AD authentication)
    Write-Section "Step 4: Configuring Easy Auth (Azure AD Authentication)"
    Write-ColorOutput "Enabling Azure AD authentication on Function App..." "Yellow"
    
    # Use Azure CLI for Easy Auth configuration
    # Note: For managed identity auth (no interactive login), we configure Azure AD with audience validation
    # All other providers must be explicitly disabled or they'll show as "enabled" in portal
    
    # Configure auth settings using az rest (direct REST API call via CLI)
    $effectiveClientId = if ($AppRegistrationClientId) { $AppRegistrationClientId } else { "00000000-0000-0000-0000-000000000000" }
    $authConfig = @{
        properties = @{
            platform = @{
                enabled = $true
            }
            globalValidation = @{
                requireAuthentication = $true
                unauthenticatedClientAction = "Return401"
            }
            identityProviders = @{
                azureActiveDirectory = @{
                    enabled = $true
                    registration = @{
                        openIdIssuer = "https://sts.windows.net/$TenantId/v2.0"
                        clientId = $effectiveClientId
                    }
                    validation = @{
                        allowedAudiences = $AllowedAudiences
                    }
                }
                facebook = @{
                    enabled = $false
                }
                gitHub = @{
                    enabled = $false
                }
                google = @{
                    enabled = $false
                }
                twitter = @{
                    enabled = $false
                }
                apple = @{
                    enabled = $false
                }
                legacyMicrosoftAccount = @{
                    enabled = $false
                }
            }
        }
    } | ConvertTo-Json -Depth 10
    
    $authConfigFile = [System.IO.Path]::GetTempFileName()
    $authConfig | Out-File -FilePath $authConfigFile -Encoding utf8
    
    try {
        az rest --method PUT `
            --uri "$functionAppId/config/authsettingsV2?api-version=2021-02-01" `
            --body "@$authConfigFile" | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "[OK] Easy Auth configured successfully" "Green"
            Write-ColorOutput "  Authentication: Required" "Gray"
            Write-ColorOutput "  Unauthenticated Action: Return401" "Gray"
            Write-ColorOutput "  Allowed Audiences: $($AllowedAudiences -join ', ')" "Gray"
        } else {
            throw "Failed to configure Easy Auth"
        }
    } finally {
        Remove-Item $authConfigFile -ErrorAction SilentlyContinue
    }

    # Get AI Foundry project Managed Identity
    Write-Section "Step 5: Retrieving AI Foundry Project Managed Identity"
    Write-ColorOutput "Fetching AI Foundry project information..." "Yellow"
    
    # Use AIFoundryResourceGroup if provided, otherwise use same as Function App
    $aiFoundryRG = if ($AIFoundryResourceGroup) { $AIFoundryResourceGroup } else { $ResourceGroupName }
    
    # Resource discovery logic with optional explicit resource type override
    $aiFoundryResource = $null
    if ($AIFoundryResourceType) {
        Write-ColorOutput "Using explicit AI Foundry resource type: $AIFoundryResourceType" "Yellow"
        $resourceJson = az resource show --name $AIFoundryProjectName --resource-group $aiFoundryRG --resource-type $AIFoundryResourceType 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "AI Foundry resource '$AIFoundryProjectName' of type '$AIFoundryResourceType' not found in resource group '$aiFoundryRG'"
        }
        $aiFoundryResource = $resourceJson | ConvertFrom-Json
    } else {
        $resourceTypes = @(
            "Microsoft.CognitiveServices/accounts",
            "Microsoft.MachineLearningServices/workspaces",
            "Microsoft.AIServices/accounts",
            "Microsoft.AI/hubs"
        )
        foreach ($resourceType in $resourceTypes) {
            $resourceJson = az resource show --name $AIFoundryProjectName --resource-group $aiFoundryRG --resource-type $resourceType 2>&1
            if ($LASTEXITCODE -eq 0) {
                $aiFoundryResource = $resourceJson | ConvertFrom-Json
                if ($aiFoundryResource) {
                    $foundType = $resourceType
                    Write-ColorOutput "[OK] Found AI Foundry resource (Type: $resourceType)" "Green"
                    break
                }
            }
        }
        if (-not $aiFoundryResource) {
            # List resource group contents to aid troubleshooting
            Write-ColorOutput "Listing resources in '$aiFoundryRG' for troubleshooting..." "Yellow"
            $rgResources = az resource list --resource-group $aiFoundryRG --query "[].{name:name,type:type}" --output json 2>&1 | ConvertFrom-Json
            $rgResourceSummary = ($rgResources | ForEach-Object { "${($_.name)} (${($_.type)})" }) -join ", "
            throw "AI Foundry project '$AIFoundryProjectName' not found in resource group '$aiFoundryRG'. Tried types: $($resourceTypes -join ', '). Resources present: $rgResourceSummary"
        }
    }
    
    Write-ColorOutput "  Resource ID: $($aiFoundryResource.id)" "Gray"
    Write-ColorOutput "  Resource Type: $($aiFoundryResource.type)" "Gray"
    
    # Get the Managed Identity Principal ID
    $principalId = $null
    
    if ($aiFoundryResource.identity.principalId) {
        $principalId = $aiFoundryResource.identity.principalId
    } elseif ($aiFoundryResource.properties.identity.principalId) {
        $principalId = $aiFoundryResource.properties.identity.principalId
    }
    
    if (-not $principalId) {
        throw "AI Foundry project does not have a Managed Identity enabled. Please enable it first."
    }
    
    Write-ColorOutput "[OK] Managed Identity found" "Green"
    Write-ColorOutput "  Principal ID: $principalId" "Gray"

    # Grant role assignment
    if (-not $SkipRoleAssignment) {
        Write-Section "Step 6: Granting Access to Function App"
        Write-ColorOutput "Assigning 'Website Contributor' role to AI Foundry MI..." "Yellow"
        
        # Check if role assignment already exists using Azure CLI
        $existingAssignments = az role assignment list --assignee $principalId --scope $functionAppId --role "Website Contributor" 2>&1 | ConvertFrom-Json
        
        if ($existingAssignments -and $existingAssignments.Count -gt 0) {
            Write-ColorOutput "[OK] Role assignment already exists" "Green"
        } else {
            az role assignment create --assignee $principalId --role "Website Contributor" --scope $functionAppId | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "[OK] Role assignment created successfully" "Green"
                Write-ColorOutput "  Role: Website Contributor" "Gray"
                Write-ColorOutput "  Scope: $FunctionAppName" "Gray"
            } else {
                # Check if it was a duplicate error (benign)
                $existingCheck = az role assignment list --assignee $principalId --scope $functionAppId --role "Website Contributor" 2>&1 | ConvertFrom-Json
                if ($existingCheck -and $existingCheck.Count -gt 0) {
                    Write-ColorOutput "[OK] Role assignment already exists" "Green"
                } else {
                    throw "Failed to create role assignment"
                }
            }
        }
    } else {
        Write-Section "Step 6: Skipping Role Assignment"
        Write-ColorOutput "Role assignment skipped (SkipRoleAssignment flag set)" "Yellow"
    }

    # Summary
    Write-Section "Deployment Complete!"
    Write-ColorOutput "[SUCCESS] Easy Auth enabled on Function App" "Green"
    Write-ColorOutput "[SUCCESS] AI Foundry project granted access" "Green"
    Write-Host ""
    Write-ColorOutput "Next Steps:" "Cyan"
    Write-ColorOutput "1. Update your OpenAPI spec with the audience:" "White"
    Write-ColorOutput "   $functionAppUrl" "Yellow"
    Write-Host ""
    Write-ColorOutput "2. Configure AI Agent with:" "White"
    Write-ColorOutput "   {" "Gray"
    Write-ColorOutput "     `"authentication`": {" "Gray"
    Write-ColorOutput "       `"type`": `"managed_identity`"," "Gray"
    Write-ColorOutput "       `"audience`": `"$functionAppUrl`"" "Gray"
    Write-ColorOutput "     }" "Gray"
    Write-ColorOutput "   }" "Gray"
    Write-Host ""
    Write-ColorOutput "3. Test the function:" "White"
    Write-ColorOutput "   Invoke from AI Foundry project using Managed Identity" "Gray"
    Write-Host ""
    Write-ColorOutput "Configuration Summary:" "Cyan"
    Write-ColorOutput "  Function App: $functionAppUrl" "White"
    Write-ColorOutput "  Audience: $functionAppUrl" "White"
    Write-ColorOutput "  Hostname Source: $rawHostName" "White"
    Write-ColorOutput "  AI Foundry MI Principal: $principalId" "White"
    Write-ColorOutput "  Role: Website Contributor" "White"
    Write-Host ""

} catch {
    Write-Host ""
    Write-ColorOutput "========================================" "Red"
    Write-ColorOutput "ERROR: Deployment Failed" "Red"
    Write-ColorOutput "========================================" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    Write-Host ""
    Write-ColorOutput "Stack Trace:" "Yellow"
    Write-ColorOutput $_.ScriptStackTrace "Gray"
    Write-Host ""
    exit 1
}
