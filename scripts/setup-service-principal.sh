#!/bin/bash

# Azure AD Service Principal Setup for Power BI Automation
# This script creates a service principal for Power BI REST API access
# and stores credentials securely in Azure Key Vault

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="PowerBI-ServicePrincipal"
SECRET_EXPIRY_MONTHS=24

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Azure CLI is logged in
check_az_login() {
    print_info "Checking Azure CLI authentication..."
    if ! az account show > /dev/null 2>&1; then
        print_error "Not logged in to Azure CLI. Please run 'az login' first."
        exit 1
    fi

    TENANT_ID=$(az account show --query tenantId -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    print_info "Logged in to tenant: $TENANT_ID"
    print_info "Using subscription: $SUBSCRIPTION_ID"
}

# Function to get Key Vault name from environment or prompt
get_key_vault_name() {
    if [ -z "$KEY_VAULT_NAME" ]; then
        print_warn "KEY_VAULT_NAME environment variable not set"
        read -p "Enter Key Vault name: " KEY_VAULT_NAME

        if [ -z "$KEY_VAULT_NAME" ]; then
            print_error "Key Vault name is required"
            exit 1
        fi
    fi

    # Verify Key Vault exists
    if ! az keyvault show --name "$KEY_VAULT_NAME" > /dev/null 2>&1; then
        print_error "Key Vault '$KEY_VAULT_NAME' not found or not accessible"
        exit 1
    fi

    print_info "Using Key Vault: $KEY_VAULT_NAME"
}

# Function to create Azure AD application
create_app_registration() {
    print_info "Step 1: Creating Azure AD Application Registration..."

    # Check if app already exists
    EXISTING_APP=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_APP" ]; then
        print_warn "Application '$APP_NAME' already exists with App ID: $EXISTING_APP"
        read -p "Do you want to use the existing app? (y/n): " USE_EXISTING

        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            APP_ID="$EXISTING_APP"
            print_info "Using existing application"
        else
            print_error "Please delete the existing app or use a different name"
            exit 1
        fi
    else
        # Create new application (no API permissions needed per best practices)
        APP_ID=$(az ad app create \
            --display-name "$APP_NAME" \
            --sign-in-audience "AzureADMyOrg" \
            --query appId \
            -o tsv)

        if [ -z "$APP_ID" ]; then
            print_error "Failed to create Azure AD application"
            exit 1
        fi

        print_info "Created application with ID: $APP_ID"

        # Wait for propagation
        print_info "Waiting for application to propagate (10 seconds)..."
        sleep 10
    fi

    # Get object ID
    APP_OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
    print_info "Application Object ID: $APP_OBJECT_ID"
}

# Function to create service principal
create_service_principal() {
    print_info "Step 2: Creating Service Principal..."

    # Check if service principal already exists
    EXISTING_SP=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_SP" ]; then
        print_warn "Service Principal already exists with Object ID: $EXISTING_SP"
        SP_OBJECT_ID="$EXISTING_SP"
    else
        # Create service principal
        SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

        if [ -z "$SP_OBJECT_ID" ]; then
            print_error "Failed to create service principal"
            exit 1
        fi

        print_info "Created service principal with Object ID: $SP_OBJECT_ID"

        # Wait for propagation
        print_info "Waiting for service principal to propagate (10 seconds)..."
        sleep 10
    fi
}

# Function to generate client secret
generate_client_secret() {
    print_info "Step 3: Generating Client Secret..."

    # Calculate expiry date
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        EXPIRY_DATE=$(date -u -v+${SECRET_EXPIRY_MONTHS}m "+%Y-%m-%dT%H:%M:%SZ")
    else
        # Linux
        EXPIRY_DATE=$(date -u -d "+${SECRET_EXPIRY_MONTHS} months" "+%Y-%m-%dT%H:%M:%SZ")
    fi

    print_info "Secret will expire on: $EXPIRY_DATE"

    # Generate credential
    CREDENTIAL_OUTPUT=$(az ad app credential reset \
        --id "$APP_ID" \
        --append \
        --end-date "$EXPIRY_DATE" \
        --display-name "PowerBI-Automation-Secret")

    CLIENT_SECRET=$(echo "$CREDENTIAL_OUTPUT" | jq -r '.password')

    if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" == "null" ]; then
        print_error "Failed to generate client secret"
        exit 1
    fi

    print_info "Client secret generated successfully"
    print_warn "This secret will be displayed only once. It will be stored in Key Vault."
}

# Function to store credentials in Key Vault
store_in_key_vault() {
    print_info "Step 4: Storing credentials in Key Vault '$KEY_VAULT_NAME'..."

    # Store client ID
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "powerbi-sp-client-id" \
        --value "$APP_ID" \
        --description "Power BI Service Principal Client ID" \
        > /dev/null
    print_info "Stored: powerbi-sp-client-id"

    # Store client secret
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "powerbi-sp-client-secret" \
        --value "$CLIENT_SECRET" \
        --description "Power BI Service Principal Client Secret" \
        --expires "$EXPIRY_DATE" \
        > /dev/null
    print_info "Stored: powerbi-sp-client-secret"

    # Store tenant ID
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "powerbi-sp-tenant-id" \
        --value "$TENANT_ID" \
        --description "Power BI Service Principal Tenant ID" \
        > /dev/null
    print_info "Stored: powerbi-sp-tenant-id"

    # Store object ID
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "powerbi-sp-object-id" \
        --value "$SP_OBJECT_ID" \
        --description "Power BI Service Principal Object ID" \
        > /dev/null
    print_info "Stored: powerbi-sp-object-id"

    print_info "All credentials stored securely in Key Vault"
}

# Function to print next steps
print_next_steps() {
    echo ""
    echo "=========================================================================================================="
    print_info "Service Principal Setup Complete!"
    echo "=========================================================================================================="
    echo ""
    echo "📋 Service Principal Details:"
    echo "   Application Name:    $APP_NAME"
    echo "   Application ID:      $APP_ID"
    echo "   Tenant ID:           $TENANT_ID"
    echo "   Object ID:           $SP_OBJECT_ID"
    echo "   Key Vault:           $KEY_VAULT_NAME"
    echo ""
    echo "🔐 Credentials stored in Key Vault as:"
    echo "   - powerbi-sp-client-id"
    echo "   - powerbi-sp-client-secret"
    echo "   - powerbi-sp-tenant-id"
    echo "   - powerbi-sp-object-id"
    echo ""
    echo "=========================================================================================================="
    print_warn "REQUIRED: Power BI Admin Portal Configuration"
    echo "=========================================================================================================="
    echo ""
    echo "A Power BI administrator must complete these steps in the Power BI Admin Portal:"
    echo ""
    echo "1. Go to: https://app.powerbi.com/admin-portal/tenantSettings"
    echo ""
    echo "2. Under 'Developer settings', enable these settings:"
    echo "   ✓ 'Embed content in apps'"
    echo "   ✓ 'Allow service principals to use Power BI APIs'"
    echo ""
    echo "3. Recommended: Create a security group and add this service principal:"
    echo "   - Service Principal Object ID: $SP_OBJECT_ID"
    echo "   - Enable settings only for this security group (not entire organization)"
    echo ""
    echo "4. Add the service principal to your Fabric workspace:"
    echo "   - Go to Workspace settings"
    echo "   - Add '$APP_NAME' with 'Member' or 'Admin' role"
    echo ""
    echo "=========================================================================================================="
    print_info "Test Authentication"
    echo "=========================================================================================================="
    echo ""
    echo "Test the service principal with:"
    echo ""
    echo "az login --service-principal \\"
    echo "  --username $APP_ID \\"
    echo "  --password \$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name powerbi-sp-client-secret --query value -o tsv) \\"
    echo "  --tenant $TENANT_ID"
    echo ""
    echo "=========================================================================================================="
    print_warn "Secret Expiry: $EXPIRY_DATE"
    echo "Set a reminder to renew the secret before it expires!"
    echo "=========================================================================================================="
    echo ""
}

# Main execution
main() {
    echo "=========================================================================================================="
    echo "Azure AD Service Principal Setup for Power BI Automation"
    echo "=========================================================================================================="
    echo ""

    check_az_login
    get_key_vault_name
    create_app_registration
    create_service_principal
    generate_client_secret
    store_in_key_vault
    print_next_steps
}

# Run main function
main
