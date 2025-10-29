// Security and Storage Module
param environmentName string
param location string
param resourceToken string
param principalId string
param tags object = {}
param privateEndpointsSubnetId string
param keyVaultDnsZoneId string
param acrDnsZoneId string
param blobDnsZoneId string
param fileDnsZoneId string

// Variables
var abbrs = loadJsonContent('../abbreviations.json')
var keyVaultName = take('${abbrs.keyVaultVaults}${replace(environmentName, '-', '')}${resourceToken}', 24)
var storageAccountName = length('st${replace(environmentName, '-', '')}${resourceToken}') >= 3 ? take('st${replace(environmentName, '-', '')}${resourceToken}', 24) : take('st${replace(environmentName, '-', '')}${resourceToken}demo', 24)
var containerRegistryName = length('cr${replace(environmentName, '-', '')}${resourceToken}') >= 5 ? take('cr${replace(environmentName, '-', '')}${resourceToken}', 50) : 'cr${replace(environmentName, '-', '')}${resourceToken}demo'

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Private Endpoint for Key Vault
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${keyVaultName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVaultName}-pe-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

// Private DNS Zone Group for Key Vault Private Endpoint
resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: keyVaultDnsZoneId
        }
      }
    ]
  }
}

// Storage Account for ML artifacts and data
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Disabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Blob containers for ML data
resource mlDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${storageAccount.name}/default/mldata'
  properties: {
    publicAccess: 'None'
  }
}

resource modelsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${storageAccount.name}/default/models'
  properties: {
    publicAccess: 'None'
  }
}

resource artifactsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${storageAccount.name}/default/artifacts'
  properties: {
    publicAccess: 'None'
  }
}

// Private Endpoint for Storage Account - Blob Service
resource storageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${storageAccountName}-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-blob-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

// Private DNS Zone Group for Blob Private Endpoint
resource storageBlobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: storageBlobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: blobDnsZoneId
        }
      }
    ]
  }
}

// Private Endpoint for Storage Account - File Service
resource storageFilePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${storageAccountName}-file-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-file-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['file']
        }
      }
    ]
  }
}

// Private DNS Zone Group for File Private Endpoint
resource storageFilePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: storageFilePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-file-core-windows-net'
        properties: {
          privateDnsZoneId: fileDnsZoneId
        }
      }
    ]
  }
}

// Private Endpoint for Storage Account - Queue Service
resource storageQueuePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${storageAccountName}-queue-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-queue-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['queue']
        }
      }
    ]
  }
}

// Private Endpoint for Storage Account - Table Service
resource storageTablePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${storageAccountName}-table-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-table-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['table']
        }
      }
    ]
  }
}

// Container Registry for ML model images
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: 'Disabled'
    networkRuleSet: {
      defaultAction: 'Deny'
    }
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
      softDeletePolicy: {
        retentionDays: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
  }
}

// Private Endpoint for Container Registry
resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${containerRegistryName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${containerRegistryName}-pe-connection'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: ['registry']
        }
      }
    ]
  }
}

// Private DNS Zone Group for ACR Private Endpoint
resource acrPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: acrPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: acrDnsZoneId
        }
      }
    ]
  }
}

// Role assignments for the principal
resource keyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  scope: keyVault
  name: guid(subscription().id, resourceGroup().id, principalId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalType: 'User'
    principalId: principalId
  }
}

resource storageAccountContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  scope: storageAccount
  name: guid(subscription().id, resourceGroup().id, principalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalType: 'User'
    principalId: principalId
  }
}

resource containerRegistryContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  scope: containerRegistry
  name: guid(subscription().id, resourceGroup().id, principalId, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalType: 'User'
    principalId: principalId
  }
}

// Outputs
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output containerRegistryId string = containerRegistry.id
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

// Storage Account Security Outputs for Test Validation
output storagePublicNetworkAccess string = storageAccount.properties.publicNetworkAccess
output storageNetworkAclsDefaultAction string = storageAccount.properties.networkAcls.defaultAction
output storageMinimumTlsVersion string = storageAccount.properties.minimumTlsVersion
output storageAllowSharedKeyAccess bool = storageAccount.properties.allowSharedKeyAccess
output storageSupportsHttpsTrafficOnly bool = storageAccount.properties.supportsHttpsTrafficOnly

// Storage Private Endpoint Outputs
output storageBlobPrivateEndpointId string = storageBlobPrivateEndpoint.id
output storageFilePrivateEndpointId string = storageFilePrivateEndpoint.id
output storageQueuePrivateEndpointId string = storageQueuePrivateEndpoint.id
output storageTablePrivateEndpointId string = storageTablePrivateEndpoint.id

// Storage Private DNS Zone Group Outputs
output storageBlobPrivateDnsZoneGroupId string = storageBlobPrivateDnsZoneGroup.id
output storageFilePrivateDnsZoneGroupId string = storageFilePrivateDnsZoneGroup.id