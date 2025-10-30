# Quick Start - AI Foundry Integration

**Enable your Azure AI Agents to analyze documents using Azure AI Content Understanding in 5 minutes.**

This function wraps Azure AI Content Understanding as an OpenAPI tool that your AI Agents can call directly.

## Deploy and Configure

```powershell
# Deploy infrastructure
.\deploy.ps1 -ResourceGroupName "rg-aicu" -Location "eastus" -FunctionAppName "func-aicu-wrapper"

# Configure AI Foundry integration
.\deploy-auth.ps1 -ResourceGroupName "rg-aicu" -FunctionAppName "func-aicu-wrapper" -AIFoundryProjectName "my-ai-project"
```

## Register with AI Foundry

1. Open Azure AI Foundry Studio
2. Navigate to **Tools** → **Functions**
3. Click **+ Add Function**
4. Configure:
   - **Name**: `ai_content_understanding`
   - **OpenAPI Spec**: Upload `aicu-proxy-function-openapi.json`
   - **Authentication**: `Managed Identity`
   - **Audience**: `https://your-function.azurewebsites.net`

## Test

```bash
curl -X POST "https://your-function.azurewebsites.net/api/ai_content_understanding" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "baseUrl": "https://your-aicu.cognitiveservices.azure.com",
    "url": "https://example.com/invoice.pdf"
  }'
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Function App not found | Verify name and resource group |
| Insufficient permissions | Need Owner or User Access Administrator role |
| 401 Unauthorized | Wait 2-3 minutes for Azure propagation, check audience |
| AI Foundry project has no MI | Enable with `az resource update --set identity.type=SystemAssigned` |

� **[DEPLOYMENT.md](DEPLOYMENT.md)** - Detailed deployment script documentation  
� **[AZURE_AI_AGENT_SETUP.md](AZURE_AI_AGENT_SETUP.md)** - Manual setup guide  
� **[INFRASTRUCTURE.md](INFRASTRUCTURE.md)** - Advanced deployment options
