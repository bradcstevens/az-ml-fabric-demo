// Private DNS Infrastructure Module
// TDD REFACTOR PHASE: Optimized implementation with cloud compatibility

param environmentName string
param vnetId string
param tags object = {}

// Variables for cloud environment compatibility
var storageSuffix = environment().suffixes.storage
var keyVaultSuffix = 'vault${environment().suffixes.keyvaultDns}'  // Build proper suffix without double dot
var acrSuffix = 'azurecr.io'  // ACR has standard suffix across clouds
var azureMLSuffix = 'api.azureml.ms'  // Azure ML has standard suffix across clouds

// Private DNS Zones for Azure Services
// 1. Storage Account - Blob Service
resource blobDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${storageSuffix}'
  location: 'global'
  tags: tags
  properties: {}
}

// 2. Storage Account - File Service
resource fileDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.${storageSuffix}'
  location: 'global'
  tags: tags
  properties: {}
}

// 3. Key Vault
resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.${keyVaultSuffix}'
  location: 'global'
  tags: tags
  properties: {}
}

// 4. Azure Container Registry
resource acrDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.${acrSuffix}'
  location: 'global'
  tags: tags
  properties: {}
}

// 5. Azure ML Workspace
resource azureMLDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.${azureMLSuffix}'
  location: 'global'
  tags: tags
  properties: {}
}

// Virtual Network Links for each DNS Zone
// Auto-registration disabled for manual DNS management

resource blobVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobDnsZone
  name: '${environmentName}-blob-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource fileVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: fileDnsZone
  name: '${environmentName}-file-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource keyVaultVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: '${environmentName}-keyvault-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource acrVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrDnsZone
  name: '${environmentName}-acr-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource azureMLVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: azureMLDnsZone
  name: '${environmentName}-azureml-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// Outputs for test validation
output blobDnsZoneName string = blobDnsZone.name
output fileDnsZoneName string = fileDnsZone.name
output keyVaultDnsZoneName string = keyVaultDnsZone.name
output acrDnsZoneName string = acrDnsZone.name
output azureMLDnsZoneName string = azureMLDnsZone.name

output blobVnetLinkId string = blobVnetLink.id
output fileVnetLinkId string = fileVnetLink.id
output keyVaultVnetLinkId string = keyVaultVnetLink.id
output acrVnetLinkId string = acrVnetLink.id
output azureMLVnetLinkId string = azureMLVnetLink.id

output autoRegistrationEnabled bool = false
output dnsZonesLocation string = 'global'

// Additional outputs for integration
output blobDnsZoneId string = blobDnsZone.id
output fileDnsZoneId string = fileDnsZone.id
output keyVaultDnsZoneId string = keyVaultDnsZone.id
output acrDnsZoneId string = acrDnsZone.id
output azureMLDnsZoneId string = azureMLDnsZone.id