# Quick Start: Deploy with Ingress Controller

This is a step-by-step guide to deploy your app to AKS using Docker Hub and NGINX Ingress Controller with your domain `mikegaohahahahagogogogo.site`.

## Prerequisites Checklist

- [ ] AKS cluster created and running
- [ ] kubectl configured: `az aks get-credentials --resource-group Mike --name your-aks-cluster`
- [ ] Docker Hub account created
- [ ] Domain `mikegaohahahahagogogogo.site` registered
- [ ] Azure App Configuration connection string ready

## Step-by-Step Instructions

### 1. Install NGINX Ingress Controller

```bash
# Add Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Wait for external IP (2-5 minutes)
kubectl get service ingress-nginx-controller -n ingress-nginx -w
```

**Save the EXTERNAL-IP** - you'll need it for DNS!

### 2. Configure DNS

Get the Ingress Controller IP:

```bash
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Configure DNS A record: $INGRESS_IP"
```

Go to your domain registrar and create:
- **Type**: A
- **Name**: @ (or blank)
- **Value**: `<INGRESS_IP>`
- **TTL**: 300

### 3. Build and Push to Docker Hub

```bash
# Login to Docker Hub
docker login

# Navigate to project
cd "c:\Users\gaom\Documents\code sample\fetch from config app"

# Build image (replace YOUR_USERNAME)
docker build -t YOUR_USERNAME/azure-app-config-app:latest .

# Push to Docker Hub
docker push YOUR_USERNAME/azure-app-config-app:latest
```

### 4. Update Deployment YAML

Edit `k8s/deployment.yaml`:

```yaml
image: YOUR_USERNAME/azure-app-config-app:latest
```

Replace `YOUR_USERNAME` with your Docker Hub username.

### 5. Create Kubernetes Secret

```bash
kubectl create secret generic azure-app-config-secret \
  --from-literal=connection-string='Endpoint=https://aks-appconfig-12.azconfig.io;Id=...;Secret=...' \
  --namespace=default
```

Replace with your actual connection string.

### 6. Deploy Application

```bash
# Deploy everything
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# Check status
kubectl get pods
kubectl get services
kubectl get ingress
```

### 7. Verify Everything Works

```bash
# Check pods are running
kubectl get pods -l app=azure-app-config-app

# Check ingress
kubectl get ingress azure-app-config-app-ingress

# Test DNS (wait 15-30 min for propagation)
nslookup mikegaohahahahagogogogo.site

# Test HTTP
curl http://mikegaohahahahagogogogo.site
```

### 8. (Optional) Enable HTTPS

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Edit cert-manager-clusterissuer.yaml and add your email
# Then apply:
kubectl apply -f cert-manager-clusterissuer.yaml

# Uncomment TLS section in k8s/ingress.yaml, then:
kubectl apply -f k8s/ingress.yaml

# Wait for certificate (1-2 minutes)
kubectl get certificate
```

## Troubleshooting

### Ingress has no address
```bash
kubectl get service ingress-nginx-controller -n ingress-nginx
# Wait for EXTERNAL-IP to be assigned
```

### 502 Bad Gateway
```bash
# Check pods
kubectl get pods -l app=azure-app-config-app
kubectl logs -l app=azure-app-config-app

# Check service endpoints
kubectl get endpoints azure-app-config-app-service
```

### DNS not working
```bash
# Verify DNS record
nslookup mikegaohahahahagogogogo.site
# Should return Ingress Controller IP
# Wait 15-30 minutes for propagation
```

### Image pull errors
```bash
# Verify image exists
docker pull YOUR_USERNAME/azure-app-config-app:latest

# Check deployment image name
kubectl get deployment azure-app-config-app -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Quick Commands Reference

```bash
# Get Ingress IP
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# View logs
kubectl logs -l app=azure-app-config-app -f

# Restart deployment
kubectl rollout restart deployment azure-app-config-app

# Scale deployment
kubectl scale deployment azure-app-config-app --replicas=3

# Check everything
kubectl get all -l app=azure-app-config-app
```

## Expected Result

After completing all steps:
- ✅ Your app accessible at: `http://mikegaohahahahagogogogo.site`
- ✅ (Optional) HTTPS at: `https://mikegaohahahahagogogogo.site`
- ✅ Ingress Controller routing traffic
- ✅ Application showing Azure App Configuration values

## Next Steps

- Monitor application: `kubectl get pods -w`
- Set up monitoring and alerting
- Configure auto-scaling
- Set up CI/CD pipeline

For detailed information, see:
- `INGRESS_SETUP.md` - Complete Ingress setup guide
- `DOCKERHUB_SETUP.md` - Docker Hub details
- `AKS_DEPLOYMENT.md` - General AKS deployment info

