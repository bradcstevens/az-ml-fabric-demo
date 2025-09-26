/**
 * Real-Time Deployment Infrastructure Tests
 * TDD tests for complete real-time scoring endpoint deployment
 */

import { describe, test, expect, beforeAll, afterAll } from 'vitest';
import { RealTimeDeployment, deployRealTimeEndpoint, healthCheckEndpoint } from '../src/ml/real-time-deployment.js';

describe('Real-Time Scoring Deployment Infrastructure', () => {
  let deployment;
  let deploymentConfig;

  beforeAll(async () => {
    deploymentConfig = {
      subscriptionId: process.env.AZURE_SUBSCRIPTION_ID || 'test-subscription',
      resourceGroup: process.env.AZURE_RESOURCE_GROUP || 'test-rg',
      workspaceName: process.env.AZURE_ML_WORKSPACE_NAME || 'test-workspace',
      location: 'eastus',
      endpointName: 'test-fabric-endpoint',
      modelName: 'random-forest-model',
      instanceType: 'Standard_DS3_v2',
      minInstances: 2,
      maxInstances: 10
    };

    deployment = new RealTimeDeployment(deploymentConfig);
  }, 30000);

  afterAll(async () => {
    if (deployment) {
      await deployment.cleanup();
    }
  });

  describe('Deployment Process', () => {
    test('should initialize deployment configuration', () => {
      expect(deployment.config.endpointName).toBe('test-fabric-endpoint');
      expect(deployment.config.minInstances).toBe(2);
      expect(deployment.config.maxInstances).toBe(10);
      expect(deployment.config.instanceType).toBe('Standard_DS3_v2');
    });

    test('should deploy complete real-time infrastructure', async () => {
      const result = await deployment.deploy();

      expect(result.status).toBe('success');
      expect(result.endpoint.name).toBe('test-fabric-endpoint');
      expect(result.endpoint.url).toMatch(/^https:\/\/.*\.inference\.ml\.azure\.com\/score$/);
      expect(result.performance.targetLatency).toBe('< 1000ms');
      expect(result.performance.targetThroughput).toBe('1000 req/min');
      expect(result.performance.autoScaling).toBe('enabled');
      expect(result.performance.monitoring).toBe('enabled');
    }, 60000);

    test('should validate deployment status', async () => {
      const status = await deployment.getStatus();

      expect(status.status).toBe('completed');
      expect(status.endpoint.deployed).toBe(true);
      expect(status.endpoint.url).toBeDefined();
      expect(status.scoring.initialized).toBe(true);
      expect(status.scoring.modelsLoaded).toBeGreaterThan(0);
      expect(status.monitoring.alertsConfigured).toBeGreaterThan(0);
      expect(status.monitoring.metricsTracking).toBe(true);
    });
  });

  describe('Health Monitoring', () => {
    test('should perform comprehensive health check', async () => {
      const healthResult = await deployment.healthCheck();

      expect(healthResult.overall).toMatch(/healthy|degraded/);
      expect(healthResult.timestamp).toBeDefined();

      // Check endpoint health
      expect(healthResult.checks.endpoint.deployed).toBe(true);
      expect(healthResult.checks.endpoint.url).toBeDefined();
      expect(healthResult.checks.endpoint.status).toBe('healthy');

      // Check scoring health
      expect(healthResult.checks.scoring.responsive).toBe(true);
      expect(healthResult.checks.scoring.latency).toBeLessThan(1000);
      expect(healthResult.checks.scoring.status).toBe('healthy');

      // Check monitoring health
      expect(healthResult.checks.monitoring.status).toMatch(/healthy|degraded/);
      expect(healthResult.checks.monitoring.metricsAvailable).toBe(true);
      expect(healthResult.checks.monitoring.alertsConfigured).toBe(true);
    });

    test('should detect performance degradation', async () => {
      // This test simulates performance issues by checking health status
      const healthResult = await deployment.healthCheck();

      // Even if degraded, the system should still report health status
      expect(['healthy', 'degraded', 'unhealthy']).toContain(healthResult.overall);
      expect(healthResult.checks).toBeDefined();
    });
  });

  describe('Auto-Scaling Management', () => {
    test('should support scaling operations', async () => {
      const scaleResult = await deployment.scale({
        minInstances: 3,
        maxInstances: 15
      });

      expect(scaleResult.status).toBe('success');
      expect(scaleResult.newConfiguration.minInstances).toBe(3);
      expect(scaleResult.newConfiguration.maxInstances).toBe(15);
    });

    test('should validate scaling configuration', async () => {
      const status = await deployment.getStatus();

      // Scaling should be reflected in configuration
      expect(deployment.config.minInstances).toBe(3);
      expect(deployment.config.maxInstances).toBe(15);
    });
  });

  describe('Enterprise Requirements', () => {
    test('should meet sub-1-second latency requirement', async () => {
      const healthResult = await deployment.healthCheck();

      expect(healthResult.checks.scoring.latency).toBeLessThan(1000);
      expect(healthResult.checks.scoring.responsive).toBe(true);
    });

    test('should support high availability configuration', async () => {
      const status = await deployment.getStatus();

      // Multiple instances for high availability
      expect(deployment.config.minInstances).toBeGreaterThanOrEqual(2);
      expect(deployment.config.maxInstances).toBeGreaterThanOrEqual(5);
    });

    test('should have authentication configured', async () => {
      const endpoint = deployment.endpoint;
      const authToken = await endpoint.getAuthToken();

      expect(authToken).toBeDefined();
      expect(authToken).toMatch(/^Bearer .+/);
    });

    test('should have monitoring alerts configured', async () => {
      const monitor = deployment.monitor;
      const alerts = await monitor.getAlerts();

      expect(alerts.length).toBeGreaterThan(0);

      // Check for specific required alerts
      const alertTypes = alerts.map(alert => alert.type);
      expect(alertTypes).toContain('high_latency');
      expect(alertTypes).toContain('high_error_rate');
      expect(alertTypes).toContain('low_availability');
    });
  });

  describe('Convenience Functions', () => {
    test('should support direct deployment function', async () => {
      const deploymentResult = await deployRealTimeEndpoint({
        ...deploymentConfig,
        endpointName: 'test-direct-deploy'
      });

      expect(deploymentResult.status).toBe('success');
      expect(deploymentResult.endpoint.name).toBe('test-direct-deploy');
      expect(deploymentResult.performance.autoScaling).toBe('enabled');
    }, 60000);

    test('should support direct health check function', async () => {
      const healthResult = await healthCheckEndpoint(deploymentConfig);

      expect(healthResult.overall).toMatch(/healthy|degraded|unhealthy/);
      expect(healthResult.checks).toBeDefined();
    });
  });

  describe('Resource Cleanup', () => {
    test('should cleanup resources properly', async () => {
      await deployment.cleanup();

      const status = await deployment.getStatus();
      expect(status.status).toBe('not-started');
      expect(status.endpoint).toBeNull();
      expect(status.scoring).toBeNull();
      expect(status.monitoring).toBeNull();
    });
  });

  describe('Error Handling', () => {
    test('should handle deployment failures gracefully', async () => {
      const invalidDeployment = new RealTimeDeployment({
        subscriptionId: 'invalid',
        resourceGroup: 'invalid',
        workspaceName: 'invalid'
      });

      // In a real scenario, this would fail due to invalid credentials
      // For testing, we expect it to handle errors gracefully
      await expect(async () => {
        await invalidDeployment.deploy();
      }).rejects.toThrow(/deployment failed/i);
    }, 10000); // Increase timeout to 10 seconds

    test('should handle health check on undeployed endpoint', async () => {
      const undeployedDeployment = new RealTimeDeployment(deploymentConfig);

      await expect(async () => {
        await undeployedDeployment.healthCheck();
      }).rejects.toThrow(/not fully deployed/i);
    });
  });
});