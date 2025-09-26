/**
 * ML Pipeline Tests - Test-Driven Development Approach
 * Task 2: Develop ML Model Pipeline
 *
 * RED PHASE: These tests will fail initially, driving implementation
 * Maximum 5 essential tests for core business logic
 */

import { describe, test, expect, beforeAll, vi } from 'vitest';
import fs from 'fs/promises';
import path from 'path';

// Test 1: Data Loading and Preprocessing
describe('ML Data Pipeline', () => {
  test('should load and preprocess synthetic data for training', async () => {
    // Import the data loader module that we'll create
    const { DataLoader } = await import('../src/ml/data-loader.js');

    const dataLoader = new DataLoader();
    const trainData = await dataLoader.loadTrainingData();

    // Verify data structure and preprocessing
    expect(trainData).toBeDefined();
    expect(trainData.features).toBeDefined();
    expect(trainData.labels).toBeDefined();
    expect(trainData.features.length).toBeGreaterThan(0);
    expect(trainData.labels.length).toBe(trainData.features.length);

    // Verify data is properly normalized/scaled
    expect(trainData.isPreprocessed).toBe(true);
    expect(trainData.metadata).toBeDefined();
    expect(trainData.metadata.featureNames).toBeDefined();
  });
});

// Test 2: Random Forest Model Training
describe('Random Forest Model', () => {
  test('should train Random Forest model and return performance metrics', async () => {
    const { RandomForestModel } = await import('../src/ml/models/random-forest.js');
    const { DataLoader } = await import('../src/ml/data-loader.js');

    const dataLoader = new DataLoader();
    const trainData = await dataLoader.loadTrainingData();

    const model = new RandomForestModel({
      nTrees: 10,
      maxDepth: 5,
      randomSeed: 42
    });

    const results = await model.train(trainData.features, trainData.labels);

    // Verify training results
    expect(results.accuracy).toBeGreaterThan(0.7); // At least 70% accuracy
    expect(results.precision).toBeGreaterThan(0.6);
    expect(results.recall).toBeGreaterThan(0.6);
    expect(results.f1Score).toBeGreaterThan(0.6);
    expect(model.isTrained).toBe(true);

    // Verify model can make predictions
    const prediction = await model.predict(trainData.features[0]);
    expect(prediction).toBeDefined();
    expect(typeof prediction).toBe('number');
  });
});

// Test 3: Neural Network Model Training
describe('Neural Network Model', () => {
  test('should train Neural Network model with proper architecture', async () => {
    const { NeuralNetworkModel } = await import('../src/ml/models/neural-network.js');
    const { DataLoader } = await import('../src/ml/data-loader.js');

    const dataLoader = new DataLoader();
    const trainData = await dataLoader.loadTrainingData();

    const model = new NeuralNetworkModel({
      inputSize: trainData.features[0].length,
      hiddenLayers: [64, 32, 16],
      outputSize: 1,
      learningRate: 0.001,
      epochs: 50
    });

    const results = await model.train(trainData.features, trainData.labels);

    // Verify neural network training
    expect(results.finalLoss).toBeLessThan(0.5);
    expect(results.epochs).toBe(50);
    expect(results.convergence).toBe(true);
    expect(model.isTrained).toBe(true);

    // Verify model architecture
    expect(model.layers.length).toBe(5); // input + 3 hidden + output
    expect(model.parameters.count).toBeGreaterThan(0);
  });
});

// Test 4: Azure ML Integration and Model Registry
describe('Azure ML Integration', () => {
  test('should register models in Azure ML and manage versions', async () => {
    const { AzureMLRegistry } = await import('../src/ml/azure-ml-registry.js');
    const { RandomForestModel } = await import('../src/ml/models/random-forest.js');

    // Mock Azure ML SDK calls for testing
    vi.mock('azure-ml-sdk', () => ({
      MLClient: vi.fn(() => ({
        models: {
          create: vi.fn().mockResolvedValue({ name: 'test-model', version: '1.0.0' }),
          get: vi.fn().mockResolvedValue({ name: 'test-model', status: 'ready' }),
          list: vi.fn().mockResolvedValue([{ name: 'test-model', version: '1.0.0' }])
        }
      }))
    }));

    const registry = new AzureMLRegistry({
      subscriptionId: 'test-sub',
      resourceGroup: 'test-rg',
      workspaceName: 'test-ws'
    });

    const model = new RandomForestModel();
    // Simulate trained model
    model.isTrained = true;
    model.modelData = { weights: 'mock-weights' };

    const registrationResult = await registry.registerModel(model, {
      name: 'equipment-failure-predictor',
      description: 'Random Forest model for equipment failure prediction',
      tags: { environment: 'test', algorithm: 'random-forest' }
    });

    // Verify model registration
    expect(registrationResult.modelId).toBeDefined();
    expect(registrationResult.version).toBeDefined();
    expect(registrationResult.status).toBe('registered');

    // Verify model retrieval
    const retrievedModel = await registry.getModel('equipment-failure-predictor', '1.0.0');
    expect(retrievedModel.name).toBe('equipment-failure-predictor');
    expect(retrievedModel.status).toBe('ready');
  });
});

// Test 5: MLOps Pipeline and Automated Training
describe('MLOps Pipeline', () => {
  test('should execute end-to-end training pipeline with monitoring', async () => {
    const { MLOpsPipeline } = await import('../src/ml/mlops-pipeline.js');

    const pipeline = new MLOpsPipeline({
      dataSource: 'synthetic',
      models: ['random-forest', 'neural-network'],
      azureConfig: {
        subscriptionId: 'test-sub',
        resourceGroup: 'test-rg',
        workspaceName: 'test-ws'
      },
      monitoring: {
        enableMetrics: true,
        enableLogging: true
      }
    });

    const pipelineResult = await pipeline.execute();

    // Verify pipeline execution
    expect(pipelineResult.status).toBe('completed');
    expect(pipelineResult.models.length).toBe(2);
    expect(pipelineResult.bestModel).toBeDefined();
    expect(pipelineResult.metrics).toBeDefined();

    // Verify each model was trained and evaluated
    pipelineResult.models.forEach(model => {
      expect(model.name).toBeDefined();
      expect(model.accuracy).toBeGreaterThan(0);
      expect(model.status).toBe('trained');
      expect(model.registryId).toBeDefined();
    });

    // Verify monitoring and logging
    expect(pipelineResult.logs.length).toBeGreaterThan(0);
    expect(pipelineResult.metrics.trainingTime).toBeGreaterThan(0);
    expect(pipelineResult.metrics.dataPipelineTime).toBeGreaterThan(0);
  });
});