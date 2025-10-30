# Infrastructure Deployment Guide

Deploy the AI Content Understanding Wrapper Function infrastructure to Azure using Bicep templates and PowerShell.

## Quick Start

```powershell
# Basic deployment
.\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper"

# With code deployment
.\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper" -DeployCode
```

## Prerequisites

- **Azure PowerShell**: `Install-Module -Name Az -AllowClobber -Scope CurrentUser`
- **Azure CLI** (for code deployment): `winget install Microsoft.AzureCLI`
- **Permissions**: Contributor or Owner role on subscription/resource group

## Common Deployment Scenarios

### Development Environment

```powershell
.\deploy.ps1 `
    -ResourceGroupName "rg-aicu-dev" `
    -Location "eastus" `
    -FunctionAppName "func-aicu-dev" `
    -FunctionAppSku "Y1" `
    -DeployCode
```

**Features**: Consumption plan, standard storage, no VNet

### Production with VNet

```powershell
.\deploy.ps1 `
    -ResourceGroupName "rg-aicu-prod" `
    -Location "eastus" `
    -FunctionAppName "func-aicu-prod" `
    -FunctionAppSku "EP1" `
    -EnableVNetIntegration `
    -EnableStoragePrivateEndpoint `
    -StorageAccountType "Standard_ZRS"
```

**Features**: Elastic Premium, VNet isolation, private endpoints, zone-redundant storage

### Using Existing Resources

```powershell
.\deploy.ps1 `
    -ResourceGroupName "rg-aicu" `
    -Location "eastus" `
    -FunctionAppName "func-aicu-wrapper" `
    -UseExistingStorage `
    -StorageAccountName "existingstorage" `
    -UseExistingVNet `
    -VNetName "vnet-existing"
```

📖 **[EXISTING-RESOURCES.md](EXISTING-RESOURCES.md)** - Complete guide for using existing infrastructure

## Network Configurations

### VNet Integration

```powershell
.\deploy.ps1 `
    -ResourceGroupName "rg-aicu" `
    -Location "eastus" `
    -FunctionAppName "func-aicu" `
    -EnableVNetIntegration `
    -VNetAddressPrefix "10.0.0.0/16" `
    -FunctionSubnetAddressPrefix "10.0.1.0/24"
```

Allows function to access resources in VNet while storage remains public.

### VNet + Private Endpoints

```powershell
.\deploy.ps1 `
    -ResourceGroupName "rg-aicu" `
    -Location "eastus" `
    -FunctionAppName "func-aicu" `
    -EnableVNetIntegration `
    -EnableStoragePrivateEndpoint `
    -VNetAddressPrefix "10.0.0.0/16" `
    -FunctionSubnetAddressPrefix "10.0.1.0/24" `
    -PrivateEndpointSubnetAddressPrefix "10.0.2.0/24"
```

Fully private deployment - storage accessible only via private endpoint.

## Post-Deployment

### Configure Easy Auth

```powershell
.\deploy-auth.ps1 `
    -ResourceGroupName "rg-aicu" `
    -FunctionAppName "func-aicu" `
    -AIFoundryProjectName "my-ai-project"
```

### Grant RBAC Access (Managed Identity)

```powershell
$functionApp = Get-AzFunctionApp -ResourceGroupName "rg-aicu" -Name "func-aicu"
$principalId = $functionApp.Identity.PrincipalId

New-AzRoleAssignment `
    -ObjectId $principalId `
    -RoleDefinitionName "Cognitive Services User" `
    -Scope "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<aicu-instance>"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Storage account name exists | Let script auto-generate name (don't specify `-StorageAccountName`) |
| Subnet delegation conflict | Use new subnet or remove existing delegation |
| Function can't access storage | Check firewall rules or enable service endpoints |
| DNS resolution failing | Verify private DNS zone link to VNet |

📖 **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete deployment script reference  
📖 **[SECURITY.md](SECURITY.md)** - Security best practices
