// Azure Virtual Network Foundation Module
// TDD GREEN PHASE: Minimal implementation to pass tests

param environmentName string
param location string
param resourceToken string
param tags object = {}

// Variables
var abbrs = loadJsonContent('../abbreviations.json')
var vnetName = '${abbrs.networkVirtualNetworks}${environmentName}-${resourceToken}'

// VNet with 10.0.0.0/16 address space (avoiding 172.17.0.0/16 per Azure ML requirements)
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
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
          networkSecurityGroup: {
            id: mlWorkspaceNsg.id
          }
          routeTable: {
            id: mlWorkspaceRouteTable.id
          }
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
          networkSecurityGroup: {
            id: computeNsg.id
          }
          routeTable: {
            id: computeRouteTable.id
          }
        }
      }
      {
        name: 'private-endpoints-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          networkSecurityGroup: {
            id: privateEndpointsNsg.id
          }
        }
      }
      {
        name: 'management-subnet'
        properties: {
          addressPrefix: '10.0.4.0/24'
          networkSecurityGroup: {
            id: managementNsg.id
          }
        }
      }
    ]
  }
}

// Network Security Groups for each subnet
resource mlWorkspaceNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vnetName}-ml-workspace-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureMLWorkspaceInbound'
        properties: {
          description: 'Allow Azure ML workspace communication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureMachineLearning'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowPrivateEndpointsInbound'
        properties: {
          description: 'Allow private endpoint connections'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureResourceManagerOutbound'
        properties: {
          description: 'Allow outbound to Azure Resource Manager'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureResourceManager'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          description: 'Allow outbound to Azure Storage'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 1100
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource computeNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vnetName}-compute-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureMLServices'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['443', '8080', '18881']
          sourceAddressPrefix: 'AzureMachineLearning'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBatchNodeManagement'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '29876-29877'
          sourceAddressPrefix: 'BatchNodeManagement'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource privateEndpointsNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vnetName}-private-endpoints-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowPrivateEndpointsInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource managementNsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vnetName}-management-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureResourceManagerOutbound'
        properties: {
          description: 'Allow management traffic to Azure Resource Manager'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureResourceManager'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureMonitorOutbound'
        properties: {
          description: 'Allow monitoring and diagnostics'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 1100
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Route Tables for controlled traffic flow
resource mlWorkspaceRouteTable 'Microsoft.Network/routeTables@2023-05-01' = {
  name: '${vnetName}-ml-workspace-rt'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'AzureMLServices'
        properties: {
          addressPrefix: 'AzureMachineLearning'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'AzureResourceManager'
        properties: {
          addressPrefix: 'AzureResourceManager'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

resource computeRouteTable 'Microsoft.Network/routeTables@2023-05-01' = {
  name: '${vnetName}-compute-rt'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'AzureMLServices'
        properties: {
          addressPrefix: 'AzureMachineLearning'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'Storage'
        properties: {
          addressPrefix: 'Storage'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

// Outputs for test validation
output vnetName string = vnet.name
output vnetId string = vnet.id
output vnetAddressSpace string = vnet.properties.addressSpace.addressPrefixes[0]

// Subnet outputs
output mlWorkspaceSubnetId string = vnet.properties.subnets[0].id
output mlWorkspaceSubnetCidr string = vnet.properties.subnets[0].properties.addressPrefix
output computeSubnetId string = vnet.properties.subnets[1].id
output computeSubnetCidr string = vnet.properties.subnets[1].properties.addressPrefix
output privateEndpointsSubnetId string = vnet.properties.subnets[2].id
output privateEndpointsSubnetCidr string = vnet.properties.subnets[2].properties.addressPrefix
output managementSubnetId string = vnet.properties.subnets[3].id
output managementSubnetCidr string = vnet.properties.subnets[3].properties.addressPrefix

// NSG outputs
output mlWorkspaceNsgId string = mlWorkspaceNsg.id
output computeNsgId string = computeNsg.id
output privateEndpointsNsgId string = privateEndpointsNsg.id
output managementNsgId string = managementNsg.id

// Delegation and policy outputs
output computeSubnetDelegation string = vnet.properties.subnets[1].properties.delegations[0].properties.serviceName
output mlWorkspacePrivateEndpointPolicies string = vnet.properties.subnets[0].properties.privateEndpointNetworkPolicies
output privateEndpointsPrivateEndpointPolicies string = vnet.properties.subnets[2].properties.privateEndpointNetworkPolicies

// Route table outputs
output mlWorkspaceRouteTableId string = mlWorkspaceRouteTable.id
output computeRouteTableId string = computeRouteTable.id