@description('Environment name')
param environment string

@description('Azure region')
param location string = resourceGroup().location

@description('Number of VM instances')
param instanceCount int = 1

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('SSH public key (optional — if empty, SSH key auth is skipped)')
param sshPublicKey string = ''

@description('Entra ID object IDs to grant Virtual Machine User Login role')
param vmUserLoginObjectIds array = []

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
            publicKeys: empty(sshPublicKey) ? [] : [
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

// Entra ID SSH login extension (only when team members are configured)
resource aadExtension 'Microsoft.Compute/virtualMachineScaleSets/extensions@2024-07-01' = if (!empty(vmUserLoginObjectIds)) {
  parent: vmss
  name: 'AADSSHLoginForLinux'
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADSSHLoginForLinux'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
}

// Grant Virtual Machine User Login role to each team member
var vmUserLoginRole = 'fb879df8-f326-4884-b1cf-06f3ad86be52'

resource vmUserRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (objectId, i) in vmUserLoginObjectIds: {
    name: guid(vmss.id, objectId, vmUserLoginRole)
    scope: vmss
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmUserLoginRole)
      principalId: objectId
      principalType: 'User'
    }
  }
]

output vmssName string = vmss.name
output vmssId string = vmss.id
