# Ingress Controller Setup Guide

This guide will help you set up NGINX Ingress Controller in AKS and configure your domain `mikegaohahahahagogogogo.site`.

## Prerequisites

- AKS cluster running
- kubectl configured to connect to your AKS cluster
- Domain `mikegaohahahahagogogogo.site` (DNS configured or ready to configure)
- Docker Hub account (for pushing images)

## Step 1: Install NGINX Ingress Controller

### Option A: Using Helm (Recommended)

```bash
# Add NGINX Ingress Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

### Option B: Using kubectl (Direct)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

### Verify Installation

```bash
# Check if ingress controller pods are running
kubectl get pods -n ingress-nginx

# Get the external IP address
kubectl get service ingress-nginx-controller -n ingress-nginx

# Wait for EXTERNAL-IP to be assigned (may take 2-5 minutes)
kubectl get service ingress-nginx-controller -n ingress-nginx -w
```

**Note**: Save the EXTERNAL-IP address - you'll need it for DNS configuration.

## Step 2: Configure DNS

You need to point your domain to the Ingress Controller's external IP.

### Get Ingress Controller IP

```bash
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress Controller IP: $INGRESS_IP"
```

### Configure DNS Records

Go to your domain registrar (where you bought `mikegaohahahahagogogogo.site`) and create an **A record**:

- **Type**: A
- **Name**: @ (or leave blank for root domain)
- **Value**: `<INGRESS_IP>` (the IP from above)
- **TTL**: 300 (or default)

**For subdomain** (e.g., `www.mikegaohahahahagogogogo.site`):
- **Type**: A
- **Name**: www
- **Value**: `<INGRESS_IP>`
- **TTL**: 300

### Verify DNS Propagation

```bash
# Check if DNS is resolving
nslookup mikegaohahahahagogogogo.site
# or
dig mikegaohahahahagogogogo.site

# Should return the Ingress Controller IP
```

**Note**: DNS propagation can take 5 minutes to 48 hours, but usually happens within 15-30 minutes.

## Step 3: Build and Push Docker Image to Docker Hub

### Login to Docker Hub

```bash
docker login
# Enter your Docker Hub username and password
```

### Build and Push Image

```bash
# Navigate to your project directory
cd "c:\Users\gaom\Documents\code sample\fetch from config app"

# Build the image (replace YOUR_DOCKERHUB_USERNAME with your actual username)
docker build -t YOUR_DOCKERHUB_USERNAME/azure-app-config-app:latest .

# Push to Docker Hub
docker push YOUR_DOCKERHUB_USERNAME/azure-app-config-app:latest
```

### Update Deployment YAML

Edit `k8s/deployment.yaml` and replace `<YOUR_DOCKERHUB_USERNAME>` with your actual Docker Hub username:

```yaml
image: your-dockerhub-username/azure-app-config-app:latest
```

## Step 4: Create Kubernetes Secret for Azure App Configuration

```bash
kubectl create secret generic azure-app-config-secret \
  --from-literal=connection-string='Endpoint=https://aks-appconfig-12.azconfig.io;Id=...;Secret=...' \
  --namespace=default
```

Replace the connection string with your actual Azure App Configuration connection string.

## Step 5: Deploy Your Application

```bash
# Apply deployment
kubectl apply -f k8s/deployment.yaml

# Apply service (ClusterIP - required for Ingress)
kubectl apply -f k8s/service.yaml

# Apply ingress
kubectl apply -f k8s/ingress.yaml

# Check deployment status
kubectl get pods
kubectl get services
kubectl get ingress
```

## Step 6: Verify Ingress

```bash
# Check ingress status
kubectl get ingress azure-app-config-app-ingress

# Describe ingress for details
kubectl describe ingress azure-app-config-app-ingress

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

## Step 7: Test Your Application

Once DNS has propagated, test your application:

```bash
# Test with curl
curl http://mikegaohahahahagogogogo.site

# Or open in browser
# http://mikegaohahahahagogogogo.site
```

## Optional: Enable HTTPS with Let's Encrypt (cert-manager)

### Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### Create ClusterIssuer

Create a file `cert-manager-clusterissuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Replace with your email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

Apply it:

```bash
kubectl apply -f cert-manager-clusterissuer.yaml
```

### Update Ingress for TLS

Uncomment the TLS section in `k8s/ingress.yaml`:

```yaml
spec:
  tls:
  - hosts:
    - mikegaohahahahagogogogo.site
    secretName: azure-app-config-tls
  rules:
  - host: mikegaohahahahagogogogo.site
    # ... rest of config
```

Apply the updated ingress:

```bash
kubectl apply -f k8s/ingress.yaml
```

cert-manager will automatically create the TLS certificate. Check status:

```bash
kubectl get certificate
kubectl describe certificate azure-app-config-tls
```

After the certificate is issued (usually 1-2 minutes), your site will be accessible via HTTPS:
- https://mikegaohahahahagogogogo.site

## Troubleshooting

### Issue: Ingress shows no address

**Symptoms**: `kubectl get ingress` shows no ADDRESS

**Solutions**:
```bash
# Check ingress controller is running
kubectl get pods -n ingress-nginx

# Check ingress controller service
kubectl get service ingress-nginx-controller -n ingress-nginx

# Check ingress events
kubectl describe ingress azure-app-config-app-ingress
```

### Issue: 502 Bad Gateway

**Symptoms**: Site loads but shows 502 error

**Solutions**:
```bash
# Check if pods are running
kubectl get pods -l app=azure-app-config-app

# Check pod logs
kubectl logs -l app=azure-app-config-app

# Check service endpoints
kubectl get endpoints azure-app-config-app-service

# Verify service selector matches pod labels
kubectl get pods --show-labels
kubectl get service azure-app-config-app-service -o yaml
```

### Issue: DNS not resolving

**Symptoms**: Domain doesn't resolve to Ingress IP

**Solutions**:
```bash
# Verify DNS record
nslookup mikegaohahahahagogogogo.site

# Check if using correct IP
kubectl get service ingress-nginx-controller -n ingress-nginx

# Wait for DNS propagation (can take up to 48 hours)
# Use online tools like https://dnschecker.org
```

### Issue: Connection timeout

**Symptoms**: Can't connect to domain

**Solutions**:
```bash
# Check if ingress controller has external IP
kubectl get service ingress-nginx-controller -n ingress-nginx

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# Verify firewall rules allow traffic on ports 80 and 443
```

### Issue: Certificate not issued

**Symptoms**: HTTPS doesn't work, certificate pending

**Solutions**:
```bash
# Check certificate status
kubectl get certificate
kubectl describe certificate azure-app-config-tls

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager

# Verify DNS is pointing to Ingress IP
nslookup mikegaohahahahagogogogo.site

# Check ClusterIssuer
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

## Useful Commands

```bash
# Get Ingress Controller IP
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Check all ingresses
kubectl get ingress --all-namespaces

# View ingress configuration
kubectl get ingress azure-app-config-app-ingress -o yaml

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f

# Test DNS resolution
nslookup mikegaohahahahagogogogo.site
dig mikegaohahahahagogogogo.site

# Test HTTP connection
curl -v http://mikegaohahahahagogogogo.site
curl -v https://mikegaohahahahagogogogo.site

# Check certificate status
kubectl get certificate
kubectl describe certificate azure-app-config-tls
```

## Quick Setup Summary

1. ✅ Install NGINX Ingress Controller
2. ✅ Get Ingress Controller external IP
3. ✅ Configure DNS A record pointing to Ingress IP
4. ✅ Build and push Docker image to Docker Hub
5. ✅ Update deployment.yaml with Docker Hub image
6. ✅ Create Kubernetes secret for Azure App Config
7. ✅ Deploy application (deployment, service, ingress)
8. ✅ Wait for DNS propagation
9. ✅ Test: http://mikegaohahahahagogogogo.site
10. ✅ (Optional) Set up HTTPS with cert-manager

## Next Steps

- Monitor your application: `kubectl get pods -w`
- View logs: `kubectl logs -l app=azure-app-config-app -f`
- Scale deployment: `kubectl scale deployment azure-app-config-app --replicas=3`
- Set up monitoring and alerting
- Configure backup strategies

For Docker Hub setup details, see `DOCKERHUB_SETUP.md`.

