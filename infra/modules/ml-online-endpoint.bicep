/**
 * Azure ML Online Endpoint Infrastructure
 * Real-time scoring endpoint with enterprise performance requirements
 */

@description('The name of the Machine Learning workspace')
param workspaceName string

@description('The name of the online endpoint')
param endpointName string

@description('The Azure region for the endpoint')
param location string = resourceGroup().location

@description('The instance type for the deployment')
param instanceType string = 'Standard_DS3_v2'

@description('The minimum number of instances')
param minInstances int = 2

@description('The maximum number of instances')
param maxInstances int = 10

@description('CPU utilization threshold for auto-scaling')
param cpuThreshold int = 70

@description('Model name to deploy')
param modelName string

@description('Model version to deploy')
param modelVersion string = '1'

@description('Tags to apply to resources')
param tags object = {}

// Reference existing ML workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-04-01' existing = {
  name: workspaceName
}

// Online Endpoint
resource onlineEndpoint 'Microsoft.MachineLearningServices/workspaces/onlineEndpoints@2023-04-01' = {
  parent: mlWorkspace
  name: endpointName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Real-time scoring endpoint for Azure ML Fabric demo'
    authMode: 'AzureADToken'
    traffic: {}
    publicNetworkAccess: 'Enabled'
  }
}

// Online Deployment with auto-scaling
resource onlineDeployment 'Microsoft.MachineLearningServices/workspaces/onlineEndpoints/deployments@2023-04-01' = {
  parent: onlineEndpoint
  name: '${endpointName}-deployment'
  location: location
  tags: tags
  sku: {
    name: 'Default'
    capacity: minInstances
  }
  properties: {
    description: 'Primary deployment for real-time scoring'
    model: {
      referenceType: 'Id'
      assetId: '${mlWorkspace.id}/models/${modelName}/versions/${modelVersion}'
    }
    instanceType: instanceType
    scaleSettings: {
      scaleType: 'TargetUtilization'
      minInstances: minInstances
      maxInstances: maxInstances
      targetUtilizationPercentage: cpuThreshold
      pollingInterval: 'PT1M'
      // Scale up delay: 5 minutes
      scaleUpCooldown: 'PT5M'
      // Scale down delay: 10 minutes
      scaleDownCooldown: 'PT10M'
    }
    requestSettings: {
      requestTimeoutMs: 60000
      maxConcurrentRequestsPerInstance: 10
      maxQueueWait: 'PT1M'
    }
    livenessProbe: {
      failureThreshold: 3
      successThreshold: 1
      period: 'PT10S'
      initialDelay: 'PT30S'
      timeout: 'PT5S'
    }
    readinessProbe: {
      failureThreshold: 3
      successThreshold: 1
      period: 'PT10S'
      initialDelay: 'PT30S'
      timeout: 'PT5S'
    }
    environmentVariables: {
      PYTHONPATH: '/var/azureml-app'
      AML_MODEL_DIR: '/var/azureml-app/azureml-models'
      AZUREML_MODEL_DIR: '/var/azureml-app/azureml-models'
    }
  }
}

// Set traffic to 100% for the deployment
resource endpointTraffic 'Microsoft.MachineLearningServices/workspaces/onlineEndpoints@2023-04-01' = {
  parent: mlWorkspace
  name: endpointName
  location: location
  properties: {
    description: 'Real-time scoring endpoint for Azure ML Fabric demo'
    authMode: 'AzureADToken'
    traffic: {
      '${endpointName}-deployment': 100
    }
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    onlineDeployment
  ]
}

// Diagnostic settings for monitoring
// Note: Requires Log Analytics workspace ID parameter for proper configuration
/*
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${endpointName}-diagnostics'
  scope: onlineEndpoint
  properties: {
    workspaceId: 'REPLACE_WITH_LOG_ANALYTICS_WORKSPACE_ID'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}
*/

// Outputs
output endpointId string = onlineEndpoint.id
output endpointName string = onlineEndpoint.name
output endpointUri string = onlineEndpoint.properties.scoringUri
output endpointSwaggerUri string = onlineEndpoint.properties.swaggerUri
output deploymentName string = onlineDeployment.name
output principalId string = onlineEndpoint.identity.principalId