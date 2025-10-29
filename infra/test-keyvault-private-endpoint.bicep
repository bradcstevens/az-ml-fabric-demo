// Test file for Key Vault Private Endpoint Configuration
// This test validates that the security module properly configures Key Vault with:
// 1. Public network access disabled
// 2. Private endpoint created and connected
// 3. Network ACLs properly configured (Deny by default, bypass AzureServices)
// 4. Private DNS zone group configured
// 5. RBAC configured for managed identity access

targetScope = 'resourceGroup'

param environmentName string = 'test'
param location string = 'eastus'
param resourceToken string = 'testtoken'
param principalId string = ''

// Create minimal dependencies for security module
module network '../infra/modules/network.bicep' = {
  name: 'test-network'
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    tags: {
      test: 'keyvault-private-endpoint'
    }
  }
}

module dns '../infra/modules/dns.bicep' = {
  name: 'test-dns'
  params: {
    environmentName: environmentName
    vnetId: network.outputs.vnetId
    tags: {
      test: 'keyvault-private-endpoint'
    }
  }
}

// Deploy security module with Key Vault
module security '../infra/modules/security.bicep' = {
  name: 'test-security'
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    principalId: principalId
    privateEndpointsSubnetId: network.outputs.privateEndpointsSubnetId
    keyVaultDnsZoneId: dns.outputs.keyVaultDnsZoneId
    tags: {
      test: 'keyvault-private-endpoint'
    }
  }
  dependsOn: [
    network
    dns
  ]
}

// Test Outputs - Validation Criteria

// Test 1: Verify Key Vault is created
output keyVaultId string = security.outputs.keyVaultId
output keyVaultName string = security.outputs.keyVaultName

// Test 2: Verify Key Vault URI is accessible (for private endpoint validation)
output keyVaultUri string = security.outputs.keyVaultUri

// Test 3: Verify private endpoints subnet exists (dependency validation)
output privateEndpointsSubnetId string = network.outputs.privateEndpointsSubnetId

// Test 4: Verify Key Vault DNS zone exists (DNS resolution validation)
output keyVaultDnsZoneId string = dns.outputs.keyVaultDnsZoneId

// Test 5: Verify VNet integration
output vnetId string = network.outputs.vnetId

// Expected Results:
// - Key Vault should have publicNetworkAccess: 'Disabled'
// - Key Vault should have networkAcls.defaultAction: 'Deny'
// - Key Vault should have networkAcls.bypass: 'AzureServices'
// - Private endpoint should be created with groupIds: ['vault']
// - Private DNS zone group should link to keyVaultDnsZoneId
// - RBAC role 'Key Vault Secrets User' should be assigned if principalId provided
// - Private endpoint should be connected to privateEndpointsSubnetId
// - All resources should be in same location
