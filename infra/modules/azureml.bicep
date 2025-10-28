// Azure Machine Learning Workspace Module
param environmentName string
param location string
param resourceToken string
param keyVaultName string
param applicationInsightsName string
param containerRegistryName string
param storageAccountName string
param vnetId string
param mlWorkspaceSubnetId string
param computeSubnetId string
param tags object = {}

// Variables
var abbrs = loadJsonContent('../abbreviations.json')
var workspaceName = take('${abbrs.machineLearningServicesWorkspaces}${replace(environmentName, '-', '')}${resourceToken}', 33)

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
// Note: Compute instances require a user objectId to be assigned
// Uncomment and provide valid objectId when needed
/*
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
          objectId: 'REPLACE_WITH_USER_OBJECT_ID'
          tenantId: tenant().tenantId
        }
      }
    }
  }
}
*/

// Compute Cluster for training - with private networking
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
      enableNodePublicIp: true
      subnet: {
        id: computeSubnetId
      }
      osType: 'Linux'
    }
  }
}

// Inference Cluster for real-time endpoints
// Note: AKS compute is being deprecated in favor of managed endpoints
// Uncomment if you need AKS compute specifically
/*
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
*/

// Outputs
output workspaceName string = mlWorkspace.name
output workspaceId string = mlWorkspace.id
output workspaceUrl string = 'https://ml.azure.com/workspaces/${mlWorkspace.id}'
// output computeInstanceName string = computeInstance.name // Commented out since compute instance is disabled
output computeClusterName string = computeCluster.name
// output inferenceClusterName string = inferenceCluster.name // Commented out since inference cluster is disabled