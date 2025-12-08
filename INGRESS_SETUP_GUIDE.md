# Ingress Setup Guide for mikegaohahaha.com

This guide explains how to set up an ingress controller and configure it for your domain.

## Prerequisites

1. AKS cluster with NGINX Ingress Controller installed
2. Domain `mikegaohahaha.com` pointing to your ingress IP
3. TLS certificate (optional but recommended)

## Step 1: Install NGINX Ingress Controller (if not already installed)

```bash
# Add the ingress-nginx Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Wait for the LoadBalancer to get an IP
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Get the ingress IP
kubectl get service ingress-nginx-controller -n ingress-nginx
```

## Step 2: Deploy Internal Service

```bash
# Deploy the internal ClusterIP service
kubectl apply -f k8s/service-internal.yaml

# Verify service
kubectl get service azure-app-config-internal-service
```

## Step 3: Deploy Ingress

```bash
# Deploy the ingress
kubectl apply -f k8s/ingress.yaml

# Check ingress status
kubectl get ingress azure-app-config-ingress

# Get the ingress IP (should match the ingress controller IP)
kubectl get ingress azure-app-config-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Step 4: Configure DNS

Point your domain to the ingress controller's IP address:

```bash
# Get the ingress controller IP
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Point your DNS records to: $INGRESS_IP"
```

**DNS Records to Create:**
- **A Record**: `mikegaohahaha.com` → `<INGRESS_IP>`
- **A Record**: `www.mikegaohahaha.com` → `<INGRESS_IP>` (optional)

## Step 5: Verify Access

```bash
# Test locally (before DNS propagates)
curl -H "Host: mikegaohahaha.com" http://<INGRESS_IP>

# Or add to /etc/hosts for testing
# <INGRESS_IP> mikegaohahaha.com
```

## Step 6: Configure TLS (Optional but Recommended)

### Option A: Using cert-manager (Recommended)

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
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
EOF

# Update ingress.yaml to enable TLS (uncomment TLS section)
# Then reapply:
kubectl apply -f k8s/ingress.yaml
```

### Option B: Using Azure Key Vault

1. Store your certificate in Azure Key Vault
2. Use Azure Key Vault CSI driver to mount the certificate
3. Create a Kubernetes secret from the certificate
4. Reference it in the ingress TLS section

## Troubleshooting

### Issue: Ingress not getting an IP

**Check**:
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Check ingress
kubectl describe ingress azure-app-config-ingress
```

### Issue: 404 Not Found

**Check**:
```bash
# Verify service endpoints
kubectl get endpoints azure-app-config-internal-service

# Verify pods are running
kubectl get pods -l app=azure-app-config-app

# Check ingress backend
kubectl describe ingress azure-app-config-ingress
```

### Issue: DNS not resolving

**Check**:
```bash
# Verify DNS records
nslookup mikegaohahaha.com
dig mikegaohahaha.com

# Test with Host header
curl -H "Host: mikegaohahaha.com" http://<INGRESS_IP>
```

### Issue: Certificate not issued

**Check cert-manager**:
```bash
# Check certificate status
kubectl get certificate -n default
kubectl describe certificate mikegaohahaha-tls

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager
```

## Architecture

```
Internet
    ↓
DNS (mikegaohahaha.com)
    ↓
Ingress Controller (LoadBalancer)
    ↓
Ingress Resource
    ↓
Internal Service (ClusterIP)
    ↓
Application Pods
```

## Service Comparison

| Service | Type | Purpose | Access |
|---------|------|---------|--------|
| `azure-app-config-internal-service` | ClusterIP | Internal access via Ingress | Through Ingress only |
| `azure-app-config-app-service` | LoadBalancer | Direct public access | Public IP |
| `azure-app-config-pls-service` | LoadBalancer (Internal) | Front Door via Private Link | Private Link only |

## Next Steps

1. ✅ Deploy internal service
2. ✅ Deploy ingress
3. ✅ Configure DNS
4. ⬜ Configure TLS (optional)
5. ⬜ Set up monitoring
6. ⬜ Configure WAF rules (if needed)

