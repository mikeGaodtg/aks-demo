# Public Ingress Setup Guide

This guide explains how to ensure your ingress is publicly accessible.

## Important: Ingress vs Ingress Controller

- **Ingress Resource** (`ingress.yaml`): Configuration that defines routing rules (no type field)
- **Ingress Controller Service**: The actual service that receives traffic (needs `type: LoadBalancer`)

## Step 1: Verify Ingress Controller is Installed

```bash
# Check if ingress controller is installed
kubectl get pods -n ingress-nginx

# Check ingress controller service
kubectl get service ingress-nginx-controller -n ingress-nginx
```

## Step 2: Ensure Ingress Controller Service is LoadBalancer

The Ingress Controller service **must** be `LoadBalancer` type to be publicly accessible.

### Check Current Type

```bash
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.type}'
```

### If Not LoadBalancer, Update It

**Option A: Using kubectl patch**

```bash
kubectl patch service ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}'
```

**Option B: Using kubectl edit**

```bash
kubectl edit service ingress-nginx-controller -n ingress-nginx
# Change type: ClusterIP to type: LoadBalancer
```

**Option C: Reinstall with Helm (Recommended)**

```bash
# Update the ingress controller with LoadBalancer
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

## Step 3: Get the Public IP

```bash
# Wait for LoadBalancer to get an IP (may take 1-2 minutes)
kubectl wait --namespace ingress-nginx \
  --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' \
  service/ingress-nginx-controller \
  --timeout=300s

# Get the public IP
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Public IP: $INGRESS_IP"
echo "Point your DNS to: $INGRESS_IP"
```

## Step 4: Verify Public Access

```bash
# Test with Host header (before DNS is configured)
curl -H "Host: mikegaohahahahagogogogo.site" http://$INGRESS_IP

# Or add to /etc/hosts for testing
# echo "$INGRESS_IP mikegaohahahahagogogogo.site" >> /etc/hosts
```

## Step 5: Configure DNS

Point your domain to the ingress controller's public IP:

**DNS Records:**
- **A Record**: `mikegaohahahahagogogogo.site` → `<INGRESS_IP>`
- **A Record**: `app.mikegaohahahahagogogogo.site` → `<INGRESS_IP>`

## Architecture

```
Internet
    ↓
DNS (mikegaohahahahagogogogo.site)
    ↓
Ingress Controller Service (LoadBalancer) ← MUST be LoadBalancer!
    ↓
Ingress Controller Pods
    ↓
Ingress Resource (routing rules)
    ↓
Internal Service (ClusterIP)
    ↓
Application Pods
```

## Troubleshooting

### Issue: No External IP

**Check service type:**
```bash
kubectl get service ingress-nginx-controller -n ingress-nginx
```

**If type is ClusterIP, update it:**
```bash
kubectl patch service ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}'
```

### Issue: External IP is Pending

**Wait a few minutes** - Azure LoadBalancer provisioning can take 2-5 minutes.

**Check events:**
```bash
kubectl get events -n ingress-nginx --sort-by='.lastTimestamp'
```

### Issue: Cannot Access from Internet

**Verify:**
1. Service type is LoadBalancer ✅
2. Service has External IP ✅
3. DNS points to the External IP ✅
4. Ingress resource is deployed ✅
5. Backend service exists ✅
6. Pods are running ✅

**Test locally first:**
```bash
# Port forward to test
kubectl port-forward service/azure-app-config-internal-service 8080:80

# Test
curl http://localhost:8080
```

## Quick Verification Commands

```bash
# 1. Check ingress controller service
kubectl get service ingress-nginx-controller -n ingress-nginx

# 2. Check ingress resource
kubectl get ingress azure-app-config-ingress

# 3. Check backend service
kubectl get service azure-app-config-internal-service

# 4. Check pods
kubectl get pods -l app=azure-app-config-app

# 5. Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

## Summary

✅ **Ingress Resource** (`ingress.yaml`): No type needed - it's just configuration  
✅ **Ingress Controller Service**: Must be `type: LoadBalancer` for public access  
✅ **Internal Service**: Should be `type: ClusterIP` (internal only)  
✅ **Application**: Accessible via Ingress → Internal Service → Pods

