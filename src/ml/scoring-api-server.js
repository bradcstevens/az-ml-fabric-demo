#!/usr/bin/env node
/**
 * Scoring API Server Entry Point
 * Production server for real-time ML predictions
 */

import { ScoringAPI } from './scoring-api.js';

async function main() {
  try {
    console.log('🚀 Starting Azure ML Real-Time Scoring API...');

    // Configuration from environment variables
    const config = {
      port: process.env.PORT || 8080,
      corsOrigins: process.env.CORS_ORIGINS ?
        process.env.CORS_ORIGINS.split(',') : ['*'],
      rateLimitMax: parseInt(process.env.RATE_LIMIT_MAX) || 1000,
      rateLimitWindow: parseInt(process.env.RATE_LIMIT_WINDOW) || 60000,
      requireAuth: process.env.REQUIRE_AUTH !== 'false'
    };

    // Azure ML endpoint configuration
    const endpointConfig = {
      subscriptionId: process.env.AZURE_SUBSCRIPTION_ID,
      resourceGroup: process.env.AZURE_RESOURCE_GROUP,
      workspaceName: process.env.AZURE_ML_WORKSPACE_NAME,
      location: process.env.AZURE_LOCATION || 'eastus',
      endpointName: process.env.ENDPOINT_NAME || 'fabric-demo-endpoint'
    };

    // Create and initialize API
    const api = new ScoringAPI(config);

    // Initialize with Azure ML endpoint if credentials available
    if (endpointConfig.subscriptionId) {
      await api.initialize(endpointConfig);
    } else {
      console.log('⚠️  Azure credentials not provided, running in mock mode');
    }

    // Start the server
    await api.start();

    // Graceful shutdown handling
    process.on('SIGTERM', async () => {
      console.log('📝 Received SIGTERM, shutting down gracefully...');
      await api.stop();
      process.exit(0);
    });

    process.on('SIGINT', async () => {
      console.log('📝 Received SIGINT, shutting down gracefully...');
      await api.stop();
      process.exit(0);
    });

  } catch (error) {
    console.error('❌ Failed to start Scoring API:', error.message);
    process.exit(1);
  }
}

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  process.exit(1);
});

main();