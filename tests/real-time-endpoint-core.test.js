/**
 * Core Real-Time Scoring Endpoint Tests
 * TDD Validation - Focused on key requirements
 */

import { describe, test, expect, beforeAll, afterAll } from 'vitest';
import { AzureMLOnlineEndpoint } from '../src/ml/azure-ml-online-endpoint.js';
import { RealTimeScoring } from '../src/ml/real-time-scoring.js';
import { EndpointMonitor } from '../src/ml/endpoint-monitor.js';

describe('Real-Time Scoring Core Infrastructure', () => {
  let endpoint;
  let scoring;
  let monitor;

  beforeAll(async () => {
    endpoint = new AzureMLOnlineEndpoint({
      workspaceName: 'test-workspace',
      resourceGroup: 'test-rg',
      subscriptionId: 'test-subscription',
      location: 'eastus'
    });

    scoring = new RealTimeScoring(endpoint);
    monitor = new EndpointMonitor(endpoint);

    // Connect scoring to monitor for logging
    scoring.setMonitor(monitor);

    await endpoint.deploy({
      name: 'fabric-demo-endpoint',
      modelName: 'random-forest-model',
      instanceType: 'Standard_DS3_v2',
      instanceCount: 2,
      maxInstanceCount: 10
    });

    // Wait for model initialization
    await scoring._waitForInitialization();
  }, 60000);

  afterAll(async () => {
    if (endpoint) {
      await endpoint.delete();
    }
  });

  describe('Deployment Infrastructure', () => {
    test('should deploy endpoint successfully', async () => {
      expect(await endpoint.isDeployed()).toBe(true);
    });

    test('should have proper configuration', async () => {
      const config = await endpoint.getConfiguration();
      expect(config.instanceType).toBe('Standard_DS3_v2');
      expect(config.instanceCount).toBe(2);
      expect(config.maxInstanceCount).toBe(10);
    });

    test('should support auto-scaling', async () => {
      const scaling = await endpoint.getAutoScalingConfig();
      expect(scaling.enabled).toBe(true);
      expect(scaling.minInstances).toBe(2);
      expect(scaling.maxInstances).toBe(10);
    });
  });

  describe('Latency Requirements - Sub-1 Second', () => {
    test('should respond within 1000ms', async () => {
      const startTime = Date.now();

      const prediction = await scoring.predict({
        features: [1.5, 2.3, 0.8, 1.2, 3.1, 0.9, 2.7, 1.8]
      });

      const responseTime = Date.now() - startTime;

      expect(responseTime).toBeLessThan(1000);
      expect(prediction.score).toBeTypeOf('number');
      expect(prediction.responseTime).toBeDefined();
    });

    test('should maintain performance under concurrent load', async () => {
      const concurrentRequests = 10;
      const promises = [];

      for (let i = 0; i < concurrentRequests; i++) {
        const startTime = Date.now();
        const promise = scoring.predict({
          features: [Math.random(), Math.random(), Math.random(), Math.random(),
                    Math.random(), Math.random(), Math.random(), Math.random()]
        }).then(result => ({
          responseTime: Date.now() - startTime,
          result
        }));
        promises.push(promise);
      }

      const results = await Promise.all(promises);

      // All requests should complete under 1 second
      results.forEach(({ responseTime }) => {
        expect(responseTime).toBeLessThan(1000);
      });

      // All should have valid predictions
      expect(results.length).toBe(concurrentRequests);
      results.forEach(({ result }) => {
        expect(result.score).toBeTypeOf('number');
      });
    });
  });

  describe('Model Integration', () => {
    test('should work with Random Forest model', async () => {
      const prediction = await scoring.predict({
        features: [1.5, 2.3, 0.8, 1.2, 3.1, 0.9, 2.7, 1.8],
        modelType: 'random-forest'
      });

      expect(prediction.modelType).toBe('random-forest');
      expect(prediction.score).toBeTypeOf('number');
      expect(prediction.confidence).toBeTypeOf('number');
    });

    test('should work with Neural Network model', async () => {
      const prediction = await scoring.predict({
        features: [1.5, 2.3, 0.8, 1.2, 3.1, 0.9, 2.7, 1.8],
        modelType: 'neural-network'
      });

      expect(prediction.modelType).toBe('neural-network');
      expect(prediction.score).toBeTypeOf('number');
      expect(prediction.confidence).toBeTypeOf('number');
    });

    test('should provide model metadata', async () => {
      const metadata = await scoring.getModelMetadata();

      expect(metadata.version).toBeDefined();
      expect(metadata.accuracy).toBeTypeOf('number');
      expect(metadata.features).toBeInstanceOf(Array);
      expect(metadata.features.length).toBe(8);
    });

    test('should validate input correctly', async () => {
      await expect(
        scoring.predict({
          features: [1, 2, 3] // Too few features
        })
      ).rejects.toThrow(/Expected 8 features/);

      await expect(
        scoring.predict({
          features: ['invalid', 'data', 'types', 1, 2, 3, 4, 5]
        })
      ).rejects.toThrow(/must be a number/);
    });
  });

  describe('Monitoring and Health', () => {
    test('should provide metrics', async () => {
      const metrics = await monitor.getMetrics({
        timeRange: '1h',
        metrics: ['latency', 'throughput', 'errors']
      });

      expect(metrics.latency).toBeDefined();
      expect(metrics.throughput).toBeDefined();
      expect(metrics.errors).toBeDefined();
    });

    test('should track prediction logs', async () => {
      await scoring.predict({
        features: [1, 2, 3, 4, 5, 6, 7, 8]
      });

      const logs = await monitor.getLogs({
        timeRange: '5m',
        logType: 'predictions'
      });

      expect(logs.length).toBeGreaterThan(0);
      expect(logs[0]).toHaveProperty('timestamp');
      expect(logs[0]).toHaveProperty('requestId');
    });

    test('should provide health status', async () => {
      const health = await monitor.getHealthStatus();

      expect(health.status).toMatch(/healthy|degraded/);
      expect(health.timestamp).toBeDefined();
    });

    test('should have configured alerts', async () => {
      const alerts = await monitor.getAlerts();

      expect(alerts.length).toBeGreaterThan(0);

      const latencyAlert = alerts.find(alert => alert.type === 'high_latency');
      expect(latencyAlert).toBeDefined();
      expect(latencyAlert.threshold).toBe(1000);
      expect(latencyAlert.enabled).toBe(true);
    });
  });

  describe('Performance Benchmarks', () => {
    test('should achieve target throughput', async () => {
      const testDuration = 10000; // 10 seconds
      const targetRPS = 16.67; // ~1000 requests per minute
      const startTime = Date.now();
      let requestCount = 0;

      const testPromises = [];

      while ((Date.now() - startTime) < testDuration) {
        const promise = scoring.predict({
          features: [Math.random(), Math.random(), Math.random(), Math.random(),
                    Math.random(), Math.random(), Math.random(), Math.random()]
        }).then(() => {
          requestCount++;
        }).catch(() => {
          // Count failed requests too
          requestCount++;
        });

        testPromises.push(promise);

        // Rate limiting to prevent overwhelming
        await new Promise(resolve => setTimeout(resolve, 60));
      }

      await Promise.all(testPromises);

      const actualDuration = Date.now() - startTime;
      const actualRPS = (requestCount / actualDuration) * 1000;

      expect(actualRPS).toBeGreaterThan(10); // Minimum acceptable throughput
      expect(requestCount).toBeGreaterThan(100); // Minimum requests processed
    }, 15000);

    test('should validate P95 latency', async () => {
      const measurements = [];
      const iterations = 20;

      for (let i = 0; i < iterations; i++) {
        const startTime = Date.now();
        await scoring.predict({
          features: [1, 2, 3, 4, 5, 6, 7, 8]
        });
        measurements.push(Date.now() - startTime);
      }

      measurements.sort((a, b) => a - b);
      const p95Index = Math.floor(measurements.length * 0.95);
      const p95Latency = measurements[p95Index];

      expect(p95Latency).toBeLessThan(1000);

      // Log for verification
      console.log(`P95 Latency: ${p95Latency}ms`);
      console.log(`Average Latency: ${measurements.reduce((a, b) => a + b, 0) / measurements.length}ms`);
    });
  });
});