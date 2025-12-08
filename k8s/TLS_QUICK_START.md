# Quick TLS Setup Guide

Your ingress is now configured for TLS! Follow these steps to enable HTTPS.

## Step 1: Verify cert-manager is Installed

```powershell
# Check if cert-manager is installed
kubectl get pods -n cert-manager

# If not installed, install it:
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready (1-2 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

## Step 2: Deploy ClusterIssuer (if not already deployed)

```powershell
# Apply the ClusterIssuer
kubectl apply -f k8s/cert-manager-clusterissuer.yaml

# Verify it's ready
kubectl get clusterissuer letsencrypt-prod
```

## Step 3: Apply the Updated Ingress

```powershell
# Apply the ingress with TLS configuration
kubectl apply -f k8s/ingress.yaml

# Check ingress status
kubectl get ingress azure-app-config-ingress
```

## Step 4: Monitor Certificate Creation

cert-manager will automatically create a certificate. Watch the progress:

```powershell
# Watch certificate creation (press Ctrl+C to stop)
kubectl get certificate -w

# Check certificate status
kubectl get certificate

# Check certificate details
kubectl describe certificate azure-app-config-tls
```

**What to expect:**
- Certificate will be created automatically
- Status will show "Ready" after 1-2 minutes
- Let's Encrypt will validate your domain ownership via HTTP-01 challenge

## Step 5: Verify TLS is Working

```powershell
# Test HTTPS
curl -I https://app.mikegaohahahahagogogogo.site

# Or test the main domain
curl -I https://mikegaohahahahagogogogo.site
```

## Troubleshooting

### Certificate not ready?

```powershell
# Check certificate status
kubectl describe certificate azure-app-config-tls

# Check certificate requests
kubectl get certificaterequest
kubectl describe certificaterequest

# Check challenges (Let's Encrypt validation)
kubectl get challenge
kubectl describe challenge
```

**Common issues:**
1. **DNS not configured** - Both domains must point to your ingress IP
2. **DNS propagation delay** - Wait 5-10 minutes after DNS changes
3. **Rate limiting** - Let's Encrypt has rate limits (50 certs/week per domain)

### Check cert-manager logs

```powershell
# View cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager --tail=50
```

## What Changed

✅ **TLS Configuration Added:**
- Both domains (`mikegaohahahahagogogogo.site` and `app.mikegaohahahahagogogogo.site`) are included in the certificate
- Automatic certificate management via cert-manager
- HTTP to HTTPS redirect enabled

✅ **Automatic Certificate Management:**
- cert-manager will automatically request certificates from Let's Encrypt
- Certificates will auto-renew 30 days before expiration
- No manual intervention needed

## Verification Checklist

- [ ] cert-manager is installed and running
- [ ] ClusterIssuer is deployed and ready
- [ ] Ingress is applied with TLS configuration
- [ ] Certificate resource is created automatically
- [ ] Certificate status shows "Ready"
- [ ] HTTPS works for both domains
- [ ] HTTP redirects to HTTPS

## Quick Status Check

```powershell
# One-liner to check everything
kubectl get clusterissuer,ingress,certificate,secret -n default
```

