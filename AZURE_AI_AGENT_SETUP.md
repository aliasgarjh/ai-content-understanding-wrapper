# Azure AI Agent Setup Guide

**Configure this Azure Function as an OpenAPI tool for your Azure AI Agents.**

This function wraps Azure AI Content Understanding so your AI Agents can analyze documents (invoices, receipts, forms, etc.) using Managed Identity authentication.

## Quick Setup (Recommended)

Use the automated script:

```powershell
.\deploy-auth.ps1 -ResourceGroupName "rg-ai" -FunctionAppName "func-aicu-wrapper" -AIFoundryProjectName "ai-project"
```

✅ **Done!** The script configures Easy Auth and grants access automatically.

📖 **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete script documentation

---

## Manual Setup (Fallback)

If you need to configure manually:

### Step 1: Enable Easy Auth

```bash
RESOURCE_GROUP="rg-ai"
FUNCTION_APP_NAME="func-aicu-wrapper"

az webapp auth update \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --enabled true \
  --action Return401 \
  --aad-allowed-token-audiences "https://$FUNCTION_APP_NAME.azurewebsites.net"
```

### Step 2: Grant AI Agent Access

```bash
# Get AI Agent's Managed Identity
AI_AGENT_PRINCIPAL_ID=$(az resource show \
  --name "ai-project" \
  --resource-group "rg-ai-foundry" \
  --resource-type "Microsoft.MachineLearningServices/workspaces" \
  --query identity.principalId -o tsv)

# Get Function App ID
FUNCTION_APP_ID=$(az functionapp show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id -o tsv)

# Grant Website Contributor role
az role assignment create \
  --assignee $AI_AGENT_PRINCIPAL_ID \
  --role "Website Contributor" \
  --scope $FUNCTION_APP_ID
```

### Step 3: Configure AI Agent

```json
{
  "type": "function",
  "function": {
    "name": "ai_content_understanding",
    "openapi_spec": "https://func-aicu-wrapper.azurewebsites.net/api/openapi",
    "authentication": {
      "type": "managed_identity",
      "audience": "https://func-aicu-wrapper.azurewebsites.net"
    }
  }
}
```

## Authentication Options Compared

| Feature | Function Key | Managed Identity |
|---------|--------------|------------------|
| Secret management | Manual rotation required | Automatic |
| Security | Keys can leak | Credential-less |
| RBAC | No | Yes |
| Audit trail | Limited | Full Azure AD logs |
| **Recommendation** | Dev/test only | ✅ Production |

## Audience Values

Use one of these for the `audience` field:

| Option | Value | Use Case |
|--------|-------|----------|
| Function URL | `https://func-name.azurewebsites.net` | ✅ Recommended (Easy Auth) |
| With scope | `https://func-name.azurewebsites.net/.default` | Alternative format |
| App ID URI | `api://func-name` | Custom App Registration |
| Client ID | `<app-id>/.default` | Custom App Registration |

## Troubleshooting

| Error | Solution |
|-------|----------|
| 401 Unauthorized | Verify Easy Auth enabled, audience matches, and role assigned |
| Invalid Audience | Update allowed audiences: `az webapp auth update --aad-allowed-token-audiences "https://func-name.azurewebsites.net"` |
| Token Acquisition Failed | Check AI Agent has Managed Identity enabled |

## Testing Authentication

```bash
# Get token from AI Foundry Managed Identity
TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://func-name.azurewebsites.net' \
  -H "Metadata: true" | jq -r .access_token)

# Test function call
curl -X POST "https://func-name.azurewebsites.net/api/ai_content_understanding" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"baseUrl": "https://aicu.cognitiveservices.azure.com", "url": "https://example.com/doc.pdf"}'

# Verify token audience
echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.aud'
```

Expected audience: `https://func-name.azurewebsites.net`

## Advanced: API Management Gateway

For enterprise scenarios, use Azure APIM as a gateway:

```
AI Agent (MI) → APIM (auth, rate limiting, caching) → Function App
```

**Benefits:** Centralized auth, rate limiting, response caching, API versioning

📖 **[DEPLOYMENT.md](DEPLOYMENT.md)** - Automated setup script documentation  
📖 **[README.md](README.md)** - Function app overview
