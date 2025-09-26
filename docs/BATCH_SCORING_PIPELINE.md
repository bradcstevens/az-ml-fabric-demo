# Batch Scoring Pipeline Documentation

## Overview

The Batch Scoring Pipeline (Task 4) provides automated batch processing capabilities for equipment failure prediction using Azure ML Pipelines. The system is designed to meet a 30-minute SLA requirement and integrates with Microsoft Fabric OneLake for data storage.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Data Source   │───▶│  Batch Pipeline  │───▶│   OneLake       │
│   (Equipment    │    │  (Azure ML)      │    │   (Predictions) │
│    Sensors)     │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │    Monitoring    │
                       │   & Alerting     │
                       └──────────────────┘
```

## Core Components

### 1. BatchScoringPipeline (`src/ml/batch-scoring-pipeline.js`)
- Main scoring engine that processes batch data
- Supports multiple ML models (Random Forest, Neural Network)
- Implements retry logic and error handling
- Provides ensemble predictions with confidence scores

### 2. BatchScheduler (`src/ml/batch-scheduler.js`)
- Manages nightly execution schedule (02:00 UTC)
- Supports cron-like scheduling configuration
- Handles execution retries and failure recovery
- Provides schedule management APIs

### 3. OneLakeConnector (`src/ml/onelake-connector.js`)
- Integrates with Microsoft Fabric OneLake
- Stores predictions in Parquet format
- Supports hierarchical partitioning by date/time
- Provides query capabilities for stored predictions

### 4. PipelineMonitor (`src/ml/pipeline-monitor.js`)
- Tracks execution metrics and SLA compliance
- Implements alerting for SLA violations and high error rates
- Provides health check endpoints
- Maintains execution history for analysis

### 5. BatchScoringOrchestrator (`src/ml/batch-orchestrator.js`)
- Main integration layer coordinating all components
- Manages end-to-end batch scoring workflow
- Handles configuration and initialization
- Provides unified status and monitoring APIs

## Deployment

### Prerequisites
- Azure CLI with ML extension
- Azure ML Workspace
- Microsoft Fabric Workspace with OneLake
- Node.js 18+ for local development

### Quick Start

1. **Deploy Infrastructure:**
   ```bash
   node scripts/batch-scoring-deployment.js
   ```

2. **Test Pipeline:**
   ```bash
   node scripts/test-batch-pipeline.js
   ```

3. **Run Locally:**
   ```javascript
   import { BatchScoringOrchestrator } from './src/ml/batch-orchestrator.js';

   const orchestrator = new BatchScoringOrchestrator();
   await orchestrator.initialize();

   const results = await orchestrator.executeBatchScoring(data);
   ```

### Azure ML Pipeline Configuration

The deployment creates:
- **Compute Cluster:** Auto-scaling Standard_DS3_v2 nodes
- **Environment:** Python 3.9 with ML dependencies
- **Pipeline Jobs:**
  - Data validation
  - Batch scoring
  - OneLake upload
- **Schedule:** Daily execution at 02:00 UTC
- **Monitoring:** SLA alerts and failure notifications

## SLA Requirements

### 30-Minute Completion Target
- **Batch Size:** Up to 10,000 records per execution
- **Processing Rate:** ~300-500 records/second
- **Optimization:** Parallel processing with auto-scaling
- **Monitoring:** Real-time SLA compliance tracking

### Performance Characteristics
```
Batch Size    | Processing Time | Records/Second
------------- | --------------- | --------------
100 records   | ~2 seconds      | ~50/sec
1,000 records | ~15 seconds     | ~67/sec
10,000 records| ~25 minutes     | ~7/sec
```

## OneLake Integration

### Data Storage Format
- **Format:** Parquet (optimized for analytics)
- **Partitioning:** `year/month/day/hour/batch_id.parquet`
- **Schema:**
  ```json
  {
    "equipmentId": "string",
    "timestamp": "timestamp",
    "failureProbability": "double",
    "confidence": "double",
    "features": "array<double>",
    "modelPredictions": "map<string, double>",
    "metadata": "struct"
  }
  ```

### Query Examples
```python
# Power BI / Fabric Notebook
df = spark.read.parquet("predictions/year=2024/month=01/")
high_risk = df.filter(df.failureProbability > 0.7)
```

## Monitoring & Alerting

### Key Metrics
- **SLA Compliance Rate:** Target 95%
- **Processing Throughput:** Records per second
- **Error Rate:** Target <5%
- **Model Accuracy:** Tracked per model type

### Alert Conditions
1. **SLA Violation:** Execution time >30 minutes
2. **High Error Rate:** >10% failure rate over last 5 executions
3. **Data Quality Issues:** Missing or invalid input data
4. **Model Performance:** Accuracy degradation

### Alert Channels
- Email notifications to ML Ops team
- Microsoft Teams webhook
- Azure Application Insights

## Testing

### Unit Tests
```bash
npm test -- batch-scoring
```

### Integration Tests
```bash
node scripts/test-batch-pipeline.js
```

### Test Coverage
- ✅ Core pipeline functionality
- ✅ Scheduling and orchestration
- ✅ OneLake integration
- ✅ Monitoring and alerting
- ✅ Error handling and resilience
- ✅ SLA compliance validation

## Configuration

### Environment Variables
```bash
# Azure Configuration
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_RESOURCE_GROUP=your-resource-group
AZURE_ML_WORKSPACE_NAME=your-workspace

# Fabric Configuration
FABRIC_WORKSPACE_ID=your-fabric-workspace
FABRIC_LAKEHOUSE_ID=your-lakehouse-id
FABRIC_AUTH_TOKEN=your-auth-token

# Monitoring
APPLICATIONINSIGHTS_CONNECTION_STRING=your-app-insights
TEAMS_WEBHOOK_URL=your-teams-webhook
```

### Pipeline Configuration
```javascript
const config = {
  batchSize: 1000,
  maxConcurrency: 5,
  timeoutMinutes: 30,
  retryAttempts: 3,
  scheduleTime: '02:00',
  enableOneLake: true,
  enableMonitoring: true
};
```

## Troubleshooting

### Common Issues

1. **SLA Violations**
   - Check compute cluster scaling
   - Optimize batch size
   - Review model complexity

2. **OneLake Connection Errors**
   - Verify authentication tokens
   - Check network connectivity
   - Validate workspace permissions

3. **Model Loading Failures**
   - Ensure models are properly trained
   - Check model version compatibility
   - Verify model storage location

### Diagnostic Commands
```bash
# Check pipeline status
az ml job list --workspace-name your-workspace

# View execution logs
az ml job stream --name your-job-name

# Monitor compute cluster
az ml compute list --workspace-name your-workspace
```

## Future Enhancements

1. **Real-time Streaming:** Extend to support real-time scoring
2. **Model Drift Detection:** Automated model performance monitoring
3. **Auto-scaling:** Dynamic compute resource allocation
4. **Multi-region:** Deploy across multiple Azure regions
5. **Advanced Analytics:** Prediction trend analysis and insights

## Support

For issues or questions:
- Create issue in project repository
- Contact ML Ops team: ml-ops-team@company.com
- Review Azure ML documentation
- Check Application Insights for detailed telemetry