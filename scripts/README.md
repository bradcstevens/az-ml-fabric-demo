# Scripts Directory

This directory contains automation scripts for Azure ML and Fabric integration demo deployment and management.

## Available Scripts

### setup-service-principal.sh

Creates an Azure AD service principal for Power BI REST API automation and stores credentials securely in Azure Key Vault.

**Usage:**
```bash
export KEY_VAULT_NAME="your-keyvault-name"
./scripts/setup-service-principal.sh
```

**What it does:**
1. Creates Azure AD application registration "PowerBI-ServicePrincipal"
2. Creates service principal with 24-month client secret
3. Stores credentials in Key Vault:
   - `powerbi-sp-client-id`
   - `powerbi-sp-client-secret`
   - `powerbi-sp-tenant-id`
   - `powerbi-sp-object-id`

**Post-setup required:**
- Power BI Administrator must enable tenant settings (see docs/powerbi-service-principal-setup.md)
- Add service principal to Fabric workspace with Member role

**Testing:**
```bash
# Test authentication
CLIENT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-id --query value -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-secret --query value -o tsv)
TENANT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-tenant-id --query value -o tsv)

az login --service-principal \
  --username $CLIENT_ID \
  --password $CLIENT_SECRET \
  --tenant $TENANT_ID
```

### setup-ml-environment.sh

Configures Azure ML workspace after infrastructure deployment.

**Usage:**
```bash
./scripts/setup-ml-environment.sh ${AZURE_ENV_NAME}
```

### validate-infrastructure.sh

Validates infrastructure configuration before deployment.

**Usage:**
```bash
./scripts/validate-infrastructure.sh ${AZURE_ENV_NAME}
```

### deploy.sh

Main deployment orchestration script.

**Usage:**
```bash
./scripts/deploy.sh
```

### cleanup.sh

Removes deployed resources from Azure subscription.

**Usage:**
```bash
./scripts/cleanup.sh
```

**Warning:** This permanently deletes resources. Use with caution.

### deploy-real-time-endpoint.sh

Deploys Azure ML real-time inference endpoints.

**Usage:**
```bash
./scripts/deploy-real-time-endpoint.sh
```

### test-azd-solution.sh

Comprehensive end-to-end testing of azd solution.

**Usage:**
```bash
./scripts/test-azd-solution.sh
```

### validate-solution-offline.sh

Validates solution configuration without deploying to Azure.

**Usage:**
```bash
./scripts/validate-solution-offline.sh
```

### validate-deployment.sh

Post-deployment validation checks.

**Usage:**
```bash
./scripts/validate-deployment.sh
```

## Prerequisites

All scripts require:
- Azure CLI (`az`) installed and configured
- Appropriate Azure subscription access
- Bash shell (Linux/macOS/WSL)

## Common Workflows

### Initial Project Setup

```bash
# 1. Deploy infrastructure
azd up

# 2. Get Key Vault name from deployment output
export KEY_VAULT_NAME=$(azd env get-values | grep AZURE_KEY_VAULT_NAME | cut -d'=' -f2)

# 3. Setup Power BI service principal
./scripts/setup-service-principal.sh

# 4. Configure ML environment
./scripts/setup-ml-environment.sh dev
```

### Service Principal Management

```bash
# Retrieve credentials from Key Vault
az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-id --query value -o tsv
az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-secret --query value -o tsv
az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-tenant-id --query value -o tsv

# Check secret expiration
az keyvault secret show \
  --vault-name $KEY_VAULT_NAME \
  --name powerbi-sp-client-secret \
  --query "attributes.expires"

# Rotate secret (before expiration)
CLIENT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-id --query value -o tsv)
az ad app credential reset --id $CLIENT_ID --append
```

## Documentation

For detailed guides and troubleshooting:
- [Power BI Service Principal Setup Guide](../docs/powerbi-service-principal-setup.md)

## Contributing

When adding new scripts:
1. Include usage documentation in this README
2. Add error handling and validation
3. Follow existing script patterns (colored output, error checking)
4. Make scripts executable: `chmod +x scripts/your-script.sh`
5. Test scripts in clean environment before committing

## Troubleshooting

### Script Permission Denied

```bash
chmod +x scripts/*.sh
```

### Azure CLI Not Logged In

```bash
az login
az account set --subscription "your-subscription-id"
```

### Key Vault Access Denied

Ensure you have appropriate permissions:
```bash
az keyvault set-policy \
  --name $KEY_VAULT_NAME \
  --upn your-email@domain.com \
  --secret-permissions get list set delete
```

### Service Principal Authentication Fails

1. Check credentials are correct in Key Vault
2. Verify secret hasn't expired
3. Ensure Power BI admin settings are enabled
4. Wait 15 minutes for Azure AD propagation

## Security Notes

- **Never commit secrets or credentials to version control**
- All sensitive values should be stored in Azure Key Vault
- Use environment variables for configuration
- Scripts automatically store credentials securely in Key Vault
- Rotate secrets regularly (before expiration)
- Monitor Key Vault access logs for unauthorized access

## Support

For issues with scripts:
1. Check script output for specific error messages
2. Review Azure CLI authentication status
3. Verify Azure subscription permissions
4. Check Azure service health status
5. Review script source code for detailed error handling
