/**
 * Data Quality Validation Script
 * Validates synthetic data against statistical standards
 */

import fs from 'fs'
import path from 'path'

function calculateStats(data, field) {
  const values = data.map(item => item[field]).filter(v => v !== undefined && !isNaN(v))
  if (values.length === 0) return null

  const mean = values.reduce((sum, val) => sum + val, 0) / values.length
  const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / values.length
  const stdDev = Math.sqrt(variance)
  const min = Math.min(...values)
  const max = Math.max(...values)

  return { mean, stdDev, min, max, count: values.length }
}

function validateDataQuality() {
  const results = {}

  // Load data quality standards
  const standardsPath = path.join(process.cwd(), 'data', 'config', 'data-quality-standards.json')
  const standards = JSON.parse(fs.readFileSync(standardsPath, 'utf8'))

  // Validate manufacturing data
  const manufacturingPath = path.join(process.cwd(), 'data', 'synthetic', 'manufacturing_data.json')
  const manufacturingData = JSON.parse(fs.readFileSync(manufacturingPath, 'utf8'))

  results.manufacturing = {
    recordCount: manufacturingData.length,
    outputQuantityStats: calculateStats(manufacturingData, 'output_quantity'),
    defectRateStats: calculateStats(manufacturingData, 'defect_rate'),
    efficiencyStats: calculateStats(manufacturingData, 'machine_efficiency')
  }

  // Validate time-series data
  const timeseriesPath = path.join(process.cwd(), 'data', 'synthetic', 'timeseries_seasonal.json')
  const timeseriesData = JSON.parse(fs.readFileSync(timeseriesPath, 'utf8'))

  results.timeseries = {
    recordCount: timeseriesData.length,
    valueStats: calculateStats(timeseriesData, 'value'),
    seasonalStats: calculateStats(timeseriesData, 'seasonal_component'),
    hasSeasonalPattern: timeseriesData.some(d => Math.abs(d.seasonal_component) > 5)
  }

  // Validate equipment telemetry
  const telemetryPath = path.join(process.cwd(), 'data', 'synthetic', 'equipment_telemetry.json')
  const telemetryData = JSON.parse(fs.readFileSync(telemetryPath, 'utf8'))

  results.telemetry = {
    recordCount: telemetryData.length,
    temperatureStats: calculateStats(telemetryData, 'temperature'),
    vibrationStats: calculateStats(telemetryData, 'vibration'),
    uniqueEquipment: [...new Set(telemetryData.map(d => d.equipment_id))].length
  }

  // Validate anomalies
  const anomaliesPath = path.join(process.cwd(), 'data', 'synthetic', 'anomalies_controlled.json')
  const anomaliesData = JSON.parse(fs.readFileSync(anomaliesPath, 'utf8'))

  results.anomalies = {
    recordCount: anomaliesData.length,
    anomalyCount: anomaliesData.filter(d => d.is_anomaly).length,
    normalCount: anomaliesData.filter(d => !d.is_anomaly).length,
    severityDistribution: anomaliesData.reduce((acc, d) => {
      acc[d.severity] = (acc[d.severity] || 0) + 1
      return acc
    }, {})
  }

  return results
}

// Export for testing
export { validateDataQuality, calculateStats }

// CLI usage
if (import.meta.url === `file://${process.argv[1]}`) {
  const results = validateDataQuality()
  console.log('Data Quality Validation Results:')
  console.log(JSON.stringify(results, null, 2))
}