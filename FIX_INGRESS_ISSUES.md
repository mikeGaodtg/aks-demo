# Fix Ingress Issues - HTTP Only (No TLS)

This guide helps you fix ingress issues by removing TLS and using HTTP only.

## Changes Made

1. ✅ Removed TLS configuration from ingress
2. ✅ Removed SSL redirect
3. ✅ Removed cert-manager annotations
4. ✅ Recreated internal service (if it was deleted)

## Step 1: Recreate Internal Service (if needed)

```bash
# Check if service exists
kubectl get service azure-app-config-internal-service

# If not found, create it
kubectl apply -f k8s/service-internal.yaml

# Verify service
kubectl get service azure-app-config-internal-service
kubectl get endpoints azure-app-config-internal-service
```

## Step 2: Apply Updated Ingress (No TLS)

```bash
# Apply the updated ingress (HTTP only, no TLS)
kubectl apply -f k8s/ingress.yaml

# Check ingress status
kubectl get ingress azure-app-config-ingress

# Describe ingress for details
kubectl describe ingress azure-app-config-ingress
```

## Step 3: Verify Ingress Controller

```bash
# Check ingress controller service
kubectl get service ingress-nginx-controller -n ingress-nginx

# Verify it's LoadBalancer type
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.type}'
# Should output: LoadBalancer

# Get the public IP
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"
```

## Step 4: Verify DNS

```bash
# Check DNS resolution
nslookup app.mikegaohahahahagogogogo.site
dig app.mikegaohahahahagogogogo.site

# Should resolve to your ingress IP
```

## Step 5: Test Access

```bash
# Test with Host header (before DNS propagates)
curl -H "Host: app.mikegaohahahahagogogogo.site" http://$INGRESS_IP

# Or test directly if DNS is configured
curl http://app.mikegaohahahahagogogogo.site
```

## Troubleshooting

### Issue: Ingress not accessible

**Check ingress controller:**
```bash
# Check pods
kubectl get pods -n ingress-nginx

# Check logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

### Issue: 404 Not Found

**Check backend service:**
```bash
# Verify service exists
kubectl get service azure-app-config-internal-service

# Check endpoints (should show pod IPs)
kubectl get endpoints azure-app-config-internal-service

# Verify pods are running
kubectl get pods -l app=azure-app-config-app
```

### Issue: Service has no endpoints

**Check pod labels match service selector:**
```bash
# Check service selector
kubectl get service azure-app-config-internal-service -o jsonpath='{.spec.selector}'

# Check pod labels
kubectl get pods -l app=azure-app-config-app --show-labels

# Should match: app: azure-app-config-app
```

### Issue: Ingress IP changed after redeploy

**Get new IP and update DNS:**
```bash
# Get new ingress IP
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Update DNS to point to: $INGRESS_IP"
```

## Quick Fix Commands

```bash
# 1. Recreate internal service
kubectl apply -f k8s/service-internal.yaml

# 2. Apply ingress (HTTP only)
kubectl apply -f k8s/ingress.yaml

# 3. Check everything
kubectl get ingress
kubectl get service azure-app-config-internal-service
kubectl get pods -l app=azure-app-config-app

# 4. Test
curl -H "Host: app.mikegaohahahahagogogogo.site" http://$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

## Verification Checklist

- [ ] Internal service exists and has endpoints
- [ ] Pods are running with correct labels
- [ ] Ingress resource is deployed
- [ ] Ingress controller service is LoadBalancer type
- [ ] Ingress controller has a public IP
- [ ] DNS points to ingress IP
- [ ] Can access via HTTP (no HTTPS)

## Why TLS Was Removed

TLS can cause issues when:
- Ingress controller is redeployed
- Certificate secret is missing
- cert-manager is not working
- DNS changes

Using HTTP only simplifies troubleshooting and ensures the site works immediately.


