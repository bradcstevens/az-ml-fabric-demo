// Azure Machine Learning Workspace Module
param environmentName string
param location string
param resourceToken string
param keyVaultName string
param applicationInsightsName string
param containerRegistryName string
param storageAccountName string
param tags object = {}

// Variables
var abbrs = loadJsonContent('../abbreviations.json')
var workspaceName = '${abbrs.machineLearningServicesWorkspaces}${environmentName}-${resourceToken}'

// Azure Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-04-01' = {
  name: workspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: '${environmentName} ML Workspace'
    description: 'Azure ML workspace for predictive analytics and model training'
    keyVault: resourceId('Microsoft.KeyVault/vaults', keyVaultName)
    applicationInsights: resourceId('Microsoft.Insights/components', applicationInsightsName)
    containerRegistry: resourceId('Microsoft.ContainerRegistry/registries', containerRegistryName)
    storageAccount: resourceId('Microsoft.Storage/storageAccounts', storageAccountName)
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }
}

// Compute Instance for development
resource computeInstance 'Microsoft.MachineLearningServices/workspaces/computes@2023-04-01' = {
  parent: mlWorkspace
  name: 'dev-instance'
  location: location
  properties: {
    computeType: 'ComputeInstance'
    properties: {
      vmSize: 'Standard_DS3_v2'
      subnet: null
      applicationSharingPolicy: 'Personal'
      sshSettings: {
        sshPublicAccess: 'Disabled'
      }
      personalComputeInstanceSettings: {
        assignedUser: {
          objectId: ''
          tenantId: tenant().tenantId
        }
      }
    }
  }
}

// Compute Cluster for training
resource computeCluster 'Microsoft.MachineLearningServices/workspaces/computes@2023-04-01' = {
  parent: mlWorkspace
  name: 'training-cluster'
  location: location
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: 'Standard_DS3_v2'
      vmPriority: 'Dedicated'
      scaleSettings: {
        minNodeCount: 0
        maxNodeCount: 4
        nodeIdleTimeBeforeScaleDown: 'PT2M'
      }
      enableNodePublicIp: false
      isolatedNetwork: false
      osType: 'Linux'
    }
  }
}

// Inference Cluster for real-time endpoints
resource inferenceCluster 'Microsoft.MachineLearningServices/workspaces/computes@2023-04-01' = {
  parent: mlWorkspace
  name: 'inference-cluster'
  location: location
  properties: {
    computeType: 'AKS'
    properties: {
      agentCount: 3
      agentVmSize: 'Standard_DS3_v2'
      clusterFqdn: ''
      sslConfiguration: {
        status: 'Disabled'
      }
      loadBalancerType: 'PublicIp'
    }
  }
}

// Outputs
output workspaceName string = mlWorkspace.name
output workspaceId string = mlWorkspace.id
output workspaceUrl string = 'https://ml.azure.com/workspaces/${mlWorkspace.id}'
output computeInstanceName string = computeInstance.name
output computeClusterName string = computeCluster.name
output inferenceClusterName string = inferenceCluster.name