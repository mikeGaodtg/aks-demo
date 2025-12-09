# Fix Key Vault Access Issue

## Problem

You're getting "Caller is not authorized" error because:
- **Key Vault Reader** role only allows reading Key Vault metadata (vault properties)
- It does **NOT** allow reading secret values
- You need a role that specifically grants secret access

## Solution: Assign the Correct RBAC Role

You need to assign **"Key Vault Secrets User"** role instead of (or in addition to) "Key Vault Reader".

## PowerShell Commands to Fix

### Option 1: Assign Key Vault Secrets User Role (Recommended)

```powershell
# Set variables
$resourceGroup = "Mike"
$keyVaultName = "testmikerandomwname2"
$identityClientId = "63b2867c-57e5-4150-aeca-da497348b4a6"

# Get the Key Vault resource ID
$keyVaultId = (Get-AzKeyVault -ResourceGroupName $resourceGroup -VaultName $keyVaultName).ResourceId

# Get the managed identity object ID
$identity = Get-AzADServicePrincipal -ServicePrincipalName $identityClientId
$objectId = $identity.Id

# Assign "Key Vault Secrets User" role (allows Get and List on secrets)
New-AzRoleAssignment `
    -ObjectId $objectId `
    -RoleDefinitionName "Key Vault Secrets User" `
    -Scope $keyVaultId

# Verify the role assignment
Get-AzRoleAssignment -Scope $keyVaultId -ObjectId $objectId | Format-Table RoleDefinitionName, Scope
```

### Option 2: Use Access Policy (Legacy Method)

If RBAC doesn't work, you can use the legacy access policy method:

```powershell
# Get the managed identity object ID
$identityClientId = "63b2867c-57e5-4150-aeca-da497348b4a6"
$identity = Get-AzADServicePrincipal -ServicePrincipalName $identityClientId
$objectId = $identity.Id

# Set access policy with Get and List permissions on secrets
Set-AzKeyVaultAccessPolicy `
    -VaultName "testmikerandomwname2" `
    -ResourceGroupName "Mike" `
    -ObjectId $objectId `
    -PermissionsToSecrets Get,List
```

## Complete Debugging Script

Run this to check and fix all access issues:

```powershell
# Set variables
$resourceGroup = "Mike"
$keyVaultName = "testmikerandomwname2"
$identityClientId = "63b2867c-57e5-4150-aeca-da497348b4a6"

Write-Host "=== Key Vault Access Debugging ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify Key Vault exists
Write-Host "1. Checking Key Vault..." -ForegroundColor Yellow
try {
    $kv = Get-AzKeyVault -ResourceGroupName $resourceGroup -VaultName $keyVaultName
    Write-Host "✓ Key Vault found: $($kv.VaultUri)" -ForegroundColor Green
    $keyVaultId = $kv.ResourceId
} catch {
    Write-Host "✗ Key Vault not found!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 2: Verify Managed Identity exists
Write-Host "2. Checking Managed Identity..." -ForegroundColor Yellow
try {
    $identity = Get-AzADServicePrincipal -ServicePrincipalName $identityClientId
    Write-Host "✓ Managed Identity found" -ForegroundColor Green
    Write-Host "  Object ID: $($identity.Id)" -ForegroundColor Gray
    Write-Host "  Display Name: $($identity.DisplayName)" -ForegroundColor Gray
    $objectId = $identity.Id
} catch {
    Write-Host "✗ Managed Identity not found!" -ForegroundColor Red
    Write-Host "  Client ID: $identityClientId" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Step 3: Check current role assignments
Write-Host "3. Checking current role assignments..." -ForegroundColor Yellow
$currentRoles = Get-AzRoleAssignment -Scope $keyVaultId -ObjectId $objectId -ErrorAction SilentlyContinue
if ($currentRoles) {
    Write-Host "Current roles:" -ForegroundColor Cyan
    $currentRoles | ForEach-Object {
        Write-Host "  - $($_.RoleDefinitionName)" -ForegroundColor White
    }
    
    $hasSecretsUser = $currentRoles | Where-Object { $_.RoleDefinitionName -eq "Key Vault Secrets User" }
    if (-not $hasSecretsUser) {
        Write-Host "⚠ 'Key Vault Secrets User' role NOT assigned!" -ForegroundColor Yellow
    } else {
        Write-Host "✓ 'Key Vault Secrets User' role is assigned" -ForegroundColor Green
    }
} else {
    Write-Host "⚠ No role assignments found!" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Assign the correct role
Write-Host "4. Assigning 'Key Vault Secrets User' role..." -ForegroundColor Yellow
try {
    # Check if role already assigned
    $existingAssignment = Get-AzRoleAssignment -Scope $keyVaultId -ObjectId $objectId -RoleDefinitionName "Key Vault Secrets User" -ErrorAction SilentlyContinue
    
    if ($existingAssignment) {
        Write-Host "✓ Role already assigned" -ForegroundColor Green
    } else {
        $assignment = New-AzRoleAssignment `
            -ObjectId $objectId `
            -RoleDefinitionName "Key Vault Secrets User" `
            -Scope $keyVaultId `
            -ErrorAction Stop
        
        Write-Host "✓ Role assigned successfully!" -ForegroundColor Green
        Write-Host "  Assignment ID: $($assignment.RoleAssignmentId)" -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ Failed to assign role: $($_.Exception.Message)" -ForegroundColor Red
    
    # Try alternative: Access Policy
    Write-Host ""
    Write-Host "Trying alternative: Access Policy method..." -ForegroundColor Yellow
    try {
        Set-AzKeyVaultAccessPolicy `
            -VaultName $keyVaultName `
            -ResourceGroupName $resourceGroup `
            -ObjectId $objectId `
            -PermissionsToSecrets Get,List
        
        Write-Host "✓ Access Policy set successfully!" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to set access policy: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""

# Step 5: Verify secret exists
Write-Host "5. Verifying secret exists..." -ForegroundColor Yellow
try {
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "AppMessage" -ErrorAction Stop
    Write-Host "✓ Secret 'AppMessage' found" -ForegroundColor Green
    Write-Host "  Secret URI: $($secret.Id)" -ForegroundColor Gray
} catch {
    Write-Host "✗ Secret 'AppMessage' not found!" -ForegroundColor Red
    Write-Host "  Creating secret..." -ForegroundColor Yellow
    
    Set-AzKeyVaultSecret `
        -VaultName $keyVaultName `
        -Name "AppMessage" `
        -SecretValue (ConvertTo-SecureString -String "Hello from Azure Key Vault!" -AsPlainText -Force)
    
    Write-Host "✓ Secret created!" -ForegroundColor Green
}
Write-Host ""

# Step 6: Final verification
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Key Vault: $keyVaultName" -ForegroundColor White
Write-Host "Managed Identity: $identityClientId" -ForegroundColor White
Write-Host "Object ID: $objectId" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Wait 1-2 minutes for role assignment to propagate" -ForegroundColor White
Write-Host "2. Restart your pod: kubectl rollout restart deployment/app-config-deployment" -ForegroundColor White
Write-Host "3. Check logs: kubectl logs -l app=azure-app-config-app --tail=50" -ForegroundColor White
```

## Quick Fix (One-Liner)

```powershell
# Quick fix - assign Key Vault Secrets User role
$kv = Get-AzKeyVault -ResourceGroupName "Mike" -VaultName "testmikerandomwname2"
$identity = Get-AzADServicePrincipal -ServicePrincipalName "63b2867c-57e5-4150-aeca-da497348b4a6"
New-AzRoleAssignment -ObjectId $identity.Id -RoleDefinitionName "Key Vault Secrets User" -Scope $kv.ResourceId
```

## Important Notes

1. **Role Propagation**: After assigning the role, wait 1-2 minutes for it to propagate
2. **Restart Pod**: You may need to restart your pod for the changes to take effect:
   ```powershell
   kubectl rollout restart deployment/app-config-deployment -n default
   ```
3. **Role vs Access Policy**: 
   - **RBAC (Role-Based)**: Use "Key Vault Secrets User" role (recommended)
   - **Access Policy (Legacy)**: Use `Set-AzKeyVaultAccessPolicy` with `Get,List` permissions

## Verify Access

After applying the fix, verify access:

```powershell
# Check role assignments
$kv = Get-AzKeyVault -ResourceGroupName "Mike" -VaultName "testmikerandomwname2"
$identity = Get-AzADServicePrincipal -ServicePrincipalName "63b2867c-57e5-4150-aeca-da497348b4a6"
Get-AzRoleAssignment -Scope $kv.ResourceId -ObjectId $identity.Id | Format-Table RoleDefinitionName, Scope

# Should show: Key Vault Secrets User
```

## Troubleshooting

### If RBAC doesn't work, use Access Policy:

```powershell
$identity = Get-AzADServicePrincipal -ServicePrincipalName "63b2867c-57e5-4150-aeca-da497348b4a6"
Set-AzKeyVaultAccessPolicy `
    -VaultName "testmikerandomwname2" `
    -ResourceGroupName "Mike" `
    -ObjectId $identity.Id `
    -PermissionsToSecrets Get,List
```

### Check if Key Vault uses RBAC or Access Policy:

```powershell
$kv = Get-AzKeyVault -ResourceGroupName "Mike" -VaultName "testmikerandomwname2"
Write-Host "Enable RBAC: $($kv.EnableRbacAuthorization)"
```

- If `True`: Use RBAC roles (Key Vault Secrets User)
- If `False`: Use Access Policy (`Set-AzKeyVaultAccessPolicy`)

