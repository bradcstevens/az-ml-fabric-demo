# Azure ML Private Endpoints and VNet Integration Research

**Research Date:** 2025-09-26
**Technologies:** Azure Machine Learning, Private Endpoints, Virtual Networks, Bicep Templates
**Focus:** Security enhancement for ML workspace isolation

## Key Findings

### Azure ML Workspace Private Endpoint Requirements

From Microsoft Learn documentation:
- Private endpoints required for workspace, storage, Key Vault, and Container Registry
- Avoid 172.17.0.0/16 IP range (conflicts with Docker bridge network)
- Requires subnet with `privateEndpointNetworkPolicies: 'Disabled'`
- Must implement trusted service access patterns

### Storage Account Security Configuration

**Critical Security Settings:**
```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  properties: {
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: subnetId
          action: 'Allow'
        }
      ]
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}
```

### Private Endpoint Bicep Patterns

**Standard Private Endpoint Template:**
```bicep
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${resourceName}-pe'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${resourceName}-connection'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: ['blob'] // or 'file', 'queue', 'table'
        }
      }
    ]
  }
}
```

### Private DNS Zone Configuration

**Required DNS Zones:**
```bicep
// Storage Account DNS Zones
resource blobDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

resource fileDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.core.windows.net'
  location: 'global'
}

// Azure ML DNS Zone
resource mlDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.api.azureml.ms'
  location: 'global'
}

// Key Vault DNS Zone
resource kvDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}
```

### VNet Configuration for ML Workloads

**Subnet Design:**
```bicep
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'ml-workspace-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'ml-compute-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          delegations: [
            {
              name: 'Microsoft.MachineLearningServices/workspaces'
              properties: {
                serviceName: 'Microsoft.MachineLearningServices/workspaces'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}
```

### Azure ML Workspace Security Configuration

**Updated Workspace Properties:**
```bicep
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-04-01' = {
  properties: {
    publicNetworkAccess: 'Disabled'
    managedNetwork: {
      isolationMode: 'AllowInternetOutbound'
      outboundRules: {
        required_outbound_rules: {
          type: 'ServiceTag'
          destination: 'AzureResourceManager'
        }
      }
    }
    // Private endpoint will be created separately
  }
}
```

### Compute Cluster Security

**Private Compute Configuration:**
```bicep
resource computeCluster 'Microsoft.MachineLearningServices/workspaces/computes@2023-04-01' = {
  properties: {
    computeType: 'AmlCompute'
    properties: {
      enableNodePublicIp: false
      subnet: {
        id: computeSubnetId
      }
      isolatedNetwork: true
    }
  }
}
```

## Implementation Key Points

1. **Deployment Order**: VNet → DNS Zones → Private Endpoints → DNS Zone Links
2. **Testing**: Validate DNS resolution and connectivity from compute instances
3. **Monitoring**: Configure NSG flow logs and diagnostic settings
4. **Security**: Implement least privilege RBAC for managed identities

## Best Practices

- Use latest API versions (2023-05-01 for networking, 2023-04-01 for ML)
- Separate subnets for different resource types
- Implement Network Security Groups with restrictive rules
- Use managed identities for authentication
- Enable diagnostic logging for all resources

## Common Issues

- DNS resolution failures without proper private DNS zone configuration
- Compute cluster deployment failures without proper subnet delegation
- Storage access issues without proper network ACL configuration