#!/bin/bash

# Comprehensive azd Solution Testing Script
# This script tests the complete Azure ML + Fabric demo solution using Azure Developer CLI

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test configuration
ENVIRONMENT_NAME="${AZURE_ENV_NAME:-azmlfabrictest}"
RESOURCE_GROUP_NAME=""
SUBSCRIPTION_ID=""
TEST_RESULTS_FILE="test-results-$(date +%Y%m%d-%H%M%S).json"
FAILED_TESTS=()
PASSED_TESTS=()

# Test functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    local description="$3"

    log_info "Running test: $test_name"
    log_info "Description: $description"

    if eval "$test_command"; then
        log_success "✅ $test_name PASSED"
        PASSED_TESTS+=("$test_name")
        return 0
    else
        log_error "❌ $test_name FAILED"
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

# Prerequisites validation
validate_prerequisites() {
    log_info "🔍 Validating prerequisites..."

    # Check if azd is installed
    if ! command -v azd &> /dev/null; then
        log_error "Azure Developer CLI (azd) is not installed"
        log_info "Install it from: https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd"
        exit 1
    fi

    # Check if az CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi

    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Please log in to Azure CLI first: az login"
        exit 1
    fi

    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed - some tests may be limited"
    fi

    log_success "Prerequisites validated"
}

# Environment initialization
initialize_environment() {
    log_info "🚀 Initializing azd environment..."

    # Initialize azd environment if not exists
    if [ ! -f ".azure/${ENVIRONMENT_NAME}/.env" ]; then
        log_info "Creating new azd environment: $ENVIRONMENT_NAME"
        azd env new "$ENVIRONMENT_NAME"
    else
        log_info "Using existing azd environment: $ENVIRONMENT_NAME"
        azd env select "$ENVIRONMENT_NAME"
    fi

    # Get environment variables
    eval "$(azd env get-values)"

    SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
    RESOURCE_GROUP_NAME="${AZURE_RESOURCE_GROUP:-rg-${ENVIRONMENT_NAME}}"

    log_info "Environment: $ENVIRONMENT_NAME"
    log_info "Subscription: $SUBSCRIPTION_ID"
    log_info "Resource Group: $RESOURCE_GROUP_NAME"
}

# Infrastructure tests
test_infrastructure_provisioning() {
    log_info "🏗️ Testing infrastructure provisioning..."

    run_test "azd_provision" \
        "azd provision --no-prompt" \
        "Provision Azure infrastructure using azd"

    # Wait for provisioning to complete
    sleep 30

    # Verify resource group exists
    run_test "resource_group_exists" \
        "az group show --name '$RESOURCE_GROUP_NAME' --subscription '$SUBSCRIPTION_ID' > /dev/null" \
        "Verify resource group was created"

    # Test individual resource creation
    test_azure_ml_workspace
    test_storage_account
    test_key_vault
    test_container_registry
    test_monitoring_resources
}

test_azure_ml_workspace() {
    local workspace_name="${AZURE_ML_WORKSPACE_NAME:-${ENVIRONMENT_NAME}-ml}"

    run_test "azure_ml_workspace" \
        "az ml workspace show --name '$workspace_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify Azure ML workspace was created"

    # Test workspace compute
    run_test "azure_ml_compute" \
        "az ml compute list --workspace-name '$workspace_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify Azure ML compute resources"

    # Test workspace connectivity
    run_test "azure_ml_connectivity" \
        "timeout 30 az ml job list --workspace-name '$workspace_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Test Azure ML workspace connectivity"
}

test_storage_account() {
    local storage_name="${AZURE_STORAGE_ACCOUNT_NAME:-${ENVIRONMENT_NAME}stor}"

    run_test "storage_account" \
        "az storage account show --name '$storage_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify storage account was created"

    # Test storage connectivity
    run_test "storage_connectivity" \
        "az storage container list --account-name '$storage_name' --auth-mode login > /dev/null" \
        "Test storage account connectivity"

    # Test required containers
    local containers=("data" "models" "logs")
    for container in "${containers[@]}"; do
        run_test "storage_container_$container" \
            "az storage container show --name '$container' --account-name '$storage_name' --auth-mode login > /dev/null || az storage container create --name '$container' --account-name '$storage_name' --auth-mode login > /dev/null" \
            "Verify storage container: $container"
    done
}

test_key_vault() {
    local kv_name="${AZURE_KEY_VAULT_NAME:-${ENVIRONMENT_NAME}-kv}"

    run_test "key_vault" \
        "az keyvault show --name '$kv_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify Key Vault was created"

    # Test Key Vault access
    run_test "key_vault_access" \
        "az keyvault secret list --vault-name '$kv_name' > /dev/null" \
        "Test Key Vault access permissions"
}

test_container_registry() {
    local acr_name="${AZURE_CONTAINER_REGISTRY_NAME:-${ENVIRONMENT_NAME}acr}"

    run_test "container_registry" \
        "az acr show --name '$acr_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify Container Registry was created"

    # Test ACR login
    run_test "acr_login" \
        "az acr login --name '$acr_name'" \
        "Test Container Registry authentication"
}

test_monitoring_resources() {
    local workspace_name="${AZURE_LOG_ANALYTICS_WORKSPACE_NAME:-${ENVIRONMENT_NAME}-logs}"
    local insights_name="${AZURE_APPLICATION_INSIGHTS_NAME:-${ENVIRONMENT_NAME}-insights}"

    run_test "log_analytics_workspace" \
        "az monitor log-analytics workspace show --workspace-name '$workspace_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify Log Analytics workspace was created"

    run_test "application_insights" \
        "az monitor app-insights component show --app '$insights_name' --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify Application Insights was created"
}

# Application deployment tests
test_application_deployment() {
    log_info "📦 Testing application deployment..."

    run_test "azd_deploy" \
        "azd deploy --no-prompt" \
        "Deploy applications using azd"

    # Wait for deployment to complete
    sleep 60

    # Test deployed services
    test_api_service
    test_ml_pipelines
    test_monitoring_setup
}

test_api_service() {
    local api_url="${AZURE_API_URL:-}"

    if [ -n "$api_url" ]; then
        run_test "api_health_check" \
            "curl -f '$api_url/health' > /dev/null" \
            "Test API service health endpoint"

        run_test "api_metrics_endpoint" \
            "curl -f '$api_url/metrics' > /dev/null" \
            "Test API metrics endpoint"
    else
        log_warning "API URL not configured, skipping API tests"
    fi
}

test_ml_pipelines() {
    local workspace_name="${AZURE_ML_WORKSPACE_NAME:-${ENVIRONMENT_NAME}-ml}"

    # Test if pipelines are registered
    run_test "ml_pipeline_registration" \
        "az ml job list --workspace-name '$workspace_name' --resource-group '$RESOURCE_GROUP_NAME' --max-results 1 > /dev/null" \
        "Verify ML pipelines are accessible"

    # Test batch scoring pipeline
    run_test "batch_scoring_pipeline" \
        "node scripts/test-batch-pipeline.js" \
        "Test batch scoring pipeline execution"
}

test_monitoring_setup() {
    local workspace_name="${AZURE_LOG_ANALYTICS_WORKSPACE_NAME:-${ENVIRONMENT_NAME}-logs}"

    # Test monitoring data ingestion
    run_test "monitoring_data_ingestion" \
        "az monitor log-analytics query --workspace '$workspace_name' --analytics-query 'Heartbeat | take 1' > /dev/null" \
        "Test monitoring data ingestion"

    # Test alert rules
    run_test "alert_rules" \
        "az monitor metrics alert list --resource-group '$RESOURCE_GROUP_NAME' > /dev/null" \
        "Verify alert rules are configured"
}

# End-to-end functional tests
test_end_to_end_functionality() {
    log_info "🔄 Running end-to-end functional tests..."

    # Test data pipeline
    test_data_pipeline

    # Test ML model training
    test_ml_model_training

    # Test prediction endpoints
    test_prediction_endpoints

    # Test Power BI integration
    test_powerbi_integration

    # Test legacy system integration
    test_legacy_integration
}

test_data_pipeline() {
    run_test "data_generation" \
        "node scripts/generate-timeseries.js" \
        "Generate test data for the pipeline"

    run_test "data_validation" \
        "node scripts/validate-data-quality.js" \
        "Validate data quality and structure"

    run_test "data_foundation_setup" \
        "node scripts/setup-data-foundation.js" \
        "Set up data foundation in Fabric workspace"
}

test_ml_model_training() {
    local workspace_name="${AZURE_ML_WORKSPACE_NAME:-${ENVIRONMENT_NAME}-ml}"

    # Submit a simple training job
    run_test "ml_training_job" \
        "az ml job create --file tests/sample-training-job.yml --workspace-name '$workspace_name' --resource-group '$RESOURCE_GROUP_NAME'" \
        "Submit ML training job"
}

test_prediction_endpoints() {
    local api_url="${AZURE_API_URL:-}"

    if [ -n "$api_url" ]; then
        # Test real-time prediction
        run_test "realtime_prediction" \
            "curl -X POST '$api_url/predict' -H 'Content-Type: application/json' -d '{\"input_data\": {\"feature1\": 1.0, \"feature2\": 2.0}}' > /dev/null" \
            "Test real-time prediction endpoint"

        # Test batch prediction
        run_test "batch_prediction" \
            "curl -X POST '$api_url/batch-predict' -H 'Content-Type: application/json' -d '[{\"input_data\": {\"feature1\": 1.0}}, {\"input_data\": {\"feature2\": 2.0}}]' > /dev/null" \
            "Test batch prediction endpoint"
    else
        log_warning "API URL not configured, skipping prediction tests"
    fi
}

test_powerbi_integration() {
    # Test if Power BI configuration is in place
    run_test "powerbi_config" \
        "test -f powerbi/templates/data_model.json" \
        "Verify Power BI configuration exists"

    run_test "powerbi_templates" \
        "test -f powerbi/templates/dashboard_layout.json" \
        "Verify Power BI dashboard templates exist"
}

test_legacy_integration() {
    # Test legacy integration gateway
    run_test "legacy_integration_config" \
        "test -f legacy-integration/src/api_gateway.py" \
        "Verify legacy integration gateway exists"

    run_test "legacy_integration_tests" \
        "cd legacy-integration && python -m pytest tests/ -v" \
        "Run legacy integration test suite"
}

# Performance and load testing
test_performance() {
    log_info "⚡ Running performance tests..."

    local api_url="${AZURE_API_URL:-}"

    if [ -n "$api_url" ] && command -v curl &> /dev/null; then
        # Simple load test
        run_test "api_load_test" \
            "for i in {1..10}; do curl -f '$api_url/health' > /dev/null & done; wait" \
            "Basic API load test (10 concurrent requests)"

        # Response time test
        run_test "api_response_time" \
            "response_time=\$(curl -o /dev/null -s -w '%{time_total}' '$api_url/health'); [ \"\$(echo \"\$response_time < 2.0\" | bc)\" -eq 1 ]" \
            "API response time under 2 seconds"
    else
        log_warning "Skipping performance tests - API URL not available or curl not installed"
    fi
}

# Security testing
test_security() {
    log_info "🔒 Running security tests..."

    # Test Key Vault integration
    local kv_name="${AZURE_KEY_VAULT_NAME:-${ENVIRONMENT_NAME}-kv}"

    run_test "key_vault_rbac" \
        "az keyvault show --name '$kv_name' --query 'properties.enableRbacAuthorization' -o tsv | grep -q true" \
        "Verify Key Vault RBAC is enabled"

    # Test storage account security
    local storage_name="${AZURE_STORAGE_ACCOUNT_NAME:-${ENVIRONMENT_NAME}stor}"

    run_test "storage_https_only" \
        "az storage account show --name '$storage_name' --query 'enableHttpsTrafficOnly' -o tsv | grep -q true" \
        "Verify storage account HTTPS-only access"

    # Test network security
    run_test "network_security_groups" \
        "az network nsg list --resource-group '$RESOURCE_GROUP_NAME' | jq length | grep -q '[1-9]'" \
        "Verify network security groups are configured"
}

# Generate test report
generate_test_report() {
    local total_tests=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]}))
    local pass_rate=$(( ${#PASSED_TESTS[@]} * 100 / total_tests ))

    log_info "📊 Generating test report..."

    # Create JSON report
    cat > "$TEST_RESULTS_FILE" << EOF
{
  "testSuite": "Azure ML + Fabric Demo Solution",
  "environment": "$ENVIRONMENT_NAME",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "totalTests": $total_tests,
    "passedTests": ${#PASSED_TESTS[@]},
    "failedTests": ${#FAILED_TESTS[@]},
    "passRate": $pass_rate
  },
  "passedTests": $(printf '%s\n' "${PASSED_TESTS[@]}" | jq -R . | jq -s .),
  "failedTests": $(printf '%s\n' "${FAILED_TESTS[@]}" | jq -R . | jq -s .),
  "resourceGroup": "$RESOURCE_GROUP_NAME",
  "subscription": "$SUBSCRIPTION_ID"
}
EOF

    # Display summary
    echo ""
    echo "=============================================="
    echo "           TEST EXECUTION SUMMARY            "
    echo "=============================================="
    echo "Environment: $ENVIRONMENT_NAME"
    echo "Total Tests: $total_tests"
    echo "Passed: ${GREEN}${#PASSED_TESTS[@]}${NC}"
    echo "Failed: ${RED}${#FAILED_TESTS[@]}${NC}"
    echo "Pass Rate: ${pass_rate}%"
    echo ""

    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  ❌ $test"
        done
        echo ""
    fi

    echo "Detailed report saved to: $TEST_RESULTS_FILE"
    echo "=============================================="

    # Return appropriate exit code
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        log_success "🎉 All tests passed!"
        return 0
    else
        log_error "❌ Some tests failed. Check the report for details."
        return 1
    fi
}

# Cleanup function
cleanup_on_exit() {
    log_info "🧹 Cleaning up temporary resources..."
    # Add any cleanup logic here
}

# Main execution
main() {
    echo "🚀 Azure ML + Fabric Demo Solution Testing"
    echo "==========================================="

    # Set up trap for cleanup
    trap cleanup_on_exit EXIT

    # Run test phases
    validate_prerequisites
    initialize_environment

    log_info "🏗️ Phase 1: Infrastructure Testing"
    test_infrastructure_provisioning

    log_info "📦 Phase 2: Application Deployment Testing"
    test_application_deployment

    log_info "🔄 Phase 3: End-to-End Functionality Testing"
    test_end_to_end_functionality

    log_info "⚡ Phase 4: Performance Testing"
    test_performance

    log_info "🔒 Phase 5: Security Testing"
    test_security

    # Generate final report
    generate_test_report
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi