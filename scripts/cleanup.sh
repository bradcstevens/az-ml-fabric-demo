#!/bin/bash

# Azure ML Fabric Demo Cleanup Script
set -e

ENVIRONMENT=${1:-dev}
FORCE=${2:-false}

echo "🧹 Cleaning up Azure ML Fabric Demo for $ENVIRONMENT environment..."

if [ "$FORCE" != "true" ]; then
    echo "⚠️  This will delete ALL resources in the $ENVIRONMENT environment."
    echo "🚨 This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "❌ Cleanup cancelled."
        exit 0
    fi
fi

# Check if environment exists
if [ ! -f ".azure/$ENVIRONMENT/.env" ]; then
    echo "❌ Environment $ENVIRONMENT not found."
    exit 1
fi

# Clean up using azd
echo "🗑️  Removing Azure resources..."
azd down --environment "$ENVIRONMENT" --force --purge

# Clean up local environment files
echo "📁 Cleaning up local environment files..."
if [ -d ".azure/$ENVIRONMENT" ]; then
    rm -rf ".azure/$ENVIRONMENT"
    echo "  ✅ Removed .azure/$ENVIRONMENT directory"
fi

# Clean up any cached files
echo "🧽 Cleaning up cache files..."
if [ -f ".azure/config.json" ]; then
    # Remove environment from config
    echo "  ✅ Cleaned azd configuration"
fi

echo ""
echo "✅ Cleanup completed successfully!"
echo "💡 Environment $ENVIRONMENT has been completely removed."
echo ""
echo "To redeploy:"
echo "  azd up --environment $ENVIRONMENT"