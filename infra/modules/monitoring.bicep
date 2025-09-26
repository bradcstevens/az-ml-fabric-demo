// Monitoring and Observability Module
param environmentName string
param location string
param resourceToken string
param tags object = {}

// Variables
var abbrs = loadJsonContent('../abbreviations.json')
var logAnalyticsName = '${abbrs.operationalInsightsWorkspaces}${environmentName}-${resourceToken}'
var applicationInsightsName = '${abbrs.insightsComponents}${environmentName}-${resourceToken}'

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2022-06-01' = {
  name: '${environmentName}-alerts'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ml-alerts'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureAutomationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// ML Model Performance Alert
resource modelPerformanceAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${environmentName}-model-performance'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when ML model performance degrades'
    severity: 2
    enabled: true
    scopes: [
      logAnalytics.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ModelAccuracy'
          metricName: 'Accuracy'
          operator: 'LessThan'
          threshold: 0.8
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Pipeline Failure Alert
resource pipelineFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${environmentName}-pipeline-failure'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when ML pipeline fails'
    severity: 1
    enabled: true
    scopes: [
      logAnalytics.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'PipelineFailures'
          metricName: 'FailedRuns'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Outputs
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output applicationInsightsId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output actionGroupId string = actionGroup.id