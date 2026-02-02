@description('Environment name')
param environment string

@description('Azure region')
param location string = resourceGroup().location

@description('Number of VM instances')
param instanceCount int = 1

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('SSH public key')
param sshPublicKey string

@description('Admin username')
param adminUsername string = 'openclaw'

@description('OpenClaw gateway port')
param openclawPort int = 18789

@description('Subnet ID for VMSS')
param subnetId string

@description('Key Vault name')
param keyVaultName string

@description('Key Vault resource ID')
param keyVaultId string

@description('Resource tags')
param tags object = {}

var namePrefix = 'openclaw-${environment}'

var cloudInitRaw = loadTextContent('../cloud-init/cloud-init.yaml')
var cloudInitFormatted = format(cloudInitRaw, adminUsername, string(openclawPort), keyVaultName)

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-07-01' = {
  name: '${namePrefix}-vmss'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: vmSize
    capacity: instanceCount
  }
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'openclaw'
        adminUsername: adminUsername
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: sshPublicKey
              }
            ]
          }
        }
        customData: base64(cloudInitFormatted)
      }
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          diskSizeGB: 30
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
        imageReference: {
          publisher: 'Canonical'
          offer: 'ubuntu-24_04-lts'
          sku: 'server'
          version: 'latest'
        }
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      networkProfile: {
        networkApiVersion: '2024-05-01'
        networkInterfaceConfigurations: [
          {
            name: '${namePrefix}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: '${namePrefix}-ipconfig'
                  properties: {
                    subnet: {
                      id: subnetId
                    }
                    publicIPAddressConfiguration: {
                      name: '${namePrefix}-pip'
                      properties: {
                        idleTimeoutInMinutes: 15
                      }
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }
    upgradePolicy: {
      mode: 'Manual'
    }
  }
}

// Grant VMSS identity Key Vault Secrets User role
var keyVaultSecretsUserRole = '4633458b-17de-408a-b874-0445c86b69e6'

resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vmss.id, keyVaultId, keyVaultSecretsUserRole)
  scope: keyVaultRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRole)
    principalId: vmss.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultRef 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

output vmssName string = vmss.name
output vmssId string = vmss.id
