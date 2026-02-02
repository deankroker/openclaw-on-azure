@description('Environment name')
param environment string

@description('Azure region')
param location string = resourceGroup().location

@secure()
@description('OpenClaw secrets as JSON string')
param openclawSecrets string

@description('Resource tags')
param tags object = {}

var namePrefix = 'openclaw-${environment}'
var kvName = '${namePrefix}-kv-${uniqueString(resourceGroup().id)}'

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource openclawSecretsEntry 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'openclaw-secrets'
  properties: {
    value: openclawSecrets
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
