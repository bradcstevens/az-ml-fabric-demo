/**
 * Production-Ready Real-Time Scoring API
 * Enterprise-grade REST API for real-time ML predictions
 */

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { RealTimeScoring } from './real-time-scoring.js';
import { AzureMLOnlineEndpoint } from './azure-ml-online-endpoint.js';
import { EndpointMonitor } from './endpoint-monitor.js';

export class ScoringAPI {
  constructor(config = {}) {
    this.app = express();
    this.port = config.port || process.env.PORT || 8080;
    this.config = {
      corsOrigins: config.corsOrigins || ['*'],
      rateLimitMax: config.rateLimitMax || 1000, // 1000 requests per window
      rateLimitWindow: config.rateLimitWindow || 60000, // 1 minute
      requireAuth: config.requireAuth !== false, // Default to requiring auth
      ...config
    };

    this.endpoint = null;
    this.scoring = null;
    this.monitor = null;
    this.server = null;

    this._setupMiddleware();
    this._setupRoutes();
    this._setupErrorHandling();
  }

  /**
   * Initialize the API with Azure ML endpoint
   */
  async initialize(endpointConfig) {
    try {
      console.log('🚀 Initializing Scoring API...');

      // Initialize endpoint
      this.endpoint = new AzureMLOnlineEndpoint(endpointConfig);

      // Initialize scoring service
      this.scoring = new RealTimeScoring(this.endpoint);
      await this.scoring._waitForInitialization();

      // Initialize monitoring
      this.monitor = new EndpointMonitor(this.endpoint);
      this.scoring.setMonitor(this.monitor);

      console.log('✅ Scoring API initialized successfully');
    } catch (error) {
      console.error('❌ Failed to initialize Scoring API:', error.message);
      throw error;
    }
  }

  /**
   * Start the API server
   */
  async start() {
    return new Promise((resolve, reject) => {
      this.server = this.app.listen(this.port, (error) => {
        if (error) {
          reject(error);
        } else {
          console.log(`🌐 Scoring API running on port ${this.port}`);
          console.log(`📊 Health check: http://localhost:${this.port}/health`);
          console.log(`🔮 Prediction endpoint: http://localhost:${this.port}/score`);
          resolve();
        }
      });
    });
  }

  /**
   * Stop the API server
   */
  async stop() {
    if (this.server) {
      return new Promise((resolve) => {
        this.server.close(resolve);
        console.log('🛑 Scoring API stopped');
      });
    }
  }

  // Private methods for setup

  _setupMiddleware() {
    // Security middleware
    this.app.use(helmet());

    // CORS configuration
    this.app.use(cors({
      origin: this.config.corsOrigins,
      methods: ['GET', 'POST', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization'],
      credentials: true
    }));

    // Rate limiting
    const limiter = rateLimit({
      windowMs: this.config.rateLimitWindow,
      max: this.config.rateLimitMax,
      message: {
        error: 'Too many requests',
        message: `Rate limit exceeded. Max ${this.config.rateLimitMax} requests per minute.`
      },
      standardHeaders: true,
      legacyHeaders: false
    });
    this.app.use(limiter);

    // Body parsing
    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true }));

    // Request logging
    this.app.use((req, res, next) => {
      const start = Date.now();
      res.on('finish', () => {
        const duration = Date.now() - start;
        console.log(`${req.method} ${req.path} ${res.statusCode} ${duration}ms`);
      });
      next();
    });

    // Authentication middleware
    if (this.config.requireAuth) {
      this.app.use('/score', this._authMiddleware.bind(this));
    }
  }

  _setupRoutes() {
    // Health check endpoint
    this.app.get('/health', async (req, res) => {
      try {
        const health = {
          status: 'healthy',
          timestamp: new Date().toISOString(),
          version: '1.0.0',
          checks: {
            api: 'healthy',
            scoring: 'unknown',
            monitoring: 'unknown'
          }
        };

        if (this.scoring) {
          health.checks.scoring = this.scoring.initialized ? 'healthy' : 'initializing';
        }

        if (this.monitor) {
          const monitorHealth = await this.monitor.getHealthStatus();
          health.checks.monitoring = monitorHealth.status;
        }

        // Determine overall health
        const unhealthyChecks = Object.values(health.checks).filter(
          status => status !== 'healthy'
        );

        if (unhealthyChecks.length > 0) {
          health.status = 'degraded';
        }

        res.status(health.status === 'healthy' ? 200 : 503).json(health);
      } catch (error) {
        res.status(503).json({
          status: 'unhealthy',
          error: error.message,
          timestamp: new Date().toISOString()
        });
      }
    });

    // Readiness check
    this.app.get('/ready', async (req, res) => {
      try {
        if (!this.scoring || !this.scoring.initialized) {
          return res.status(503).json({
            ready: false,
            message: 'Scoring service not initialized'
          });
        }

        res.json({
          ready: true,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        res.status(503).json({
          ready: false,
          error: error.message
        });
      }
    });

    // Model metadata endpoint
    this.app.get('/models', async (req, res) => {
      try {
        if (!this.scoring) {
          return res.status(503).json({
            error: 'Scoring service not initialized'
          });
        }

        const metadata = await this.scoring.getModelMetadata();
        res.json(metadata);
      } catch (error) {
        res.status(500).json({
          error: 'Failed to get model metadata',
          message: error.message
        });
      }
    });

    // Main scoring endpoint
    this.app.post('/score', async (req, res) => {
      const startTime = Date.now();

      try {
        if (!this.scoring) {
          return res.status(503).json({
            error: 'Scoring service not initialized'
          });
        }

        // Validate request format
        const { data, features, model_type, modelType } = req.body;

        let inputFeatures;
        if (data) {
          inputFeatures = data;
        } else if (features) {
          inputFeatures = features;
        } else {
          return res.status(400).json({
            error: 'Invalid request format',
            message: 'Request must contain "data" or "features" field with an array of numbers'
          });
        }

        // Validate features array
        if (!Array.isArray(inputFeatures)) {
          return res.status(400).json({
            error: 'Invalid input format',
            message: 'Features must be an array of numbers'
          });
        }

        if (inputFeatures.length !== 8) {
          return res.status(400).json({
            error: 'Invalid input size',
            message: 'Expected 8 features, received ' + inputFeatures.length
          });
        }

        // Make prediction
        const prediction = await this.scoring.predict({
          features: inputFeatures,
          modelType: model_type || modelType || 'random-forest'
        });

        const responseTime = Date.now() - startTime;

        // Log successful prediction
        if (this.monitor) {
          this.monitor.recordMetric('latency', responseTime);
          this.monitor.recordMetric('throughput', 1);
        }

        res.json({
          score: prediction.score,
          confidence: prediction.confidence,
          model_type: prediction.modelType,
          response_time_ms: responseTime,
          request_id: prediction.requestId,
          timestamp: prediction.timestamp
        });

      } catch (error) {
        const responseTime = Date.now() - startTime;

        // Log error
        if (this.monitor) {
          this.monitor.recordMetric('latency', responseTime);
          this.monitor.recordMetric('errors', 1);
        }

        console.error('❌ Prediction error:', error.message);

        res.status(400).json({
          error: 'Prediction failed',
          message: error.message,
          response_time_ms: responseTime,
          timestamp: new Date().toISOString()
        });
      }
    });

    // Metrics endpoint
    this.app.get('/metrics', async (req, res) => {
      try {
        if (!this.monitor) {
          return res.status(503).json({
            error: 'Monitoring not initialized'
          });
        }

        const timeRange = req.query.timeRange || '1h';
        const metrics = await this.monitor.getMetrics({ timeRange });

        res.json({
          timeRange,
          metrics,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        res.status(500).json({
          error: 'Failed to get metrics',
          message: error.message
        });
      }
    });

    // API documentation
    this.app.get('/', (req, res) => {
      res.json({
        name: 'Azure ML Real-Time Scoring API',
        version: '1.0.0',
        description: 'Enterprise-grade real-time machine learning prediction service',
        endpoints: {
          'POST /score': 'Make predictions with ML models',
          'GET /health': 'Health check endpoint',
          'GET /ready': 'Readiness check endpoint',
          'GET /models': 'Get model metadata',
          'GET /metrics': 'Get performance metrics'
        },
        performance: {
          targetLatency: '< 1000ms',
          targetThroughput: '1000 req/min',
          autoScaling: 'enabled'
        }
      });
    });
  }

  _setupErrorHandling() {
    // 404 handler
    this.app.use('*', (req, res) => {
      res.status(404).json({
        error: 'Not Found',
        message: `Path ${req.originalUrl} not found`,
        availableEndpoints: ['/', '/health', '/ready', '/score', '/models', '/metrics']
      });
    });

    // Global error handler
    this.app.use((error, req, res, next) => {
      console.error('Unhandled error:', error);

      res.status(500).json({
        error: 'Internal Server Error',
        message: error.message,
        timestamp: new Date().toISOString()
      });
    });
  }

  async _authMiddleware(req, res, next) {
    try {
      const authHeader = req.headers.authorization;

      if (!authHeader) {
        return res.status(401).json({
          error: 'Authentication required',
          message: 'Authorization header is required'
        });
      }

      if (!authHeader.startsWith('Bearer ')) {
        return res.status(401).json({
          error: 'Invalid authentication format',
          message: 'Authorization header must start with "Bearer "'
        });
      }

      // In production, validate the token with Azure AD
      const token = authHeader.substring(7);

      // For demo purposes, accept any token that looks like a JWT
      if (token.length < 10) {
        return res.status(401).json({
          error: 'Invalid token',
          message: 'Token appears to be invalid'
        });
      }

      // Add user context to request
      req.user = {
        id: 'authenticated-user',
        token: token
      };

      next();
    } catch (error) {
      res.status(401).json({
        error: 'Authentication failed',
        message: error.message
      });
    }
  }
}

// Convenience function to start the API
export async function startScoringAPI(config = {}, endpointConfig = {}) {
  const api = new ScoringAPI(config);

  if (Object.keys(endpointConfig).length > 0) {
    await api.initialize(endpointConfig);
  }

  await api.start();
  return api;
}