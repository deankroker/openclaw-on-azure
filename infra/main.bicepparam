using './main.bicep'

param environment = 'dev'
param instanceCount = 1
param vmSize = 'Standard_B2s'
param adminUsername = 'openclaw'
param openclawPort = 18789
