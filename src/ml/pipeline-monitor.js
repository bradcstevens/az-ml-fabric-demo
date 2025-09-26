/**
 * Pipeline Monitor Implementation
 * Task 4: Implement Batch Scoring Pipeline - Monitoring and Alerting
 *
 * Handles monitoring and alerting for batch scoring pipeline execution
 */

export class PipelineMonitor {
  constructor(options = {}) {
    this.config = {
      slaThresholdMinutes: options.slaThresholdMinutes || 30,
      errorRateThreshold: options.errorRateThreshold || 0.1, // 10%
      alertingEnabled: options.alertingEnabled !== false,
      retentionDays: options.retentionDays || 30,
      ...options
    };

    this.executions = [];
    this.alerts = [];
    this.alertCallback = null;
    this.startTime = new Date();
  }

  recordExecution(executionMetrics) {
    if (!executionMetrics || typeof executionMetrics !== 'object') {
      throw new Error('Invalid execution metrics provided');
    }

    const startTime = new Date(executionMetrics.startTime);
    const endTime = new Date(executionMetrics.endTime);
    const duration = endTime.getTime() - startTime.getTime();

    const execution = {
      id: this._generateExecutionId(),
      startTime: startTime,
      endTime: endTime,
      duration: Math.max(duration, 1), // Ensure minimum 1ms duration for metrics
      recordsProcessed: executionMetrics.recordsProcessed || 0,
      errors: executionMetrics.errors || 0,
      modelAccuracy: executionMetrics.modelAccuracy,
      success: (executionMetrics.errors || 0) === 0,
      recordedAt: new Date()
    };

    this.executions.push(execution);

    // Check for SLA violations
    this._checkSLACompliance(execution);

    // Check error rates
    this._checkErrorRates();

    // Clean up old executions
    this._cleanupOldExecutions();

    return execution.id;
  }

  getMetrics() {
    if (this.executions.length === 0) {
      return {
        totalExecutions: 0,
        successRate: 0,
        averageProcessingTime: 0,
        averageRecordsProcessed: 0,
        slaComplianceRate: 0,
        lastExecution: null
      };
    }

    const totalExecutions = this.executions.length;
    const successfulExecutions = this.executions.filter(e => e.success).length;
    const slaCompliantExecutions = this.executions.filter(e =>
      e.duration <= (this.config.slaThresholdMinutes * 60 * 1000)
    ).length;

    const totalProcessingTime = this.executions.reduce((sum, e) => sum + e.duration, 0);
    const totalRecordsProcessed = this.executions.reduce((sum, e) => sum + e.recordsProcessed, 0);

    return {
      totalExecutions,
      successRate: successfulExecutions / totalExecutions,
      averageProcessingTime: totalProcessingTime / totalExecutions,
      averageRecordsProcessed: totalRecordsProcessed / totalExecutions,
      slaComplianceRate: slaCompliantExecutions / totalExecutions,
      lastExecution: this.executions[this.executions.length - 1],
      uptime: Date.now() - this.startTime.getTime()
    };
  }

  getHealthStatus() {
    const metrics = this.getMetrics();
    const recentExecutions = this.executions.slice(-5); // Last 5 executions

    let status = 'healthy';
    const issues = [];

    // Check recent success rate
    if (recentExecutions.length > 0) {
      const recentSuccessRate = recentExecutions.filter(e => e.success).length / recentExecutions.length;
      if (recentSuccessRate < 0.8) {
        status = 'degraded';
        issues.push('Low recent success rate');
      }
    }

    // Check SLA compliance
    if (metrics.slaComplianceRate < 0.9) {
      status = 'degraded';
      issues.push('SLA compliance below 90%');
    }

    // Check if no recent executions (stale)
    const lastExecution = metrics.lastExecution;
    if (lastExecution) {
      const timeSinceLastExecution = Date.now() - new Date(lastExecution.endTime).getTime();
      if (timeSinceLastExecution > (25 * 60 * 60 * 1000)) { // More than 25 hours
        status = 'unhealthy';
        issues.push('No recent executions detected');
      }
    }

    return {
      status,
      uptime: Date.now() - this.startTime.getTime(),
      lastExecution: lastExecution?.recordedAt || null,
      metrics,
      issues,
      timestamp: new Date().toISOString()
    };
  }

  setAlertCallback(callback) {
    if (typeof callback !== 'function') {
      throw new Error('Alert callback must be a function');
    }
    this.alertCallback = callback;
  }

  getAlerts(limit = 50) {
    return this.alerts
      .slice(-limit)
      .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  }

  clearAlerts() {
    this.alerts = [];
  }

  _checkSLACompliance(execution) {
    const slaThresholdMs = this.config.slaThresholdMinutes * 60 * 1000;

    if (execution.duration > slaThresholdMs) {
      const alert = {
        id: this._generateAlertId(),
        type: 'SLA_VIOLATION',
        severity: 'HIGH',
        message: `Execution exceeded 30-minute SLA: ${Math.round(execution.duration / 60000)} minutes`,
        executionId: execution.id,
        duration: execution.duration,
        threshold: slaThresholdMs,
        timestamp: new Date().toISOString()
      };

      this._triggerAlert(alert);
    }
  }

  _checkErrorRates() {
    // Check error rate over recent executions
    const recentExecutions = this.executions.slice(-10); // Last 10 executions

    if (recentExecutions.length >= 5) {
      const failedExecutions = recentExecutions.filter(e => !e.success).length;
      const errorRate = failedExecutions / recentExecutions.length;

      if (errorRate > this.config.errorRateThreshold) {
        const alert = {
          id: this._generateAlertId(),
          type: 'HIGH_ERROR_RATE',
          severity: 'CRITICAL',
          message: `High error rate detected: ${Math.round(errorRate * 100)}% over last ${recentExecutions.length} executions`,
          errorRate,
          threshold: this.config.errorRateThreshold,
          recentExecutions: recentExecutions.length,
          timestamp: new Date().toISOString()
        };

        this._triggerAlert(alert);
      }
    }
  }

  _triggerAlert(alert) {
    this.alerts.push(alert);

    if (this.config.alertingEnabled && this.alertCallback) {
      try {
        this.alertCallback(alert);
      } catch (error) {
        console.error('Error triggering alert callback:', error);
      }
    }

    // Log alert to console for demo purposes
    console.warn(`[ALERT] ${alert.severity}: ${alert.message}`);
  }

  _cleanupOldExecutions() {
    const retentionMs = this.config.retentionDays * 24 * 60 * 60 * 1000;
    const cutoffTime = new Date(Date.now() - retentionMs);

    this.executions = this.executions.filter(execution =>
      execution.recordedAt > cutoffTime
    );

    // Also cleanup old alerts
    this.alerts = this.alerts.filter(alert =>
      new Date(alert.timestamp) > cutoffTime
    );
  }

  _generateExecutionId() {
    return `exec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  _generateAlertId() {
    return `alert_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
  }
}