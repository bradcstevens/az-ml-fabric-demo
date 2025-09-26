/**
 * Test Suite for Batch Scoring Pipeline
 * Task 4: Implement Batch Scoring Pipeline - TDD Tests
 *
 * Tests for batch processing capabilities, scheduling, and monitoring
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { BatchScoringPipeline } from '../src/ml/batch-scoring-pipeline.js';
import { BatchScheduler } from '../src/ml/batch-scheduler.js';
import { OneLakeConnector } from '../src/ml/onelake-connector.js';
import { PipelineMonitor } from '../src/ml/pipeline-monitor.js';

describe('Batch Scoring Pipeline - TDD Tests', () => {
  let batchPipeline;
  let mockData;

  beforeEach(() => {
    batchPipeline = new BatchScoringPipeline();
    mockData = [
      { temperature: 25.5, vibration: 2.1, pressure: 1013.25, timestamp: '2024-01-01T00:00:00Z' },
      { temperature: 26.0, vibration: 2.3, pressure: 1012.80, timestamp: '2024-01-01T01:00:00Z' },
      { temperature: 24.8, vibration: 1.9, pressure: 1014.10, timestamp: '2024-01-01T02:00:00Z' }
    ];
  });

  describe('Batch Processing Core Functionality', () => {
    it('should initialize with required components', () => {
      expect(batchPipeline).toBeDefined();
      expect(batchPipeline.config).toEqual({
        batchSize: 1000,
        maxConcurrency: 5,
        timeoutMinutes: 30,
        retryAttempts: 3
      });
    });

    it('should fail when no models are loaded', async () => {
      await expect(batchPipeline.processBatch(mockData))
        .rejects.toThrow('Pipeline not initialized');
    });

    it('should load models successfully', async () => {
      const modelConfigs = [
        { type: 'RandomForest', path: './src/ml/models/random-forest.js' },
        { type: 'NeuralNetwork', path: './src/ml/models/neural-network.js' }
      ];

      await batchPipeline.loadModels(modelConfigs);
      expect(batchPipeline.models.size).toBe(2);
      expect(batchPipeline.models.has('RandomForest')).toBe(true);
      expect(batchPipeline.models.has('NeuralNetwork')).toBe(true);
    });

    it('should process batch data and return predictions', async () => {
      // Load models first
      await batchPipeline.loadModels([
        { type: 'RandomForest', path: './src/ml/models/random-forest.js' }
      ]);

      const results = await batchPipeline.processBatch(mockData);

      expect(results).toBeDefined();
      expect(results.predictions).toHaveLength(3);
      expect(results.processedAt).toBeDefined();
      expect(results.metadata.totalRecords).toBe(3);
      expect(results.metadata.processingTimeMs).toBeGreaterThan(0);
    });

    it('should meet 30-minute SLA requirement for batch processing', async () => {
      const startTime = Date.now();
      const smallBatch = Array(5).fill(mockData[0]); // Very small batch for test speed

      await batchPipeline.loadModels([
        { type: 'RandomForest', path: './src/ml/models/random-forest.js' }
      ]);

      const results = await batchPipeline.processBatch(smallBatch);
      const processingTime = Date.now() - startTime;

      expect(processingTime).toBeLessThan(30 * 60 * 1000); // 30 minutes in milliseconds
      expect(results.metadata.slaCompliant).toBe(true);
    });
  });

  describe('Batch Scheduler', () => {
    let scheduler;

    beforeEach(() => {
      scheduler = new BatchScheduler();
    });

    it('should schedule nightly execution', () => {
      const schedule = scheduler.createSchedule({
        frequency: 'daily',
        time: '02:00',
        timezone: 'UTC'
      });

      expect(schedule.cronExpression).toBe('0 2 * * *');
      expect(schedule.nextRun).toBeDefined();
    });

    it('should fail when invalid schedule configuration is provided', () => {
      expect(() => {
        scheduler.createSchedule({
          frequency: 'invalid',
          time: '25:00'
        });
      }).toThrow('Invalid schedule configuration');
    });

    it('should start and stop scheduler', async () => {
      const mockCallback = vi.fn();

      scheduler.schedule({
        frequency: 'daily',
        time: '02:00'
      }, mockCallback);

      expect(scheduler.isRunning()).toBe(false);

      await scheduler.start();
      expect(scheduler.isRunning()).toBe(true);

      await scheduler.stop();
      expect(scheduler.isRunning()).toBe(false);
    });
  });

  describe('OneLake Integration', () => {
    let oneLakeConnector;

    beforeEach(() => {
      oneLakeConnector = new OneLakeConnector();
    });

    it('should initialize with OneLake configuration', () => {
      expect(oneLakeConnector.config).toEqual({
        workspaceId: null,
        lakehouseId: null,
        authentication: null,
        format: 'parquet',
        basePath: 'predictions'
      });
    });

    it('should fail without proper authentication', async () => {
      const mockPredictions = {
        predictions: [0.8, 0.2, 0.9],
        timestamp: new Date().toISOString()
      };

      await expect(oneLakeConnector.storePredictions(mockPredictions))
        .rejects.toThrow('OneLake authentication not configured');
    });

    it('should store predictions in OneLake format', async () => {
      // Mock authentication
      oneLakeConnector.configure({
        workspaceId: 'test-workspace',
        lakehouseId: 'test-lakehouse',
        authentication: 'mock-token'
      });

      const mockPredictions = {
        predictions: [
          { equipmentId: 'EQ001', failureProbability: 0.8, timestamp: '2024-01-01T00:00:00Z' },
          { equipmentId: 'EQ002', failureProbability: 0.2, timestamp: '2024-01-01T00:00:00Z' }
        ],
        metadata: { modelType: 'RandomForest', version: '1.0' }
      };

      const result = await oneLakeConnector.storePredictions(mockPredictions);

      expect(result.success).toBe(true);
      expect(result.lakePath).toContain('predictions');
      expect(result.format).toBe('parquet');
    });
  });

  describe('Pipeline Monitoring and Alerting', () => {
    let monitor;

    beforeEach(() => {
      monitor = new PipelineMonitor();
    });

    it('should track pipeline execution metrics', () => {
      const executionMetrics = {
        startTime: new Date(),
        endTime: new Date(),
        recordsProcessed: 1000,
        errors: 0,
        modelAccuracy: 0.85
      };

      monitor.recordExecution(executionMetrics);

      const metrics = monitor.getMetrics();
      expect(metrics.totalExecutions).toBe(1);
      expect(metrics.averageProcessingTime).toBeGreaterThan(0);
      expect(metrics.successRate).toBe(1.0);
    });

    it('should trigger alerts for SLA violations', () => {
      const alertCallback = vi.fn();
      monitor.setAlertCallback(alertCallback);

      const slowExecution = {
        startTime: new Date(Date.now() - (35 * 60 * 1000)), // 35 minutes ago
        endTime: new Date(),
        recordsProcessed: 1000,
        errors: 0
      };

      monitor.recordExecution(slowExecution);

      expect(alertCallback).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'SLA_VIOLATION',
          severity: 'HIGH',
          message: expect.stringContaining('30-minute SLA')
        })
      );
    });

    it('should trigger alerts for high error rates', () => {
      const alertCallback = vi.fn();
      monitor.setAlertCallback(alertCallback);

      // Simulate multiple failed executions
      for (let i = 0; i < 5; i++) {
        monitor.recordExecution({
          startTime: new Date(),
          endTime: new Date(),
          recordsProcessed: 0,
          errors: 100
        });
      }

      expect(alertCallback).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'HIGH_ERROR_RATE',
          severity: 'CRITICAL',
          message: expect.stringContaining('error rate')
        })
      );
    });

    it('should provide health check endpoint', () => {
      const health = monitor.getHealthStatus();

      expect(health).toHaveProperty('status');
      expect(health).toHaveProperty('uptime');
      expect(health).toHaveProperty('lastExecution');
      expect(health).toHaveProperty('metrics');
    });
  });

  describe('Error Handling and Resilience', () => {
    it('should retry failed batch processing', async () => {
      const mockFailingModel = {
        predict: vi.fn()
          .mockRejectedValueOnce(new Error('Temporary failure'))
          .mockRejectedValueOnce(new Error('Temporary failure'))
          .mockResolvedValueOnce(0.85)
      };

      // Initialize pipeline and load models first
      await batchPipeline.loadModels([]);
      batchPipeline.models.set('TestModel', mockFailingModel);

      const result = await batchPipeline.processBatch([mockData[0]]);

      expect(mockFailingModel.predict).toHaveBeenCalledTimes(3);
      expect(result.predictions).toHaveLength(1);
    });

    it('should handle partial batch failures gracefully', async () => {
      const mockModel = {
        predict: vi.fn()
          .mockResolvedValueOnce(0.8)
          .mockRejectedValueOnce(new Error('Processing error'))
          .mockResolvedValueOnce(0.6)
      };

      // Initialize pipeline and load models first
      await batchPipeline.loadModels([]);
      batchPipeline.models.set('TestModel', mockModel);

      const result = await batchPipeline.processBatch(mockData);

      expect(result.predictions).toHaveLength(2); // 2 successful, 1 failed
      expect(result.errors).toHaveLength(1);
      expect(result.metadata.successRate).toBe(2/3);
    });
  });
});