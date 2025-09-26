# Legacy System Integration Gateway

This component provides seamless integration between legacy applications and Azure ML real-time prediction endpoints without requiring code changes to existing legacy systems.

## Overview

The Legacy Integration Gateway acts as a translation layer that:

- **Translates** legacy API formats to Azure ML API requirements
- **Authenticates** legacy systems using multiple authentication methods
- **Handles** errors with enterprise-grade resilience patterns
- **Monitors** performance and provides comprehensive observability
- **Scales** automatically to handle production workloads

## Architecture

```
┌─────────────────┐    ┌──────────────────────┐    ┌──────────────────┐
│  Legacy System  │───▶│  Integration Gateway │───▶│   Azure ML API   │
│                 │    │                      │    │                  │
│ - ERP Systems   │    │ - Auth Bridge        │    │ - Real-time      │
│ - CRM Systems   │    │ - API Translation    │    │   Predictions    │
│ - Custom Apps   │    │ - Error Handling     │    │ - Model Serving  │
│ - Databases     │    │ - Circuit Breakers   │    │ - Monitoring     │
└─────────────────┘    └──────────────────────┘    └──────────────────┘
```

## Key Features

### 🔐 Multi-Method Authentication
- **JWT Bearer Tokens** - Modern token-based authentication
- **API Keys** - Simple key-based authentication for legacy systems
- **Basic Auth** - Username/password authentication
- **Legacy Tokens** - Custom encrypted token format support
- **Azure Key Vault** integration for secure credential storage

### 🔄 Request/Response Translation
- **Automatic Format Conversion** - Legacy formats ↔ Azure ML formats
- **Flexible Schema Mapping** - Configurable field mappings
- **Batch Processing** - Support for bulk prediction requests
- **Correlation Tracking** - End-to-end request correlation

### 🛡️ Enterprise-Grade Resilience
- **Circuit Breakers** - Prevent cascade failures
- **Retry Logic** - Exponential backoff with jitter
- **Rate Limiting** - Protect downstream services
- **Timeout Management** - Configurable timeout policies
- **Health Checks** - Comprehensive service health monitoring

### 📊 Comprehensive Monitoring
- **Real-time Metrics** - Performance and error tracking
- **Azure Application Insights** integration
- **Structured Logging** - JSON-formatted logs with correlation IDs
- **Alerting** - Proactive issue detection and notification
- **Dashboard Integration** - Ready-to-use monitoring dashboards

## Quick Start

### 1. Environment Setup

```bash
# Clone the repository
git clone <repository-url>
cd legacy-integration

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_ML_API_KEY="your-azure-ml-api-key"
export JWT_SECRET_KEY="your-jwt-secret"
```

### 2. Configuration

Create a configuration file or use environment variables:

```yaml
# config.yaml
server:
  host: "0.0.0.0"
  port: 8000
  debug_mode: false

authentication:
  azure:
    use_managed_identity: true
  api_keys:
    "your-api-key":
      user_id: "legacy_system_1"
      username: "legacy_system_1"
      roles: ["user"]
      permissions: ["predict"]

monitoring:
  app_insights_enabled: true
  metrics_enabled: true
```

### 3. Start the Gateway

```bash
# Development mode
python -m uvicorn src.api_gateway:app --reload --host 0.0.0.0 --port 8000

# Production mode
python -m uvicorn src.api_gateway:app --host 0.0.0.0 --port 8000 --workers 4
```

### 4. Test the Integration

```bash
# Health check
curl http://localhost:8000/health

# Prediction request
curl -X POST http://localhost:8000/predict \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "input_data": {
      "feature1": 1.0,
      "feature2": 2.0,
      "feature3": "value"
    },
    "correlation_id": "request-123"
  }'
```

## API Reference

### Authentication

The gateway supports multiple authentication methods:

#### 1. API Key Authentication
```http
Authorization: Bearer your-api-key
```

#### 2. JWT Token Authentication
```http
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...
```

#### 3. Basic Authentication
```http
Authorization: Basic dXNlcm5hbWU6cGFzc3dvcmQ=
```

#### 4. Legacy Token Authentication
```http
Authorization: Legacy encrypted-legacy-token
```

### Endpoints

#### POST /predict
Single prediction request

**Request:**
```json
{
  "input_data": {
    "feature1": 1.0,
    "feature2": "string_value",
    "feature3": true
  },
  "model_id": "optional-model-id",
  "correlation_id": "optional-correlation-id"
}
```

**Response:**
```json
{
  "prediction": 0.85,
  "confidence": 0.92,
  "model_version": "v1.2.3",
  "request_id": "req_1234567890",
  "timestamp": "2024-01-15T10:30:00Z",
  "status": "success"
}
```

#### POST /batch-predict
Batch prediction request

**Request:**
```json
[
  {
    "input_data": {"feature1": 1.0, "feature2": "value1"},
    "correlation_id": "batch-item-1"
  },
  {
    "input_data": {"feature1": 2.0, "feature2": "value2"},
    "correlation_id": "batch-item-2"
  }
]
```

**Response:**
```json
{
  "batch_id": "batch_1234567890",
  "total_requests": 2,
  "successful_predictions": 2,
  "failed_predictions": 0,
  "responses": [
    {
      "prediction": 0.85,
      "confidence": 0.92,
      "request_id": "req_1234567890_batch-item-1",
      "timestamp": "2024-01-15T10:30:00Z",
      "status": "success"
    },
    {
      "prediction": 0.73,
      "confidence": 0.88,
      "request_id": "req_1234567891_batch-item-2",
      "timestamp": "2024-01-15T10:30:01Z",
      "status": "success"
    }
  ]
}
```

#### GET /health
Health check endpoint

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "1.0.0",
  "uptime_seconds": 3600.0,
  "azure_ml_status": "healthy",
  "dependencies": {
    "azure_ml": "healthy",
    "key_vault": "healthy",
    "app_insights": "healthy"
  }
}
```

#### GET /metrics
Service metrics (authenticated)

**Response:**
```json
{
  "requests": {
    "total": 10000,
    "successful": 9850,
    "failed": 150,
    "success_rate": 98.5
  },
  "performance": {
    "avg_response_time": 0.25,
    "p95_response_time": 0.5,
    "p99_response_time": 0.8
  },
  "errors": {
    "total_errors": 150,
    "error_rate_1min": 2.5,
    "errors_by_category": {
      "timeout": 50,
      "azure_ml_error": 30,
      "validation": 70
    }
  }
}
```

## Configuration Reference

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `AZURE_TENANT_ID` | Azure AD tenant ID | - | Yes* |
| `AZURE_CLIENT_ID` | Azure AD client ID | - | Yes* |
| `AZURE_CLIENT_SECRET` | Azure AD client secret | - | Yes* |
| `USE_MANAGED_IDENTITY` | Use Azure Managed Identity | `false` | No |
| `AZURE_ML_API_KEY` | Azure ML API key | - | Yes |
| `KEY_VAULT_URL` | Azure Key Vault URL | - | No |
| `JWT_SECRET_KEY` | JWT signing key | - | Yes |
| `HOST` | Server host | `0.0.0.0` | No |
| `PORT` | Server port | `8000` | No |
| `DEBUG` | Debug mode | `false` | No |
| `LOG_LEVEL` | Logging level | `INFO` | No |
| `CORS_ORIGINS` | CORS allowed origins | `*` | No |
| `MAX_CONCURRENT_REQUESTS` | Max concurrent requests | `100` | No |

*Required unless using managed identity

### Configuration File Format

```yaml
server:
  host: "0.0.0.0"
  port: 8000
  debug_mode: false
  cors_origins: ["*"]
  max_concurrent_requests: 100

authentication:
  jwt:
    algorithm: "HS256"
    verify_signature: true
  azure:
    use_managed_identity: true
  api_keys:
    "api-key-1":
      user_id: "system1"
      username: "system1"
      roles: ["user"]
      permissions: ["predict"]
  basic_auth_users:
    "legacy_user":
      password: "secure_password"
      roles: ["legacy_user"]
      permissions: ["predict"]
  model_endpoints:
    "default":
      endpoint_url: "https://your-endpoint.azureml.net/score"
      api_key: "your-api-key"
      model_name: "your-model"
      model_version: "1"
      deployment_name: "default"

monitoring:
  app_insights_enabled: true
  metrics_enabled: true
  health_check_interval: 30

error_handling:
  circuit_breaker:
    failure_threshold: 5
    recovery_timeout: 30
  retry:
    max_attempts: 3
    backoff_factor: 1.5
  timeouts:
    request_timeout: 30
    azure_ml_timeout: 25
```

## Integration Patterns

### Pattern 1: Direct API Integration

Legacy system makes direct HTTP calls to the gateway:

```python
# Legacy system code (no changes required)
import requests

response = requests.post(
    "http://gateway:8000/predict",
    headers={"Authorization": "Bearer your-api-key"},
    json={"input_data": {"feature1": 1.0, "feature2": "value"}}
)

result = response.json()
prediction = result["prediction"]
```

### Pattern 2: Database Integration

Gateway polls database for prediction requests:

```sql
-- Prediction request table
CREATE TABLE prediction_requests (
    id SERIAL PRIMARY KEY,
    input_data JSONB,
    status VARCHAR(20) DEFAULT 'pending',
    prediction FLOAT,
    confidence FLOAT,
    created_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP
);
```

### Pattern 3: Message Queue Integration

Asynchronous processing via message queues:

```python
# Producer (legacy system)
import pika

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

message = {
    "input_data": {"feature1": 1.0, "feature2": "value"},
    "correlation_id": "request-123"
}

channel.basic_publish(
    exchange='predictions',
    routing_key='predict',
    body=json.dumps(message)
)
```

## Deployment

### Docker Deployment

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY src/ ./src/
COPY config/ ./config/

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "src.api_gateway:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-integration-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: legacy-integration-gateway
  template:
    metadata:
      labels:
        app: legacy-integration-gateway
    spec:
      containers:
      - name: gateway
        image: your-registry/legacy-integration-gateway:latest
        ports:
        - containerPort: 8000
        env:
        - name: USE_MANAGED_IDENTITY
          value: "true"
        - name: AZURE_ML_API_KEY
          valueFrom:
            secretKeyRef:
              name: azure-ml-secret
              key: api-key
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: legacy-integration-gateway-service
spec:
  selector:
    app: legacy-integration-gateway
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
  type: LoadBalancer
```

### Azure Container Instances

```bash
az container create \
  --resource-group myResourceGroup \
  --name legacy-integration-gateway \
  --image your-registry/legacy-integration-gateway:latest \
  --cpu 2 \
  --memory 4 \
  --ports 8000 \
  --environment-variables \
    USE_MANAGED_IDENTITY=true \
    AZURE_ML_API_KEY=your-api-key \
  --restart-policy Always
```

## Monitoring and Observability

### Azure Application Insights Integration

The gateway automatically sends telemetry to Application Insights:

- **Request telemetry** - All HTTP requests with timing and status
- **Dependency telemetry** - Azure ML API calls and database queries
- **Exception telemetry** - All unhandled exceptions with stack traces
- **Custom metrics** - Business metrics like prediction accuracy
- **Custom events** - Important business events and state changes

### Custom Dashboards

Import the provided dashboard templates:

1. **Performance Dashboard** - Response times, throughput, error rates
2. **Error Analysis Dashboard** - Error patterns, root cause analysis
3. **Business Metrics Dashboard** - Prediction volumes, model performance
4. **Infrastructure Dashboard** - Resource utilization, scaling metrics

### Alerting Rules

Configure alerts for:

- **High error rate** - >5% errors in 5 minutes
- **High response time** - >2 seconds average response time
- **Circuit breaker open** - Any circuit breaker opens
- **Low prediction confidence** - Average confidence <70%
- **Azure ML service issues** - Downstream service failures

## Security Considerations

### Authentication Security
- **JWT tokens** validated with proper signature verification
- **API keys** stored securely with proper hashing
- **Legacy tokens** encrypted with strong encryption
- **Azure Key Vault** integration for credential management

### Network Security
- **HTTPS only** in production environments
- **CORS policies** properly configured
- **Rate limiting** to prevent abuse
- **IP whitelisting** for additional security

### Data Security
- **No sensitive data logging** - PII and credentials excluded
- **Request/response encryption** in transit
- **Audit logging** for compliance requirements
- **Data retention policies** properly configured

## Troubleshooting

### Common Issues

#### Authentication Failures
```
Error: 401 Unauthorized
Solution: Check API key validity and permissions
```

#### Timeout Errors
```
Error: 408 Request Timeout
Solution: Check Azure ML endpoint availability and increase timeout
```

#### Rate Limiting
```
Error: 429 Too Many Requests
Solution: Implement client-side rate limiting or request more quota
```

#### Circuit Breaker Open
```
Error: 503 Service Unavailable
Solution: Wait for circuit breaker to close or check downstream service
```

### Debugging Steps

1. **Check health endpoint** - `GET /health`
2. **Review logs** - Check Application Insights or container logs
3. **Verify configuration** - Validate all environment variables
4. **Test Azure ML endpoint** - Direct test to Azure ML API
5. **Check network connectivity** - Verify firewall and DNS settings

### Log Analysis

Use Application Insights queries:

```kusto
// High error rate analysis
requests
| where timestamp > ago(1h)
| summarize
    total = count(),
    errors = countif(success == false),
    error_rate = (countif(success == false) * 100.0 / count())
| where error_rate > 5

// Slow requests analysis
requests
| where timestamp > ago(1h) and duration > 2000
| project timestamp, name, duration, resultCode
| order by duration desc

// Error pattern analysis
exceptions
| where timestamp > ago(1h)
| summarize count() by type, method
| order by count_ desc
```

## Performance Tuning

### Scaling Guidelines

- **Horizontal scaling** - Add more instances for higher throughput
- **Vertical scaling** - Increase CPU/memory for better response times
- **Connection pooling** - Configure appropriate connection limits
- **Caching** - Implement response caching for repeated requests

### Optimization Tips

1. **Batch requests** - Use batch endpoint for bulk operations
2. **Connection reuse** - Enable HTTP connection pooling
3. **Async processing** - Use async/await for better concurrency
4. **Circuit breakers** - Fail fast when downstream services are down
5. **Resource limits** - Set appropriate CPU and memory limits

## Support and Maintenance

### Support Channels
- **Documentation** - https://docs.company.com/legacy-integration
- **Support Email** - ml-support@company.com
- **Status Page** - https://status.company.com
- **Emergency Escalation** - +1-555-EMERGENCY

### Maintenance Windows
- **Scheduled maintenance** - First Sunday of each month, 2-4 AM UTC
- **Emergency patches** - As needed with 24h notice
- **Configuration updates** - No downtime required

### Version History
- **v1.0.0** - Initial release with basic functionality
- **v1.1.0** - Added batch processing support
- **v1.2.0** - Enhanced monitoring and alerting
- **v1.3.0** - Added circuit breaker patterns

This documentation provides comprehensive guidance for implementing and maintaining the Legacy System Integration Gateway.