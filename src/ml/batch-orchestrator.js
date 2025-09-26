/**
 * Batch Scoring Orchestrator
 * Task 4: Implement Batch Scoring Pipeline - Main Integration
 *
 * Orchestrates the complete batch scoring pipeline with all components
 */

import { BatchScoringPipeline } from './batch-scoring-pipeline.js';
import { BatchScheduler } from './batch-scheduler.js';
import { OneLakeConnector } from './onelake-connector.js';
import { PipelineMonitor } from './pipeline-monitor.js';
import { AzurePipelineConfig } from './azure-pipeline-config.js';

export class BatchScoringOrchestrator {
  constructor(options = {}) {
    this.config = {
      enableScheduling: options.enableScheduling !== false,
      enableOneLake: options.enableOneLake !== false,
      enableMonitoring: options.enableMonitoring !== false,
      scheduleTime: options.scheduleTime || '02:00',
      ...options
    };

    // Initialize components
    this.pipeline = new BatchScoringPipeline(options.pipeline);
    this.scheduler = new BatchScheduler(options.scheduler);
    this.oneLakeConnector = new OneLakeConnector(options.oneLake);
    this.monitor = new PipelineMonitor(options.monitoring);
    this.azureConfig = new AzurePipelineConfig(options.azure);

    this.isInitialized = false;
    this.scheduleId = null;
  }

  async initialize() {
    console.log('🚀 Initializing Batch Scoring Orchestrator...');

    try {
      // Load ML models
      await this.loadModels();

      // Configure OneLake if enabled
      if (this.config.enableOneLake) {
        await this.configureOneLake();
      }

      // Set up monitoring if enabled
      if (this.config.enableMonitoring) {
        this.setupMonitoring();
      }

      // Configure scheduling if enabled
      if (this.config.enableScheduling) {
        await this.setupScheduling();
      }

      this.isInitialized = true;
      console.log('✅ Batch Scoring Orchestrator initialized successfully');

      return {
        success: true,
        components: {
          pipeline: 'initialized',
          oneLake: this.config.enableOneLake ? 'configured' : 'disabled',
          monitoring: this.config.enableMonitoring ? 'active' : 'disabled',
          scheduling: this.config.enableScheduling ? 'scheduled' : 'disabled'
        }
      };

    } catch (error) {
      console.error('❌ Initialization failed:', error.message);
      throw error;
    }
  }

  async loadModels() {
    console.log('📦 Loading ML models...');

    const modelConfigs = [
      { type: 'RandomForest', path: './src/ml/models/random-forest.js' },
      { type: 'NeuralNetwork', path: './src/ml/models/neural-network.js' }
    ];

    await this.pipeline.loadModels(modelConfigs);
    console.log(`✓ Loaded ${this.pipeline.models.size} models`);
  }

  async configureOneLake() {
    console.log('🏞️ Configuring OneLake integration...');

    // In real scenario, these would come from Azure Key Vault or environment variables
    const oneLakeConfig = {
      workspaceId: process.env.FABRIC_WORKSPACE_ID || 'demo-workspace',
      lakehouseId: process.env.FABRIC_LAKEHOUSE_ID || 'demo-lakehouse',
      authentication: process.env.FABRIC_AUTH_TOKEN || 'demo-token'
    };

    this.oneLakeConnector.configure(oneLakeConfig);
    console.log('✓ OneLake integration configured');
  }

  setupMonitoring() {
    console.log('📊 Setting up monitoring and alerting...');

    this.monitor.setAlertCallback((alert) => {
      console.log(`🚨 ALERT [${alert.severity}]: ${alert.message}`);

      // In real scenario, would send to Teams, email, etc.
      if (alert.type === 'SLA_VIOLATION') {
        this.handleSLAViolation(alert);
      } else if (alert.type === 'HIGH_ERROR_RATE') {
        this.handleHighErrorRate(alert);
      }
    });

    console.log('✓ Monitoring and alerting configured');
  }

  async setupScheduling() {
    console.log('⏰ Setting up nightly scheduling...');

    const scheduleConfig = {
      frequency: 'daily',
      time: this.config.scheduleTime,
      timezone: 'UTC'
    };

    this.scheduleId = this.scheduler.schedule(scheduleConfig, async (context) => {
      console.log(`🌙 Nightly batch scoring started (${context.executionId})`);
      await this.executeScheduledBatch(context);
    });

    await this.scheduler.start();
    console.log(`✓ Nightly schedule configured for ${this.config.scheduleTime} UTC`);
  }

  async executeScheduledBatch(context) {
    const executionStart = new Date();

    try {
      // Simulate data loading (in real scenario, would load from data lake)
      const batchData = await this.loadBatchData();

      // Execute batch scoring
      const results = await this.executeBatchScoring(batchData, context);

      // Store results in OneLake
      if (this.config.enableOneLake) {
        await this.storeResultsInOneLake(results, context);
      }

      // Record successful execution
      this.recordExecution(executionStart, new Date(), batchData.length, 0);

      console.log(`✅ Scheduled batch scoring completed (${context.executionId})`);

      return {
        success: true,
        executionId: context.executionId,
        recordsProcessed: batchData.length,
        duration: Date.now() - executionStart.getTime()
      };

    } catch (error) {
      console.error(`❌ Scheduled batch scoring failed (${context.executionId}):`, error.message);

      // Record failed execution
      this.recordExecution(executionStart, new Date(), 0, 1);

      throw error;
    }
  }

  async executeBatchScoring(data, context = {}) {
    if (!this.isInitialized) {
      throw new Error('Orchestrator not initialized. Call initialize() first.');
    }

    console.log(`🔄 Processing batch of ${data.length} records...`);

    const results = await this.pipeline.processBatch(data);

    console.log(`✓ Processed ${results.predictions.length} predictions`);
    console.log(`⏱️ Processing time: ${results.metadata.processingTimeMs}ms`);
    console.log(`🎯 SLA compliant: ${results.metadata.slaCompliant}`);

    return {
      ...results,
      executionContext: context
    };
  }

  async storeResultsInOneLake(results, context) {
    console.log('💾 Storing results in OneLake...');

    const predictionData = {
      predictions: results.predictions,
      metadata: {
        ...results.metadata,
        executionId: context.executionId,
        batchId: `batch_${Date.now()}`,
        modelVersion: '1.0'
      }
    };

    const storeResult = await this.oneLakeConnector.storePredictions(predictionData);

    console.log(`✓ Stored ${storeResult.recordCount} predictions in OneLake`);
    console.log(`📍 Path: ${storeResult.lakePath}`);

    return storeResult;
  }

  async loadBatchData() {
    // Simulate loading batch data
    // In real scenario, would load from Azure Data Lake, blob storage, etc.
    const mockData = [];
    const now = new Date();

    for (let i = 0; i < 1000; i++) {
      mockData.push({
        equipmentId: `EQ${String(i + 1).padStart(4, '0')}`,
        timestamp: new Date(now.getTime() - (i * 3600000)).toISOString(),
        temperature: 20 + Math.random() * 30,
        vibration: 1 + Math.random() * 3,
        pressure: 1010 + Math.random() * 10,
        rpm: 1000 + Math.random() * 2000,
        current: 10 + Math.random() * 20
      });
    }

    return mockData;
  }

  recordExecution(startTime, endTime, recordsProcessed, errors) {
    if (this.config.enableMonitoring) {
      this.monitor.recordExecution({
        startTime,
        endTime,
        recordsProcessed,
        errors
      });
    }
  }

  handleSLAViolation(alert) {
    console.log('🚨 SLA Violation detected - taking corrective actions...');
    // In real scenario, would:
    // 1. Scale up compute resources
    // 2. Optimize batch size
    // 3. Notify operations team
    // 4. Trigger diagnostic collection
  }

  handleHighErrorRate(alert) {
    console.log('🚨 High error rate detected - investigating...');
    // In real scenario, would:
    // 1. Check model health
    // 2. Validate input data quality
    // 3. Review compute resource availability
    // 4. Escalate to ML engineering team
  }

  async getStatus() {
    return {
      initialized: this.isInitialized,
      components: {
        pipeline: {
          modelsLoaded: this.pipeline.models.size,
          isInitialized: this.pipeline.isInitialized
        },
        scheduler: {
          isRunning: this.scheduler.isRunning(),
          scheduleCount: this.scheduler.getSchedules().length
        },
        oneLake: {
          isConfigured: this.oneLakeConnector.isConfigured
        },
        monitoring: {
          totalExecutions: this.monitor.getMetrics().totalExecutions,
          healthStatus: this.monitor.getHealthStatus().status
        }
      },
      metrics: this.config.enableMonitoring ? this.monitor.getMetrics() : null
    };
  }

  async shutdown() {
    console.log('🛑 Shutting down Batch Scoring Orchestrator...');

    if (this.scheduler.isRunning()) {
      await this.scheduler.stop();
      console.log('✓ Scheduler stopped');
    }

    console.log('✓ Orchestrator shutdown complete');
  }
}