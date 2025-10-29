// Microsoft Fabric Workspace Module
param environmentName string
param location string
param resourceToken string
param principalId string = ''
param fabricAdminEmail string = ''
param tags object = {}

// Variables
var abbrs = loadJsonContent('../abbreviations.json')
var fabricWorkspaceName = length(replace('${abbrs.fabricWorkspaces}${environmentName}${resourceToken}', '-', '')) >= 3 ? take(replace('${abbrs.fabricWorkspaces}${environmentName}${resourceToken}', '-', ''), 63) : '${replace('${abbrs.fabricWorkspaces}${environmentName}${resourceToken}', '-', '')}demo'

// Microsoft Fabric Capacity
// Note: Microsoft.Fabric/capacities API may not be available in all regions
// Uncomment when Fabric capacity is available in your region
/*
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
*/

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
      members: !empty(fabricAdminEmail) ? [fabricAdminEmail] : (!empty(principalId) ? [principalId] : ['brad.stevens@MngEnvMCAP786696.onmicrosoft.com'])
    }
    mode: 'Gen2'
  }
}

// Data Factory for data integration (part of Fabric ecosystem)
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: '${abbrs.dataFactoryFactories}${replace(environmentName, '-', '')}${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// Event Hub for real-time data streaming
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2022-10-01-preview' = {
  name: '${abbrs.eventHubNamespaces}${replace(environmentName, '-', '')}${resourceToken}'
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

// Synapse Analytics workspace - Removed to avoid creating empty managed resource group
// If needed in the future, uncomment this resource
/*
resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: '${abbrs.synapseWorkspaces}${replace(environmentName, '-', '')}${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://st${replace(environmentName, '-', '')}${resourceToken}.dfs.${environment().suffixes.storage}'
      filesystem: 'fabricdata'
    }
    sqlAdministratorLogin: 'sqladmin'
    sqlAdministratorLoginPassword: 'TempPassword123!'
    managedResourceGroupName: 'rg-${environmentName}-synapse-managed'
    publicNetworkAccess: 'Enabled'
    trustedServiceBypassEnabled: true
  }
}
*/

// Outputs
output workspaceName string = fabricWorkspace.name
output workspaceId string = fabricWorkspace.id
output workspaceUrl string = 'https://app.fabric.microsoft.com/workspaces/${fabricWorkspace.name}'
// output capacityName string = fabricCapacity.name // Commented out since capacity is disabled
output dataFactoryName string = dataFactory.name
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
// output synapseWorkspaceName string = synapseWorkspace.name  // Removed - Synapse workspace commented out