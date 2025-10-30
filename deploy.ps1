#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploys the AI Content Understanding Wrapper Function to Azure with full infrastructure provisioning.

.DESCRIPTION
    This script deploys a complete Azure Function infrastructure including:
    - Storage Account (new or existing)
    - App Service Plan (Flex Consumption, Consumption, or Elastic Premium)
    - Function App with Managed Identity
    - Optional VNet integration with subnets
    - Optional Storage Private Endpoints
    - Application Insights for monitoring
    - Proper RBAC assignments

.PARAMETER ResourceGroupName
    Name of the resource group to deploy to. Will be created if it doesn't exist.

.PARAMETER Location
    Azure region for deployment (e.g., 'eastus', 'westus2').

.PARAMETER FunctionAppName
    Name of the function app. Must be globally unique.

.PARAMETER StorageAccountName
    Name of the storage account. Must be globally unique. If not provided, auto-generated.

.PARAMETER UseExistingStorage
    Use an existing storage account instead of creating a new one.

.PARAMETER StorageAccountType
    Storage account SKU. Options: Standard_LRS, Standard_GRS, Standard_RAGRS, Standard_ZRS, Premium_LRS.

.PARAMETER Runtime
    Runtime for the function app. Options: python, node, dotnet, java.

.PARAMETER RuntimeVersion
    Runtime version (e.g., '3.11' for Python, '20' for Node.js).

.PARAMETER FunctionAppSku
    Function App hosting plan SKU. Options: FC1 (Flex Consumption), Y1 (Consumption), EP1/EP2/EP3 (Elastic Premium).

.PARAMETER EnableVNetIntegration
    Enable VNet integration for the function app.

.PARAMETER VNetName
    Name of the VNet. Will be created if it doesn't exist.

.PARAMETER VNetAddressPrefix
    Address prefix for VNet (e.g., '10.0.0.0/16').

.PARAMETER FunctionSubnetAddressPrefix
    Address prefix for function app subnet (e.g., '10.0.1.0/24').

.PARAMETER PrivateEndpointSubnetAddressPrefix
    Address prefix for private endpoint subnet (e.g., '10.0.2.0/24').

.PARAMETER EnableStoragePrivateEndpoint
    Enable private endpoint for storage account (requires VNet integration).

.PARAMETER ContentUnderstandingBaseUrl
    Azure AI Content Understanding base URL.

.PARAMETER DefaultAnalyzerId
    Default analyzer ID to use.

.PARAMETER EnableApplicationInsights
    Enable Application Insights for monitoring.

.PARAMETER DeployCode
    Deploy the function code after infrastructure provisioning.

.PARAMETER ParameterFile
    Path to a JSON parameter file for deployment.

.EXAMPLE
    # Basic deployment with defaults
    .\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper-prod"

.EXAMPLE
    # Deployment with VNet integration
    .\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper" -EnableVNetIntegration -VNetName "vnet-aicu"

.EXAMPLE
    # Deployment with VNet and Storage Private Endpoint
    .\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper" `
        -EnableVNetIntegration -EnableStoragePrivateEndpoint -VNetName "vnet-aicu"

.EXAMPLE
    # Use existing storage account
    .\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper" `
        -UseExistingStorage -StorageAccountName "existingstorage123"

.EXAMPLE
    # Full deployment with code deployment
    .\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper" `
        -ContentUnderstandingBaseUrl "https://my-aicu.cognitiveservices.azure.com" `
        -DefaultAnalyzerId "prebuilt-invoice" -DeployCode

.NOTES
    Requires:
    - Azure PowerShell module (Az)
    - Azure CLI (for code deployment if -DeployCode is specified)
    - Appropriate Azure subscription permissions
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $false)]
    [switch]$UseExistingStorage,

    [Parameter(Mandatory = $false)]
    [switch]$UseExistingVNet,

    [Parameter(Mandatory = $false)]
    [string]$ExistingAppServicePlanName = '',

    [Parameter(Mandatory = $false)]
    [string]$ExistingApplicationInsightsName = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS')]
    [string]$StorageAccountType = 'Standard_LRS',

    [Parameter(Mandatory = $false)]
    [ValidateSet('python', 'node', 'dotnet', 'java')]
    [string]$Runtime = 'python',

    [Parameter(Mandatory = $false)]
    [string]$RuntimeVersion = '3.11',

    [Parameter(Mandatory = $false)]
    [ValidateSet('FC1', 'Y1', 'EP1', 'EP2', 'EP3')]
    [string]$FunctionAppSku = 'FC1',

    [Parameter(Mandatory = $false)]
    [switch]$EnableVNetIntegration,

    [Parameter(Mandatory = $false)]
    [string]$VNetName = '',

    [Parameter(Mandatory = $false)]
    [string]$VNetAddressPrefix = '10.0.0.0/16',

    [Parameter(Mandatory = $false)]
    [string]$FunctionSubnetAddressPrefix = '10.0.1.0/24',

    [Parameter(Mandatory = $false)]
    [string]$PrivateEndpointSubnetAddressPrefix = '10.0.2.0/24',

    [Parameter(Mandatory = $false)]
    [switch]$EnableStoragePrivateEndpoint,

    [Parameter(Mandatory = $false)]
    [string]$ContentUnderstandingBaseUrl = '',

    [Parameter(Mandatory = $false)]
    [string]$DefaultAnalyzerId = '',

    [Parameter(Mandatory = $false)]
    [bool]$EnableApplicationInsights = $true,

    [Parameter(Mandatory = $false)]
    [switch]$DeployCode,

    [Parameter(Mandatory = $false)]
    [string]$ParameterFile = ''
)

$ErrorActionPreference = "Stop"

# Helper functions
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "========================================" "Cyan"
    Write-ColorOutput $Title "Cyan"
    Write-ColorOutput "========================================" "Cyan"
}

try {
    Write-Section "AI Content Understanding Wrapper - Azure Deployment"
    
    # Check prerequisites
    Write-Section "Step 1: Checking Prerequisites"
    
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "Azure PowerShell module (Az) is not installed. Install it with: Install-Module -Name Az -AllowClobber -Scope CurrentUser"
    }
    Write-ColorOutput "[OK] Azure PowerShell module found" "Green"

    # Check Azure login
    $context = Get-AzContext
    if (-not $context) {
        Write-ColorOutput "Not logged in to Azure. Initiating login..." "Yellow"
        Connect-AzAccount
        $context = Get-AzContext
    }
    Write-ColorOutput "[OK] Logged in as: $($context.Account.Id)" "Green"
    Write-ColorOutput "  Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" "Gray"

    # Validate VNet and Private Endpoint requirements
    if ($EnableStoragePrivateEndpoint -and -not $EnableVNetIntegration) {
        throw "Storage Private Endpoint requires VNet integration. Please enable -EnableVNetIntegration"
    }

    # Validate existing resource parameters
    if ($UseExistingVNet -and -not $EnableVNetIntegration) {
        throw "UseExistingVNet requires EnableVNetIntegration to be enabled"
    }

    if ($UseExistingVNet -and -not $VNetName) {
        throw "VNetName is required when using UseExistingVNet"
    }

    if ($ExistingAppServicePlanName) {
        Write-ColorOutput "[INFO] Using existing App Service Plan: $ExistingAppServicePlanName" "Cyan"
    }

    if ($ExistingApplicationInsightsName) {
        Write-ColorOutput "[INFO] Using existing Application Insights: $ExistingApplicationInsightsName" "Cyan"
    }

    # Generate storage account name if not provided
    if (-not $StorageAccountName) {
        # Storage account names must be 3-24 characters, lowercase letters and numbers only
        $prefix = $FunctionAppName -replace '[^a-z0-9]', '' | Select-Object -First 15
        $suffix = -join ((97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_})
        $StorageAccountName = ($prefix + $suffix).ToLower()
        Write-ColorOutput "Generated storage account name: $StorageAccountName" "Yellow"
    }

    # Validate storage account name
    if ($StorageAccountName -notmatch '^[a-z0-9]{3,24}$') {
        throw "Storage account name must be 3-24 characters, lowercase letters and numbers only. Got: $StorageAccountName"
    }

    # Create or verify resource group
    Write-Section "Step 2: Resource Group"
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-ColorOutput "Creating resource group '$ResourceGroupName' in '$Location'..." "Yellow"
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
        Write-ColorOutput "[OK] Resource group created" "Green"
    } else {
        Write-ColorOutput "[OK] Using existing resource group" "Green"
    }

    # Build deployment parameters
    Write-Section "Step 3: Preparing Deployment Parameters"
    
    $deploymentParams = @{
        functionAppName = $FunctionAppName
        location = $Location
        storageAccountName = $StorageAccountName
        useExistingStorageAccount = $UseExistingStorage.IsPresent
        storageAccountType = $StorageAccountType
        runtime = $Runtime
        runtimeVersion = $RuntimeVersion
        functionAppSku = $FunctionAppSku
        enableVNetIntegration = $EnableVNetIntegration.IsPresent
        useExistingVNet = $UseExistingVNet.IsPresent
        enableStoragePrivateEndpoint = $EnableStoragePrivateEndpoint.IsPresent
        enableApplicationInsights = $EnableApplicationInsights
    }

    # Add existing resource names if provided
    if ($ExistingAppServicePlanName) {
        $deploymentParams['useExistingAppServicePlan'] = $true
        $deploymentParams['existingAppServicePlanName'] = $ExistingAppServicePlanName
    } else {
        $deploymentParams['useExistingAppServicePlan'] = $false
    }

    if ($ExistingApplicationInsightsName) {
        $deploymentParams['useExistingApplicationInsights'] = $true
        $deploymentParams['existingApplicationInsightsName'] = $ExistingApplicationInsightsName
    } else {
        $deploymentParams['useExistingApplicationInsights'] = $false
    }

    if ($EnableVNetIntegration) {
        $deploymentParams['vnetName'] = if ($VNetName) { $VNetName } else { "$FunctionAppName-vnet" }
        $deploymentParams['vnetAddressPrefix'] = $VNetAddressPrefix
        $deploymentParams['functionSubnetAddressPrefix'] = $FunctionSubnetAddressPrefix
        $deploymentParams['privateEndpointSubnetAddressPrefix'] = $PrivateEndpointSubnetAddressPrefix
    }

    if ($ContentUnderstandingBaseUrl) {
        $deploymentParams['contentUnderstandingBaseUrl'] = $ContentUnderstandingBaseUrl
    }

    if ($DefaultAnalyzerId) {
        $deploymentParams['defaultAnalyzerId'] = $DefaultAnalyzerId
    }

    Write-ColorOutput "Deployment Configuration:" "Cyan"
    Write-ColorOutput "  Function App: $FunctionAppName" "Gray"
    Write-ColorOutput "  Storage Account: $StorageAccountName $(if ($UseExistingStorage) { '(existing)' } else { '(new)' })" "Gray"
    Write-ColorOutput "  Runtime: $Runtime $RuntimeVersion" "Gray"
    Write-ColorOutput "  SKU: $FunctionAppSku" "Gray"
    if ($ExistingAppServicePlanName) {
        Write-ColorOutput "  App Service Plan: $ExistingAppServicePlanName (existing)" "Gray"
    } else {
        Write-ColorOutput "  App Service Plan: $FunctionAppName-plan (new)" "Gray"
    }
    Write-ColorOutput "  VNet Integration: $($EnableVNetIntegration.IsPresent)" "Gray"
    if ($EnableVNetIntegration -and $UseExistingVNet) {
        Write-ColorOutput "  VNet: $VNetName (existing)" "Gray"
    } elseif ($EnableVNetIntegration) {
        Write-ColorOutput "  VNet: $VNetName (new)" "Gray"
    }
    Write-ColorOutput "  Storage Private Endpoint: $($EnableStoragePrivateEndpoint.IsPresent)" "Gray"
    if ($ExistingApplicationInsightsName) {
        Write-ColorOutput "  Application Insights: $ExistingApplicationInsightsName (existing)" "Gray"
    } else {
        Write-ColorOutput "  Application Insights: $(if ($EnableApplicationInsights) { 'Enabled (new)' } else { 'Disabled' })" "Gray"
    }

    # Deploy infrastructure
    Write-Section "Step 4: Deploying Infrastructure"
    Write-ColorOutput "Starting Bicep deployment... This may take 5-10 minutes." "Yellow"
    
    $bicepFile = Join-Path $PSScriptRoot "main.bicep"
    if (-not (Test-Path $bicepFile)) {
        throw "Bicep template not found at: $bicepFile"
    }

    $deploymentName = "aicu-wrapper-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    $deployment = New-AzResourceGroupDeployment `
        -Name $deploymentName `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $bicepFile `
        -TemplateParameterObject $deploymentParams `
        -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-ColorOutput "[OK] Infrastructure deployment completed successfully" "Green"
    } else {
        throw "Deployment failed with state: $($deployment.ProvisioningState)"
    }

    # Extract outputs
    $functionAppUrl = $deployment.Outputs['functionAppUrl'].Value
    $functionAppPrincipalId = $deployment.Outputs['functionAppPrincipalId'].Value
    $storageAccountNameOutput = $deployment.Outputs['storageAccountName'].Value
    $appInsightsConnectionString = if ($EnableApplicationInsights) { $deployment.Outputs['applicationInsightsConnectionString'].Value } else { '' }

    Write-ColorOutput "Deployment Outputs:" "Cyan"
    Write-ColorOutput "  Function App URL: $functionAppUrl" "Green"
    Write-ColorOutput "  Function App Principal ID: $functionAppPrincipalId" "Gray"
    Write-ColorOutput "  Storage Account: $storageAccountNameOutput" "Gray"
    if ($appInsightsConnectionString) {
        Write-ColorOutput "  Application Insights configured" "Gray"
    }

    # Deploy code if requested
    if ($DeployCode) {
        Write-Section "Step 5: Deploying Function Code"
        
        # Check if Azure CLI is available
        $azCliAvailable = Get-Command az -ErrorAction SilentlyContinue
        if (-not $azCliAvailable) {
            Write-ColorOutput "[WARN] Azure CLI not found. Skipping code deployment." "Yellow"
            Write-ColorOutput "Install Azure CLI from: https://aka.ms/InstallAzureCLI" "Yellow"
        } else {
            Write-ColorOutput "Deploying code using Azure Functions Core Tools..." "Yellow"
            
            # Check if in correct directory
            if (-not (Test-Path "function_app.py")) {
                throw "function_app.py not found in current directory. Please run this script from the project root."
            }

            # Deploy using func azure functionapp publish
            $funcToolAvailable = Get-Command func -ErrorAction SilentlyContinue
            if ($funcToolAvailable) {
                func azure functionapp publish $FunctionAppName --python
                Write-ColorOutput "[OK] Code deployed successfully" "Green"
            } else {
                Write-ColorOutput "[WARN] Azure Functions Core Tools (func) not found. Using zip deployment..." "Yellow"
                
                # Create deployment package
                $timestamp = Get-Date -Format "yyyyMMddHHmmss"
                $zipFile = "deployment-$timestamp.zip"
                
                # Files to include
                $filesToZip = @(
                    "function_app.py",
                    "host.json",
                    "requirements.txt"
                )
                
                if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
                Compress-Archive -Path $filesToZip -DestinationPath $zipFile
                
                # Deploy zip
                az functionapp deployment source config-zip `
                    --resource-group $ResourceGroupName `
                    --name $FunctionAppName `
                    --src $zipFile
                
                Remove-Item $zipFile -Force
                Write-ColorOutput "[OK] Code deployed via zip deployment" "Green"
            }
        }
    }

    # Summary
    Write-Section "Deployment Complete!"
    Write-ColorOutput "[SUCCESS] Infrastructure provisioned" "Green"
    if ($DeployCode) {
        Write-ColorOutput "[SUCCESS] Function code deployed" "Green"
    }
    
    Write-Host ""
    Write-ColorOutput "Next Steps:" "Cyan"
    Write-ColorOutput "1. Test the function endpoint:" "White"
    Write-ColorOutput "   $functionAppUrl/api/whoami" "Yellow"
    Write-Host ""
    
    if (-not $DeployCode) {
        Write-ColorOutput "2. Deploy your function code:" "White"
        Write-ColorOutput "   func azure functionapp publish $FunctionAppName" "Yellow"
        Write-Host ""
    }
    
    Write-ColorOutput "3. Configure Easy Auth (if using Azure AI Agent):" "White"
    Write-ColorOutput "   .\deploy-auth.ps1 -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName -AIFoundryProjectName <your-ai-project>" "Yellow"
    Write-Host ""
    
    Write-ColorOutput "4. Update OpenAPI spec with your function URL:" "White"
    Write-ColorOutput "   Replace 'your-function-app-name' with: $($FunctionAppName -replace '^func-','')" "Yellow"
    Write-Host ""
    
    Write-ColorOutput "Deployment Summary:" "Cyan"
    Write-ColorOutput "  Resource Group: $ResourceGroupName" "White"
    Write-ColorOutput "  Function App: $FunctionAppName" "White"
    Write-ColorOutput "  Function URL: $functionAppUrl" "White"
    Write-ColorOutput "  Storage Account: $storageAccountNameOutput" "White"
    Write-ColorOutput "  VNet Integration: $($EnableVNetIntegration.IsPresent)" "White"
    Write-ColorOutput "  Private Endpoint: $($EnableStoragePrivateEndpoint.IsPresent)" "White"
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
    
    Write-ColorOutput "Troubleshooting:" "Yellow"
    Write-ColorOutput "- Check Azure Activity Log for detailed errors" "Gray"
    Write-ColorOutput "- Verify subscription permissions" "Gray"
    Write-ColorOutput "- Ensure resource names are globally unique" "Gray"
    Write-ColorOutput "- Check quota limits for the selected region" "Gray"
    Write-Host ""
    
    exit 1
}
