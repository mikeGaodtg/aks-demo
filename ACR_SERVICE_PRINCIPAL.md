# ACR Service Principal Access - Quick Reference

This guide focuses specifically on setting up service principal access to Azure Container Registry.

## Why Use Service Principal?

- **CI/CD Pipelines**: Automated builds and deployments
- **Cross-tenant access**: Access ACR from different Azure subscriptions
- **Fine-grained control**: Assign specific roles (AcrPull, AcrPush, AcrDelete)
- **Legacy AKS clusters**: If your AKS cluster uses service principal instead of managed identity

## Method 1: Grant Access to Existing AKS Service Principal

If your AKS cluster already uses a service principal:

```bash
# Set variables
RESOURCE_GROUP="Mike"
ACR_NAME="your-acr-name"
AKS_CLUSTER_NAME="your-aks-cluster-name"

# Get AKS service principal ID
AKS_SP_ID=$(az aks show \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "servicePrincipalProfile.clientId" \
  --output tsv)

echo "AKS Service Principal ID: $AKS_SP_ID"

# Get ACR resource ID
ACR_ID=$(az acr show \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" \
  --output tsv)

# Grant AcrPull role (for pulling images)
az role assignment create \
  --assignee $AKS_SP_ID \
  --role acrpull \
  --scope $ACR_ID

# Verify the assignment
az role assignment list \
  --assignee $AKS_SP_ID \
  --scope $ACR_ID \
  --output table
```

**Note**: If `servicePrincipalProfile.clientId` is null, your AKS cluster uses managed identity. Use `az aks update --attach-acr` instead (see Method 3).

## Method 2: Create New Service Principal for ACR

Create a dedicated service principal specifically for ACR access:

```bash
# Set variables
RESOURCE_GROUP="Mike"
ACR_NAME="your-acr-name"
SP_NAME="acr-sp-$(date +%s)"  # Unique name with timestamp

# Create service principal
SP_OUTPUT=$(az ad sp create-for-rbac \
  --name $SP_NAME \
  --skip-assignment \
  --output json)

# Extract values
SP_APP_ID=$(echo $SP_OUTPUT | jq -r '.appId')
SP_PASSWORD=$(echo $SP_OUTPUT | jq -r '.password')

# Save these values - you won't be able to retrieve the password again!
echo "Service Principal App ID: $SP_APP_ID"
echo "Service Principal Password: $SP_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Save the password now - you cannot retrieve it later!"

# Get ACR resource ID
ACR_ID=$(az acr show \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" \
  --output tsv)

# Grant AcrPull role (for pulling images from AKS)
az role assignment create \
  --assignee $SP_APP_ID \
  --role acrpull \
  --scope $ACR_ID

# Optional: Grant AcrPush role (for pushing images from CI/CD)
az role assignment create \
  --assignee $SP_APP_ID \
  --role acrpush \
  --scope $ACR_ID

# Optional: Grant AcrDelete role (for deleting images)
az role assignment create \
  --assignee $SP_APP_ID \
  --role acrdelete \
  --scope $ACR_ID

# Verify assignments
az role assignment list \
  --assignee $SP_APP_ID \
  --scope $ACR_ID \
  --output table
```

### Create Kubernetes Secret

After creating the service principal, create a Kubernetes secret so pods can pull images:

```bash
# Create secret in Kubernetes
kubectl create secret docker-registry acr-secret \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=$SP_APP_ID \
  --docker-password=$SP_PASSWORD \
  --namespace=default

# Verify secret
kubectl get secret acr-secret -o yaml
```

### Update Deployment YAML

Make sure your `k8s/deployment.yaml` includes the imagePullSecrets:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: acr-secret
      containers:
      - name: azure-app-config-app
        image: your-acr-name.azurecr.io/azure-app-config-app:latest
        # ... rest of config
```

## Method 3: Use Managed Identity (Recommended - Easiest)

If your AKS cluster uses managed identity (default for clusters created after 2020), this is the simplest method:

```bash
# Set variables
RESOURCE_GROUP="Mike"
ACR_NAME="your-acr-name"
AKS_CLUSTER_NAME="your-aks-cluster-name"

# Attach ACR to AKS (automatically grants managed identity access)
az aks update \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --attach-acr $ACR_NAME
```

**Benefits**:
- No passwords to manage
- No Kubernetes secrets needed
- Automatic access granted
- More secure

**Note**: Remove `imagePullSecrets` from your deployment.yaml when using this method.

## ACR Role Permissions

| Role | Permissions | Use Case |
|------|-------------|----------|
| **AcrPull** | Pull images | AKS pods pulling images |
| **AcrPush** | Push images | CI/CD pipelines pushing images |
| **AcrDelete** | Delete images | Cleanup jobs |
| **AcrImageSigner** | Sign images | Content trust |
| **Owner** | Full access | Admin access (not recommended) |
| **Contributor** | Full access except permissions | Admin access (not recommended) |

## Verify Service Principal Access

### Test Login with Service Principal

```bash
# Login using service principal
docker login $ACR_NAME.azurecr.io \
  --username $SP_APP_ID \
  --password $SP_PASSWORD

# Try pulling an image
docker pull $ACR_NAME.azurecr.io/azure-app-config-app:latest
```

### Check Role Assignments

```bash
# List all role assignments for ACR
ACR_ID=$(az acr show \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" \
  --output tsv)

az role assignment list \
  --scope $ACR_ID \
  --output table
```

### Check Service Principal Details

```bash
# Get service principal details
az ad sp show --id $SP_APP_ID

# List all service principals (filter by name)
az ad sp list --display-name "acr-sp*" --output table
```

## Troubleshooting

### Issue: "unauthorized: authentication required"

**Cause**: Service principal doesn't have proper permissions or credentials are wrong.

**Solution**:
```bash
# Verify role assignment
az role assignment list --assignee $SP_APP_ID --scope $ACR_ID

# Re-grant permissions if needed
az role assignment create \
  --assignee $SP_APP_ID \
  --role acrpull \
  --scope $ACR_ID
```

### Issue: "ImagePullBackOff" in Kubernetes

**Cause**: Kubernetes secret is missing or incorrect.

**Solution**:
```bash
# Check if secret exists
kubectl get secret acr-secret

# Delete and recreate secret
kubectl delete secret acr-secret
kubectl create secret docker-registry acr-secret \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=$SP_APP_ID \
  --docker-password=$SP_PASSWORD \
  --namespace=default

# Verify deployment has imagePullSecrets
kubectl get deployment azure-app-config-app -o yaml | grep imagePullSecrets
```

### Issue: Service Principal Password Lost

**Solution**: You cannot retrieve the password. You must create a new service principal or reset the existing one:

```bash
# Reset service principal password
az ad sp credential reset \
  --name $SP_NAME \
  --password "new-password-here"

# Update Kubernetes secret with new password
kubectl create secret docker-registry acr-secret \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=$SP_APP_ID \
  --docker-password="new-password-here" \
  --namespace=default \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Best Practices

### 1. Use Managed Identity When Possible

```bash
# Check if AKS uses managed identity
az aks show \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "identity"

# If identity.type is "UserAssigned" or "SystemAssigned", use:
az aks update --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME
```

### 2. Use Least Privilege

Only grant the minimum permissions needed:
- AKS pods: `AcrPull` only
- CI/CD pipelines: `AcrPush` + `AcrPull`
- Cleanup jobs: `AcrDelete` + `AcrPull`

### 3. Rotate Credentials Regularly

```bash
# Create new password
NEW_PASSWORD=$(az ad sp credential reset --name $SP_NAME --query "password" -o tsv)

# Update Kubernetes secret
kubectl create secret docker-registry acr-secret \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=$SP_APP_ID \
  --docker-password=$NEW_PASSWORD \
  --namespace=default \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to use new credentials
kubectl rollout restart deployment azure-app-config-app
```

### 4. Use Different Service Principals for Different Environments

```bash
# Dev environment
SP_DEV_NAME="acr-sp-dev"
# Prod environment
SP_PROD_NAME="acr-sp-prod"
```

### 5. Store Credentials Securely

- **Never commit passwords to git**
- Use Azure Key Vault for storing secrets
- Use Kubernetes secrets (encrypted at rest)
- Consider using Azure Key Vault Provider for Secrets Store CSI Driver

## Quick Command Reference

```bash
# Variables
RESOURCE_GROUP="Mike"
ACR_NAME="your-acr-name"
AKS_CLUSTER_NAME="your-aks-cluster-name"

# Get AKS service principal
az aks show --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --query "servicePrincipalProfile.clientId" -o tsv

# Grant AcrPull to AKS service principal
AKS_SP_ID=$(az aks show --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --query "servicePrincipalProfile.clientId" -o tsv)
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" -o tsv)
az role assignment create --assignee $AKS_SP_ID --role acrpull --scope $ACR_ID

# Create new service principal
az ad sp create-for-rbac --name "acr-sp-$(date +%s)" --skip-assignment

# Create Kubernetes secret
kubectl create secret docker-registry acr-secret \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=$SP_APP_ID \
  --docker-password=$SP_PASSWORD

# Use managed identity (easiest)
az aks update --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME
```

## Next Steps

1. Choose your method (Managed Identity recommended)
2. Set up access using one of the methods above
3. Update `k8s/deployment.yaml` accordingly
4. Deploy and verify

For complete ACR setup, see `ACR_SETUP.md`.

