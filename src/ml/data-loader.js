/**
 * Data Loader Module
 * Task 2: ML Model Pipeline - Data Loading and Preprocessing
 *
 * Loads synthetic data from Task 1 and prepares it for ML training
 */

import fs from 'fs/promises';
import path from 'path';

export class DataLoader {
  constructor(dataPath = './data/synthetic') {
    this.dataPath = dataPath;
    this.preprocessed = false;
  }

  async loadTrainingData() {
    try {
      // Load equipment telemetry data for failure prediction
      const telemetryPath = path.join(this.dataPath, 'equipment_telemetry.json');
      const anomaliesPath = path.join(this.dataPath, 'anomalies_controlled.json');

      const telemetryData = JSON.parse(await fs.readFile(telemetryPath, 'utf8'));
      const anomaliesData = JSON.parse(await fs.readFile(anomaliesPath, 'utf8'));

      // Prepare features and labels for ML training
      const features = this._extractFeatures(telemetryData);
      const labels = this._generateLabels(telemetryData, anomaliesData);

      // Normalize features
      const normalizedFeatures = this._normalizeFeatures(features);

      return {
        features: normalizedFeatures,
        labels: labels,
        isPreprocessed: true,
        metadata: {
          featureNames: ['temperature', 'vibration', 'pressure', 'flow_rate', 'runtime_hours'],
          totalSamples: features.length,
          featuresCount: features[0].length,
          dataSource: 'synthetic_equipment_telemetry'
        }
      };
    } catch (error) {
      throw new Error(`Failed to load training data: ${error.message}`);
    }
  }

  _extractFeatures(telemetryData) {
    return telemetryData.map(record => [
      record.temperature,
      record.vibration,
      record.pressure,
      record.flow_rate,
      record.runtime_hours
    ]);
  }

  _generateLabels(telemetryData, anomaliesData) {
    // Create labels based on equipment status and anomalies
    const anomalyTimes = new Set(anomaliesData.map(a => a.timestamp));

    return telemetryData.map(record => {
      // Label as 1 (failure/anomaly) if status is not normal or timestamp matches anomaly
      if (record.status !== 'NORMAL' || anomalyTimes.has(record.timestamp)) {
        return 1;
      }
      return 0;
    });
  }

  _normalizeFeatures(features) {
    if (features.length === 0) return features;

    const featureCount = features[0].length;
    const stats = [];

    // Calculate mean and std for each feature
    for (let i = 0; i < featureCount; i++) {
      const values = features.map(row => row[i]);
      const mean = values.reduce((sum, val) => sum + val, 0) / values.length;
      const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / values.length;
      const std = Math.sqrt(variance);

      stats.push({ mean, std: std || 1 }); // Avoid division by zero
    }

    // Normalize features using z-score normalization
    return features.map(row =>
      row.map((value, index) => (value - stats[index].mean) / stats[index].std)
    );
  }
}