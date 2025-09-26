#!/bin/bash

# Azure ML Environment Setup Script
set -e

ENVIRONMENT=${1:-dev}
RESOURCE_GROUP="rg-${ENVIRONMENT}"
WORKSPACE_NAME="mlw-${ENVIRONMENT}"

echo "🔧 Setting up Azure ML environment for $ENVIRONMENT..."

# Create custom environments for ML training
echo "📦 Creating ML environments..."

# Python environment for machine learning
az ml environment create --file - <<EOF
name: ml-training-env
version: 1
description: Python environment for ML training with common libraries
image: mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04:latest
conda_file: |
  name: ml-training
  channels:
    - conda-forge
    - defaults
  dependencies:
    - python=3.9
    - pip
    - numpy
    - pandas
    - scikit-learn
    - matplotlib
    - seaborn
    - jupyter
    - pip:
      - azureml-core
      - azureml-dataset-runtime
      - mlflow
      - azure-storage-blob
EOF

# Create model registry
echo "📋 Setting up model registry..."
az ml model create --name "predictive-model" --version 1 --type "mlflow_model" --path "models/" || true

# Create data assets
echo "💾 Creating data assets..."
az ml data create --file - <<EOF
name: training-data
version: 1
description: Training dataset for predictive analytics
type: uri_folder
path: data/training/
EOF

az ml data create --file - <<EOF
name: validation-data
version: 1
description: Validation dataset for model evaluation
type: uri_folder
path: data/validation/
EOF

# Create compute targets if they don't exist
echo "💻 Configuring compute targets..."

# Training cluster
az ml compute create --name training-cluster --type amlcompute --min-instances 0 --max-instances 4 --size Standard_DS3_v2 || true

# Inference cluster (AKS)
az ml compute create --name inference-cluster --type aks --agent-count 3 --vm-size Standard_DS3_v2 || true

echo "✅ Azure ML environment setup completed for $ENVIRONMENT"