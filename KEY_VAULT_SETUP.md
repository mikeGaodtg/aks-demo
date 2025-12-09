# Azure Key Vault Setup Guide

This guide shows you how to set up Azure Key Vault and create secrets using PowerShell.

## Prerequisites

- Azure PowerShell module installed
- Logged in to Azure (`Connect-AzAccount`)
- Appropriate permissions to create Key Vault and secrets

## Step 1: Create Azure Key Vault

```powershell
# Set variables
$resourceGroup = "Mike"  # Your resource group name
$keyVaultName = "your-key-vault-name"  # Must be globally unique, lowercase, alphanumeric and hyphens only
$location = "eastus"  # Your preferred location

# Create Key Vault
New-AzKeyVault `
    -ResourceGroupName $resourceGroup `
    -Name $keyVaultName `
    -Location $location `
    -EnabledForDeployment `
    -EnabledForTemplateDeployment `
    -EnabledForDiskEncryption `
    -Sku Standard
```

**Note:** Key Vault name must be:
- 3-24 characters
- Alphanumeric and hyphens only
- Globally unique across all Azure
- Start with a letter

## Step 2: Create a Secret in Key Vault

### Option A: Create Secret with Value

```powershell
# Set the secret value
$secretValue = "Hello from Azure Key Vault!"

# Create the secret
$secret = Set-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name "AppMessage" `
    -SecretValue (ConvertTo-SecureString -String $secretValue -AsPlainText -Force)

# Display the secret URI (for reference)
Write-Host "Secret created successfully!"
Write-Host "Secret URI: $($secret.Id)"
```

### Option B: Create Secret from File

```powershell
# Read secret value from a file
$secretValue = Get-Content -Path "C:\path\to\secret.txt" -Raw

# Create the secret
Set-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name "AppMessage" `
    -SecretValue (ConvertTo-SecureString -String $secretValue -AsPlainText -Force)
```

### Option C: Create Secret with Expiration Date

```powershell
# Set expiration date (e.g., 1 year from now)
$expirationDate = (Get-Date).AddYears(1)

# Create secret with expiration
$secret = Set-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name "AppMessage" `
    -SecretValue (ConvertTo-SecureString -String "Hello from Azure Key Vault!" -AsPlainText -Force) `
    -Expires $expirationDate

Write-Host "Secret expires on: $expirationDate"
```

### Option D: Create Secret with Tags

```powershell
# Create secret with tags for better organization
$tags = @{
    Environment = "Production"
    Application = "AzureAppConfigApp"
    Owner = "DevOps Team"
}

Set-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name "AppMessage" `
    -SecretValue (ConvertTo-SecureString -String "Hello from Azure Key Vault!" -AsPlainText -Force) `
    -Tag $tags
```

## Step 3: View Secret

```powershell
# Get secret (value will be shown as SecureString)
$secret = Get-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name "AppMessage"

# Display secret metadata
Write-Host "Secret Name: $($secret.Name)"
Write-Host "Secret Version: $($secret.Version)"
Write-Host "Secret URI: $($secret.Id)"
Write-Host "Created: $($secret.Created)"
Write-Host "Updated: $($secret.Updated)"

# To see the actual value (requires additional permission)
$secretValue = Get-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name "AppMessage" `
    -AsPlainText

Write-Host "Secret Value: $secretValue"
```

## Step 4: Update Secret Value

```powershell
# Update existing secret with new value
$newValue = "Updated message from Key Vault!"

Set-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name "AppMessage" `
    -SecretValue (ConvertTo-SecureString -String $newValue -AsPlainText -Force)

Write-Host "Secret updated successfully!"
```

## Step 5: List All Secrets

```powershell
# List all secrets in the Key Vault
Get-AzKeyVaultSecret -VaultName $keyVaultName

# List secrets with details
Get-AzKeyVaultSecret -VaultName $keyVaultName | Format-Table Name, Version, Created, Updated
```

## Step 6: Configure Access Policy for Managed Identity

Your AKS node pool's managed identity needs access to read secrets from Key Vault.

### Get Managed Identity Client ID

```powershell
# Get your AKS cluster details
$aksClusterName = "your-aks-cluster-name"
$resourceGroup = "Mike"

# Get the node pool managed identity client ID
# This is typically the kubelet identity
$identityClientId = "63b2867c-57e5-4150-aeca-da497348b4a6"  # Your managed identity client ID

# Or get it from the cluster
$cluster = Get-AzAksCluster -ResourceGroupName $resourceGroup -Name $aksClusterName
# Check the cluster's identity profile
```

### Grant Secret Permissions to Managed Identity

```powershell
# Grant "Get" and "List" permissions on secrets
Set-AzKeyVaultAccessPolicy `
    -VaultName $keyVaultName `
    -ObjectId (Get-AzADServicePrincipal -ServicePrincipalName $identityClientId).Id `
    -PermissionsToSecrets Get,List `
    -BypassObjectIdValidation
```

**Alternative: Using Object ID directly**

```powershell
# If you have the object ID of the managed identity
$objectId = "your-managed-identity-object-id"

Set-AzKeyVaultAccessPolicy `
    -VaultName $keyVaultName `
    -ObjectId $objectId `
    -PermissionsToSecrets Get,List
```

## Step 7: Verify Access

```powershell
# Test if the managed identity can access the secret
# This requires running from within the AKS cluster or using the identity
# You can test by deploying a test pod with the managed identity

# Or verify access policy
Get-AzKeyVaultAccessPolicy -VaultName $keyVaultName
```

## Step 8: Update Deployment YAML

Update your deployment to use Key Vault:

```yaml
env:
- name: AZURE_KEY_VAULT_URL
  value: "https://your-key-vault-name.vault.azure.net"
- name: KEY_VAULT_SECRET_NAME
  value: "AppMessage"
```

## Complete PowerShell Script Example

```powershell
# Complete setup script
$resourceGroup = "Mike"
$keyVaultName = "mike-keyvault-$(Get-Random -Maximum 9999)"  # Random suffix for uniqueness
$location = "eastus"
$secretName = "AppMessage"
$secretValue = "Hello from Azure Key Vault!"
$identityClientId = "63b2867c-57e5-4150-aeca-da497348b4a6"  # Your managed identity client ID

# Step 1: Create Key Vault
Write-Host "Creating Key Vault: $keyVaultName" -ForegroundColor Cyan
$kv = New-AzKeyVault `
    -ResourceGroupName $resourceGroup `
    -Name $keyVaultName `
    -Location $location `
    -Sku Standard

Write-Host "Key Vault created: $($kv.VaultUri)" -ForegroundColor Green

# Step 2: Create Secret
Write-Host "Creating secret: $secretName" -ForegroundColor Cyan
$secret = Set-AzKeyVaultSecret `
    -VaultName $keyVaultName `
    -Name $secretName `
    -SecretValue (ConvertTo-SecureString -String $secretValue -AsPlainText -Force)

Write-Host "Secret created: $($secret.Id)" -ForegroundColor Green

# Step 3: Grant Access to Managed Identity
Write-Host "Granting access to managed identity..." -ForegroundColor Cyan
try {
    $sp = Get-AzADServicePrincipal -ServicePrincipalName $identityClientId -ErrorAction Stop
    Set-AzKeyVaultAccessPolicy `
        -VaultName $keyVaultName `
        -ObjectId $sp.Id `
        -PermissionsToSecrets Get,List
    
    Write-Host "Access granted successfully!" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not grant access automatically. Please grant manually:" -ForegroundColor Yellow
    Write-Host "Set-AzKeyVaultAccessPolicy -VaultName $keyVaultName -ObjectId <object-id> -PermissionsToSecrets Get,List" -ForegroundColor Yellow
}

# Step 4: Display summary
Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "Key Vault URL: $($kv.VaultUri)" -ForegroundColor Cyan
Write-Host "Secret Name: $secretName" -ForegroundColor Cyan
Write-Host "`nUpdate your deployment with:" -ForegroundColor Yellow
Write-Host "AZURE_KEY_VAULT_URL=$($kv.VaultUri)" -ForegroundColor White
Write-Host "KEY_VAULT_SECRET_NAME=$secretName" -ForegroundColor White
```

## Common Operations

### Delete a Secret

```powershell
# Soft delete (secret can be recovered)
Remove-AzKeyVaultSecret -VaultName $keyVaultName -Name "AppMessage"

# Permanently delete (if soft-delete is enabled)
Remove-AzKeyVaultSecret -VaultName $keyVaultName -Name "AppMessage" -InRemovedState -Force
```

### Recover a Deleted Secret

```powershell
# List deleted secrets
Get-AzKeyVaultSecret -VaultName $keyVaultName -InRemovedState

# Recover a deleted secret
Undo-AzKeyVaultSecretRemoval -VaultName $keyVaultName -Name "AppMessage"
```

### Get Secret Versions

```powershell
# Get all versions of a secret
Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "AppMessage" -IncludeVersions

# Get specific version
Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "AppMessage" -Version "specific-version-id"
```

## Troubleshooting

### Issue: Access Denied

**Solution:** Grant proper permissions to the managed identity:
```powershell
Set-AzKeyVaultAccessPolicy `
    -VaultName $keyVaultName `
    -ObjectId <managed-identity-object-id> `
    -PermissionsToSecrets Get,List
```

### Issue: Key Vault Name Already Exists

**Solution:** Key Vault names must be globally unique. Use a different name:
```powershell
$keyVaultName = "mike-keyvault-$(Get-Random -Maximum 99999)"
```

### Issue: Secret Not Found

**Solution:** Verify the secret name matches exactly (case-sensitive):
```powershell
# List all secrets
Get-AzKeyVaultSecret -VaultName $keyVaultName | Select-Object Name
```

## Quick Reference

```powershell
# Create Key Vault
New-AzKeyVault -ResourceGroupName "Mike" -Name "my-keyvault" -Location "eastus" -Sku Standard

# Create Secret
Set-AzKeyVaultSecret -VaultName "my-keyvault" -Name "AppMessage" -SecretValue (ConvertTo-SecureString "Hello!" -AsPlainText -Force)

# Get Secret
Get-AzKeyVaultSecret -VaultName "my-keyvault" -Name "AppMessage" -AsPlainText

# Update Secret
Set-AzKeyVaultSecret -VaultName "my-keyvault" -Name "AppMessage" -SecretValue (ConvertTo-SecureString "Updated!" -AsPlainText -Force)

# List Secrets
Get-AzKeyVaultSecret -VaultName "my-keyvault"

# Grant Access
Set-AzKeyVaultAccessPolicy -VaultName "my-keyvault" -ObjectId <object-id> -PermissionsToSecrets Get,List
```

