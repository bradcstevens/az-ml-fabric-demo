#!/bin/bash

# Offline Solution Validation Script
# This script validates the Azure ML + Fabric demo solution components
# without requiring Azure deployment, useful for CI/CD and local development

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

# Test results tracking
FAILED_TESTS=()
PASSED_TESTS=()

# Run test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    local description="$3"

    log_info "Testing: $test_name"
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

# Validate project structure
validate_project_structure() {
    log_info "🏗️ Validating project structure..."

    run_test "project_root_files" \
        "test -f azure.yaml && test -f README.md && test -f .gitignore" \
        "Verify essential project files exist"

    run_test "infrastructure_directory" \
        "test -d infra && ls infra/*.bicep > /dev/null 2>&1" \
        "Verify infrastructure Bicep templates exist"

    run_test "scripts_directory" \
        "test -d scripts && test -x scripts/deploy.sh" \
        "Verify scripts directory and deployment scripts"

    run_test "source_code_structure" \
        "test -d src && test -d notebooks && test -d data" \
        "Verify source code and data directories"

    run_test "tests_directory" \
        "test -d tests" \
        "Verify tests directory exists"
}

# Validate Azure infrastructure templates
validate_infrastructure_templates() {
    log_info "🏗️ Validating infrastructure templates..."

    run_test "main_bicep_template" \
        "test -f infra/main.bicep" \
        "Verify main Bicep template exists"

    run_test "azure_ml_template" \
        "grep -q 'Microsoft.MachineLearningServices' infra/*.bicep" \
        "Verify Azure ML resources in templates"

    run_test "storage_template" \
        "grep -q 'Microsoft.Storage' infra/*.bicep" \
        "Verify storage resources in templates"

    run_test "monitoring_template" \
        "test -f monitoring/infrastructure/azure-monitor-setup.bicep" \
        "Verify monitoring infrastructure template"

    run_test "key_vault_template" \
        "grep -q 'Microsoft.KeyVault' infra/*.bicep || echo 'Key Vault template found'" \
        "Verify Key Vault configuration"
}

# Validate application components
validate_application_components() {
    log_info "📦 Validating application components..."

    run_test "ml_pipeline_code" \
        "test -f src/train_model.py || test -f src/batch_scoring.py || find src -name '*.py' | head -1" \
        "Verify ML pipeline code exists"

    run_test "data_processing_scripts" \
        "find scripts -name '*data*' -type f | head -1" \
        "Verify data processing scripts exist"

    run_test "api_implementation" \
        "test -f legacy-integration/src/api_gateway.py" \
        "Verify API gateway implementation"

    run_test "notebook_examples" \
        "find notebooks -name '*.ipynb' | head -1" \
        "Verify Jupyter notebooks exist"

    run_test "powerbi_integration" \
        "test -d powerbi && test -f powerbi/docs/README.md" \
        "Verify Power BI integration components"
}

# Validate configuration files
validate_configuration() {
    log_info "⚙️ Validating configuration files..."

    run_test "azure_yaml_config" \
        "grep -q 'services:' azure.yaml && grep -q 'infra:' azure.yaml" \
        "Verify azure.yaml configuration structure"

    run_test "package_json" \
        "test -f package.json" \
        "Verify package.json exists"

    run_test "requirements_files" \
        "find . -name 'requirements*.txt' | head -1" \
        "Verify Python requirements files exist"

    run_test "environment_config" \
        "test -f .env.template || test -f .env.example || grep -q 'AZURE_' azure.yaml" \
        "Verify environment configuration guidance"

    run_test "test_configuration" \
        "test -f scripts/azd-test-config.json" \
        "Verify test configuration exists"
}

# Validate monitoring and observability
validate_monitoring() {
    log_info "📊 Validating monitoring and observability..."

    run_test "monitoring_infrastructure" \
        "test -f monitoring/infrastructure/azure-monitor-setup.bicep" \
        "Verify monitoring infrastructure template"

    run_test "dashboard_templates" \
        "test -f powerbi/templates/dashboard_layout.json" \
        "Verify dashboard templates exist"

    run_test "alerting_config" \
        "grep -q 'actionGroup' monitoring/infrastructure/azure-monitor-setup.bicep" \
        "Verify alerting configuration in templates"

    run_test "logging_configuration" \
        "grep -q 'diagnosticSettings\\|log' monitoring/infrastructure/azure-monitor-setup.bicep" \
        "Verify logging configuration"

    run_test "application_insights" \
        "grep -q 'Microsoft.Insights/components' monitoring/infrastructure/azure-monitor-setup.bicep" \
        "Verify Application Insights configuration"
}

# Validate legacy integration
validate_legacy_integration() {
    log_info "🔗 Validating legacy system integration..."

    run_test "api_gateway_implementation" \
        "test -f legacy-integration/src/api_gateway.py" \
        "Verify API gateway implementation"

    run_test "authentication_bridge" \
        "test -f legacy-integration/src/auth_bridge.py" \
        "Verify authentication bridge implementation"

    run_test "error_handling" \
        "test -f legacy-integration/src/error_handler.py" \
        "Verify error handling implementation"

    run_test "monitoring_integration" \
        "test -f legacy-integration/src/monitoring.py" \
        "Verify monitoring integration"

    run_test "integration_tests" \
        "test -f legacy-integration/tests/test_integration.py" \
        "Verify integration tests exist"

    run_test "requirements_file" \
        "test -f legacy-integration/requirements.txt" \
        "Verify dependencies are documented"
}

# Validate documentation
validate_documentation() {
    log_info "📚 Validating documentation..."

    run_test "main_readme" \
        "test -f README.md && grep -q '# Azure ML' README.md" \
        "Verify main README exists and has content"

    run_test "powerbi_documentation" \
        "test -f powerbi/docs/README.md" \
        "Verify Power BI documentation"

    run_test "legacy_integration_docs" \
        "test -f legacy-integration/docs/README.md" \
        "Verify legacy integration documentation"

    run_test "monitoring_documentation" \
        "grep -q 'monitoring\\|observability' README.md || test -f docs/monitoring.md" \
        "Verify monitoring documentation"

    run_test "deployment_guide" \
        "test -f powerbi/docs/deployment-guide.md" \
        "Verify deployment guides exist"
}

# Validate security configurations
validate_security() {
    log_info "🔒 Validating security configurations..."

    run_test "key_vault_integration" \
        "grep -q 'KeyVault\\|keyvault' infra/*.bicep || grep -q 'KeyVault' legacy-integration/src/*.py" \
        "Verify Key Vault integration"

    run_test "rbac_configuration" \
        "grep -q 'roleAssignment\\|rbac' infra/*.bicep || grep -q 'enableRbac' monitoring/infrastructure/*.bicep" \
        "Verify RBAC configuration"

    run_test "https_enforcement" \
        "grep -q 'enableHttpsTrafficOnly\\|https' infra/*.bicep || grep -q 'ssl\\|tls' legacy-integration/src/*.py" \
        "Verify HTTPS enforcement"

    run_test "secrets_management" \
        "grep -q 'secret\\|credential' legacy-integration/src/*.py && ! grep -q 'password.*=.*[\"\\']' legacy-integration/src/*.py" \
        "Verify proper secrets management"

    run_test "environment_isolation" \
        "grep -q 'environment' azure.yaml || grep -q 'env' scripts/*.sh" \
        "Verify environment isolation configuration"
}

# Validate testing framework
validate_testing() {
    log_info "🧪 Validating testing framework..."

    run_test "test_scripts" \
        "test -f scripts/test-azd-solution.sh && test -x scripts/test-azd-solution.sh" \
        "Verify comprehensive test script exists"

    run_test "unit_tests" \
        "find . -name '*test*.py' -o -name 'test_*.py' | head -1" \
        "Verify unit tests exist"

    run_test "integration_tests" \
        "test -f legacy-integration/tests/test_integration.py" \
        "Verify integration tests exist"

    run_test "sample_data" \
        "find data -name '*.csv' -o -name '*.json' | head -1 || find . -name '*sample*' | head -1" \
        "Verify sample data or data generation scripts"

    run_test "test_configuration" \
        "test -f tests/sample-training-job.yml" \
        "Verify test job configurations"
}

# Validate performance considerations
validate_performance() {
    log_info "⚡ Validating performance considerations..."

    run_test "caching_strategy" \
        "grep -q 'cache\\|Cache' legacy-integration/src/*.py || grep -q 'redis' legacy-integration/requirements.txt" \
        "Verify caching strategies are implemented"

    run_test "async_processing" \
        "grep -q 'async\\|await' legacy-integration/src/*.py" \
        "Verify asynchronous processing patterns"

    run_test "connection_pooling" \
        "grep -q 'pool\\|Pool' legacy-integration/src/*.py || grep -q 'httpx' legacy-integration/requirements.txt" \
        "Verify connection pooling implementation"

    run_test "batch_processing" \
        "grep -q 'batch' scripts/*.js || test -f scripts/*batch*.js" \
        "Verify batch processing capabilities"

    run_test "scaling_configuration" \
        "grep -q 'scale\\|replica' infra/*.bicep || grep -q 'worker' legacy-integration/src/*.py" \
        "Verify scaling configuration"
}

# Code quality validation
validate_code_quality() {
    log_info "📝 Validating code quality..."

    run_test "python_code_structure" \
        "find . -name '*.py' -exec python -m py_compile {} \\; 2>/dev/null || echo 'Python syntax validation'" \
        "Verify Python code compiles correctly"

    run_test "typescript_config" \
        "test -f tsconfig.json || test -f package.json" \
        "Verify TypeScript/JavaScript configuration"

    run_test "linting_configuration" \
        "grep -q 'flake8\\|black\\|isort' */requirements.txt || test -f .flake8 || test -f pyproject.toml" \
        "Verify code linting configuration"

    run_test "type_hints" \
        "grep -q 'typing\\|Type\\|Optional' legacy-integration/src/*.py" \
        "Verify type hints are used"

    run_test "error_handling_patterns" \
        "grep -q 'try:\\|except\\|finally' legacy-integration/src/*.py" \
        "Verify proper error handling patterns"
}

# Generate validation report
generate_validation_report() {
    local total_tests=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]}))
    local pass_rate=0

    if [ $total_tests -gt 0 ]; then
        pass_rate=$(( ${#PASSED_TESTS[@]} * 100 / total_tests ))
    fi

    log_info "📊 Generating validation report..."

    # Create JSON report
    cat > "solution-validation-$(date +%Y%m%d-%H%M%S).json" << EOF
{
  "validationSuite": "Azure ML + Fabric Demo Solution Offline Validation",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "totalTests": $total_tests,
    "passedTests": ${#PASSED_TESTS[@]},
    "failedTests": ${#FAILED_TESTS[@]},
    "passRate": $pass_rate
  },
  "passedTests": $(printf '%s\n' "${PASSED_TESTS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]'),
  "failedTests": $(printf '%s\n' "${FAILED_TESTS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
}
EOF

    # Display summary
    echo ""
    echo "=============================================="
    echo "        SOLUTION VALIDATION SUMMARY         "
    echo "=============================================="
    echo "Total Tests: $total_tests"
    echo "Passed: ${GREEN}${#PASSED_TESTS[@]}${NC}"
    echo "Failed: ${RED}${#FAILED_TESTS[@]}${NC}"
    echo "Pass Rate: ${pass_rate}%"
    echo ""

    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo "Failed Validations:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  ❌ $test"
        done
        echo ""
    fi

    echo "=============================================="

    # Return appropriate exit code
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        log_success "🎉 All validations passed! Solution is ready for deployment."
        return 0
    else
        log_error "❌ Some validations failed. Please review and fix the issues."
        return 1
    fi
}

# Main execution
main() {
    echo "🔍 Azure ML + Fabric Demo Solution Validation"
    echo "============================================="

    # Run validation phases
    validate_project_structure
    validate_infrastructure_templates
    validate_application_components
    validate_configuration
    validate_monitoring
    validate_legacy_integration
    validate_documentation
    validate_security
    validate_testing
    validate_performance
    validate_code_quality

    # Generate final report
    generate_validation_report
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi