# Azure AI Content Understanding Wrapper Function

**An Azure Function that wraps Azure AI Content Understanding as an OpenAPI tool for Azure AI Agents.**

This wrapper enables Azure AI Agents to analyze documents (invoices, receipts, forms, layouts) by calling Azure AI Content Understanding with automatic polling, dual authentication, and a complete OpenAPI specification.

> **⚠️ Sample Project Notice**  
> This is a sample/reference implementation. Before deploying to production, review [SECURITY.md](SECURITY.md) for best practices.

## Features

✅ **Azure AI Agent Ready** - Complete OpenAPI 3.0 spec for agent integration  
✅ **Automatic Polling** - Submit documents and get results automatically  
✅ **Dual Authentication** - Managed Identity (recommended) and API Key support  
✅ **Flexible Input** - URL or base64-encoded documents  
✅ **Correlation Tracking** - Built-in distributed tracing  

## Quick Start

### Deploy to Azure

```powershell
.\deploy.ps1 -ResourceGroupName "rg-aicu-wrapper" -Location "eastus" -FunctionAppName "func-aicu-wrapper"
```

📖 **[QUICKSTART.md](QUICKSTART.md)** - 5-minute setup guide  
📖 **[INFRASTRUCTURE.md](INFRASTRUCTURE.md)** - Complete deployment options

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Configure local.settings.json
{
  "Values": {
    "CONTENT_UNDERSTANDING_BASE_URL": "https://your-aicu-resource.cognitiveservices.azure.com",
    "CONTENT_UNDERSTANDING_API_KEY": "your-api-key-here"
  }
}

# Run locally
func start
```

## Usage

```bash
# Submit document for analysis
curl -X POST "http://localhost:7071/api/ai_content_understanding" \
  -H "Content-Type: application/json" \
  -d '{
    "baseUrl": "https://your-aicu-resource.cognitiveservices.azure.com",
    "analyzerId": "prebuilt-invoice",
    "url": "https://example.com/invoice.pdf"
  }'
```

📖 **[EXAMPLES.md](EXAMPLES.md)** - Complete API examples and response formats

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/ai_content_understanding` | POST | Submit document for analysis |
| `/api/ai_content_understanding` | GET | Check operation status |
| `/api/whoami` | GET | Diagnostic endpoint for auth troubleshooting |

**Key Parameters:**
- `baseUrl` - Content Understanding endpoint URL
- `analyzerId` - Analyzer type (e.g., `prebuilt-invoice`)
- `url` or `data` - Document URL or base64 content
- `maxWaitSeconds` - Max polling time (default: 600s)

## Configuration

| Environment Variable | Description |
|---------------------|-------------|
| `CONTENT_UNDERSTANDING_BASE_URL` | Azure AI Content Understanding endpoint |
| `CONTENT_UNDERSTANDING_API_KEY` | API key (optional if using Managed Identity) |
| `DEFAULT_ANALYZER_ID` | Default analyzer (default: `prebuilt-invoice`) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Telemetry connection string (optional) |

## Azure AI Agent Integration

Automated setup:
```powershell
.\deploy-auth.ps1 -ResourceGroupName "rg-aicu" -FunctionAppName "func-aicu-wrapper" -AIFoundryProjectName "my-ai-project"
```

📖 **[AZURE_AI_AGENT_SETUP.md](AZURE_AI_AGENT_SETUP.md)** - Complete AI Agent integration guide  
📖 **[DEPLOYMENT.md](DEPLOYMENT.md)** - Deployment script reference

## Authentication

**Managed Identity** (Recommended):
- Uses `DefaultAzureCredential` for upstream calls
- Enable on Function App and grant "Cognitive Services User" role

**API Key**:
- Set `CONTENT_UNDERSTANDING_API_KEY` environment variable

**Function App Security**:
- Easy Auth (Azure AD) for AI Agent integration
- Function keys for development/testing

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - 5-minute deployment guide
- **[INFRASTRUCTURE.md](INFRASTRUCTURE.md)** - Deployment options and network configurations
- **[EXAMPLES.md](EXAMPLES.md)** - API request/response examples
- **[AZURE_AI_AGENT_SETUP.md](AZURE_AI_AGENT_SETUP.md)** - AI Agent integration
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Deployment script reference
- **[SECURITY.md](SECURITY.md)** - Security best practices

## Support

- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
- [AI Content Understanding](https://docs.microsoft.com/azure/ai-services/)
- [GitHub Issues](../../issues)

## License

MIT - See [LICENSE](LICENSE) file for details.
