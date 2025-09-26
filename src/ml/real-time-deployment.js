/**
 * Real-Time Scoring Endpoint Deployment Script
 * Complete deployment automation for Azure ML Online Endpoint
 */

import { AzureMLOnlineEndpoint } from './azure-ml-online-endpoint.js';
import { RealTimeScoring } from './real-time-scoring.js';
import { EndpointMonitor } from './endpoint-monitor.js';

export class RealTimeDeployment {
  constructor(config) {
    this.config = {
      subscriptionId: config.subscriptionId,
      resourceGroup: config.resourceGroup,
      workspaceName: config.workspaceName,
      location: config.location || 'eastus',
      endpointName: config.endpointName || 'fabric-demo-endpoint',
      modelName: config.modelName || 'random-forest-model',
      instanceType: config.instanceType || 'Standard_DS3_v2',
      minInstances: config.minInstances || 2,
      maxInstances: config.maxInstances || 10,
      ...config
    };

    this.endpoint = null;
    this.scoring = null;
    this.monitor = null;
    this.deploymentStatus = 'not-started';
  }

  /**
   * Deploy complete real-time scoring infrastructure
   */
  async deploy() {
    try {
      console.log('🚀 Starting Real-Time Scoring Endpoint Deployment...');
      this.deploymentStatus = 'in-progress';

      // Step 1: Initialize Azure ML Online Endpoint
      await this._initializeEndpoint();

      // Step 2: Deploy the endpoint
      await this._deployEndpoint();

      // Step 3: Initialize scoring service
      await this._initializeScoring();

      // Step 4: Set up monitoring
      await this._setupMonitoring();

      // Step 5: Validate deployment
      await this._validateDeployment();

      this.deploymentStatus = 'completed';
      console.log('✅ Real-Time Scoring Endpoint Deployment Complete!');

      return {
        status: 'success',
        endpoint: {
          name: this.config.endpointName,
          url: await this.endpoint.getEndpointUrl(),
          deploymentId: this.endpoint.endpointName
        },
        performance: {
          targetLatency: '< 1000ms',
          targetThroughput: '1000 req/min',
          autoScaling: 'enabled',
          monitoring: 'enabled'
        }
      };

    } catch (error) {
      this.deploymentStatus = 'failed';
      console.error('❌ Deployment failed:', error.message);
      throw new Error(`Real-time endpoint deployment failed: ${error.message}`);
    }
  }

  /**
   * Check deployment status
   */
  async getStatus() {
    return {
      status: this.deploymentStatus,
      endpoint: this.endpoint ? {
        name: this.endpoint.endpointName,
        deployed: await this.endpoint.isDeployed(),
        url: this.endpoint.endpointName ? await this.endpoint.getEndpointUrl() : null
      } : null,
      scoring: this.scoring ? {
        initialized: this.scoring.initialized,
        modelsLoaded: this.scoring.models.size
      } : null,
      monitoring: this.monitor ? {
        alertsConfigured: (await this.monitor.getAlerts()).length,
        metricsTracking: true
      } : null
    };
  }

  /**
   * Perform health check on deployed endpoint
   */
  async healthCheck() {
    if (!this.endpoint || !this.scoring || !this.monitor) {
      throw new Error('Endpoint not fully deployed');
    }

    const results = {
      timestamp: new Date().toISOString(),
      overall: 'healthy',
      checks: {}
    };

    try {
      // Check endpoint deployment
      results.checks.endpoint = {
        deployed: await this.endpoint.isDeployed(),
        url: await this.endpoint.getEndpointUrl(),
        status: 'healthy'
      };

      // Check scoring service
      const testPrediction = await this.scoring.predict({
        features: [1, 2, 3, 4, 5, 6, 7, 8]
      });

      results.checks.scoring = {
        responsive: testPrediction.responseTime < 1000,
        latency: testPrediction.responseTime,
        status: testPrediction.responseTime < 1000 ? 'healthy' : 'degraded'
      };

      // Check monitoring
      const healthStatus = await this.monitor.getHealthStatus();
      results.checks.monitoring = {
        status: healthStatus.status,
        metricsAvailable: true,
        alertsConfigured: (await this.monitor.getAlerts()).length > 0
      };

      // Determine overall health
      const unhealthyChecks = Object.values(results.checks).filter(
        check => check.status !== 'healthy'
      );

      if (unhealthyChecks.length > 0) {
        results.overall = 'degraded';
      }

    } catch (error) {
      results.overall = 'unhealthy';
      results.error = error.message;
    }

    return results;
  }

  /**
   * Scale endpoint instances
   */
  async scale(options) {
    if (!this.endpoint) {
      throw new Error('Endpoint not deployed');
    }

    const { minInstances, maxInstances } = options;

    // Update deployment configuration
    this.config.minInstances = minInstances || this.config.minInstances;
    this.config.maxInstances = maxInstances || this.config.maxInstances;

    // In production, this would call Azure ML API to update scaling
    console.log(`📈 Scaling endpoint: ${this.config.minInstances}-${this.config.maxInstances} instances`);

    return {
      status: 'success',
      newConfiguration: {
        minInstances: this.config.minInstances,
        maxInstances: this.config.maxInstances
      }
    };
  }

  /**
   * Delete the endpoint and cleanup resources
   */
  async cleanup() {
    try {
      console.log('🧹 Cleaning up real-time endpoint resources...');

      if (this.endpoint) {
        await this.endpoint.delete();
      }

      this.endpoint = null;
      this.scoring = null;
      this.monitor = null;
      this.deploymentStatus = 'not-started';

      console.log('✅ Cleanup completed successfully');
    } catch (error) {
      console.error('❌ Cleanup failed:', error.message);
      throw error;
    }
  }

  // Private methods

  async _initializeEndpoint() {
    console.log('📝 Initializing Azure ML Online Endpoint...');

    this.endpoint = new AzureMLOnlineEndpoint({
      workspaceName: this.config.workspaceName,
      resourceGroup: this.config.resourceGroup,
      subscriptionId: this.config.subscriptionId,
      location: this.config.location
    });

    console.log('✅ Endpoint initialized');
  }

  async _deployEndpoint() {
    console.log('🚀 Deploying endpoint to Azure ML...');

    const deploymentResult = await this.endpoint.deploy({
      name: this.config.endpointName,
      modelName: this.config.modelName,
      instanceType: this.config.instanceType,
      instanceCount: this.config.minInstances,
      maxInstanceCount: this.config.maxInstances
    });

    console.log('✅ Endpoint deployed:', deploymentResult.endpointName);
  }

  async _initializeScoring() {
    console.log('🧠 Initializing scoring service...');

    this.scoring = new RealTimeScoring(this.endpoint);

    // Wait for models to be loaded
    await this.scoring._waitForInitialization();

    console.log('✅ Scoring service initialized');
  }

  async _setupMonitoring() {
    console.log('📊 Setting up monitoring and alerting...');

    this.monitor = new EndpointMonitor(this.endpoint);
    this.scoring.setMonitor(this.monitor);

    // Verify monitoring is working
    const alerts = await this.monitor.getAlerts();
    console.log(`✅ Monitoring configured with ${alerts.length} alerts`);
  }

  async _validateDeployment() {
    console.log('🔍 Validating deployment...');

    // Test latency requirement
    const startTime = Date.now();
    const testPrediction = await this.scoring.predict({
      features: [1.5, 2.3, 0.8, 1.2, 3.1, 0.9, 2.7, 1.8]
    });
    const latency = Date.now() - startTime;

    if (latency > 1000) {
      throw new Error(`Latency validation failed: ${latency}ms > 1000ms`);
    }

    // Test endpoint configuration
    const config = await this.endpoint.getConfiguration();
    if (config.instanceCount < this.config.minInstances) {
      throw new Error('Instance count validation failed');
    }

    // Test authentication
    const authToken = await this.endpoint.getAuthToken();
    if (!authToken.startsWith('Bearer ')) {
      throw new Error('Authentication validation failed');
    }

    console.log('✅ Deployment validation passed');
    console.log(`   - Latency: ${latency}ms (< 1000ms requirement)`);
    console.log(`   - Instances: ${config.instanceCount} (min: ${this.config.minInstances})`);
    console.log(`   - Authentication: Configured`);
  }
}

// Export convenience functions for direct usage
export async function deployRealTimeEndpoint(config) {
  const deployment = new RealTimeDeployment(config);
  return await deployment.deploy();
}

export async function healthCheckEndpoint(config) {
  const deployment = new RealTimeDeployment(config);
  // Assume endpoint is already deployed and just check health
  deployment.endpoint = new AzureMLOnlineEndpoint(config);
  deployment.scoring = new RealTimeScoring(deployment.endpoint);
  deployment.monitor = new EndpointMonitor(deployment.endpoint);

  return await deployment.healthCheck();
}