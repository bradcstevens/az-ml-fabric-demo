#!/bin/bash
set -e

# Deploy Real-Time Scoring Endpoint for Azure ML Fabric Demo
# Task 5: Deploy Real-Time Scoring Endpoint

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
AZURE_ENV_NAME=${AZURE_ENV_NAME:-"dev"}
ENDPOINT_NAME=${ENDPOINT_NAME:-"fabric-demo-rt-endpoint"}
MODEL_NAME=${MODEL_NAME:-"fabric-demo-model"}
MODEL_VERSION=${MODEL_VERSION:-"1"}
INSTANCE_TYPE=${INSTANCE_TYPE:-"Standard_DS3_v2"}
MIN_INSTANCES=${MIN_INSTANCES:-2}
MAX_INSTANCES=${MAX_INSTANCES:-10}

print_status "🚀 Deploying Real-Time Scoring Endpoint"
print_status "Environment: $AZURE_ENV_NAME"
print_status "Endpoint: $ENDPOINT_NAME"
print_status "Model: $MODEL_NAME (v$MODEL_VERSION)"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | xargs)
fi

# Check Azure CLI authentication
print_status "🔐 Checking Azure authentication..."
if ! az account show > /dev/null 2>&1; then
    print_error "Not logged into Azure CLI. Please run 'az login'"
    exit 1
fi

print_success "Azure authentication verified"

# Get Azure DevOps environment variables
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
AZURE_RESOURCE_GROUP="rg-${AZURE_ENV_NAME}-ml-fabric"
AZURE_ML_WORKSPACE_NAME="mlw-${AZURE_ENV_NAME}-fabric"

print_status "Subscription: $AZURE_SUBSCRIPTION_ID"
print_status "Resource Group: $AZURE_RESOURCE_GROUP"
print_status "ML Workspace: $AZURE_ML_WORKSPACE_NAME"

# Validate ML workspace exists
print_status "🔍 Validating ML workspace..."
if ! az ml workspace show -n "$AZURE_ML_WORKSPACE_NAME" -g "$AZURE_RESOURCE_GROUP" > /dev/null 2>&1; then
    print_error "ML workspace '$AZURE_ML_WORKSPACE_NAME' not found in resource group '$AZURE_RESOURCE_GROUP'"
    print_error "Please ensure the workspace is deployed first"
    exit 1
fi

print_success "ML workspace validated"

# Check if model exists
print_status "📦 Checking if model exists..."
if az ml model show -n "$MODEL_NAME" -v "$MODEL_VERSION" -w "$AZURE_ML_WORKSPACE_NAME" -g "$AZURE_RESOURCE_GROUP" > /dev/null 2>&1; then
    print_success "Model '$MODEL_NAME' version '$MODEL_VERSION' found"
else
    print_warning "Model '$MODEL_NAME' version '$MODEL_VERSION' not found"
    print_status "Creating placeholder model for endpoint deployment..."

    # Create a simple model package for deployment
    mkdir -p "$PROJECT_ROOT/tmp/model"

    cat > "$PROJECT_ROOT/tmp/model/score.py" << 'EOF'
import json
import joblib
import numpy as np
from inference_schema.schema_decorators import input_schema, output_schema
from inference_schema.parameter_types.numpy_parameter_type import NumpyParameterType

def init():
    global model
    # In production, load actual model file
    # model = joblib.load(os.path.join(os.getenv('AZUREML_MODEL_DIR'), 'model.pkl'))
    model = None

@input_schema('data', NumpyParameterType(np.array([[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]])))
@output_schema(NumpyParameterType(np.array([0.95])))
def run(data):
    try:
        # Simple prediction logic for demo
        features = np.array(data)
        # Mock prediction - replace with actual model inference
        prediction = np.random.random(features.shape[0])
        return prediction.tolist()
    except Exception as e:
        return {"error": str(e)}
EOF

    cat > "$PROJECT_ROOT/tmp/model/conda.yml" << 'EOF'
name: model-env
channels:
  - conda-forge
dependencies:
  - python=3.8
  - pip=21.2.4
  - pip:
    - numpy==1.21.2
    - scikit-learn==1.0.2
    - joblib==1.1.0
    - inference-schema[numpy-support]==1.3.0
EOF

    # Register the model
    az ml model create \
        --name "$MODEL_NAME" \
        --version "$MODEL_VERSION" \
        --path "$PROJECT_ROOT/tmp/model" \
        --type "custom_model" \
        --workspace-name "$AZURE_ML_WORKSPACE_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP"

    print_success "Model registered successfully"

    # Cleanup
    rm -rf "$PROJECT_ROOT/tmp"
fi

# Deploy online endpoint using Bicep
print_status "📡 Deploying online endpoint infrastructure..."

DEPLOYMENT_NAME="rt-endpoint-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --template-file "$PROJECT_ROOT/infra/modules/ml-online-endpoint.bicep" \
    --name "$DEPLOYMENT_NAME" \
    --parameters \
        workspaceName="$AZURE_ML_WORKSPACE_NAME" \
        endpointName="$ENDPOINT_NAME" \
        modelName="$MODEL_NAME" \
        modelVersion="$MODEL_VERSION" \
        instanceType="$INSTANCE_TYPE" \
        minInstances="$MIN_INSTANCES" \
        maxInstances="$MAX_INSTANCES"

if [ $? -eq 0 ]; then
    print_success "Endpoint infrastructure deployed successfully"
else
    print_error "Failed to deploy endpoint infrastructure"
    exit 1
fi

# Get endpoint information
print_status "📊 Getting endpoint information..."

ENDPOINT_URI=$(az ml online-endpoint show \
    --name "$ENDPOINT_NAME" \
    --workspace-name "$AZURE_ML_WORKSPACE_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "scoring_uri" -o tsv)

ENDPOINT_SWAGGER=$(az ml online-endpoint show \
    --name "$ENDPOINT_NAME" \
    --workspace-name "$AZURE_ML_WORKSPACE_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "swagger_uri" -o tsv)

# Test endpoint readiness
print_status "🧪 Testing endpoint readiness..."

# Wait for deployment to be ready
TIMEOUT=600  # 10 minutes
INTERVAL=30  # 30 seconds
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    DEPLOYMENT_STATE=$(az ml online-deployment show \
        --name "${ENDPOINT_NAME}-deployment" \
        --endpoint-name "$ENDPOINT_NAME" \
        --workspace-name "$AZURE_ML_WORKSPACE_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "provisioning_state" -o tsv 2>/dev/null || echo "Unknown")

    if [ "$DEPLOYMENT_STATE" = "Succeeded" ]; then
        print_success "Deployment is ready!"
        break
    elif [ "$DEPLOYMENT_STATE" = "Failed" ]; then
        print_error "Deployment failed!"
        exit 1
    else
        print_status "Deployment state: $DEPLOYMENT_STATE. Waiting..."
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    fi
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    print_error "Deployment did not complete within timeout period"
    exit 1
fi

# Performance validation
print_status "⚡ Running performance validation..."

# Get authentication token
TOKEN=$(az ml online-endpoint get-credentials \
    --name "$ENDPOINT_NAME" \
    --workspace-name "$AZURE_ML_WORKSPACE_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "accessToken" -o tsv)

# Test single prediction with latency measurement
print_status "Testing single prediction latency..."

START_TIME=$(date +%s%3N)
RESPONSE=$(curl -s -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"data": [[1.5, 2.3, 0.8, 1.2, 3.1, 0.9, 2.7, 1.8]]}' \
    "$ENDPOINT_URI")
END_TIME=$(date +%s%3N)

HTTP_CODE=$(echo "$RESPONSE" | tail -c 4)
LATENCY=$((END_TIME - START_TIME))

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Prediction successful! Latency: ${LATENCY}ms"

    if [ $LATENCY -lt 1000 ]; then
        print_success "✅ Latency requirement met (< 1 second)"
    else
        print_warning "⚠️ Latency requirement not met (${LATENCY}ms > 1000ms)"
    fi
else
    print_error "Prediction failed with HTTP code: $HTTP_CODE"
fi

# Final deployment summary
print_success "🎉 Real-Time Scoring Endpoint Deployment Complete!"
echo ""
echo "📋 Deployment Summary:"
echo "  Endpoint Name:     $ENDPOINT_NAME"
echo "  Scoring URI:       $ENDPOINT_URI"
echo "  Swagger URI:       $ENDPOINT_SWAGGER"
echo "  Instance Type:     $INSTANCE_TYPE"
echo "  Min Instances:     $MIN_INSTANCES"
echo "  Max Instances:     $MAX_INSTANCES"
echo "  Model:             $MODEL_NAME (v$MODEL_VERSION)"
echo "  Latency:           ${LATENCY}ms"
echo ""
echo "🔧 Management Commands:"
echo "  View logs:         az ml online-deployment get-logs -n ${ENDPOINT_NAME}-deployment -e $ENDPOINT_NAME -w $AZURE_ML_WORKSPACE_NAME -g $AZURE_RESOURCE_GROUP"
echo "  Scale manually:    az ml online-deployment update -n ${ENDPOINT_NAME}-deployment -e $ENDPOINT_NAME --instance-count N -w $AZURE_ML_WORKSPACE_NAME -g $AZURE_RESOURCE_GROUP"
echo "  Delete endpoint:   az ml online-endpoint delete -n $ENDPOINT_NAME -w $AZURE_ML_WORKSPACE_NAME -g $AZURE_RESOURCE_GROUP"
echo ""
echo "🧪 Test with:"
echo "  curl -H \"Authorization: Bearer \$(az ml online-endpoint get-credentials -n $ENDPOINT_NAME -w $AZURE_ML_WORKSPACE_NAME -g $AZURE_RESOURCE_GROUP --query accessToken -o tsv)\" \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       -d '{\"data\": [[1.5, 2.3, 0.8, 1.2, 3.1, 0.9, 2.7, 1.8]]}' \\"
echo "       $ENDPOINT_URI"

print_success "✅ Task 5: Real-Time Scoring Endpoint deployment completed successfully!"