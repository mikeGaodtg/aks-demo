# Free TLS Certificate Setup with Let's Encrypt

This guide shows you how to set up a free SSL/TLS certificate using Let's Encrypt and cert-manager.

## Prerequisites

1. Domain `app.mikegaohahahahagogogogo.site` pointing to your ingress IP
2. Ingress Controller installed and accessible
3. DNS records configured correctly

## Step 1: Install cert-manager

cert-manager automatically manages certificates from Let's Encrypt.

```bash
# Install cert-manager using kubectl
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready (takes 1-2 minutes)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager \
  --timeout=300s

# Verify installation
kubectl get pods -n cert-manager
```

**Expected output:**
```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-xxx                           1/1     Running   0          2m
cert-manager-cainjector-xxx                1/1     Running   0          2m
cert-manager-webhook-xxx                   1/1     Running   0          2m
```

## Step 2: Update ClusterIssuer with Your Email

Edit `k8s/cert-manager-clusterissuer.yaml` and replace the email:

```yaml
email: your-email@example.com  # Replace with your actual email
```

**Important:** Use a real email address - Let's Encrypt sends expiration notices here.

## Step 3: Deploy ClusterIssuer

```bash
# Apply the ClusterIssuer
kubectl apply -f k8s/cert-manager-clusterissuer.yaml

# Verify ClusterIssuer is ready
kubectl get clusterissuer letsencrypt-prod
```

**Expected output:**
```
NAME               READY   AGE
letsencrypt-prod   True    30s
```

## Step 4: Verify DNS is Configured

**Critical:** Your domain must point to the ingress IP before requesting a certificate!

```bash
# Get ingress IP
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Your domain must point to: $INGRESS_IP"

# Verify DNS
nslookup app.mikegaohahahahagogogogo.site
dig app.mikegaohahahahagogogogo.site
```

**DNS Record:**
- **A Record**: `app.mikegaohahahahagogogogo.site` → `<INGRESS_IP>`

## Step 5: Deploy Updated Ingress

The ingress is already configured with TLS. Just apply it:

```bash
# Apply the ingress (with TLS configuration)
kubectl apply -f k8s/ingress.yaml

# Check ingress status
kubectl get ingress azure-app-config-ingress
```

## Step 6: Monitor Certificate Request

cert-manager will automatically create a Certificate resource and request from Let's Encrypt:

```bash
# Watch certificate creation
kubectl get certificate -w

# Check certificate details
kubectl describe certificate app-mikegaohahahahagogogogo-tls

# Check certificate request
kubectl get certificaterequest
kubectl describe certificaterequest
```

**What happens:**
1. Ingress is created with TLS annotation
2. cert-manager detects the annotation
3. Certificate resource is created automatically
4. CertificateRequest is created
5. Let's Encrypt validates domain ownership (HTTP-01 challenge)
6. Certificate is issued and stored in secret
7. Ingress uses the certificate

## Step 7: Verify Certificate

```bash
# Check certificate status
kubectl get certificate

# Should show:
# NAME                              READY   SECRET                            AGE
# app-mikegaohahahahagogogogo-tls   True    app-mikegaohahahahagogogogo-tls   2m

# Check the secret (certificate is stored here)
kubectl get secret app-mikegaohahahahagogogogo-tls

# View certificate details
kubectl get certificate app-mikegaohahahahagogogogo-tls -o yaml
```

## Step 8: Test HTTPS Access

```bash
# Test HTTPS (should work now!)
curl -I https://app.mikegaohahahahagogogogo.site

# Or open in browser
# https://app.mikegaohahahahagogogogo.site
```

## Troubleshooting

### Issue: Certificate not ready

**Check certificate status:**
```bash
kubectl describe certificate app-mikegaohahahahagogogogo-tls
```

**Common causes:**
1. **DNS not configured** - Domain must point to ingress IP
2. **DNS propagation delay** - Wait 5-10 minutes after DNS change
3. **Rate limiting** - Let's Encrypt has rate limits (50/week per domain)

**Check certificate request:**
```bash
kubectl describe certificaterequest
```

### Issue: Challenge failed

**Check challenge status:**
```bash
kubectl get challenge
kubectl describe challenge
```

**Common issues:**
- DNS not pointing to ingress IP
- Ingress not accessible from internet
- Firewall blocking port 80 (needed for HTTP-01 challenge)

### Issue: Rate limit exceeded

**Solution:** Use staging issuer for testing:

1. Edit `k8s/cert-manager-clusterissuer.yaml`
2. Uncomment the staging ClusterIssuer
3. Update ingress annotation to use `letsencrypt-staging`
4. Apply changes
5. Test with staging
6. Switch back to production when ready

### Issue: Certificate secret not created

**Check cert-manager logs:**
```bash
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager
```

**Verify ClusterIssuer:**
```bash
kubectl get clusterissuer letsencrypt-prod -o yaml
```

## Certificate Renewal

**Automatic:** cert-manager automatically renews certificates before expiration (30 days before expiry).

**Manual renewal:**
```bash
# Delete the certificate to force renewal
kubectl delete certificate app-mikegaohahahahagogogogo-tls

# cert-manager will automatically recreate it
```

## Verification Checklist

- [ ] cert-manager installed and running
- [ ] ClusterIssuer created and ready
- [ ] DNS points to ingress IP
- [ ] Ingress deployed with TLS configuration
- [ ] Certificate resource created
- [ ] Certificate status is "Ready"
- [ ] Secret created with certificate
- [ ] HTTPS access works
- [ ] Browser shows valid certificate

## Testing with Staging (Optional)

For testing without hitting rate limits:

1. Uncomment staging ClusterIssuer in `cert-manager-clusterissuer.yaml`
2. Update ingress annotation: `cert-manager.io/cluster-issuer: "letsencrypt-staging"`
3. Apply and test
4. Switch back to production when ready

**Note:** Staging certificates are not trusted by browsers but useful for testing.

## Additional Domains

To add more domains to the same certificate, update the ingress TLS section:

```yaml
tls:
- hosts:
  - app.mikegaohahahahagogogogo.site
  - www.mikegaohahahahagogogogo.site
  - api.mikegaohahahahagogogogo.site
  secretName: app-mikegaohahahahagogogogo-tls
```

## Summary

✅ **Free Certificate**: Let's Encrypt provides free SSL/TLS certificates  
✅ **Automatic Renewal**: cert-manager handles renewal automatically  
✅ **No Manual Steps**: Once set up, certificates are managed automatically  
✅ **Production Ready**: Let's Encrypt certificates are trusted by all browsers  

## Quick Commands Reference

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Deploy ClusterIssuer
kubectl apply -f k8s/cert-manager-clusterissuer.yaml

# Deploy Ingress with TLS
kubectl apply -f k8s/ingress.yaml

# Check certificate status
kubectl get certificate

# Check certificate details
kubectl describe certificate app-mikegaohahahahagogogogo-tls

# Test HTTPS
curl -I https://app.mikegaohahahahagogogogo.site
```

