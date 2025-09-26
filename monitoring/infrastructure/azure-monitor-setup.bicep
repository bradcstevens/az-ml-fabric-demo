// Azure Monitor Infrastructure Setup
// This Bicep template deploys comprehensive monitoring infrastructure
// for the Azure ML + Fabric demo including Log Analytics, Application Insights,
// and monitoring configuration for all system components.

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Project name prefix')
param projectName string = 'az-ml-fabric-demo'

@description('Log Analytics workspace retention in days')
param logRetentionDays int = 30

@description('Application Insights sampling percentage')
param samplingPercentage int = 100

@description('Enable diagnostic logs for all resources')
param enableDiagnosticLogs bool = true

@description('Tags to apply to all resources')
param resourceTags object = {
  project: 'azure-ml-fabric-demo'
  environment: environment
  purpose: 'monitoring'
  costCenter: 'ml-engineering'
}

// Variables
var workspaceName = '${projectName}-logs-${environment}'
var appInsightsName = '${projectName}-insights-${environment}'
var actionGroupName = '${projectName}-alerts-${environment}'
var dashboardName = '${projectName}-dashboard-${environment}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10 // 10GB daily cap to control costs
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    SamplingPercentage: samplingPercentage
    RetentionInDays: logRetentionDays
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'MLAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'ML Engineering Team'
        emailAddress: 'ml-team@company.com'
        useCommonAlertSchema: true
      }
      {
        name: 'DevOps Team'
        emailAddress: 'devops@company.com'
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunction: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: [
      {
        name: 'Owner Role'
        roleId: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Data Collection Rules for Azure ML Services
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${projectName}-dcr-${environment}'
  location: location
  tags: resourceTags
  properties: {
    description: 'Data collection rule for Azure ML and Fabric services'
    dataSources: {
      performanceCounters: [
        {
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
            '\\Memory\\% Committed Bytes In Use'
            '\\Network Interface(*)\\Bytes Total/sec'
            '\\PhysicalDisk(_Total)\\% Disk Time'
            '\\PhysicalDisk(_Total)\\Disk Bytes/sec'
          ]
          name: 'perfCounterDataSource'
        }
      ]
      windowsEventLogs: [
        {
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
          ]
          name: 'eventLogsDataSource'
        }
      ]
      syslog: [
        {
          streams: ['Microsoft-Syslog']
          facilityNames: ['*']
          logLevels: ['*']
          name: 'syslogDataSource'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'logAnalyticsDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Perf']
        destinations: ['logAnalyticsDestination']
      }
      {
        streams: ['Microsoft-Event']
        destinations: ['logAnalyticsDestination']
      }
      {
        streams: ['Microsoft-Syslog']
        destinations: ['logAnalyticsDestination']
      }
    ]
  }
}

// Diagnostic Settings for Resource Group
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  scope: resourceGroup()
  name: 'resourceGroupDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'Administrative'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'Security'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'Alert'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Azure ML Workspace Monitoring (if exists)
resource azureMLWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-10-01' existing = {
  name: '${projectName}-ml-${environment}'
}

resource mlWorkspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  scope: azureMLWorkspace
  name: 'mlWorkspaceDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AmlComputeClusterEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'AmlComputeClusterNodeEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'AmlComputeJobEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'AmlComputeCpuGpuUtilization'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'AmlRunStatusChangedEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'ModelsChangeEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'ModelsReadEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'ModelsActionEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'DataLabelChangeEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'DataLabelReadEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'DataSetChangeEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'DataSetReadEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'DataStoreChangeEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'DataStoreReadEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'EnvironmentChangeEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'EnvironmentReadEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'InferencingOperationEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Storage Account Monitoring (for data lake)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: '${replace(projectName, '-', '')}stor${environment}'
}

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  scope: storageAccount
  name: 'storageAccountDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'StorageRead'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'StorageWrite'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'StorageDelete'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Container Registry Monitoring (if exists)
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: '${replace(projectName, '-', '')}acr${environment}'
}

resource acrDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  scope: containerRegistry
  name: 'acrDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'ContainerRegistryLoginEvents'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Key Vault Monitoring (if exists)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: '${projectName}-kv-${environment}'
}

resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  scope: keyVault
  name: 'keyVaultDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Outputs
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output applicationInsightsId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output actionGroupId string = actionGroup.id
output actionGroupName string = actionGroup.name
output dataCollectionRuleId string = dataCollectionRule.id

// Resource information for reference
output monitoringResources object = {
  logAnalytics: {
    id: logAnalyticsWorkspace.id
    name: logAnalyticsWorkspace.name
    customerId: logAnalyticsWorkspace.properties.customerId
  }
  applicationInsights: {
    id: applicationInsights.id
    name: applicationInsights.name
    instrumentationKey: applicationInsights.properties.InstrumentationKey
    connectionString: applicationInsights.properties.ConnectionString
  }
  actionGroup: {
    id: actionGroup.id
    name: actionGroup.name
  }
  dataCollectionRule: {
    id: dataCollectionRule.id
    name: dataCollectionRule.name
  }
}