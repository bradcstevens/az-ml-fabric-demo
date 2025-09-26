/**
 * Batch Scheduler Implementation
 * Task 4: Implement Batch Scoring Pipeline - Scheduling Component
 *
 * Handles scheduled execution of batch scoring jobs
 */

export class BatchScheduler {
  constructor(options = {}) {
    this.config = {
      timezone: options.timezone || 'UTC',
      maxRetries: options.maxRetries || 3,
      ...options
    };

    this.schedules = new Map();
    this.running = false;
    this.intervalHandles = new Map();
  }

  createSchedule(scheduleConfig) {
    if (!scheduleConfig || typeof scheduleConfig !== 'object') {
      throw new Error('Invalid schedule configuration');
    }

    const { frequency, time, timezone } = scheduleConfig;

    // Validate frequency
    if (!['daily', 'weekly', 'hourly'].includes(frequency)) {
      throw new Error('Invalid schedule configuration');
    }

    // Validate time format (HH:MM)
    if (time && !/^([0-1][0-9]|2[0-3]):[0-5][0-9]$/.test(time)) {
      throw new Error('Invalid schedule configuration');
    }

    const cronExpression = this._generateCronExpression(frequency, time);
    const nextRun = this._calculateNextRun(cronExpression, timezone);

    return {
      frequency,
      time,
      timezone: timezone || this.config.timezone,
      cronExpression,
      nextRun,
      created: new Date().toISOString()
    };
  }

  schedule(scheduleConfig, callback) {
    if (typeof callback !== 'function') {
      throw new Error('Callback function is required');
    }

    const schedule = this.createSchedule(scheduleConfig);
    const scheduleId = this._generateScheduleId(schedule);

    this.schedules.set(scheduleId, {
      ...schedule,
      callback,
      enabled: true,
      lastRun: null,
      runCount: 0
    });

    return scheduleId;
  }

  async start() {
    if (this.running) {
      return;
    }

    this.running = true;

    // Set up intervals for each schedule
    for (const [scheduleId, schedule] of this.schedules) {
      if (schedule.enabled) {
        this._setupScheduleInterval(scheduleId, schedule);
      }
    }
  }

  async stop() {
    this.running = false;

    // Clear all intervals
    for (const handle of this.intervalHandles.values()) {
      clearInterval(handle);
    }
    this.intervalHandles.clear();
  }

  isRunning() {
    return this.running;
  }

  getSchedules() {
    return Array.from(this.schedules.entries()).map(([id, schedule]) => ({
      id,
      ...schedule
    }));
  }

  removeSchedule(scheduleId) {
    if (this.intervalHandles.has(scheduleId)) {
      clearInterval(this.intervalHandles.get(scheduleId));
      this.intervalHandles.delete(scheduleId);
    }
    return this.schedules.delete(scheduleId);
  }

  _generateCronExpression(frequency, time) {
    const [hour, minute] = time ? time.split(':').map(Number) : [2, 0];

    switch (frequency) {
      case 'hourly':
        return `${minute} * * * *`;
      case 'daily':
        return `${minute} ${hour} * * *`;
      case 'weekly':
        return `${minute} ${hour} * * 0`; // Sunday
      default:
        throw new Error(`Unsupported frequency: ${frequency}`);
    }
  }

  _calculateNextRun(cronExpression, timezone) {
    // Simplified next run calculation for demo purposes
    const now = new Date();
    const [minute, hour] = cronExpression.split(' ').map(Number);

    let nextRun = new Date(now);
    nextRun.setHours(hour, minute, 0, 0);

    // If the time has passed today, schedule for tomorrow
    if (nextRun <= now) {
      nextRun.setDate(nextRun.getDate() + 1);
    }

    return nextRun.toISOString();
  }

  _generateScheduleId(schedule) {
    return `schedule_${schedule.frequency}_${schedule.time}_${Date.now()}`;
  }

  _setupScheduleInterval(scheduleId, schedule) {
    // For demo purposes, use a simple interval check
    // In production, you'd use a proper cron job scheduler
    const checkInterval = 60000; // Check every minute

    const intervalHandle = setInterval(async () => {
      if (!this.running || !schedule.enabled) {
        return;
      }

      const now = new Date();
      const nextRun = new Date(schedule.nextRun);

      if (now >= nextRun) {
        try {
          await this._executeScheduledJob(scheduleId, schedule);
        } catch (error) {
          console.error(`Error executing scheduled job ${scheduleId}:`, error);
        }
      }
    }, checkInterval);

    this.intervalHandles.set(scheduleId, intervalHandle);
  }

  async _executeScheduledJob(scheduleId, schedule) {
    const execution = {
      scheduleId,
      startTime: new Date(),
      attempt: 0
    };

    let success = false;
    let lastError = null;

    // Retry logic
    while (execution.attempt < this.config.maxRetries && !success) {
      execution.attempt++;

      try {
        await schedule.callback({
          scheduleId,
          executionId: `${scheduleId}_${Date.now()}`,
          attempt: execution.attempt
        });

        success = true;
      } catch (error) {
        lastError = error;
        console.warn(`Scheduled job ${scheduleId} failed (attempt ${execution.attempt}):`, error.message);

        if (execution.attempt < this.config.maxRetries) {
          // Wait before retry (exponential backoff)
          await this._delay(Math.pow(2, execution.attempt) * 1000);
        }
      }
    }

    // Update schedule metadata
    const scheduleData = this.schedules.get(scheduleId);
    if (scheduleData) {
      scheduleData.lastRun = execution.startTime.toISOString();
      scheduleData.runCount++;
      scheduleData.lastSuccess = success;
      scheduleData.lastError = lastError?.message || null;

      // Calculate next run
      scheduleData.nextRun = this._calculateNextRun(
        scheduleData.cronExpression,
        scheduleData.timezone
      );
    }

    return {
      scheduleId,
      success,
      attempts: execution.attempt,
      error: lastError?.message,
      executionTime: Date.now() - execution.startTime.getTime()
    };
  }

  _delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}