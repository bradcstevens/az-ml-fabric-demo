#!/bin/bash

# Infrastructure Validation Script
set -e

ENVIRONMENT=${1:-dev}
echo "🔍 Validating infrastructure for $ENVIRONMENT environment..."

# Check if azd is initialized
if [ ! -f ".azure/$ENVIRONMENT/.env" ]; then
    echo "❌ Environment $ENVIRONMENT is not initialized. Run 'azd env new $ENVIRONMENT' first."
    exit 1
fi

echo "✅ Environment $ENVIRONMENT is initialized"

# Validate Bicep templates
echo "🔧 Validating Bicep templates..."

# Main template
if ! az bicep build --file infra/main.bicep --stdout > /dev/null; then
    echo "❌ Main Bicep template validation failed"
    exit 1
fi

# Module templates
for module in infra/modules/*.bicep; do
    if ! az bicep build --file "$module" --stdout > /dev/null; then
        echo "❌ Module $module validation failed"
        exit 1
    fi
done

echo "✅ All Bicep templates are valid"

# Validate parameter files
echo "📋 Validating parameter files..."
for param_file in infra/main.*.bicepparam; do
    if [ -f "$param_file" ]; then
        echo "  - Validating $(basename "$param_file")"
        # Basic syntax check by attempting to build
        if ! az bicep build-params --file "$param_file" --stdout > /dev/null 2>&1; then
            echo "⚠️  Warning: Parameter file $param_file may have issues"
        else
            echo "  ✅ $(basename "$param_file") is valid"
        fi
    fi
done

# Validate azure.yaml
echo "📄 Validating azure.yaml..."
if [ -f "azure.yaml" ]; then
    # Check if yaml is valid
    if command -v python3 &> /dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('azure.yaml'))" 2>/dev/null && echo "  ✅ azure.yaml is valid YAML" || echo "  ❌ azure.yaml has syntax errors"
    fi

    # Check required fields
    if grep -q "name:" azure.yaml && grep -q "infra:" azure.yaml && grep -q "services:" azure.yaml; then
        echo "  ✅ azure.yaml has required fields"
    else
        echo "  ❌ azure.yaml is missing required fields"
        exit 1
    fi
else
    echo "❌ azure.yaml not found"
    exit 1
fi

# Check for required tools
echo "🛠️  Checking required tools..."
tools=("az" "azd")
for tool in "${tools[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "  ✅ $tool is installed"
    else
        echo "  ❌ $tool is not installed"
        exit 1
    fi
done

echo "🎉 Infrastructure validation completed successfully for $ENVIRONMENT environment!"
echo "💡 Ready to deploy with: azd up --environment $ENVIRONMENT"