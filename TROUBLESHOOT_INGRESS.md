# Troubleshooting Ingress 404 Errors

## Common Issues and Solutions

### Issue: 404 when accessing via domain or IP

**Symptoms**: 
- Service works directly: `curl 10.10.10.69` ✅
- Ingress returns 404: `curl app.mikegaohahahahagogogogo.site` ❌
- Direct IP returns 404: `curl http://4.254.127.223/` ❌

## Diagnostic Commands

### 1. Check Ingress Status

```bash
# Check if ingress exists and is configured
kubectl get ingress azure-app-config-app-ingress

# Describe ingress for details
kubectl describe ingress azure-app-config-app-ingress

# Check ingress in YAML format
kubectl get ingress azure-app-config-app-ingress -o yaml
```

**Expected**: Should show ADDRESS with the Ingress Controller IP.

### 2. Check Service and Endpoints

```bash
# Check service exists
kubectl get service azure-app-config-app-service

# Check service endpoints (pods must be running)
kubectl get endpoints azure-app-config-app-service

# Describe service
kubectl describe service azure-app-config-app-service
```

**Expected**: Endpoints should show pod IPs. If empty, pods aren't running or labels don't match.

### 3. Check Pods

```bash
# Check if pods are running
kubectl get pods -l app=azure-app-config-app

# Check pod labels match service selector
kubectl get pods --show-labels -l app=azure-app-config-app

# Check service selector
kubectl get service azure-app-config-app-service -o jsonpath='{.spec.selector}'
```

**Expected**: Pods should be Running and labels must match service selector.

### 4. Check Ingress Controller Logs

```bash
# View ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# Follow logs in real-time
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f
```

**Look for**: Errors, routing issues, or backend connection failures.

### 5. Test Service Directly

```bash
# Get service ClusterIP
SERVICE_IP=$(kubectl get service azure-app-config-app-service -o jsonpath='{.spec.clusterIP}')
echo "Service IP: $SERVICE_IP"

# Test from within cluster (if you have a test pod)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://$SERVICE_IP
```

## Common Fixes

### Fix 1: Update Ingress Class Annotation

**Problem**: Using deprecated `kubernetes.io/ingress.class` annotation.

**Solution**: Use `ingressClassName` in spec instead:

```yaml
spec:
  ingressClassName: nginx  # Add this
  # Remove: kubernetes.io/ingress.class: nginx from annotations
```

### Fix 2: Add Default Backend for IP Access

**Problem**: Accessing via IP (no Host header) doesn't match any rule.

**Solution**: Add a default rule without host:

```yaml
rules:
  - host: mikegaohahahahagogogogo.site
    # ... paths
  - http:  # Default rule (no host)
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: azure-app-config-app-service
            port:
              number: 80
```

### Fix 3: Fix SSL Redirect Without TLS

**Problem**: SSL redirect enabled but no TLS configured.

**Solution**: Remove or disable SSL redirect:

```yaml
annotations:
  # Remove or set to false
  # nginx.ingress.kubernetes.io/ssl-redirect: "false"
```

### Fix 4: Verify Service Selector Matches Pod Labels

**Problem**: Service can't find pods because labels don't match.

**Check**:
```bash
# Service selector
kubectl get service azure-app-config-app-service -o jsonpath='{.spec.selector}'

# Pod labels
kubectl get pods -l app=azure-app-config-app --show-labels
```

**Fix**: Ensure both have matching labels (e.g., `app: azure-app-config-app`).

### Fix 5: Check Ingress Controller Class

**Problem**: Ingress controller not recognizing ingress class.

**Check**:
```bash
# List ingress classes
kubectl get ingressclass

# Check ingress controller
kubectl get ingressclass nginx -o yaml
```

**Fix**: Ensure ingress class `nginx` exists. If using Helm, it should be created automatically.

### Fix 6: Verify DNS Configuration

**Problem**: DNS not pointing to Ingress Controller IP.

**Check**:
```bash
# Get Ingress Controller IP
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ingress IP: $INGRESS_IP"

# Check DNS
nslookup mikegaohahahahagogogogo.site
nslookup app.mikegaohahahahagogogogo.site
```

**Expected**: DNS should resolve to the Ingress Controller IP.

## Step-by-Step Troubleshooting

### Step 1: Verify Basic Setup

```bash
# 1. Check ingress exists
kubectl get ingress

# 2. Check service exists
kubectl get service azure-app-config-app-service

# 3. Check pods are running
kubectl get pods -l app=azure-app-config-app

# 4. Check endpoints
kubectl get endpoints azure-app-config-app-service
```

### Step 2: Test Service Directly

```bash
# Port forward to test service
kubectl port-forward service/azure-app-config-app-service 8080:80

# In another terminal
curl http://localhost:8080
```

If this works, the service is fine. The issue is with Ingress.

### Step 3: Check Ingress Controller

```bash
# Check ingress controller is running
kubectl get pods -n ingress-nginx

# Check ingress controller service
kubectl get service ingress-nginx-controller -n ingress-nginx

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100
```

### Step 4: Reapply Ingress

```bash
# Delete and recreate ingress
kubectl delete ingress azure-app-config-app-ingress
kubectl apply -f k8s/ingress.yaml

# Wait a few seconds for ingress controller to pick up changes
kubectl get ingress azure-app-config-app-ingress
```

### Step 5: Test with Host Header

```bash
# Test with correct host header
curl -H "Host: mikegaohahahahagogogogo.site" http://4.254.127.223/

# Test with app subdomain
curl -H "Host: app.mikegaohahahahagogogogo.site" http://4.254.127.223/
```

If this works, DNS is the issue. If not, Ingress configuration is wrong.

## Quick Fix Script

```bash
#!/bin/bash

# Quick diagnostic
echo "=== Checking Ingress ==="
kubectl get ingress azure-app-config-app-ingress

echo -e "\n=== Checking Service ==="
kubectl get service azure-app-config-app-service

echo -e "\n=== Checking Endpoints ==="
kubectl get endpoints azure-app-config-app-service

echo -e "\n=== Checking Pods ==="
kubectl get pods -l app=azure-app-config-app

echo -e "\n=== Checking Ingress Controller ==="
kubectl get service ingress-nginx-controller -n ingress-nginx

echo -e "\n=== Ingress Controller Logs (last 20 lines) ==="
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=20
```

## Expected Working Configuration

### Ingress YAML
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: azure-app-config-app-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: mikegaohahahahagogogogo.site
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: azure-app-config-app-service
            port:
              number: 80
  - host: app.mikegaohahahahagogogogo.site
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: azure-app-config-app-service
            port:
              number: 80
  - http:  # Default for IP access
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: azure-app-config-app-service
            port:
              number: 80
```

### Service YAML
```yaml
apiVersion: v1
kind: Service
metadata:
  name: azure-app-config-app-service
spec:
  type: ClusterIP
  selector:
    app: azure-app-config-app
  ports:
  - port: 80
    targetPort: 3000
```

## Still Not Working?

1. **Check ingress controller version compatibility**
2. **Verify namespace matches** (default vs ingress-nginx)
3. **Check for conflicting ingresses**
4. **Review ingress controller configuration**
5. **Check firewall/network policies**

For more help, check the ingress controller logs and describe output.

