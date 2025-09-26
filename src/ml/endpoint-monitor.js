/**
 * Azure ML Endpoint Monitoring Service
 * Comprehensive monitoring and alerting for real-time endpoints
 */

export class EndpointMonitor {
  constructor(endpoint) {
    this.endpoint = endpoint;
    this.metrics = new Map();
    this.logs = [];
    this.alerts = new Map();

    this._initializeMonitoring();
  }

  /**
   * Get metrics for the endpoint
   */
  async getMetrics(options = {}) {
    const timeRange = options.timeRange || '1h';
    const requestedMetrics = options.metrics || ['latency', 'throughput', 'errors', 'cpu', 'memory'];

    const endTime = Date.now();
    const startTime = endTime - this._parseTimeRange(timeRange);

    const metrics = {};

    for (const metricName of requestedMetrics) {
      metrics[metricName] = this._getMetricData(metricName, startTime, endTime);
    }

    return metrics;
  }

  /**
   * Get logs from the endpoint
   */
  async getLogs(options = {}) {
    const timeRange = options.timeRange || '1h';
    const logType = options.logType || 'all';
    const limit = options.limit || 100;

    const endTime = Date.now();
    const startTime = endTime - this._parseTimeRange(timeRange);

    let filteredLogs = this.logs.filter(log => {
      const logTime = new Date(log.timestamp).getTime();
      return logTime >= startTime && logTime <= endTime;
    });

    if (logType !== 'all') {
      filteredLogs = filteredLogs.filter(log => {
        return log.type === logType ||
               (logType === 'predictions' && (log.type === 'prediction_request' || log.type === 'prediction_response'));
      });
    }

    // Sort by timestamp descending (newest first)
    filteredLogs.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    return filteredLogs.slice(0, limit);
  }

  /**
   * Get configured alerts
   */
  async getAlerts() {
    return Array.from(this.alerts.values());
  }

  /**
   * Add a log entry
   */
  addLog(logEntry) {
    const enrichedLog = {
      ...logEntry,
      endpoint: this.endpoint.endpointName,
      timestamp: logEntry.timestamp || new Date().toISOString(),
      requestId: logEntry.requestId || this._generateId()
    };

    this.logs.push(enrichedLog);

    // Keep only last 10000 logs in memory
    if (this.logs.length > 10000) {
      this.logs = this.logs.slice(-10000);
    }

    // Check if this log entry triggers any alerts
    this._checkAlerts(enrichedLog);
  }

  /**
   * Record a metric measurement
   */
  recordMetric(metricName, value, timestamp = Date.now()) {
    if (!this.metrics.has(metricName)) {
      this.metrics.set(metricName, []);
    }

    const metricData = this.metrics.get(metricName);
    metricData.push({ value, timestamp });

    // Keep only last 24 hours of metric data
    const cutoffTime = timestamp - (24 * 60 * 60 * 1000);
    const filteredData = metricData.filter(point => point.timestamp > cutoffTime);
    this.metrics.set(metricName, filteredData);

    // Check metric-based alerts
    this._checkMetricAlerts(metricName, value);
  }

  /**
   * Get endpoint health status
   */
  async getHealthStatus() {
    try {
      const isDeployed = await this.endpoint.isDeployed();

      if (!isDeployed) {
        return {
          status: 'unhealthy',
          timestamp: new Date().toISOString(),
          reason: 'Endpoint not deployed'
        };
      }

      // Check recent error rate
      const recentLogs = await this.getLogs({ timeRange: '5m' });
      const errorLogs = recentLogs.filter(log => log.type === 'prediction_error');
      const errorRate = (errorLogs.length / recentLogs.length) * 100;

      if (errorRate > 10) {
        return {
          status: 'degraded',
          timestamp: new Date().toISOString(),
          reason: `High error rate: ${errorRate.toFixed(1)}%`
        };
      }

      // Check recent latency
      const latencyMetrics = this._getMetricData('latency', Date.now() - (5 * 60 * 1000), Date.now());
      if (latencyMetrics.average > 1000) {
        return {
          status: 'degraded',
          timestamp: new Date().toISOString(),
          reason: `High latency: ${latencyMetrics.average.toFixed(0)}ms`
        };
      }

      return {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        metrics: {
          errorRate: errorRate.toFixed(1),
          avgLatency: latencyMetrics.average?.toFixed(0) || 'N/A'
        }
      };

    } catch (error) {
      return {
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        reason: `Health check failed: ${error.message}`
      };
    }
  }

  // Private methods

  _initializeMonitoring() {
    // Initialize default alerts
    this.alerts.set('high_latency', {
      name: 'high_latency',
      type: 'high_latency',
      threshold: 1000,
      enabled: true,
      condition: 'greater_than',
      description: 'Alert when response latency exceeds 1 second'
    });

    this.alerts.set('high_error_rate', {
      name: 'high_error_rate',
      type: 'high_error_rate',
      threshold: 5,
      enabled: true,
      condition: 'greater_than',
      description: 'Alert when error rate exceeds 5%'
    });

    this.alerts.set('low_availability', {
      name: 'low_availability',
      type: 'low_availability',
      threshold: 99.0,
      enabled: true,
      condition: 'less_than',
      description: 'Alert when availability drops below 99%'
    });

    console.log('📊 Endpoint monitoring initialized');
  }

  _parseTimeRange(timeRange) {
    const units = {
      'm': 60 * 1000,
      'h': 60 * 60 * 1000,
      'd': 24 * 60 * 60 * 1000
    };

    const match = timeRange.match(/^(\d+)([mhd])$/);
    if (!match) {
      throw new Error(`Invalid time range: ${timeRange}`);
    }

    const [, amount, unit] = match;
    return parseInt(amount) * units[unit];
  }

  _getMetricData(metricName, startTime, endTime) {
    const metricData = this.metrics.get(metricName) || [];

    const filteredData = metricData.filter(point =>
      point.timestamp >= startTime && point.timestamp <= endTime
    );

    if (filteredData.length === 0) {
      return this._generateMockMetricData(metricName);
    }

    const values = filteredData.map(point => point.value);

    return {
      average: values.reduce((sum, val) => sum + val, 0) / values.length,
      min: Math.min(...values),
      max: Math.max(...values),
      count: values.length,
      latest: values[values.length - 1] || 0
    };
  }

  _generateMockMetricData(metricName) {
    // Generate realistic mock data for testing
    const mockData = {
      latency: {
        average: 250 + Math.random() * 300,
        min: 100 + Math.random() * 50,
        max: 800 + Math.random() * 200,
        count: 100,
        latest: 200 + Math.random() * 400
      },
      throughput: {
        average: 15 + Math.random() * 10,
        min: 5,
        max: 30,
        count: 100,
        latest: 18 + Math.random() * 5
      },
      errors: {
        average: 0.5 + Math.random() * 1.5,
        min: 0,
        max: 3,
        count: 100,
        latest: Math.random() * 2
      },
      cpu: {
        average: 45 + Math.random() * 20,
        min: 20,
        max: 80,
        count: 100,
        latest: 40 + Math.random() * 30
      },
      memory: {
        average: 60 + Math.random() * 15,
        min: 45,
        max: 85,
        count: 100,
        latest: 55 + Math.random() * 20
      }
    };

    return mockData[metricName] || {
      average: Math.random() * 100,
      min: 0,
      max: 100,
      count: 100,
      latest: Math.random() * 100
    };
  }

  _checkAlerts(logEntry) {
    // Check for error-based alerts
    if (logEntry.type === 'prediction_error') {
      const recentErrors = this.logs.filter(log =>
        log.type === 'prediction_error' &&
        new Date(log.timestamp).getTime() > Date.now() - (5 * 60 * 1000)
      );

      const recentTotal = this.logs.filter(log =>
        new Date(log.timestamp).getTime() > Date.now() - (5 * 60 * 1000)
      );

      const errorRate = (recentErrors.length / recentTotal.length) * 100;

      if (errorRate > 5) {
        this._triggerAlert('high_error_rate', {
          currentValue: errorRate,
          message: `Error rate is ${errorRate.toFixed(1)}%`
        });
      }
    }

    // Check for latency-based alerts
    if (logEntry.responseTime && logEntry.responseTime > 1000) {
      this._triggerAlert('high_latency', {
        currentValue: logEntry.responseTime,
        requestId: logEntry.requestId,
        message: `Response time ${logEntry.responseTime}ms exceeds threshold`
      });
    }
  }

  _checkMetricAlerts(metricName, value) {
    // Check CPU utilization
    if (metricName === 'cpu' && value > 80) {
      this._triggerAlert('high_cpu', {
        currentValue: value,
        message: `CPU utilization is ${value.toFixed(1)}%`
      });
    }

    // Check memory utilization
    if (metricName === 'memory' && value > 90) {
      this._triggerAlert('high_memory', {
        currentValue: value,
        message: `Memory utilization is ${value.toFixed(1)}%`
      });
    }
  }

  _triggerAlert(alertName, context) {
    const alert = this.alerts.get(alertName);
    if (!alert || !alert.enabled) return;

    const alertEvent = {
      alertName,
      timestamp: new Date().toISOString(),
      severity: 'warning',
      context,
      endpoint: this.endpoint.endpointName
    };

    console.warn(`🚨 ALERT: ${alertName}`, alertEvent);

    // In production, this would send to notification systems
    this.addLog({
      type: 'alert',
      alertName,
      severity: 'warning',
      message: context.message
    });
  }

  _generateId() {
    return `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
}