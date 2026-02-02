targetScope = 'resourceGroup'

@description('Environment name (used for resource naming and tagging)')
param environment string = 'dev'

@description('Azure region')
param location string = resourceGroup().location

@description('Number of VMSS instances')
param instanceCount int = 1

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('SSH public key for VM access (optional — if empty, SSH key auth is skipped)')
param sshPublicKey string = ''

@description('Entra ID object IDs to grant Virtual Machine User Login role')
param vmUserLoginObjectIds array = []

@description('Admin username for VMs')
param adminUsername string = 'openclaw'

@description('OpenClaw gateway port')
param openclawPort int = 18789

@secure()
@description('OpenClaw secrets as JSON string')
param openclawSecrets string

@description('Source address CIDR for SSH access')
param sshSourceCidr string = '*'

@description('Source address CIDR for OpenClaw gateway access')
param gatewaySourceCidr string = '*'

@description('Resource tags')
param tags object = {
  project: 'openclaw'
  environment: environment
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    environment: environment
    location: location
    openclawPort: openclawPort
    sshSourceCidr: sshSourceCidr
    gatewaySourceCidr: gatewaySourceCidr
    tags: tags
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    environment: environment
    location: location
    openclawSecrets: openclawSecrets
    tags: tags
  }
}

module vmss 'modules/vmss.bicep' = {
  name: 'vmss'
  params: {
    environment: environment
    location: location
    instanceCount: instanceCount
    vmSize: vmSize
    sshPublicKey: sshPublicKey
    vmUserLoginObjectIds: vmUserLoginObjectIds
    adminUsername: adminUsername
    openclawPort: openclawPort
    subnetId: network.outputs.subnetId
    keyVaultName: keyvault.outputs.keyVaultName
    keyVaultId: keyvault.outputs.keyVaultId
    tags: tags
  }
}

output vmssName string = vmss.outputs.vmssName
output keyVaultName string = keyvault.outputs.keyVaultName
output vnetName string = network.outputs.vnetName
