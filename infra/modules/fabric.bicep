// Microsoft Fabric Workspace Module
param environmentName string
param location string
param resourceToken string
param tags object = {}

// Variables
var abbrs = loadJsonContent('../abbreviations.json')
var fabricWorkspaceName = '${abbrs.fabricWorkspaces}${environmentName}-${resourceToken}'
var fabricCapacityName = '${abbrs.fabricCapacities}${environmentName}-${resourceToken}'

// Microsoft Fabric Capacity
resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: fabricCapacityName
  location: location
  tags: tags
  sku: {
    name: 'F2'
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: []
    }
  }
}

// Microsoft Fabric Workspace
resource fabricWorkspace 'Microsoft.PowerBIDedicated/capacities@2021-01-01' = {
  name: fabricWorkspaceName
  location: location
  tags: tags
  sku: {
    name: 'A1'
    tier: 'PBIE_Azure'
  }
  properties: {
    administration: {
      members: []
    }
    mode: 'Gen2'
  }
}

// Data Factory for data integration (part of Fabric ecosystem)
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: '${abbrs.dataFactoryFactories}${environmentName}-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    globalConfigurations: {}
    publicNetworkAccess: 'Enabled'
  }
}

// Event Hub for real-time data streaming
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2022-10-01-preview' = {
  name: '${abbrs.eventHubNamespaces}${environmentName}-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    kafkaEnabled: true
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2022-10-01-preview' = {
  parent: eventHubNamespace
  name: 'ml-predictions'
  properties: {
    messageRetentionInDays: 7
    partitionCount: 4
    status: 'Active'
  }
}

// Synapse Analytics workspace for big data processing
resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: '${abbrs.synapseWorkspaces}${environmentName}-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://fabricstorage${resourceToken}.dfs.core.windows.net'
      filesystem: 'fabricdata'
    }
    sqlAdministratorLogin: 'sqladmin'
    sqlAdministratorLoginPassword: 'TempPassword123!'
    managedResourceGroupName: 'rg-${environmentName}-synapse-managed'
    publicNetworkAccess: 'Enabled'
    trustedServiceBypassEnabled: true
  }
}

// Outputs
output workspaceName string = fabricWorkspace.name
output workspaceId string = fabricWorkspace.id
output workspaceUrl string = 'https://app.fabric.microsoft.com/workspaces/${fabricWorkspace.name}'
output capacityName string = fabricCapacity.name
output dataFactoryName string = dataFactory.name
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output synapseWorkspaceName string = synapseWorkspace.name