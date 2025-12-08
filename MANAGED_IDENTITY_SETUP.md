# Managed Identity Setup for AKS

This guide explains how to configure Azure Managed Identity for your AKS pods to access Azure App Configuration without using connection strings.

## Overview

Instead of using connection strings (which are secrets), we'll use **Azure Managed Identity** with **Workload Identity** (recommended) or **Pod Identity** (legacy).

**Benefits:**
- ✅ No secrets to manage
- ✅ Automatic credential rotation
- ✅ Better security
- ✅ Role-based access control (RBAC)
- ✅ Audit trail

## Prerequisites

- AKS cluster running
- Azure CLI installed and logged in
- kubectl configured
- Azure App Configuration resource exists: `aks-appconfig-12` (Resource Group: `Mike`)

## Method 1: Workload Identity (Recommended)

Workload Identity is the modern, recommended way to use managed identity in AKS.

### Step 1: Enable Workload Identity on AKS Cluster

```bash
# Set variables
RESOURCE_GROUP="Mike"
AKS_CLUSTER_NAME="your-aks-cluster-name"

# Enable OIDC issuer (required for Workload Identity)
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --enable-oidc-issuer \
  --enable-workload-identity

# Verify OIDC issuer is enabled
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "oidcIssuerProfile" -o tsv
```

**Note**: If your cluster doesn't support these flags, you may need to upgrade or create a new cluster.

### Step 2: Create User-Assigned Managed Identity

```bash
# Set variables
RESOURCE_GROUP="Mike"
IDENTITY_NAME="aks-app-config-identity"
LOCATION="eastus"  # or your preferred region

# Create managed identity
az identity create \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --location $LOCATION

# Get the managed identity details
IDENTITY_CLIENT_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query "clientId" \
  --output tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query "principalId" \
  --output tsv)

IDENTITY_TENANT_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query "tenantId" \
  --output tsv)

echo "Managed Identity Client ID: $IDENTITY_CLIENT_ID"
echo "Managed Identity Principal ID: $IDENTITY_PRINCIPAL_ID"
echo "Managed Identity Tenant ID: $IDENTITY_TENANT_ID"
```

**Save these values** - you'll need them later!

### Step 3: Get AKS OIDC Issuer URL

```bash
# Get OIDC issuer URL
AKS_OIDC_ISSUER=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)

echo "OIDC Issuer URL: $AKS_OIDC_ISSUER"
```

### Step 4: Create Federated Identity Credential

This links the Kubernetes service account to the managed identity.

```bash
# Set variables (from previous steps)
SERVICE_ACCOUNT_NAMESPACE="default"
SERVICE_ACCOUNT_NAME="azure-app-config-sa"

# Create federated identity credential
az identity federated-credential create \
  --name "aks-app-config-federated-credential" \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" \
  --audience "api://AzureADTokenExchange"
```

### Step 5: Assign Role to Managed Identity

Grant the managed identity permission to read from Azure App Configuration.

```bash
# Get App Configuration resource ID
APP_CONFIG_NAME="aks-appconfig-12"
APP_CONFIG_ID=$(az appconfig show \
  --name $APP_CONFIG_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" \
  --output tsv)

# Assign "App Configuration Data Reader" role
az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role "App Configuration Data Reader" \
  --scope $APP_CONFIG_ID

# Verify role assignment
az role assignment list \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --scope $APP_CONFIG_ID \
  --output table
```

**Available Roles:**
- `App Configuration Data Reader` - Read-only access
- `App Configuration Data Owner` - Read and write access

### Step 6: Create Kubernetes Service Account

```bash
# Update serviceaccount.yaml with your managed identity client ID
# Then apply:
kubectl apply -f k8s/serviceaccount.yaml
```

Or create directly:

```bash
kubectl create serviceaccount azure-app-config-sa \
  --namespace default \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - \
    azure.workload.identity/client-id=$IDENTITY_CLIENT_ID -o yaml | \
  kubectl apply -f -
```

### Step 7: Update Deployment

The deployment.yaml already references the service account. Just update the environment variables:

```bash
# Edit k8s/deployment.yaml and update:
# - AZURE_APP_CONFIG_ENDPOINT: https://aks-appconfig-12.azconfig.io
# - AZURE_CLIENT_ID: <YOUR_MANAGED_IDENTITY_CLIENT_ID>
```

Then apply:

```bash
kubectl apply -f k8s/deployment.yaml
```

### Step 8: Verify

```bash
# Check pods are running
kubectl get pods -l app=azure-app-config-app

# Check pod logs
kubectl logs -l app=azure-app-config-app

# Test the application
kubectl port-forward service/azure-app-config-app-service 8080:80
# Then visit http://localhost:8080
```

## Method 2: Pod Identity (Legacy - Not Recommended)

Pod Identity is the older method and is being deprecated. Use only if Workload Identity is not available.

### Step 1: Install AAD Pod Identity

```bash
# Install AAD Pod Identity
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=mic -n kube-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=nmi -n kube-system --timeout=300s
```

### Step 2: Create Managed Identity

```bash
# Create managed identity (same as Workload Identity Step 2)
az identity create \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --location $LOCATION
```

### Step 3: Assign Role

```bash
# Assign role (same as Workload Identity Step 5)
az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role "App Configuration Data Reader" \
  --scope $APP_CONFIG_ID
```

### Step 4: Create AzureIdentity and AzureIdentityBinding

```bash
# Create AzureIdentity
cat <<EOF | kubectl apply -f -
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
  name: azure-app-config-identity
  namespace: default
spec:
  type: 0  # User-assigned managed identity
  resourceID: /subscriptions/<SUBSCRIPTION_ID>/resourcegroups/$RESOURCE_GROUP/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$IDENTITY_NAME
  clientID: $IDENTITY_CLIENT_ID
EOF

# Create AzureIdentityBinding
cat <<EOF | kubectl apply -f -
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
  name: azure-app-config-identity-binding
  namespace: default
spec:
  azureIdentity: azure-app-config-identity
  selector: azure-app-config
EOF
```

### Step 5: Update Deployment

Add label to deployment:

```yaml
spec:
  template:
    metadata:
      labels:
        aadpodidbinding: azure-app-config
```

## Troubleshooting

### Issue: Authentication Failed

**Symptoms**: Pods show authentication errors in logs

**Solutions**:

```bash
# Check service account annotation
kubectl get serviceaccount azure-app-config-sa -o yaml

# Verify managed identity exists
az identity show --resource-group $RESOURCE_GROUP --name $IDENTITY_NAME

# Check role assignment
az role assignment list --assignee $IDENTITY_PRINCIPAL_ID --scope $APP_CONFIG_ID

# Check pod logs
kubectl logs -l app=azure-app-config-app
```

### Issue: Workload Identity Not Working

**Solutions**:

```bash
# Verify OIDC issuer is enabled
az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "oidcIssuerProfile"

# Check federated credential
az identity federated-credential list \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP

# Verify service account annotation matches federated credential subject
kubectl get serviceaccount azure-app-config-sa -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}'
```

### Issue: Permission Denied

**Symptoms**: 403 Forbidden errors

**Solutions**:

```bash
# Verify role is assigned
az role assignment list --assignee $IDENTITY_PRINCIPAL_ID --scope $APP_CONFIG_ID

# Check if correct role is assigned
az role assignment list \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --scope $APP_CONFIG_ID \
  --query "[].roleDefinitionName" \
  --output table

# Re-assign role if needed
az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role "App Configuration Data Reader" \
  --scope $APP_CONFIG_ID
```

### Issue: Pod Can't Get Token

**Solutions**:

```bash
# Check if Workload Identity webhook is installed
kubectl get mutatingwebhookconfigurations | grep workload-identity

# Check pod annotations
kubectl get pod -l app=azure-app-config-app -o jsonpath='{.items[0].metadata.annotations}'

# Verify service account is used
kubectl get pod -l app=azure-app-config-app -o jsonpath='{.items[0].spec.serviceAccountName}'
```

## Quick Setup Script

```bash
#!/bin/bash

# Set variables
RESOURCE_GROUP="Mike"
AKS_CLUSTER_NAME="your-aks-cluster-name"
IDENTITY_NAME="aks-app-config-identity"
APP_CONFIG_NAME="aks-appconfig-12"
SERVICE_ACCOUNT_NAMESPACE="default"
SERVICE_ACCOUNT_NAME="azure-app-config-sa"

# 1. Enable Workload Identity
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --enable-oidc-issuer \
  --enable-workload-identity

# 2. Create Managed Identity
az identity create \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --location eastus

IDENTITY_CLIENT_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query "clientId" -o tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
  --resource-group $RESOURCE_GROUP \
  --name $IDENTITY_NAME \
  --query "principalId" -o tsv)

# 3. Get OIDC Issuer
AKS_OIDC_ISSUER=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

# 4. Create Federated Credential
az identity federated-credential create \
  --name "aks-app-config-federated-credential" \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" \
  --audience "api://AzureADTokenExchange"

# 5. Assign Role
APP_CONFIG_ID=$(az appconfig show \
  --name $APP_CONFIG_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" -o tsv)

az role assignment create \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --role "App Configuration Data Reader" \
  --scope $APP_CONFIG_ID

# 6. Create Service Account
kubectl create serviceaccount $SERVICE_ACCOUNT_NAME \
  --namespace $SERVICE_ACCOUNT_NAMESPACE \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - \
    azure.workload.identity/client-id=$IDENTITY_CLIENT_ID -o yaml | \
  kubectl apply -f -

echo "Setup complete!"
echo "Managed Identity Client ID: $IDENTITY_CLIENT_ID"
echo "Update k8s/deployment.yaml with this client ID"
```

## Migration from Connection String

If you're currently using connection strings:

1. **Follow the setup steps above** to create managed identity and assign roles
2. **Update your code** to use `DefaultAzureCredential` (already done in server.js)
3. **Update deployment.yaml** to remove connection string secret and add endpoint
4. **Deploy** the updated configuration
5. **Delete** the old connection string secret (optional, for cleanup)

## Best Practices

1. **Use Workload Identity** instead of Pod Identity (newer, more secure)
2. **Use least privilege** - Only assign "App Configuration Data Reader" if read-only access is needed
3. **Separate identities** - Use different managed identities for different applications/environments
4. **Monitor access** - Review role assignments regularly
5. **Use resource-specific scopes** - Assign roles at the App Configuration resource level, not subscription level

## Next Steps

1. ✅ Enable Workload Identity on AKS
2. ✅ Create managed identity
3. ✅ Create federated credential
4. ✅ Assign role to managed identity
5. ✅ Create Kubernetes service account
6. ✅ Update deployment.yaml
7. ✅ Deploy and test

For code changes, see the updated `server.js` which now uses `DefaultAzureCredential` instead of connection strings.

