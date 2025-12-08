# Azure Container Registry (ACR) Setup Guide

This guide will help you set up Azure Container Registry and configure service principal access for AKS.

## Prerequisites

- Azure CLI installed and logged in
- AKS cluster (or plan to create one)
- Docker installed locally

## Step 1: Create Azure Container Registry

### Option A: Using Azure CLI

```bash
# Set variables (customize as needed)
RESOURCE_GROUP="Mike"
ACR_NAME="your-acr-name"  # Must be globally unique, lowercase, alphanumeric only
LOCATION="eastus"  # or your preferred region

# Create ACR with Basic SKU (cheapest option)
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --location $LOCATION

# Verify ACR was created
az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP
```

### Option B: Using Azure Portal

1. Go to [Azure Portal](https://portal.azure.com)
2. Click "Create a resource"
3. Search for "Container Registry"
4. Click "Create"
5. Fill in:
   - **Resource Group**: Mike
   - **Registry name**: your-acr-name (must be globally unique)
   - **Location**: Choose your region
   - **SKU**: Basic (for cost savings) or Standard (recommended for production)
6. Click "Review + create" then "Create"

### ACR SKU Options

- **Basic**: $5/month, 10GB storage, 1GB/day webhook throughput
- **Standard**: $25/month, 100GB storage, 5GB/day webhook throughput
- **Premium**: $100/month, 500GB storage, 10GB/day webhook throughput, geo-replication

## Step 2: Login to ACR

### Option A: Using Azure CLI (Recommended)

```bash
# Login to ACR using Azure CLI
az acr login --name $ACR_NAME
```

This automatically uses your Azure credentials.

### Option B: Using Docker Login

```bash
# Get ACR login credentials
az acr credential show --name $ACR_NAME

# Use the username and password to login
docker login $ACR_NAME.azurecr.io -u <username> -p <password>
```

## Step 3: Build and Push Docker Image

```bash
# Navigate to your project directory
cd "c:\Users\gaom\Documents\code sample\fetch from config app"

# Build the image
docker build -t $ACR_NAME.azurecr.io/azure-app-config-app:latest .

# Tag for versioning (optional)
docker tag $ACR_NAME.azurecr.io/azure-app-config-app:latest $ACR_NAME.azurecr.io/azure-app-config-app:v1.0.0

# Push to ACR
docker push $ACR_NAME.azurecr.io/azure-app-config-app:latest
docker push $ACR_NAME.azurecr.io/azure-app-config-app:v1.0.0  # if you tagged a version
```

### Verify Image in ACR

```bash
# List repositories
az acr repository list --name $ACR_NAME --output table

# List tags for your image
az acr repository show-tags --name $ACR_NAME --repository azure-app-config-app --output table
```

## Step 4: Configure AKS to Access ACR

You have several options to allow AKS to pull images from ACR:

### Option A: Attach ACR to AKS (Easiest - Recommended)

This automatically grants the AKS cluster's managed identity access to ACR:

```bash
# Set variables
AKS_CLUSTER_NAME="your-aks-cluster-name"
RESOURCE_GROUP="Mike"

# Attach ACR to AKS
az aks update \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --attach-acr $ACR_NAME
```

**Note**: This only works if your AKS cluster uses a managed identity (default for new clusters).

### Option B: Grant Access Using Service Principal

If your AKS cluster uses a service principal, you need to grant it access:

#### 1. Get AKS Service Principal

```bash
# Get the service principal ID used by AKS
AKS_SERVICE_PRINCIPAL_ID=$(az aks show \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "servicePrincipalProfile.clientId" \
  --output tsv)

echo "AKS Service Principal ID: $AKS_SERVICE_PRINCIPAL_ID"
```

#### 2. Grant ACR Pull Permission to Service Principal

```bash
# Get ACR resource ID
ACR_ID=$(az acr show \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" \
  --output tsv)

# Grant AcrPull role to AKS service principal
az role assignment create \
  --assignee $AKS_SERVICE_PRINCIPAL_ID \
  --role acrpull \
  --scope $ACR_ID
```

### Option C: Create New Service Principal for ACR Access

If you want a dedicated service principal for ACR access:

#### 1. Create Service Principal

```bash
# Create service principal with ACR pull permissions
ACR_SERVICE_PRINCIPAL_NAME="acr-sp-$(date +%s)"

# Create the service principal and get its details
SP_PASSWORD=$(az ad sp create-for-rbac \
  --name $ACR_SERVICE_PRINCIPAL_NAME \
  --skip-assignment \
  --query "password" \
  --output tsv)

SP_APP_ID=$(az ad sp list \
  --display-name $ACR_SERVICE_PRINCIPAL_NAME \
  --query "[0].appId" \
  --output tsv)

echo "Service Principal App ID: $SP_APP_ID"
echo "Service Principal Password: $SP_PASSWORD"
```

**Important**: Save the password - you won't be able to retrieve it again!

#### 2. Grant ACR Permissions

```bash
# Get ACR resource ID
ACR_ID=$(az acr show \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "id" \
  --output tsv)

# Grant AcrPull role (for pulling images)
az role assignment create \
  --assignee $SP_APP_ID \
  --role acrpull \
  --scope $ACR_ID

# Optional: Grant AcrPush role (for pushing images from CI/CD)
az role assignment create \
  --assignee $SP_APP_ID \
  --role acrpush \
  --scope $ACR_ID
```

#### 3. Create Kubernetes Secret for Service Principal

```bash
# Create secret in Kubernetes
kubectl create secret docker-registry acr-secret \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=$SP_APP_ID \
  --docker-password=$SP_PASSWORD \
  --namespace=default
```

## Step 5: Update Deployment YAML

Update `k8s/deployment.yaml` to use your ACR image:

```yaml
containers:
- name: azure-app-config-app
  image: your-acr-name.azurecr.io/azure-app-config-app:latest
  # ... rest of config
```

### If Using Service Principal Secret

If you created a Kubernetes secret (Option C), make sure your deployment references it:

```yaml
imagePullSecrets:
- name: acr-secret
```

If you used `az aks update --attach-acr` (Option A), you can remove the `imagePullSecrets` section as AKS will use managed identity automatically.

## Step 6: Deploy to AKS

```bash
# Update deployment.yaml with your ACR name first, then:
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Check if pods are pulling images successfully
kubectl get pods
kubectl describe pod <pod-name>  # Check Events section for image pull status
```

## Troubleshooting

### Issue: ImagePullBackOff Error

**Symptoms**: Pods show `ImagePullBackOff` or `ErrImagePull`

**Solutions**:

1. **Check ACR access**:
   ```bash
   # Verify ACR is attached to AKS
   az aks show --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --query "servicePrincipalProfile"
   
   # Re-attach if needed
   az aks update --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME
   ```

2. **Check image exists**:
   ```bash
   az acr repository show-tags --name $ACR_NAME --repository azure-app-config-app
   ```

3. **Verify image name in deployment**:
   ```bash
   kubectl get deployment azure-app-config-app -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

4. **Check service principal permissions**:
   ```bash
   # List role assignments for ACR
   az role assignment list --scope $ACR_ID --output table
   ```

### Issue: Authentication Failed

**Solutions**:

1. **Refresh AKS credentials**:
   ```bash
   az aks get-credentials --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --overwrite-existing
   ```

2. **Re-login to ACR**:
   ```bash
   az acr login --name $ACR_NAME
   ```

3. **Update Kubernetes secret** (if using service principal):
   ```bash
   kubectl delete secret acr-secret
   kubectl create secret docker-registry acr-secret \
     --docker-server=$ACR_NAME.azurecr.io \
     --docker-username=$SP_APP_ID \
     --docker-password=$SP_PASSWORD \
     --namespace=default
   ```

## Best Practices

### 1. Use Managed Identity (Recommended)

- AKS clusters created after 2020 use managed identity by default
- Use `az aks update --attach-acr` for automatic access
- No need to manage service principal passwords

### 2. Image Tagging Strategy

```bash
# Use semantic versioning
docker tag $ACR_NAME.azurecr.io/azure-app-config-app:latest \
           $ACR_NAME.azurecr.io/azure-app-config-app:v1.0.0

# Use commit SHA for traceability
docker tag $ACR_NAME.azurecr.io/azure-app-config-app:latest \
           $ACR_NAME.azurecr.io/azure-app-config-app:$(git rev-parse --short HEAD)

# Push all tags
docker push $ACR_NAME.azurecr.io/azure-app-config-app:latest
docker push $ACR_NAME.azurecr.io/azure-app-config-app:v1.0.0
```

### 3. Enable ACR Admin User (Optional - Not Recommended for Production)

```bash
# Enable admin user (for testing only)
az acr update --name $ACR_NAME --admin-enabled true

# Get admin credentials
az acr credential show --name $ACR_NAME
```

**Note**: Admin user is less secure than service principals. Use only for development/testing.

### 4. ACR Retention Policies

```bash
# Set retention policy (keep only last 10 versions)
az acr repository update \
  --name $ACR_NAME \
  --repository azure-app-config-app \
  --retention-policy-enabled true \
  --retention-policy-days 30
```

### 5. ACR Webhooks (for CI/CD)

```bash
# Create webhook to trigger deployments on image push
az acr webhook create \
  --name myWebhook \
  --registry $ACR_NAME \
  --uri https://your-webhook-url.com \
  --actions push
```

## Quick Reference Commands

```bash
# Set variables
RESOURCE_GROUP="Mike"
ACR_NAME="your-acr-name"
AKS_CLUSTER_NAME="your-aks-cluster-name"

# Create ACR
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic

# Login
az acr login --name $ACR_NAME

# Build and push
docker build -t $ACR_NAME.azurecr.io/azure-app-config-app:latest .
docker push $ACR_NAME.azurecr.io/azure-app-config-app:latest

# Attach ACR to AKS
az aks update --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME

# List images
az acr repository list --name $ACR_NAME --output table
az acr repository show-tags --name $ACR_NAME --repository azure-app-config-app --output table

# Delete ACR (if needed)
az acr delete --name $ACR_NAME --resource-group $RESOURCE_GROUP
```

## Next Steps

1. ✅ Create ACR
2. ✅ Build and push your Docker image
3. ✅ Attach ACR to AKS (or configure service principal)
4. ✅ Update `k8s/deployment.yaml` with your ACR image path
5. ✅ Deploy to AKS
6. ✅ Verify pods are running

For deployment steps, see `AKS_DEPLOYMENT.md`.

