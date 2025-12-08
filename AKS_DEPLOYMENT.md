# AKS Deployment Guide

This guide will help you deploy the Azure App Configuration app to Azure Kubernetes Service (AKS).

## Prerequisites

Before deploying to AKS, you need:

1. **Azure CLI** installed and logged in
   ```bash
   az login
   az account set --subscription <your-subscription-id>
   ```

2. **kubectl** installed
   ```bash
   az aks install-cli
   ```

3. **Docker** installed (for building images)

4. **AKS Cluster** created (or use existing)
   ```bash
   # Create AKS cluster (if you don't have one)
   az aks create \
     --resource-group Mike \
     --name your-aks-cluster \
     --node-count 2 \
     --enable-addons monitoring \
     --generate-ssh-keys
   ```

5. **Get AKS credentials**
   ```bash
   az aks get-credentials --resource-group Mike --name your-aks-cluster
   ```

## Step 1: Build and Push Docker Image

You have two options for container registry:

### Option A: Azure Container Registry (ACR) - Recommended

1. **Create ACR** (if you don't have one):
   ```bash
   az acr create --resource-group Mike --name your-acr-name --sku Basic
   ```

2. **Login to ACR**:
   ```bash
   az acr login --name your-acr-name
   ```

3. **Build and push image**:
   ```bash
   # Build the image
   docker build -t your-acr-name.azurecr.io/azure-app-config-app:latest .
   
   # Push to ACR
   docker push your-acr-name.azurecr.io/azure-app-config-app:latest
   ```

4. **Attach ACR to AKS** (allows AKS to pull images):
   ```bash
   az aks update -n your-aks-cluster -g Mike --attach-acr your-acr-name
   ```

5. **Update deployment.yaml**: Replace `<YOUR_REGISTRY>` with `your-acr-name.azurecr.io`

### Option B: Docker Hub

1. **Login to Docker Hub**:
   ```bash
   docker login
   ```

2. **Build and push image**:
   ```bash
   docker build -t your-dockerhub-username/azure-app-config-app:latest .
   docker push your-dockerhub-username/azure-app-config-app:latest
   ```

3. **Create registry secret** (for private repos):
   ```bash
   kubectl create secret docker-registry registry-secret \
     --docker-server=https://index.docker.io/v1/ \
     --docker-username=your-dockerhub-username \
     --docker-password=your-dockerhub-password \
     --docker-email=your-email@example.com \
     --namespace=default
   ```

4. **Update deployment.yaml**: Replace `<YOUR_REGISTRY>` with `docker.io/your-dockerhub-username`

## Step 2: Create Kubernetes Secret

Create a secret for your Azure App Configuration connection string:

```bash
kubectl create secret generic azure-app-config-secret \
  --from-literal=connection-string='Endpoint=https://aks-appconfig-12.azconfig.io;Id=...;Secret=...' \
  --namespace=default
```

**Important**: Replace the connection string with your actual Azure App Configuration connection string.

To get your connection string:
- Go to Azure Portal
- Navigate to your App Configuration resource: `aks-appconfig-12` (Resource Group: `Mike`)
- Go to "Access keys"
- Copy the connection string

## Step 3: Update Deployment YAML

Edit `k8s/deployment.yaml` and replace `<YOUR_REGISTRY>` with your actual registry path:

- For ACR: `your-acr-name.azurecr.io/azure-app-config-app:latest`
- For Docker Hub: `docker.io/your-dockerhub-username/azure-app-config-app:latest`

If using ACR and you've attached it to AKS, you can remove the `imagePullSecrets` section from the deployment.

## Step 4: Deploy to AKS

1. **Apply the deployment**:
   ```bash
   kubectl apply -f k8s/deployment.yaml
   ```

2. **Apply the service**:
   ```bash
   kubectl apply -f k8s/service.yaml
   ```

3. **Check deployment status**:
   ```bash
   kubectl get pods
   kubectl get services
   ```

4. **View logs** (if needed):
   ```bash
   kubectl logs -f deployment/azure-app-config-app
   ```

## Step 5: Access Your Application

### Using LoadBalancer Service

After deploying, get the external IP:

```bash
kubectl get service azure-app-config-app-service
```

Wait for the `EXTERNAL-IP` to be assigned (may take a few minutes), then access:
```
http://<EXTERNAL-IP>
```

### Using Ingress (Optional)

If you prefer using Ingress:

1. Install NGINX Ingress Controller:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
   ```

2. Update `k8s/ingress.yaml` with your domain

3. Apply ingress:
   ```bash
   kubectl apply -f k8s/ingress.yaml
   ```

4. Update service type to ClusterIP in `k8s/service.yaml`:
   ```yaml
   type: ClusterIP
   ```

## Monitoring and Troubleshooting

### Check Pod Status
```bash
kubectl get pods -l app=azure-app-config-app
```

### View Pod Logs
```bash
kubectl logs -l app=azure-app-config-app --tail=50
```

### Describe Pod (for errors)
```bash
kubectl describe pod <pod-name>
```

### Check Service
```bash
kubectl get svc azure-app-config-app-service
kubectl describe svc azure-app-config-app-service
```

### Scale Deployment
```bash
kubectl scale deployment azure-app-config-app --replicas=3
```

### Update Image
```bash
# After pushing new image
kubectl set image deployment/azure-app-config-app azure-app-config-app=your-registry/azure-app-config-app:v2
```

### Rollback
```bash
kubectl rollout undo deployment/azure-app-config-app
```

## Clean Up

To remove all resources:

```bash
kubectl delete -f k8s/service.yaml
kubectl delete -f k8s/deployment.yaml
kubectl delete secret azure-app-config-secret
```

## Security Best Practices

1. **Use Azure Key Vault** for secrets (instead of Kubernetes secrets):
   - Install Azure Key Vault Provider for Secrets Store CSI Driver
   - Mount secrets as volumes instead of environment variables

2. **Use Managed Identity** for Azure App Configuration:
   - Instead of connection strings, use Azure AD authentication
   - Assign managed identity to your AKS pods

3. **Network Policies**:
   - Implement Kubernetes Network Policies to restrict pod-to-pod communication

4. **RBAC**:
   - Use Role-Based Access Control for Kubernetes resources

5. **Image Security**:
   - Scan images for vulnerabilities
   - Use private registries (ACR)

## Additional Resources

- [AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Azure App Configuration](https://docs.microsoft.com/azure/azure-app-configuration/)

