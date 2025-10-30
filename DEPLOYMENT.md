# Deployment Scripts - Easy Auth Setup

**Configure your Azure Function as a secure OpenAPI tool for Azure AI Agents.**

These automated scripts enable Azure AD authentication and grant your AI Foundry project's Managed Identity access to call this wrapper function.

## Quick Start

```powershell
.\deploy-auth.ps1 `
    -ResourceGroupName "rg-ai-content" `
    -FunctionAppName "func-aicu-wrapper" `
    -AIFoundryProjectName "ai-foundry-project"
```

## Prerequisites

**PowerShell 7+ with Azure modules:**
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser
Connect-AzAccount
```

**Required Permissions:**
- **Owner** or **User Access Administrator** on Function App
- **Reader** on AI Foundry project

## Parameters

### PowerShell Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `ResourceGroupName` | ✅ | Function App resource group | - |
| `FunctionAppName` | ✅ | Function App name | - |
| `AIFoundryProjectName` | ✅ | AI Foundry project name | - |
| `AIFoundryResourceGroup` | ❌ | AI Foundry RG (if different) | Same as Function RG |
| `TenantId` | ❌ | Azure AD Tenant ID | Current tenant |
| `AllowedAudiences` | ❌ | Custom token audiences | Function App URL |
| `SkipRoleAssignment` | ❌ | Skip role assignment | `$false` |

### Bash Arguments

| Position | Required | Description |
|----------|----------|-------------|
| 1 | ✅ | Function App resource group |
| 2 | ✅ | Function App name |
| 3 | ✅ | AI Foundry project name |
| 4 | ❌ | AI Foundry RG (if different) |

## What Gets Configured

**Easy Auth Settings:**
- Authentication enabled and required
- Identity Provider: Azure AD (Entra ID)
- Allowed Audiences: Function App URL
- Unauthenticated Action: HTTP 401

**Role Assignment:**
- Principal: AI Foundry Managed Identity
- Role: Website Contributor
- Scope: Function App

## Troubleshooting

| Error | Solution |
|-------|----------|
| "Function App not found" | `az functionapp list --query "[].{name:name, rg:resourceGroup}" -o table` |
| "AI Foundry project not found" | Specify `AIFoundryResourceGroup` parameter |
| "AI Foundry has no Managed Identity" | Enable MI: `az resource update --ids <id> --set identity.type=SystemAssigned` |
| "Insufficient permissions" | Request Owner/User Access Administrator role |
| Easy Auth not working | Wait 2-3 minutes for propagation |

## CI/CD Integration

### Azure DevOps
```yaml
- task: AzurePowerShell@5
  inputs:
    azureSubscription: 'Azure-Connection'
    ScriptPath: 'deploy-auth.ps1'
    ScriptArguments: '-ResourceGroupName $(RG) -FunctionAppName $(FunctionApp) -AIFoundryProjectName $(AIProject)'
```

### GitHub Actions
```yaml
- uses: azure/powershell@v1
  with:
    inlineScript: |
      ./deploy-auth.ps1 -ResourceGroupName ${{ secrets.RG }} -FunctionAppName ${{ secrets.FUNCTION }} -AIFoundryProjectName ${{ secrets.AI_PROJECT }}
```

📖 **[AZURE_AI_AGENT_SETUP.md](AZURE_AI_AGENT_SETUP.md)** - Manual setup guide  
📖 **[README.md](README.md)** - Function app overview
