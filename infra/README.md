# Azure ML Fabric Demo Infrastructure

This directory contains the Infrastructure as Code (IaC) templates for deploying the Azure ML and Microsoft Fabric integration demo using Azure Developer CLI (azd).

## Architecture Overview

The infrastructure includes:

- **Azure Machine Learning Workspace** - For model development, training, and deployment
- **Microsoft Fabric Workspace** - For data integration and analytics
- **Azure Key Vault** - For secure secrets management
- **Application Insights** - For monitoring and observability
- **Container Registry** - For ML model containerization
- **Storage Account** - For ML artifacts and data storage
- **Synapse Analytics** - For big data processing
- **Event Hub** - For real-time data streaming

## Prerequisites

1. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed
2. [Azure Developer CLI (azd)](https://docs.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) installed
3. [Bicep CLI](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) installed
4. Azure subscription with appropriate permissions

## Quick Start

1. **Initialize the environment:**
   ```bash
   azd init
   ```

2. **Deploy to development environment:**
   ```bash
   azd up --environment dev
   ```

3. **Deploy to staging environment:**
   ```bash
   azd up --environment staging
   ```

4. **Deploy to production environment:**
   ```bash
   azd up --environment prod
   ```

## File Structure

```
infra/
├── main.bicep                    # Main infrastructure template
├── main.dev.bicepparam          # Development environment parameters
├── main.staging.bicepparam      # Staging environment parameters
├── main.prod.bicepparam         # Production environment parameters
├── abbreviations.json           # Azure resource naming abbreviations
└── modules/                     # Modular Bicep templates
    ├── azureml.bicep           # Azure ML workspace and compute
    ├── fabric.bicep            # Microsoft Fabric resources
    ├── monitoring.bicep        # Application Insights and Log Analytics
    └── security.bicep          # Key Vault, Storage, Container Registry
```

## Environment Configuration

Each environment has its own parameter file and configuration:

- **Development (dev)**: Minimal resources for development and testing
- **Staging (staging)**: Production-like environment for testing
- **Production (prod)**: Full production environment with high availability

## Deployment Commands

### Using Azure Developer CLI (azd)

```bash
# Deploy to specific environment
azd up --environment <env-name>

# Monitor deployment
azd monitor

# Clean up resources
azd down --environment <env-name>
```

### Using Azure CLI directly

```bash
# Create resource group
az group create --name rg-az-ml-fabric-demo --location eastus2

# Deploy Bicep template
az deployment group create \
  --resource-group rg-az-ml-fabric-demo \
  --template-file main.bicep \
  --parameters @main.dev.bicepparam
```

## Resource Naming Convention

Resources follow Azure naming best practices using abbreviations defined in `abbreviations.json`:

- Resource Group: `rg-{environmentName}`
- ML Workspace: `mlw-{environmentName}-{resourceToken}`
- Key Vault: `kv-{environmentName}-{resourceToken}`
- Storage Account: `st{environmentName}{resourceToken}`
- Container Registry: `cr{environmentName}{resourceToken}`

## Security Considerations

- All resources use managed identities where possible
- Key Vault access is controlled via RBAC
- Storage accounts have public access disabled
- Container registry has admin user disabled
- Network access is configurable per environment

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

- **Application Insights** for application performance monitoring
- **Log Analytics** for centralized logging
- **Azure Monitor** alerts for proactive monitoring
- **Action Groups** for alert notifications

## Cost Optimization

- Development environment uses minimal SKUs
- Auto-scaling is configured for compute resources
- Storage tiers are optimized for each environment
- Resource policies enforce cost controls

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure you have Contributor access to the subscription
2. **Naming Conflicts**: Resource names must be globally unique
3. **Region Availability**: Some services may not be available in all regions

### Useful Commands

```bash
# Validate Bicep template
az bicep build --file main.bicep

# What-if deployment
az deployment group what-if \
  --resource-group rg-az-ml-fabric-demo \
  --template-file main.bicep \
  --parameters @main.dev.bicepparam

# Check deployment status
az deployment group show \
  --resource-group rg-az-ml-fabric-demo \
  --name main
```

## Contributing

When making changes to the infrastructure:

1. Test changes in development environment first
2. Use `az deployment group what-if` to preview changes
3. Follow the modular structure for new resources
4. Update parameter files for all environments
5. Update this documentation as needed

## Support

For infrastructure-related issues:
1. Check Azure Resource Manager deployment logs
2. Validate Bicep syntax using `az bicep build`
3. Use Azure Advisor recommendations for optimization
4. Review Azure Service Health for service issues