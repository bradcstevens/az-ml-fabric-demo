#!/bin/bash

# Azure ML Fabric Demo Deployment Script
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT=${1:-dev}

echo "🚀 Starting Azure ML Fabric Demo deployment to $ENVIRONMENT environment..."

# Validate prerequisites
echo "📋 Validating prerequisites..."

if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v azd &> /dev/null; then
    echo "❌ Azure Developer CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

echo "✅ Prerequisites validated"

# Set working directory
cd "$PROJECT_ROOT"

# Initialize azd if not already done
if [ ! -f ".azure/$ENVIRONMENT/.env" ]; then
    echo "🔧 Initializing Azure Developer CLI for $ENVIRONMENT environment..."
    azd env new "$ENVIRONMENT"
fi

# Deploy infrastructure
echo "🏗️  Deploying infrastructure to $ENVIRONMENT environment..."
azd up --environment "$ENVIRONMENT"

if [ $? -eq 0 ]; then
    echo "✅ Deployment completed successfully!"
    echo "📊 You can monitor your resources at: https://portal.azure.com"

    # Get deployment outputs
    echo "📋 Deployment Information:"
    azd env get-values --environment "$ENVIRONMENT"
else
    echo "❌ Deployment failed. Check the logs above for details."
    exit 1
fi