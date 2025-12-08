# Troubleshooting Managed Identity Authentication

## Error: "Identity not found"

This error means the managed identity cannot be found or Workload Identity is not properly configured.

## Quick Diagnostic Steps

### 1. Verify Managed Identity Exists

```bash
# Check if managed identity exists
az identity show \
  --resource-group Mike \
  --name aks-app-config-identity \
  --query "{clientId: clientId, principalId: principalId}" \
  --output table

# Verify the client ID matches what's in deployment
# Should be: ebf4922a-8d3d-4731-8bb9-baa56d432cdb
```

### 2. Check Workload Identity Setup

```bash
# Verify OIDC issuer is enabled
az aks show \
  --resource-group Mike \
  --name your-aks-cluster-name \
  --query "oidcIssuerProfile" \
  --output table

# Check federated credential exists
az identity federated-credential list \
  --identity-name aks-app-config-identity \
  --resource-group Mike \
  --output table
```

### 3. Verify Service Account

```bash
# Check service account annotation
kubectl get serviceaccount azure-app-config-sa -o yaml

# Should have annotation:
# azure.workload.identity/client-id: ebf4922a-8d3d-4731-8bb9-baa56d432cdb
```

### 4. Check Pod Configuration

```bash
# Verify pod is using the service account
kubectl get pod -l app=azure-app-config-app -o jsonpath='{.items[0].spec.serviceAccountName}'

# Should output: azure-app-config-sa

# Check pod annotations (Workload Identity webhook should inject these)
kubectl get pod -l app=azure-app-config-app -o jsonpath='{.items[0].metadata.annotations}' | grep azure.workload.identity

# Should see:
# azure.workload.identity/client-id: ebf4922a-8d3d-4731-8bb9-baa56d432cdb
```

### 5. Check Environment Variables in Pod

```bash
# Check if AZURE_FEDERATED_TOKEN_FILE is set (injected by webhook)
kubectl exec -it $(kubectl get pod -l app=azure-app-config-app -o jsonpath='{.items[0].metadata.name}') -- env | grep AZURE

# Should see:
# AZURE_CLIENT_ID=ebf4922a-8d3d-4731-8bb9-baa56d432cdb
# AZURE_TENANT_ID=<tenant-id>
# AZURE_FEDERATED_TOKEN_FILE=/var/run/secrets/azure/tokens/azure-identity-token
```

### 6. Verify Role Assignment

```bash
# Get managed identity principal ID
IDENTITY_PRINCIPAL_ID=$(az identity show \
  --resource-group Mike \
  --name aks-app-config-identity \
  --query "principalId" \
  --output tsv)

# Get App Configuration resource ID
APP_CONFIG_ID=$(az appconfig show \
  --name aks-appconfig-12 \
  --resource-group Mike \
  --query "id" \
  --output tsv)

# Check role assignment
az role assignment list \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --scope $APP_CONFIG_ID \
  --output table

# Should show "App Configuration Data Reader" role
```

## Common Fixes

### Fix 1: Recreate Federated Credential

```bash
RESOURCE_GROUP="Mike"
AKS_CLUSTER_NAME="your-aks-cluster-name"
IDENTITY_NAME="aks-app-config-identity"
SERVICE_ACCOUNT_NAMESPACE="default"
SERVICE_ACCOUNT_NAME="azure-app-config-sa"

# Get OIDC issuer
AKS_OIDC_ISSUER=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)

# Delete old federated credential
az identity federated-credential delete \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --name "aks-app-config-federated-credential"

# Create new federated credential
az identity federated-credential create \
  --name "aks-app-config-federated-credential" \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" \
  --audience "api://AzureADTokenExchange"
```

### Fix 2: Verify Workload Identity Webhook is Installed

```bash
# Check if webhook is installed
kubectl get mutatingwebhookconfigurations | grep workload-identity

# If not found, Workload Identity might not be enabled on cluster
az aks show \
  --resource-group Mike \
  --name your-aks-cluster-name \
  --query "securityProfile.workloadIdentity" \
  --output table
```

### Fix 3: Restart Pods

```bash
# Delete pods to force recreation with correct annotations
kubectl delete pods -l app=azure-app-config-app

# Wait for new pods
kubectl get pods -l app=azure-app-config-app -w
```

### Fix 4: Check Managed Identity Client ID

```bash
# Verify the client ID in Azure matches what's in deployment
az identity show \
  --resource-group Mike \
  --name aks-app-config-identity \
  --query "clientId" \
  --output tsv

# Compare with deployment.yaml:
# Should match: ebf4922a-8d3d-4731-8bb9-baa56d432cdb
```

## Complete Setup Verification Script

```bash
#!/bin/bash

RESOURCE_GROUP="Mike"
AKS_CLUSTER_NAME="your-aks-cluster-name"
IDENTITY_NAME="aks-app-config-identity"
APP_CONFIG_NAME="aks-appconfig-12"
CLIENT_ID="ebf4922a-8d3d-4731-8bb9-baa56d432cdb"

echo "=== Verifying Managed Identity Setup ==="

# 1. Check managed identity exists
echo -e "\n[1] Checking managed identity..."
IDENTITY_CLIENT_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query "clientId" \
  --output tsv 2>/dev/null)

if [ "$IDENTITY_CLIENT_ID" == "$CLIENT_ID" ]; then
  echo "✓ Managed identity exists with correct client ID"
else
  echo "✗ Managed identity not found or client ID mismatch"
  echo "  Expected: $CLIENT_ID"
  echo "  Found: $IDENTITY_CLIENT_ID"
fi

# 2. Check OIDC issuer
echo -e "\n[2] Checking OIDC issuer..."
OIDC_ISSUER=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv 2>/dev/null)

if [ -n "$OIDC_ISSUER" ]; then
  echo "✓ OIDC issuer enabled: $OIDC_ISSUER"
else
  echo "✗ OIDC issuer not enabled"
fi

# 3. Check federated credential
echo -e "\n[3] Checking federated credential..."
FED_CRED=$(az identity federated-credential list \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[?name=='aks-app-config-federated-credential']" \
  --output tsv 2>/dev/null)

if [ -n "$FED_CRED" ]; then
  echo "✓ Federated credential exists"
else
  echo "✗ Federated credential not found"
fi

# 4. Check role assignment
echo -e "\n[4] Checking role assignment..."
IDENTITY_PRINCIPAL_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query "principalId" \
  --output tsv 2>/dev/null)

APP_CONFIG_ID=$(az appconfig show \
  --name $APP_CONFIG_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" \
  --output tsv 2>/dev/null)

ROLE=$(az role assignment list \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --scope $APP_CONFIG_ID \
  --query "[?roleDefinitionName=='App Configuration Data Reader']" \
  --output tsv 2>/dev/null)

if [ -n "$ROLE" ]; then
  echo "✓ Role assigned"
else
  echo "✗ Role not assigned"
fi

# 5. Check service account
echo -e "\n[5] Checking Kubernetes service account..."
SA_CLIENT_ID=$(kubectl get serviceaccount azure-app-config-sa \
  -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>/dev/null)

if [ "$SA_CLIENT_ID" == "$CLIENT_ID" ]; then
  echo "✓ Service account configured correctly"
else
  echo "✗ Service account client ID mismatch"
  echo "  Expected: $CLIENT_ID"
  echo "  Found: $SA_CLIENT_ID"
fi

echo -e "\n=== Verification Complete ==="
```

## Next Steps After Fixing

1. Rebuild and push Docker image with updated code
2. Restart deployment
3. Check logs again

