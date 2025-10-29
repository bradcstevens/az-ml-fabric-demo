# Power BI Service Principal Setup Guide

This guide provides detailed instructions for configuring Power BI Service Principal authentication for automation and REST API access.

## Overview

A service principal allows automated applications to authenticate with Power BI REST APIs without user credentials. This is essential for CI/CD pipelines, automated deployments, and programmatic dashboard management.

## Prerequisites

- Azure subscription with appropriate permissions
- Power BI Premium or Fabric capacity
- Power BI Administrator access for tenant settings
- Azure CLI installed and configured

## Step 1: Create Service Principal

Run the automated setup script:

```bash
# Set Key Vault name environment variable
export KEY_VAULT_NAME="your-keyvault-name"

# Run setup script
./scripts/setup-service-principal.sh
```

The script will:
1. Create an Azure AD application registration named "PowerBI-ServicePrincipal"
2. Create a service principal from the application
3. Generate a client secret (valid for 24 months)
4. Store all credentials securely in Azure Key Vault

### Script Output

The script outputs the following information:
- **Application ID (Client ID)**: Used for authentication
- **Tenant ID**: Your Azure AD tenant identifier
- **Object ID**: Service principal object identifier
- **Key Vault Secrets**: Credentials stored securely

## Step 2: Configure Power BI Admin Portal Settings

⚠️ **REQUIRED**: A Power BI administrator must complete these steps.

### 2.1 Navigate to Admin Portal

1. Go to [Power BI Admin Portal](https://app.powerbi.com/admin-portal/tenantSettings)
2. Sign in with a Power BI Administrator account

### 2.2 Enable Developer Settings

Navigate to **Developer settings** and enable:

#### Setting 1: "Embed content in apps"
- Location: Developer settings → Embed content in apps
- Action: Toggle to **Enabled**
- Scope Options:
  - ✅ **Recommended**: Apply to specific security group (best practice)
  - ⚠️ **Not recommended**: Apply to entire organization

#### Setting 2: "Allow service principals to use Power BI APIs"
- Location: Developer settings → Allow service principals to use Power BI APIs
- Action: Toggle to **Enabled**
- Scope Options:
  - ✅ **Recommended**: Apply to specific security group (best practice)
  - ⚠️ **Not recommended**: Apply to entire organization

### 2.3 Create Security Group (Recommended)

For better security and governance:

1. Go to [Azure AD Groups](https://portal.azure.com/#view/Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/AllGroups)
2. Click **New group**
3. Configure:
   - **Group type**: Security
   - **Group name**: "PowerBI-ServicePrincipals"
   - **Group description**: "Service principals authorized for Power BI API access"
   - **Members**: Add your service principal using its **Object ID**
4. Click **Create**

4. Return to Power BI Admin Portal
5. Configure both developer settings to apply only to "PowerBI-ServicePrincipals" group

Benefits:
- Least privilege access
- Easier audit and compliance
- Centralized service principal management

### 2.4 Wait for Propagation

Settings may take **up to 15 minutes** to propagate across Power BI services. If authentication fails immediately after configuration, wait and retry.

## Step 3: Add Service Principal to Workspace

The service principal must be added to any workspace it needs to access.

### 3.1 Via Power BI Portal

1. Navigate to your Fabric/Power BI workspace
2. Click **Workspace settings** (⚙️ icon)
3. Go to **Access** tab
4. Click **Add people or groups**
5. Search for "PowerBI-ServicePrincipal" (the app name)
6. Select appropriate role:
   - **Member**: Read/write access to content (recommended for automation)
   - **Admin**: Full workspace control
   - **Contributor**: Can create/edit content
   - **Viewer**: Read-only access
7. Click **Add**

### 3.2 Via Power BI REST API

Alternatively, add the service principal programmatically:

```bash
# Get service principal details from Key Vault
CLIENT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-id --query value -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-secret --query value -o tsv)
TENANT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-tenant-id --query value -o tsv)
SP_OBJECT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-object-id --query value -o tsv)

# Get access token
ACCESS_TOKEN=$(curl -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=https://analysis.windows.net/powerbi/api/.default" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

# Add service principal to workspace (replace with your workspace ID)
WORKSPACE_ID="your-workspace-id"

curl -X POST "https://api.powerbi.com/v1.0/myorg/groups/$WORKSPACE_ID/users" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"identifier\": \"$SP_OBJECT_ID\",
    \"groupUserAccessRight\": \"Member\",
    \"principalType\": \"App\"
  }"
```

## Step 4: Test Authentication

### 4.1 Test Azure Login

```bash
CLIENT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-id --query value -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-secret --query value -o tsv)
TENANT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-tenant-id --query value -o tsv)

az login --service-principal \
  --username $CLIENT_ID \
  --password $CLIENT_SECRET \
  --tenant $TENANT_ID
```

### 4.2 Test Power BI API Access

```bash
# Get access token
ACCESS_TOKEN=$(curl -X POST "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=https://analysis.windows.net/powerbi/api/.default" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')

# List workspaces
curl -X GET "https://api.powerbi.com/v1.0/myorg/groups" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

Expected response: JSON list of workspaces the service principal has access to.

## Step 5: Retrieve Credentials from Key Vault

Applications can retrieve credentials programmatically:

### Using Azure CLI

```bash
CLIENT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-id --query value -o tsv)
CLIENT_SECRET=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-secret --query value -o tsv)
TENANT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-tenant-id --query value -o tsv)
```

### Using Python

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

credential = DefaultAzureCredential()
vault_url = f"https://{KEY_VAULT_NAME}.vault.azure.net"
client = SecretClient(vault_url=vault_url, credential=credential)

client_id = client.get_secret("powerbi-sp-client-id").value
client_secret = client.get_secret("powerbi-sp-client-secret").value
tenant_id = client.get_secret("powerbi-sp-tenant-id").value
```

### Using PowerShell

```powershell
$ClientId = (Get-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME -Name "powerbi-sp-client-id").SecretValue | ConvertFrom-SecureString -AsPlainText
$ClientSecret = (Get-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME -Name "powerbi-sp-client-secret").SecretValue | ConvertFrom-SecureString -AsPlainText
$TenantId = (Get-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME -Name "powerbi-sp-tenant-id").SecretValue | ConvertFrom-SecureString -AsPlainText
```

## Common Use Cases

### Dataset Refresh

```python
import requests
from azure.identity import ClientSecretCredential

# Get credentials from Key Vault
credential = ClientSecretCredential(
    tenant_id=tenant_id,
    client_id=client_id,
    client_secret=client_secret
)

# Get Power BI access token
token = credential.get_token("https://analysis.windows.net/powerbi/api/.default")

# Trigger dataset refresh
headers = {"Authorization": f"Bearer {token.token}"}
refresh_url = f"https://api.powerbi.com/v1.0/myorg/groups/{workspace_id}/datasets/{dataset_id}/refreshes"

response = requests.post(refresh_url, headers=headers)
print(f"Refresh initiated: {response.status_code}")
```

### Workspace Management

```python
# List all reports in workspace
reports_url = f"https://api.powerbi.com/v1.0/myorg/groups/{workspace_id}/reports"
response = requests.get(reports_url, headers=headers)
reports = response.json()

for report in reports['value']:
    print(f"Report: {report['name']} (ID: {report['id']})")
```

### Pipeline Deployment

```python
# Deploy to pipeline stage
pipeline_url = f"https://api.powerbi.com/v1.0/myorg/pipelines/{pipeline_id}/deploy"

payload = {
    "sourceStageOrder": 0,  # Development
    "targetStageOrder": 1,  # Test
    "options": {
        "allowOverwriteArtifact": True
    }
}

response = requests.post(pipeline_url, headers=headers, json=payload)
print(f"Deployment status: {response.status_code}")
```

## Security Best Practices

### 1. Secret Rotation

The client secret expires after 24 months. Set up reminders to rotate secrets before expiration:

```bash
# Check secret expiration
az keyvault secret show \
  --vault-name $KEY_VAULT_NAME \
  --name powerbi-sp-client-secret \
  --query "attributes.expires"

# Generate new secret before expiration
az ad app credential reset --id $CLIENT_ID --append
```

### 2. Use Security Groups

Always scope Power BI admin settings to security groups, never to the entire organization.

### 3. Least Privilege Access

- Only grant necessary workspace roles
- Use **Member** role for automation (not Admin unless required)
- Regularly audit service principal permissions

### 4. Monitor Usage

Enable audit logging in Power BI Admin Portal:
- Admin Portal → Audit and usage settings → Create audit logs for internal activity
- Review service principal activity regularly

### 5. Secure Key Vault Access

```bash
# Grant Key Vault access only to necessary identities
az keyvault set-policy \
  --name $KEY_VAULT_NAME \
  --object-id $USER_OR_APP_OBJECT_ID \
  --secret-permissions get list
```

## Troubleshooting

### Error: "Service principal is not enabled"

**Solution**: Verify Power BI admin settings are enabled and propagated (wait 15 minutes).

### Error: "Operation not allowed"

**Solution**: Ensure service principal is added to workspace with appropriate role.

### Error: "Audience validation failed"

**Solution**: Use correct scope: `https://analysis.windows.net/powerbi/api/.default`

### Error: "401 Unauthorized"

**Solutions**:
1. Verify credentials are correct
2. Check secret hasn't expired
3. Ensure admin settings are enabled
4. Wait for propagation (up to 15 minutes)

### Error: "403 Forbidden"

**Solution**: Service principal needs higher role in workspace (e.g., Member instead of Viewer).

## Maintenance

### Secret Expiration Monitoring

Set up Azure Monitor alerts for secret expiration:

```bash
# Create alert rule (example)
az monitor metrics alert create \
  --name "powerbi-sp-secret-expiry" \
  --resource-group $RESOURCE_GROUP \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
  --condition "avg SecretNearExpiry > 0" \
  --window-size 1d \
  --evaluation-frequency 1h \
  --action-group $ACTION_GROUP_ID
```

### Regular Audits

Review service principal usage quarterly:
1. Check workspace access is still required
2. Verify no unused permissions
3. Rotate secrets as security policy dictates
4. Review audit logs for unusual activity

## Additional Resources

- [Power BI REST API Documentation](https://learn.microsoft.com/en-us/rest/api/power-bi/)
- [Service Principal Authentication Guide](https://learn.microsoft.com/en-us/power-bi/developer/embedded/embed-service-principal)
- [Power BI Admin API](https://learn.microsoft.com/en-us/rest/api/power-bi/admin)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)

## Support

For issues or questions:
1. Check Power BI Admin Portal settings
2. Verify Key Vault access permissions
3. Review Azure AD application configuration
4. Contact Power BI Administrator for tenant-level issues
