// Azure ML Fabric Demo - Main Infrastructure Template
targetScope = 'subscription'

// Parameters
@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash for resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

// Variables
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  'project': 'az-ml-fabric-demo'
  'purpose': 'ml-fabric-integration'
}

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Security Module
module security './modules/security.bicep' = {
  name: 'security'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    principalId: principalId
    tags: tags
  }
}

// Monitoring Module
module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// Azure ML Module
module azureML './modules/azureml.bicep' = {
  name: 'azureml'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    keyVaultName: security.outputs.keyVaultName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    containerRegistryName: security.outputs.containerRegistryName
    storageAccountName: security.outputs.storageAccountName
    tags: tags
  }
}

// Microsoft Fabric Module
module fabric './modules/fabric.bicep' = {
  name: 'fabric'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

output AZURE_ML_WORKSPACE_NAME string = azureML.outputs.workspaceName
output AZURE_ML_WORKSPACE_URL string = azureML.outputs.workspaceUrl

output FABRIC_WORKSPACE_NAME string = fabric.outputs.workspaceName
output FABRIC_WORKSPACE_URL string = fabric.outputs.workspaceUrl

output AZURE_KEY_VAULT_NAME string = security.outputs.keyVaultName
output AZURE_APPLICATION_INSIGHTS_NAME string = monitoring.outputs.applicationInsightsName