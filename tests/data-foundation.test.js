/**
 * TDD Tests for Data Foundation Setup (Task 1)
 * Tests synthetic data generation, quality validation, and ingestion pipelines
 */

import { describe, it, expect, beforeAll } from 'vitest'
import fs from 'fs'
import path from 'path'

describe('Data Foundation Infrastructure', () => {
  const dataDir = path.join(process.cwd(), 'data')
  const syntheticDataDir = path.join(dataDir, 'synthetic')
  const configDir = path.join(dataDir, 'config')
  const notebooksDir = path.join(process.cwd(), 'notebooks')

  describe('Data Directory Structure', () => {
    it('should have data directory structure', () => {
      expect(fs.existsSync(dataDir)).toBe(true)
      expect(fs.existsSync(syntheticDataDir)).toBe(true)
      expect(fs.existsSync(configDir)).toBe(true)
    })
  })

  describe('Synthetic Data Generation', () => {
    it('should have manufacturing datasets', () => {
      const manufacturingFile = path.join(syntheticDataDir, 'manufacturing_data.json')
      expect(fs.existsSync(manufacturingFile)).toBe(true)

      const data = JSON.parse(fs.readFileSync(manufacturingFile, 'utf8'))
      expect(Array.isArray(data)).toBe(true)
      expect(data.length).toBeGreaterThan(0)
      expect(data[0]).toHaveProperty('timestamp')
      expect(data[0]).toHaveProperty('production_line')
      expect(data[0]).toHaveProperty('output_quantity')
    })

    it('should have time-series data with seasonal patterns', () => {
      const timeSeriesFile = path.join(syntheticDataDir, 'timeseries_seasonal.json')
      expect(fs.existsSync(timeSeriesFile)).toBe(true)

      const data = JSON.parse(fs.readFileSync(timeSeriesFile, 'utf8'))
      expect(Array.isArray(data)).toBe(true)
      expect(data.length).toBeGreaterThanOrEqual(365) // At least 1 year of data
      expect(data[0]).toHaveProperty('date')
      expect(data[0]).toHaveProperty('value')
      expect(data[0]).toHaveProperty('seasonal_component')
    })

    it('should have equipment telemetry data', () => {
      const telemetryFile = path.join(syntheticDataDir, 'equipment_telemetry.json')
      expect(fs.existsSync(telemetryFile)).toBe(true)

      const data = JSON.parse(fs.readFileSync(telemetryFile, 'utf8'))
      expect(Array.isArray(data)).toBe(true)
      expect(data[0]).toHaveProperty('equipment_id')
      expect(data[0]).toHaveProperty('timestamp')
      expect(data[0]).toHaveProperty('temperature')
      expect(data[0]).toHaveProperty('vibration')
      expect(data[0]).toHaveProperty('status')
    })

    it('should have controlled anomalies for model validation', () => {
      const anomaliesFile = path.join(syntheticDataDir, 'anomalies_controlled.json')
      expect(fs.existsSync(anomaliesFile)).toBe(true)

      const data = JSON.parse(fs.readFileSync(anomaliesFile, 'utf8'))
      expect(Array.isArray(data)).toBe(true)
      expect(data[0]).toHaveProperty('timestamp')
      expect(data[0]).toHaveProperty('anomaly_type')
      expect(data[0]).toHaveProperty('severity')
      expect(data[0]).toHaveProperty('is_anomaly')
    })
  })

  describe('Data Quality Validation', () => {
    it('should have data quality validation script', () => {
      const validationScript = path.join(process.cwd(), 'scripts', 'validate-data-quality.js')
      expect(fs.existsSync(validationScript)).toBe(true)
    })

    it('should have statistical properties configuration', () => {
      const statsConfig = path.join(configDir, 'data-quality-standards.json')
      expect(fs.existsSync(statsConfig)).toBe(true)

      const config = JSON.parse(fs.readFileSync(statsConfig, 'utf8'))
      expect(config).toHaveProperty('manufacturing')
      expect(config).toHaveProperty('timeseries')
      expect(config).toHaveProperty('telemetry')
    })
  })

  describe('Data Ingestion Pipelines', () => {
    it('should have ingestion pipeline configuration', () => {
      const pipelineConfig = path.join(configDir, 'ingestion-pipelines.json')
      expect(fs.existsSync(pipelineConfig)).toBe(true)

      const config = JSON.parse(fs.readFileSync(pipelineConfig, 'utf8'))
      expect(config).toHaveProperty('pipelines')
      expect(Array.isArray(config.pipelines)).toBe(true)
    })

    it('should have Fabric workspace configuration', () => {
      const fabricConfig = path.join(configDir, 'fabric-workspace.json')
      expect(fs.existsSync(fabricConfig)).toBe(true)

      const config = JSON.parse(fs.readFileSync(fabricConfig, 'utf8'))
      expect(config).toHaveProperty('workspace_name')
      expect(config).toHaveProperty('onelake_config')
    })
  })

  describe('Data Preparation Notebooks', () => {
    it('should have notebooks directory', () => {
      expect(fs.existsSync(notebooksDir)).toBe(true)
    })

    it('should have initial data preparation notebook', () => {
      const prepNotebook = path.join(notebooksDir, 'data-preparation.ipynb')
      expect(fs.existsSync(prepNotebook)).toBe(true)
    })

    it('should have synthetic data generation notebook', () => {
      const genNotebook = path.join(notebooksDir, 'synthetic-data-generation.ipynb')
      expect(fs.existsSync(genNotebook)).toBe(true)
    })
  })
})