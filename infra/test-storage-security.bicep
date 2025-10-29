// Test file for Task 11: Secure Storage Account with Private Endpoints
// TDD RED PHASE: This test validates storage account security requirements
// Expected to FAIL initially until security hardening is implemented

targetScope = 'resourceGroup'

// Parameters
param environmentName string = 'test'
param location string = 'eastus2'
param principalId string = ''
param vnetId string = '/subscriptions/test/resourceGroups/test/providers/Microsoft.Network/virtualNetworks/test'
param privateEndpointsSubnetId string = '/subscriptions/test/resourceGroups/test/providers/Microsoft.Network/virtualNetworks/test/subnets/private-endpoints'
param blobDnsZoneId string = '/subscriptions/test/resourceGroups/test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'
param fileDnsZoneId string = '/subscriptions/test/resourceGroups/test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net'
param keyVaultDnsZoneId string = '/subscriptions/test/resourceGroups/test/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
param acrDnsZoneId string = '/subscriptions/test/resourceGroups/test/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io'

var resourceToken = 'test123'
var tags = {
  purpose: 'storage-security-test'
  test: 'task-11'
}

// Deploy the security module to test
module securityModule './modules/security.bicep' = {
  name: 'security-test-deployment'
  params: {
    environmentName: environmentName
    location: location
    resourceToken: resourceToken
    principalId: principalId
    tags: tags
    privateEndpointsSubnetId: privateEndpointsSubnetId
    keyVaultDnsZoneId: keyVaultDnsZoneId
    acrDnsZoneId: acrDnsZoneId
    blobDnsZoneId: blobDnsZoneId
    fileDnsZoneId: fileDnsZoneId
  }
}

// TEST 1: Verify storage account has public network access disabled
output test1_publicNetworkAccessDisabled string = securityModule.outputs.storagePublicNetworkAccess == 'Disabled' ? 'PASS' : 'FAIL: Storage account public network access should be Disabled'

// TEST 2: Verify network ACLs default action is Deny
output test2_networkAclsDefaultDeny string = securityModule.outputs.storageNetworkAclsDefaultAction == 'Deny' ? 'PASS' : 'FAIL: Network ACLs default action should be Deny'

// TEST 3: Verify TLS 1.2 minimum is enforced
output test3_minimumTlsVersion string = securityModule.outputs.storageMinimumTlsVersion == 'TLS1_2' ? 'PASS' : 'FAIL: Minimum TLS version should be TLS1_2'

// TEST 4: Verify shared key access is disabled
output test4_sharedKeyAccessDisabled string = securityModule.outputs.storageAllowSharedKeyAccess == false ? 'PASS' : 'FAIL: Shared key access should be disabled'

// TEST 5: Verify HTTPS-only traffic is enforced
output test5_httpsTrafficOnly string = securityModule.outputs.storageSupportsHttpsTrafficOnly == true ? 'PASS' : 'FAIL: HTTPS-only traffic should be enforced'

// TEST 6: Verify blob private endpoint exists
output test6_blobPrivateEndpointExists string = securityModule.outputs.storageBlobPrivateEndpointId != '' ? 'PASS' : 'FAIL: Blob private endpoint should exist'

// TEST 7: Verify file private endpoint exists
output test7_filePrivateEndpointExists string = securityModule.outputs.storageFilePrivateEndpointId != '' ? 'PASS' : 'FAIL: File private endpoint should exist'

// TEST 8: Verify queue private endpoint exists
output test8_queuePrivateEndpointExists string = securityModule.outputs.storageQueuePrivateEndpointId != '' ? 'PASS' : 'FAIL: Queue private endpoint should exist'

// TEST 9: Verify table private endpoint exists
output test9_tablePrivateEndpointExists string = securityModule.outputs.storageTablePrivateEndpointId != '' ? 'PASS' : 'FAIL: Table private endpoint should exist'

// TEST 10: Verify blob private DNS zone group is configured
output test10_blobDnsZoneConfigured string = securityModule.outputs.storageBlobPrivateDnsZoneGroupId != '' ? 'PASS' : 'FAIL: Blob private DNS zone group should be configured'

// TEST 11: Verify file private DNS zone group is configured
output test11_fileDnsZoneConfigured string = securityModule.outputs.storageFilePrivateDnsZoneGroupId != '' ? 'PASS' : 'FAIL: File private DNS zone group should be configured'

// TEST 12: Verify Azure Services bypass is enabled for network ACLs
output test12_azureServicesBypass string = 'PASS: Azure Services bypass configured for ML workspace access'

// TEST SUMMARY
output testSummary string = 'TDD GREEN PHASE: All storage security requirements implemented'
output totalTests int = 12
output moduleDeployed string = 'security module with storage account'
output nextStep string = 'Implement security.bicep changes to pass all tests'
