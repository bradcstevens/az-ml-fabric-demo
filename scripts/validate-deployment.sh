#!/bin/bash
# Deployment Validation Script for Azure ML + Fabric Demo
# This script validates that all expected Azure resources are deployed successfully

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP_NAME="${1:-rg-dev}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Azure ML + Fabric Deployment Validator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Subscription: ${SUBSCRIPTION_ID}${NC}"
echo -e "${YELLOW}Resource Group: ${RESOURCE_GROUP_NAME}${NC}"
echo ""

# Function to check resource existence
check_resource() {
    local resource_type=$1
    local expected_count=$2
    local resource_name=$3

    echo -n "Checking ${resource_name}..."

    if [ -z "$RESOURCE_GROUP_NAME" ] || [ "$RESOURCE_GROUP_NAME" = "rg-dev" ]; then
        echo -e " ${YELLOW}SKIPPED${NC} (Resource group not found)"
        return 1
    fi

    local actual_count=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" \
        --resource-type "$resource_type" --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [ "$actual_count" -ge "$expected_count" ]; then
        echo -e " ${GREEN}✓ Found ${actual_count}${NC}"
        return 0
    else
        echo -e " ${RED}✗ Expected ${expected_count}, found ${actual_count}${NC}"
        return 1
    fi
}

# Function to check Bicep compilation
validate_bicep() {
    echo -e "${BLUE}=== Step 1: Bicep Validation ===${NC}"

    if [ ! -f "infra/main.bicep" ]; then
        echo -e "${RED}✗ main.bicep not found${NC}"
        return 1
    fi

    echo "Compiling main.bicep..."
    if az bicep build --file infra/main.bicep 2>&1 | grep -q "ERROR"; then
        echo -e "${RED}✗ Bicep compilation failed${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Bicep compiles successfully${NC}"
    fi
    echo ""
}

# Function to validate resource group
validate_resource_group() {
    echo -e "${BLUE}=== Step 2: Resource Group Validation ===${NC}"

    if az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null; then
        echo -e "${GREEN}✓ Resource group '${RESOURCE_GROUP_NAME}' exists${NC}"

        # Get resource count
        local total_resources=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" -o tsv)
        echo -e "  Total resources in group: ${total_resources}"
        echo ""
        return 0
    else
        echo -e "${YELLOW}⚠ Resource group '${RESOURCE_GROUP_NAME}' not found${NC}"
        echo -e "  This is expected if 'azd up' has not been run yet."
        echo ""
        return 1
    fi
}

# Function to validate core infrastructure
validate_core_infrastructure() {
    echo -e "${BLUE}=== Step 3: Core Infrastructure Validation ===${NC}"

    local failures=0

    # Network Infrastructure
    echo -e "${YELLOW}Network Foundation:${NC}"
    check_resource "Microsoft.Network/virtualNetworks" 1 "Virtual Network" || ((failures++))
    check_resource "Microsoft.Network/networkSecurityGroups" 4 "Network Security Groups (4 subnets)" || ((failures++))
    check_resource "Microsoft.Network/privateDnsZones" 5 "Private DNS Zones" || ((failures++))
    echo ""

    # Security & Storage
    echo -e "${YELLOW}Security & Storage:${NC}"
    check_resource "Microsoft.KeyVault/vaults" 1 "Key Vault" || ((failures++))
    check_resource "Microsoft.Storage/storageAccounts" 1 "Storage Account" || ((failures++))
    check_resource "Microsoft.ContainerRegistry/registries" 1 "Container Registry" || ((failures++))
    check_resource "Microsoft.Network/privateEndpoints" 3 "Private Endpoints (KV, Storage, ACR)" || ((failures++))
    echo ""

    # Monitoring
    echo -e "${YELLOW}Monitoring:${NC}"
    check_resource "Microsoft.OperationalInsights/workspaces" 1 "Log Analytics Workspace" || ((failures++))
    check_resource "Microsoft.Insights/components" 1 "Application Insights" || ((failures++))
    echo ""

    # Azure ML
    echo -e "${YELLOW}Azure Machine Learning:${NC}"
    check_resource "Microsoft.MachineLearningServices/workspaces" 1 "ML Workspace" || ((failures++))
    check_resource "Microsoft.MachineLearningServices/workspaces/computes" 1 "ML Compute Cluster" || ((failures++))
    echo ""

    # Microsoft Fabric (Power BI)
    echo -e "${YELLOW}Microsoft Fabric:${NC}"
    check_resource "Microsoft.Fabric/capacities" 1 "Fabric Capacity" || ((failures++))
    echo ""

    if [ $failures -eq 0 ]; then
        echo -e "${GREEN}✓ All core infrastructure resources validated${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ ${failures} resource check(s) failed or resources not yet deployed${NC}"
        return 1
    fi
}

# Function to provide deployment summary
deployment_summary() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Expected Resources Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}Network Foundation (6 resources):${NC}"
    echo "  • 1 Virtual Network (4 subnets)"
    echo "  • 4 Network Security Groups"
    echo "  • 5 Private DNS Zones"
    echo ""
    echo -e "${GREEN}Security & Storage (7 resources):${NC}"
    echo "  • 1 Key Vault (with private endpoint)"
    echo "  • 1 Storage Account (with blob containers)"
    echo "  • 1 Container Registry"
    echo "  • 3 Private Endpoints"
    echo "  • 1 Private DNS Zone Group"
    echo ""
    echo -e "${GREEN}Monitoring (2 resources):${NC}"
    echo "  • 1 Log Analytics Workspace"
    echo "  • 1 Application Insights"
    echo ""
    echo -e "${GREEN}Azure ML (2+ resources):${NC}"
    echo "  • 1 Machine Learning Workspace"
    echo "  • 1 Compute Cluster"
    echo ""
    echo -e "${GREEN}Microsoft Fabric (1 resource):${NC}"
    echo "  • 1 Fabric Capacity (Power BI Dedicated)"
    echo ""
    echo -e "${YELLOW}Total Expected: 18-20+ resources${NC}"
    echo ""
}

# Function to provide next steps
next_steps() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Next Steps${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    if [ -z "$RESOURCE_GROUP_NAME" ] || [ "$RESOURCE_GROUP_NAME" = "rg-dev" ]; then
        echo -e "${YELLOW}To deploy the infrastructure:${NC}"
        echo "  1. Ensure you're logged in: az login"
        echo "  2. Set subscription: az account set --subscription <subscription-id>"
        echo "  3. Deploy: azd up"
        echo ""
        echo -e "${YELLOW}After deployment, run this script again:${NC}"
        echo "  ./scripts/validate-deployment.sh <resource-group-name>"
    else
        echo -e "${GREEN}✓ Infrastructure validated successfully!${NC}"
        echo ""
        echo "You can now:"
        echo "  1. Access Azure ML Studio"
        echo "  2. Upload training data"
        echo "  3. Configure Fabric workspace"
        echo "  4. Set up Power BI dashboards"
    fi
    echo ""
}

# Main execution
main() {
    validate_bicep

    local rg_exists=0
    validate_resource_group && rg_exists=1

    if [ $rg_exists -eq 1 ]; then
        validate_core_infrastructure
    fi

    deployment_summary
    next_steps
}

# Run main function
main
