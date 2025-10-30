@description('The name of the function app. Must be globally unique.')
param functionAppName string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The name of the storage account. Must be globally unique.')
param storageAccountName string

@description('Use an existing storage account instead of creating a new one.')
param useExistingStorageAccount bool = false

@description('Storage account SKU name.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountType string = 'Standard_LRS'

@description('The language worker runtime to load in the function app.')
@allowed([
  'python'
  'node'
  'dotnet'
  'java'
])
param runtime string = 'python'

@description('Runtime version (e.g., 3.11 for Python, 20 for Node.js)')
param runtimeVersion string = '3.11'

@description('Enable VNet integration for the function app.')
param enableVNetIntegration bool = false

@description('Use an existing VNet instead of creating a new one.')
param useExistingVNet bool = false

@description('Name of the VNet (required if enableVNetIntegration is true)')
param vnetName string = ''

@description('Address prefix for VNet (e.g., 10.0.0.0/16)')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet name for function app integration')
param functionSubnetName string = 'function-subnet'

@description('Address prefix for function subnet (e.g., 10.0.1.0/24)')
param functionSubnetAddressPrefix string = '10.0.1.0/24'

@description('Subnet name for private endpoints')
param privateEndpointSubnetName string = 'private-endpoint-subnet'

@description('Address prefix for private endpoint subnet (e.g., 10.0.2.0/24)')
param privateEndpointSubnetAddressPrefix string = '10.0.2.0/24'

@description('Enable private endpoint for storage account.')
param enableStoragePrivateEndpoint bool = false

@description('Azure AI Content Understanding base URL')
param contentUnderstandingBaseUrl string = ''

@description('Default analyzer ID to use')
param defaultAnalyzerId string = ''

@description('Application Insights connection string')
param applicationInsightsConnectionString string = ''

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Use an existing App Service Plan instead of creating a new one.')
param useExistingAppServicePlan bool = false

@description('Name of existing App Service Plan (required if useExistingAppServicePlan is true)')
param existingAppServicePlanName string = ''

@description('Use an existing Application Insights instance instead of creating a new one.')
param useExistingApplicationInsights bool = false

@description('Name of existing Application Insights (required if useExistingApplicationInsights is true)')
param existingApplicationInsightsName string = ''

@description('Function App hosting plan SKU')
@allowed([
  'FC1' // Flex Consumption
  'Y1'  // Consumption (Dynamic)
  'EP1' // Elastic Premium
  'EP2'
  'EP3'
])
param functionAppSku string = 'FC1'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Production'
  Application: 'AI Content Understanding Wrapper'
}

// Variables
var functionWorkerRuntime = runtime
var linuxFxVersion = runtime == 'python' ? 'Python|${runtimeVersion}' : runtime == 'node' ? 'Node|${runtimeVersion}' : 'DOTNET-ISOLATED|${runtimeVersion}'
var isFlexConsumption = functionAppSku == 'FC1'
var applicationInsightsName = '${functionAppName}-insights'
var logAnalyticsName = '${functionAppName}-logs'

// Storage Account - Create new
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (!useExistingStorageAccount) {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: enableVNetIntegration ? {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: useExistingVNet ? functionSubnetExisting.id : functionSubnetNew.id
          action: 'Allow'
        }
      ]
    } : {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Storage Account - Reference existing
resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (useExistingStorageAccount) {
  name: storageAccountName
}

// VNet - Create new (only if VNet integration is enabled and not using existing)
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = if (enableVNetIntegration && !useExistingVNet) {
  name: vnetName != '' ? vnetName : '${functionAppName}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: functionSubnetName
        properties: {
          addressPrefix: functionSubnetAddressPrefix
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          serviceEndpoints: enableStoragePrivateEndpoint ? [] : [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// VNet - Reference existing
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = if (enableVNetIntegration && useExistingVNet) {
  name: vnetName
}

// Reference to function subnet - new VNet
resource functionSubnetNew 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = if (enableVNetIntegration && !useExistingVNet) {
  parent: vnet
  name: functionSubnetName
}

// Reference to function subnet - existing VNet
resource functionSubnetExisting 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = if (enableVNetIntegration && useExistingVNet) {
  parent: existingVnet
  name: functionSubnetName
}

// Reference to private endpoint subnet - new VNet
resource privateEndpointSubnetNew 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = if (enableVNetIntegration && enableStoragePrivateEndpoint && !useExistingVNet) {
  parent: vnet
  name: privateEndpointSubnetName
}

// Reference to private endpoint subnet - existing VNet
resource privateEndpointSubnetExisting 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = if (enableVNetIntegration && enableStoragePrivateEndpoint && useExistingVNet) {
  parent: existingVnet
  name: privateEndpointSubnetName
}

// Private DNS Zone for Storage Blob (if private endpoint enabled)
resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableStoragePrivateEndpoint) {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

// VNet Link for Blob Private DNS Zone
resource blobPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableStoragePrivateEndpoint) {
  parent: blobPrivateDnsZone
  name: '${functionAppName}-blob-dns-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: useExistingVNet ? existingVnet.id : vnet.id
    }
  }
}

// Private Endpoint for Storage Blob
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = if (enableStoragePrivateEndpoint) {
  name: '${storageAccountName}-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: useExistingVNet ? privateEndpointSubnetExisting.id : privateEndpointSubnetNew.id
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-blob-plsc'
        properties: {
          privateLinkServiceId: useExistingStorageAccount ? existingStorageAccount.id : storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = if (enableStoragePrivateEndpoint) {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-config'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
}

// Log Analytics Workspace - Create new
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableApplicationInsights && !useExistingApplicationInsights) {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights - Create new
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights && !useExistingApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights && !useExistingApplicationInsights ? logAnalytics.id : null
  }
}

// Application Insights - Reference existing
resource existingApplicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (useExistingApplicationInsights) {
  name: existingApplicationInsightsName
}

// App Service Plan - Create new
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = if (!useExistingAppServicePlan) {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: isFlexConsumption ? 'FlexConsumption' : functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// App Service Plan - Reference existing
resource existingHostingPlan 'Microsoft.Web/serverfarms@2023-01-01' existing = if (useExistingAppServicePlan) {
  name: existingAppServicePlanName
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: useExistingAppServicePlan ? existingHostingPlan.id : hostingPlan.id
    httpsOnly: true
    virtualNetworkSubnetId: enableVNetIntegration ? (useExistingVNet ? functionSubnetExisting.id : functionSubnetNew.id) : null
    vnetRouteAllEnabled: enableVNetIntegration
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: useExistingStorageAccount ? 'DefaultEndpointsProtocol=https;AccountName=${existingStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${existingStorageAccount.listKeys().keys[0].value}' : 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: useExistingStorageAccount ? 'DefaultEndpointsProtocol=https;AccountName=${existingStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${existingStorageAccount.listKeys().keys[0].value}' : 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: useExistingApplicationInsights ? existingApplicationInsights.properties.ConnectionString : ((enableApplicationInsights && !useExistingApplicationInsights) ? applicationInsights.?properties.?ConnectionString ?? applicationInsightsConnectionString : applicationInsightsConnectionString)
        }
        {
          name: 'CONTENT_UNDERSTANDING_BASE_URL'
          value: contentUnderstandingBaseUrl
        }
        {
          name: 'DEFAULT_ANALYZER_ID'
          value: defaultAnalyzerId
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: isFlexConsumption ? 100 : 0
    }
  }
}

// Flex Consumption specific configuration
resource functionAppConfig 'Microsoft.Web/sites/config@2023-01-01' = if (isFlexConsumption) {
  parent: functionApp
  name: 'web'
  properties: {
    functionAppScaleLimit: 100
    minimumElasticInstanceCount: 0
  }
}

// Grant Function App access to Storage Account (Blob Data Contributor) - for new storage
resource storageBlobDataContributorRoleNew 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (isFlexConsumption && !useExistingStorageAccount) {
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Storage Account (Blob Data Contributor) - for existing storage
resource storageBlobDataContributorRoleExisting 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (isFlexConsumption && useExistingStorageAccount) {
  name: guid(existingStorageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: existingStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppPrincipalId string = functionApp.identity.principalId
output storageAccountName string = useExistingStorageAccount ? existingStorageAccount.name : storageAccount.name
output applicationInsightsName string = useExistingApplicationInsights ? existingApplicationInsights.name : ((enableApplicationInsights && !useExistingApplicationInsights) ? applicationInsights.?name ?? '' : '')
output applicationInsightsConnectionString string = useExistingApplicationInsights ? existingApplicationInsights.properties.ConnectionString : ((enableApplicationInsights && !useExistingApplicationInsights) ? applicationInsights.?properties.?ConnectionString ?? '' : '')
output vnetName string = enableVNetIntegration ? (useExistingVNet ? existingVnet.name : vnet.name) : ''
output vnetId string = enableVNetIntegration ? (useExistingVNet ? existingVnet.id : vnet.id) : ''
