# Azure ML + Fabric Demo - Deployment Guide

## Overview

This guide describes the expected Azure resources when deploying the Azure ML + Microsoft Fabric integration demo using Azure Developer CLI (`azd`).

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI installed and configured
- Azure Developer CLI (azd) installed
- Bicep CLI (comes with Azure CLI)

## Quick Start

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription <subscription-id>

# Deploy all infrastructure
azd up
```

## Expected Resources

When deployment completes successfully, the following resources will be created:

### 1. Network Foundation (6+ resources)

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| Virtual Network | 1 | Foundation for all network connectivity |
| Subnets | 4 | ML Workspace, Compute, Private Endpoints, Management |
| Network Security Groups | 4 | One per subnet for traffic control |
| Private DNS Zones | 5 | For private endpoint DNS resolution |

**Private DNS Zones:**
- `privatelink.blob.core.windows.net` - Storage blob service
- `privatelink.file.core.windows.net` - Storage file service
- `privatelink.vaultcore.azure.net` - Key Vault
- `privatelink.azurecr.io` - Container Registry
- `privatelink.api.azureml.ms` - Azure ML workspace

### 2. Security & Storage (7+ resources)

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| Key Vault | 1 | Secrets management with private endpoint |
| Storage Account | 1 | ML data, models, and artifacts storage |
| Blob Containers | 3 | mldata, models, artifacts |
| Container Registry | 1 | ML model container images |
| Private Endpoints | 3 | Key Vault, Storage, Container Registry |

**Storage Account Configuration:**
- TLS 1.2 minimum
- Public blob access disabled
- Blob containers: mldata, models, artifacts
- Private endpoint enabled (Task 11 - pending implementation)

**Key Vault Configuration:**
- Public network access: Disabled
- Private endpoint: Enabled
- Network ACLs: Deny by default, bypass Azure Services
- RBAC authorization enabled

**Container Registry Configuration:**
- Public network access: Enabled (Task 13 - pending private endpoint)
- Admin user: Disabled
- Azure AD authentication: Enabled

### 3. Monitoring (2 resources)

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| Log Analytics Workspace | 1 | Centralized logging and monitoring |
| Application Insights | 1 | Application performance monitoring |

### 4. Azure Machine Learning (2+ resources)

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| ML Workspace | 1 | Central workspace for ML operations |
| Compute Cluster | 1 | Training compute resources |

**ML Workspace Configuration:**
- Connected to Key Vault, Storage, Container Registry
- Application Insights integration
- Private network: Pending (Task 14)
- Managed VNet: Pending (Task 14)

### 5. Microsoft Fabric (1 resource)

| Resource Type | Count | Purpose |
|--------------|-------|---------|
| Fabric Capacity | 1 | Power BI Premium capacity for dashboards |

**Fabric Capacity Configuration:**
- SKU: F2 (or configured size)
- Admin: Configured via `fabricAdminEmail` parameter
- Location: Same as other resources

## Deployment Validation

After running `azd up`, use the validation script to confirm all resources are deployed:

```bash
# Run validation script
./scripts/validate-deployment.sh <resource-group-name>

# Example
./scripts/validate-deployment.sh rg-dev
```

### Expected Validation Output

✅ **All checks should pass:**
- Bicep compilation successful
- Resource group exists
- All core infrastructure resources present
- Network foundation configured
- Security and storage deployed
- Monitoring infrastructure active
- Azure ML workspace ready
- Fabric capacity running

## Known Configuration Details

### Resource Group Naming
- Pattern: `rg-{environmentName}`
- Default: `rg-dev`

### Resource Naming Conventions
- Uses Azure abbreviations from `abbreviations.json`
- Includes unique suffix from `resourceToken`
- Example: `kv-dev-abc123` (Key Vault)

### Location
- Prompted during first `azd up` execution
- Stored in `.azure/{environment}/.env`
- All resources deployed to same location

## Current Implementation Status

### ✅ Completed Components
1. **Network Foundation** (Task 9 ✓)
   - Virtual Network with 4 subnets
   - Network Security Groups

2. **DNS Infrastructure** (Task 10 ✓)
   - 5 Private DNS zones
   - VNet links configured

3. **Key Vault Private Endpoint** (Task 12 ✓)
   - Public access disabled
   - Private endpoint configured
   - Network ACLs set to Deny

### 🚧 Pending Components
1. **Storage Account Private Endpoints** (Task 11)
   - Currently public access enabled
   - Private endpoints need implementation

2. **Container Registry Private Endpoint** (Task 13)
   - Currently public access enabled
   - Private endpoint implementation in progress

3. **ML Workspace Private Network** (Task 14)
   - Depends on Tasks 11, 12, 13
   - Managed VNet isolation pending

4. **Azure Bastion** (Task 17)
   - Secure management access
   - Not yet implemented

## Troubleshooting

### Issue: Fabric Capacity Administrator Error

**Symptom:** Fabric capacity deployment fails with admin configuration error

**Solution:** Ensure `fabricAdminEmail` parameter is set correctly:
```bash
# In main.bicep or via parameter
param fabricAdminEmail string = 'your.email@domain.com'
```

### Issue: Empty Managed Resource Groups

**Symptom:** Additional empty resource groups created

**Status:** This is expected behavior for some Azure services
- Azure ML may create managed resource groups
- These are automatically cleaned up when workspace is deleted

### Issue: Location Prompt Appears Multiple Times

**Current:** Location is prompted once during deployment
**Expected:** Single location prompt (working as designed)

### Issue: Resource Count Lower Than Expected

**Possible Causes:**
1. Deployment still in progress
2. Deployment failed partially
3. Optional resources not deployed

**Check deployment status:**
```bash
# View deployment operations
az deployment sub show --name <deployment-name>

# Check resource group deployments
az deployment group list --resource-group <rg-name>
```

## Security Considerations

### Current Security Posture
- Key Vault: Private endpoint enabled ✅
- Storage Account: Public access (pending Task 11)
- Container Registry: Public access (pending Task 13)
- ML Workspace: Public access (pending Task 14)

### Target Security Posture (Zero-Trust)
All resources will use:
- Private endpoints only
- Public network access disabled
- VNet isolation
- Network ACLs with Deny default
- Managed identity authentication

**Timeline:** Private endpoint implementation planned in Tasks 11-15

## Next Steps

After successful deployment validation:

1. **Configure Synthetic Data Generation** (Task 21)
   - Create data generation scripts
   - Upload sample data to storage

2. **Set Up Azure ML Training** (Task 23)
   - Create training notebooks
   - Configure ML pipelines

3. **Configure Power BI Dashboards** (Task 26-28)
   - Create semantic models
   - Design visualizations
   - Automate deployment

## Support

### Validation Script
Run the validation script after any deployment:
```bash
./scripts/validate-deployment.sh <resource-group-name>
```

### Manual Resource Verification
```bash
# List all resources in resource group
az resource list --resource-group <rg-name> --output table

# Count resources
az resource list --resource-group <rg-name> --query "length(@)"

# Check specific resource types
az network vnet list --resource-group <rg-name>
az ml workspace list --resource-group <rg-name>
az keyvault list --resource-group <rg-name>
```

## References

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure ML Documentation](https://learn.microsoft.com/azure/machine-learning/)
- [Microsoft Fabric Documentation](https://learn.microsoft.com/fabric/)

---

**Last Updated:** Based on completed Tasks 9, 10, 12 and current infrastructure state
**Status:** Infrastructure validation framework complete (Task 19 ✓)
