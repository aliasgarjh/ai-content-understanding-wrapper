# Security Policy

## Supported Versions

This is a sample project demonstrating Azure Functions integration with Azure AI Content Understanding. As a sample, it does not have formal version support, but we recommend always using the latest code from the `main` branch.

## Security Best Practices

### Authentication & Authorization

1. **Use Managed Identity in Production**
   - Never hardcode credentials in code or configuration files
   - Enable system-assigned or user-assigned managed identity on your Function App
   - Grant least-privilege roles (e.g., "Cognitive Services User" for upstream resources)

2. **API Key Authentication**
   - Store function keys securely (Azure Key Vault recommended)
   - Use separate keys for development and production
   - Rotate keys regularly
   - Never commit keys to source control

3. **Azure AD (Easy Auth)**
   - Use tenant-specific App Registrations
   - Configure proper audience validation
   - Use client credentials flow for service-to-service calls
   - Validate tokens on every request

### Environment Variables

Never commit sensitive values to source control:
- ❌ Don't: Hardcode `CONTENT_UNDERSTANDING_API_KEY` in `local.settings.json`
- ✅ Do: Use Azure Key Vault references or App Settings encryption

Example secure configuration:
```bash
# In Azure Function App Settings (encrypted at rest):
CONTENT_UNDERSTANDING_API_KEY=@Microsoft.KeyVault(SecretUri=https://myvault.vault.azure.net/secrets/api-key/)
```

### Secret Management

1. **Local Development**
   - Use `local.settings.json` (already in `.gitignore`)
   - Never commit `local.settings.json` with real credentials
   - Use Azure CLI login (`az login`) for local testing

2. **Production**
   - Store secrets in Azure Key Vault
   - Use App Settings with Key Vault references
   - Enable App Settings encryption

3. **Rotation**
   - Rotate API keys every 90 days minimum
   - Rotate function keys every 180 days minimum
   - Update Key Vault secrets and restart Function App

### Network Security

1. **Function App**
   - Consider enabling Virtual Network integration
   - Use Private Endpoints for Azure resources when possible
   - Enable HTTPS only (disable HTTP)

2. **Upstream Resources**
   - Use private endpoints for AI Content Understanding resources
   - Configure firewall rules to allow only Function App subnet
   - Enable diagnostic logs

### Data Protection

1. **Input Validation**
   - Function validates `baseUrl` format
   - Implement additional validation for untrusted inputs
   - Sanitize file paths if accepting user-provided document locations

2. **Document Security**
   - Documents submitted via URL must be accessible to the function
   - Base64 data is transmitted in request body (ensure HTTPS)
   - Consider encryption at rest for temporary storage

3. **Response Data**
   - Analyzer results may contain sensitive extracted data
   - Implement appropriate access controls on responses
   - Consider data retention policies

### OpenAPI Spec Security

1. **Before Publishing**
   - Remove production URLs
   - Remove tenant IDs and domain names
   - Remove actual client IDs
   - Use placeholders (e.g., `YOUR_TENANT_ID`)

2. **Distribution**
   - Host OpenAPI spec on secure endpoints (HTTPS)
   - Version the spec to track changes
   - Document required replacements clearly

### Dependency Management

1. **Python Packages**
   - Regularly update dependencies: `pip list --outdated`
   - Review security advisories: `pip-audit`
   - Pin versions in `requirements.txt` for reproducibility

2. **Azure SDK**
   - Keep Azure SDK packages updated
   - Monitor for security patches
   - Test updates in non-production first

### Monitoring & Auditing

1. **Enable Logging**
   - Configure Application Insights
   - Log all authentication attempts
   - Monitor for unusual patterns (spike in 401s, excessive retries)

2. **Audit Trail**
   - Use correlation IDs for request tracking
   - Log principal IDs for authenticated requests
   - Retain logs per compliance requirements

3. **Alerting**
   - Set up alerts for authentication failures
   - Monitor for rate limiting or throttling
   - Alert on unexpected error rates

## Reporting a Vulnerability

This is a sample project. For vulnerabilities in Azure services:
- Report to Microsoft Security Response Center: https://msrc.microsoft.com/create-report

For issues specific to this sample code:
- Open a GitHub issue (for non-sensitive issues)
- For sensitive security concerns, contact the repository maintainer directly

## Deployment Checklist

Before deploying to production:

- [ ] Remove all hardcoded secrets and credentials
- [ ] Enable Managed Identity on Function App
- [ ] Grant minimal required RBAC roles
- [ ] Configure Azure AD authentication (Easy Auth) if needed
- [ ] Update OpenAPI spec with your tenant/audience values
- [ ] Store API keys in Key Vault
- [ ] Enable HTTPS only
- [ ] Configure Application Insights
- [ ] Set up diagnostic logging
- [ ] Review and test error handling
- [ ] Implement rate limiting if needed
- [ ] Document your deployment-specific configuration
- [ ] Test with production-like data
- [ ] Verify token validation works correctly

## Additional Resources

- [Azure Functions Security](https://learn.microsoft.com/azure/azure-functions/security-concepts)
- [Managed Identity Best Practices](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/managed-identity-best-practice-recommendations)
- [Azure Key Vault](https://learn.microsoft.com/azure/key-vault/general/overview)
- [Azure AD App Registration](https://learn.microsoft.com/azure/active-directory/develop/quickstart-register-app)
