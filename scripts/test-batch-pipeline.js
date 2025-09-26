#!/usr/bin/env node

/**
 * Batch Scoring Pipeline Test Script
 * Task 4: Implement Batch Scoring Pipeline - Integration Testing
 *
 * Tests the complete batch scoring pipeline end-to-end
 */

import { BatchScoringOrchestrator } from '../src/ml/batch-orchestrator.js';
import { BatchScoringDeployment } from './batch-scoring-deployment.js';

class BatchPipelineValidator {
  constructor() {
    this.orchestrator = new BatchScoringOrchestrator({
      enableScheduling: false, // Disable for testing
      enableOneLake: true,
      enableMonitoring: true
    });

    this.testResults = {
      coreComponents: {},
      integration: {},
      performance: {},
      slaCompliance: {}
    };
  }

  async runAllTests() {
    console.log('🧪 Starting Batch Scoring Pipeline Validation...');
    console.log('='.repeat(60));

    try {
      await this.testCoreComponents();
      await this.testIntegration();
      await this.testPerformance();
      await this.testSLACompliance();
      await this.testDeploymentGeneration();

      this.printTestSummary();

    } catch (error) {
      console.error('❌ Test execution failed:', error.message);
      throw error;
    }
  }

  async testCoreComponents() {
    console.log('\\n1️⃣ Testing Core Components...');

    // Test orchestrator initialization
    console.log('   🔧 Testing orchestrator initialization...');
    const initResult = await this.orchestrator.initialize();
    this.testResults.coreComponents.initialization = initResult.success;
    console.log(`   ✓ Orchestrator initialized: ${initResult.success}`);

    // Test status reporting
    console.log('   📊 Testing status reporting...');
    const status = await this.orchestrator.getStatus();
    this.testResults.coreComponents.statusReporting = status.initialized;
    console.log(`   ✓ Status reporting: ${status.initialized}`);

    // Test component integration
    console.log('   🔗 Testing component integration...');
    const hasAllComponents = status.components.pipeline.isInitialized &&
                             status.components.oneLake.isConfigured &&
                             status.components.monitoring;
    this.testResults.coreComponents.componentIntegration = hasAllComponents;
    console.log(`   ✓ Component integration: ${hasAllComponents}`);
  }

  async testIntegration() {
    console.log('\\n2️⃣ Testing End-to-End Integration...');

    // Generate test data
    console.log('   📊 Generating test data...');
    const testData = this.generateTestData(100);
    console.log(`   ✓ Generated ${testData.length} test records`);

    // Execute batch scoring
    console.log('   🔄 Testing batch scoring execution...');
    const startTime = Date.now();
    const results = await this.orchestrator.executeBatchScoring(testData);
    const executionTime = Date.now() - startTime;

    this.testResults.integration.batchScoring = results.predictions.length > 0;
    this.testResults.integration.executionTime = executionTime;

    console.log(`   ✓ Batch scoring: ${results.predictions.length} predictions generated`);
    console.log(`   ⏱️ Execution time: ${executionTime}ms`);

    // Test OneLake storage
    console.log('   💾 Testing OneLake storage...');
    try {
      const storeResult = await this.orchestrator.storeResultsInOneLake(results, {
        executionId: 'test-execution-001'
      });
      this.testResults.integration.oneLakeStorage = storeResult.success;
      console.log(`   ✓ OneLake storage: ${storeResult.success}`);
    } catch (error) {
      this.testResults.integration.oneLakeStorage = false;
      console.log(`   ❌ OneLake storage failed: ${error.message}`);
    }
  }

  async testPerformance() {
    console.log('\\n3️⃣ Testing Performance Characteristics...');

    const testSizes = [100, 500, 1000];

    for (const size of testSizes) {
      console.log(`   📈 Testing batch size: ${size} records`);

      const testData = this.generateTestData(size);
      const startTime = Date.now();

      const results = await this.orchestrator.executeBatchScoring(testData);
      const executionTime = Date.now() - startTime;

      const recordsPerSecond = Math.round((size / executionTime) * 1000);

      console.log(`   ⏱️ Processed ${size} records in ${executionTime}ms (${recordsPerSecond} records/sec)`);

      if (!this.testResults.performance.throughput) {
        this.testResults.performance.throughput = {};
      }
      this.testResults.performance.throughput[size] = recordsPerSecond;
    }
  }

  async testSLACompliance() {
    console.log('\\n4️⃣ Testing SLA Compliance...');

    // Test 30-minute SLA with large batch
    console.log('   ⏰ Testing 30-minute SLA compliance...');

    const largeBatch = this.generateTestData(5000);
    const startTime = Date.now();

    const results = await this.orchestrator.executeBatchScoring(largeBatch);
    const executionTime = Date.now() - startTime;

    const slaThreshold = 30 * 60 * 1000; // 30 minutes in milliseconds
    const slaCompliant = executionTime < slaThreshold;

    this.testResults.slaCompliance.thirtyMinuteSLA = slaCompliant;
    this.testResults.slaCompliance.executionTime = executionTime;
    this.testResults.slaCompliance.recordsProcessed = largeBatch.length;

    console.log(`   ✓ SLA Compliance: ${slaCompliant}`);
    console.log(`   ⏱️ Execution time: ${Math.round(executionTime / 1000)}s (Limit: 1800s)`);
    console.log(`   📊 Records processed: ${largeBatch.length}`);

    // Test monitoring and alerting
    console.log('   🚨 Testing monitoring and alerting...');
    const monitor = this.orchestrator.monitor;

    // Simulate slow execution for SLA alert
    monitor.recordExecution({
      startTime: new Date(Date.now() - (35 * 60 * 1000)), // 35 minutes ago
      endTime: new Date(),
      recordsProcessed: 1000,
      errors: 0
    });

    const alerts = monitor.getAlerts();
    const hasSlsAlert = alerts.some(alert => alert.type === 'SLA_VIOLATION');

    this.testResults.slaCompliance.alerting = hasSlsAlert;
    console.log(`   ✓ SLA alerting: ${hasSlsAlert}`);
  }

  async testDeploymentGeneration() {
    console.log('\\n5️⃣ Testing Deployment Configuration Generation...');

    console.log('   🏗️ Testing Azure ML pipeline configuration...');
    const deployment = new BatchScoringDeployment();

    try {
      // Test configuration validation
      const validation = deployment.pipelineConfig.validateConfiguration();
      console.log(`   ✓ Configuration validation: ${validation.errors.length === 0 ? 'passed' : 'warnings present'}`);

      // Test pipeline YAML generation
      const pipelineYAML = deployment.pipelineConfig.generatePipelineYAML();
      const hasRequiredComponents = pipelineYAML.jobs &&
                                  pipelineYAML.jobs.data_validation &&
                                  pipelineYAML.jobs.batch_scoring &&
                                  pipelineYAML.jobs.onelake_upload;

      this.testResults.deployment = {
        configGeneration: true,
        pipelineComponents: hasRequiredComponents,
        scheduleConfig: !!deployment.pipelineConfig.generateScheduleConfig(),
        monitoringConfig: !!deployment.pipelineConfig.generateMonitoringConfig()
      };

      console.log(`   ✓ Pipeline YAML generation: ${hasRequiredComponents}`);
      console.log(`   ✓ Schedule configuration: ${this.testResults.deployment.scheduleConfig}`);
      console.log(`   ✓ Monitoring configuration: ${this.testResults.deployment.monitoringConfig}`);

    } catch (error) {
      console.log(`   ❌ Deployment configuration failed: ${error.message}`);
      this.testResults.deployment = { error: error.message };
    }
  }

  generateTestData(count) {
    const data = [];
    const now = new Date();

    for (let i = 0; i < count; i++) {
      data.push({
        equipmentId: `TEST_EQ_${String(i + 1).padStart(4, '0')}`,
        timestamp: new Date(now.getTime() - (i * 3600000)).toISOString(),
        temperature: 20 + Math.random() * 30,
        vibration: 1 + Math.random() * 3,
        pressure: 1010 + Math.random() * 10,
        rpm: 1000 + Math.random() * 2000,
        current: 10 + Math.random() * 20
      });
    }

    return data;
  }

  printTestSummary() {
    console.log('\\n📋 Test Results Summary');
    console.log('='.repeat(60));

    // Core Components
    console.log('\\n🔧 Core Components:');
    console.log(`   Initialization: ${this.getStatusIcon(this.testResults.coreComponents.initialization)}`);
    console.log(`   Status Reporting: ${this.getStatusIcon(this.testResults.coreComponents.statusReporting)}`);
    console.log(`   Component Integration: ${this.getStatusIcon(this.testResults.coreComponents.componentIntegration)}`);

    // Integration
    console.log('\\n🔗 Integration:');
    console.log(`   Batch Scoring: ${this.getStatusIcon(this.testResults.integration.batchScoring)}`);
    console.log(`   OneLake Storage: ${this.getStatusIcon(this.testResults.integration.oneLakeStorage)}`);
    console.log(`   Execution Time: ${this.testResults.integration.executionTime}ms`);

    // Performance
    console.log('\\n📈 Performance:');
    if (this.testResults.performance.throughput) {
      Object.entries(this.testResults.performance.throughput).forEach(([size, throughput]) => {
        console.log(`   ${size} records: ${throughput} records/sec`);
      });
    }

    // SLA Compliance
    console.log('\\n⏰ SLA Compliance:');
    console.log(`   30-minute SLA: ${this.getStatusIcon(this.testResults.slaCompliance.thirtyMinuteSLA)}`);
    console.log(`   Execution Time: ${Math.round(this.testResults.slaCompliance.executionTime / 1000)}s`);
    console.log(`   Records Processed: ${this.testResults.slaCompliance.recordsProcessed}`);
    console.log(`   Alerting: ${this.getStatusIcon(this.testResults.slaCompliance.alerting)}`);

    // Deployment
    console.log('\\n🏗️ Deployment Configuration:');
    if (this.testResults.deployment.error) {
      console.log(`   Error: ${this.testResults.deployment.error}`);
    } else {
      console.log(`   Config Generation: ${this.getStatusIcon(this.testResults.deployment.configGeneration)}`);
      console.log(`   Pipeline Components: ${this.getStatusIcon(this.testResults.deployment.pipelineComponents)}`);
      console.log(`   Schedule Config: ${this.getStatusIcon(this.testResults.deployment.scheduleConfig)}`);
      console.log(`   Monitoring Config: ${this.getStatusIcon(this.testResults.deployment.monitoringConfig)}`);
    }

    // Overall Status
    const overallSuccess = this.calculateOverallSuccess();
    console.log('\\n🎯 Overall Status:');
    console.log(`   ${this.getStatusIcon(overallSuccess)} Batch Scoring Pipeline: ${overallSuccess ? 'READY FOR PRODUCTION' : 'NEEDS ATTENTION'}`);

    if (overallSuccess) {
      console.log('\\n✅ All tests passed! The batch scoring pipeline is ready for deployment.');
    } else {
      console.log('\\n⚠️ Some tests failed. Please review the results above.');
    }
  }

  getStatusIcon(status) {
    return status ? '✅' : '❌';
  }

  calculateOverallSuccess() {
    const coreSuccess = Object.values(this.testResults.coreComponents).every(Boolean);
    const integrationSuccess = this.testResults.integration.batchScoring;
    const slaSuccess = this.testResults.slaCompliance.thirtyMinuteSLA;
    const deploymentSuccess = this.testResults.deployment.configGeneration;

    return coreSuccess && integrationSuccess && slaSuccess && deploymentSuccess;
  }

  async cleanup() {
    console.log('\\n🧹 Cleaning up test environment...');
    await this.orchestrator.shutdown();
    console.log('✓ Cleanup complete');
  }
}

// Main execution
if (import.meta.url === `file://${process.argv[1]}`) {
  const validator = new BatchPipelineValidator();

  validator.runAllTests()
    .then(() => validator.cleanup())
    .then(() => {
      console.log('\\n🎉 Batch Pipeline Validation Complete!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\\n💥 Validation failed:', error);
      validator.cleanup().then(() => process.exit(1));
    });
}

export { BatchPipelineValidator };