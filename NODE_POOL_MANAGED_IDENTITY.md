# Using Node Pool Managed Identity

This guide explains how to use the managed identity inherited from the AKS node pool to access Azure App Configuration.

## Overview

When using the node pool's managed identity:
- ✅ **No service account needed** - The identity is inherited from the node pool
- ✅ **No Workload Identity setup** - Uses IMDS (Instance Metadata Service) directly
- ✅ **Simpler configuration** - Just use DefaultAzureCredential
- ✅ **Automatic** - Works out of the box if the node pool has a managed identity

## Architecture

```
Application Pod
    ↓ (DefaultAzureCredential)
IMDS (Instance Metadata Service)
    ↓
Node Pool Managed Identity
    ↓
Azure App Configuration
```

## Prerequisites

1. AKS cluster with managed identity enabled on the node pool
2. The node pool's managed identity has permissions to read App Configuration

## Step 1: Grant Permissions to Node Pool Managed Identity

```bash
# Get the node pool managed identity
RESOURCE_GROUP="Mike"
AKS_CLUSTER_NAME="AKS-Mike1"

# Get the kubelet identity (node pool managed identity)
KUBELET_IDENTITY=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "identityProfile.kubeletidentity.clientId" -o tsv)

echo "Kubelet Identity Client ID: $KUBELET_IDENTITY"

# Get App Configuration resource ID
APP_CONFIG_NAME="aks-appconfig-12"
APP_CONFIG_ID=$(az appconfig show \
  --name $APP_CONFIG_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" -o tsv)

# Grant "App Configuration Data Reader" role
az role assignment create \
  --assignee $KUBELET_IDENTITY \
  --role "App Configuration Data Reader" \
  --scope $APP_CONFIG_ID

# Verify role assignment
az role assignment list \
  --assignee $KUBELET_IDENTITY \
  --scope $APP_CONFIG_ID \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

## Step 2: Update Deployment

The deployment doesn't need a service account. Just set the endpoint:

```yaml
env:
- name: AZURE_APP_CONFIG_ENDPOINT
  value: "https://aks-appconfig-12.azconfig.io"
# Optional: Only specify if node pool has multiple managed identities
# - name: AZURE_CLIENT_ID
#   value: "<KUBELET_IDENTITY_CLIENT_ID>"
```

## Step 3: Deploy

```bash
# No service account needed!
kubectl apply -f k8s/deployment.yaml

# Check pods
kubectl get pods -l app=azure-app-config-app

# Check logs
kubectl logs -l app=azure-app-config-app
```

## How It Works

1. **DefaultAzureCredential** tries multiple authentication methods in order:
   - Environment variables (if set)
   - **Managed Identity (IMDS)** ← This is what we use!
   - Azure CLI (for local development)
   - Visual Studio Code
   - Azure PowerShell
   - Azure Developer CLI

2. When running in AKS, it automatically detects the node pool's managed identity via IMDS

3. The managed identity is inherited by all pods running on that node pool

## Optional: Specify Client ID

If your node pool has multiple managed identities, you can specify which one to use:

```yaml
env:
- name: AZURE_APP_CONFIG_ENDPOINT
  value: "https://aks-appconfig-12.azconfig.io"
- name: AZURE_CLIENT_ID
  value: "63b2867c-57e5-4150-aeca-da497348b4a6"  # Kubelet identity client ID
```

Or in code, it will use `ManagedIdentityCredential` with the specified client ID.

## Troubleshooting

### Issue: Authentication fails

**Check node pool managed identity**:
```bash
az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "identityProfile.kubeletidentity" -o json
```

**Check role assignments**:
```bash
KUBELET_IDENTITY=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "identityProfile.kubeletidentity.clientId" -o tsv)

az role assignment list \
  --assignee $KUBELET_IDENTITY \
  --scope $APP_CONFIG_ID
```

**Check pod logs**:
```bash
kubectl logs -l app=azure-app-config-app
```

### Issue: Cannot access IMDS

**Verify IMDS is accessible from pods**:
```bash
kubectl run -it --rm test-imds --image=curlimages/curl --restart=Never -- \
  curl -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
```

## Comparison: Node Pool MI vs Workload Identity

| Feature | Node Pool Managed Identity | Workload Identity |
|---------|---------------------------|-------------------|
| **Setup Complexity** | Simple | More complex |
| **Service Account** | Not needed | Required |
| **Federated Credential** | Not needed | Required |
| **Token Injection** | Via IMDS | Via webhook |
| **Isolation** | Shared across node pool | Per service account |
| **Best For** | Simple scenarios | Fine-grained access control |

## Benefits

- ✅ **Simpler**: No service accounts or federated credentials
- ✅ **Automatic**: Works if node pool has managed identity
- ✅ **Less configuration**: Just set the endpoint
- ✅ **Secure**: Still uses managed identity (no secrets)

## Next Steps

1. Grant permissions to node pool managed identity
2. Update deployment with endpoint
3. Deploy and test
4. Monitor logs to verify authentication

