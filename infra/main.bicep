// Azure ML Fabric Demo - Main Infrastructure Template
targetScope = 'subscription'

// Parameters
@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash for resources.')
param environmentName string = 'dev'

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

@description('Email address of the Fabric capacity administrator')
param fabricAdminEmail string = 'brad.stevens@MngEnvMCAP786696.onmicrosoft.com'

// Variables
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  azd_env_name: environmentName
  project: 'az-ml-fabric-demo'
  purpose: 'ml-fabric-integration'
}

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Network Foundation Module
module network './modules/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

// DNS Infrastructure Module
module dns './modules/dns.bicep' = {
  name: 'dns'
  scope: rg
  params: {
    environmentName: environmentName
    vnetId: network.outputs.vnetId
    tags: tags
  }
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
    privateEndpointsSubnetId: network.outputs.privateEndpointsSubnetId
    keyVaultDnsZoneId: dns.outputs.keyVaultDnsZoneId
    acrDnsZoneId: dns.outputs.acrDnsZoneId
    blobDnsZoneId: dns.outputs.blobDnsZoneId
    fileDnsZoneId: dns.outputs.fileDnsZoneId
  }
  dependsOn: [
    network
    dns
  ]
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
    vnetId: network.outputs.vnetId
    mlWorkspaceSubnetId: network.outputs.mlWorkspaceSubnetId
    computeSubnetId: network.outputs.computeSubnetId
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
    principalId: principalId
    fabricAdminEmail: fabricAdminEmail
    tags: tags
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

// Network Outputs
output AZURE_VNET_NAME string = network.outputs.vnetName
output AZURE_VNET_ID string = network.outputs.vnetId
output AZURE_ML_WORKSPACE_SUBNET_ID string = network.outputs.mlWorkspaceSubnetId
output AZURE_COMPUTE_SUBNET_ID string = network.outputs.computeSubnetId
output AZURE_PRIVATE_ENDPOINTS_SUBNET_ID string = network.outputs.privateEndpointsSubnetId

// DNS Outputs
output AZURE_BLOB_DNS_ZONE_ID string = dns.outputs.blobDnsZoneId
output AZURE_FILE_DNS_ZONE_ID string = dns.outputs.fileDnsZoneId
output AZURE_KEYVAULT_DNS_ZONE_ID string = dns.outputs.keyVaultDnsZoneId
output AZURE_ACR_DNS_ZONE_ID string = dns.outputs.acrDnsZoneId
output AZURE_AZUREML_DNS_ZONE_ID string = dns.outputs.azureMLDnsZoneId

output AZURE_ML_WORKSPACE_NAME string = azureML.outputs.workspaceName
output AZURE_ML_WORKSPACE_URL string = azureML.outputs.workspaceUrl

output FABRIC_WORKSPACE_NAME string = fabric.outputs.workspaceName
output FABRIC_WORKSPACE_URL string = fabric.outputs.workspaceUrl

output AZURE_KEY_VAULT_NAME string = security.outputs.keyVaultName
output AZURE_APPLICATION_INSIGHTS_NAME string = monitoring.outputs.applicationInsightsName