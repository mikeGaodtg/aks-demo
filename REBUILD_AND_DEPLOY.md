# Rebuild and Deploy with Managed Identity

Your code is updated to use managed identity, but the Docker image needs to be rebuilt.

## Quick Steps

### 1. Rebuild Docker Image

```bash
# Navigate to project directory
cd "c:\Users\gaom\Documents\code sample\fetch from config app"

# Rebuild the image with updated code
docker build -t wsztg008/app-config:latest .

# Verify the build succeeded
docker images | grep app-config
```

### 2. Push to Docker Hub

```bash
# Login to Docker Hub (if not already logged in)
docker login

# Push the updated image
docker push wsztg008/app-config:latest
```

### 3. Restart Deployment

```bash
# Option 1: Restart the deployment (will pull new image)
kubectl rollout restart deployment azure-app-config-app

# Option 2: Force pull new image
kubectl set image deployment/azure-app-config-app \
  azure-app-config-app=wsztg008/app-config:latest

# Wait for rollout to complete
kubectl rollout status deployment azure-app-config-app

# Check new pods
kubectl get pods -l app=azure-app-config-app
```

### 4. Verify

```bash
# Check logs (should see "Using managed identity for authentication")
kubectl logs -l app=azure-app-config-app --tail=50

# Should NOT see connection string errors anymore
```

## What Changed

- ✅ Code updated to use `AZURE_APP_CONFIG_ENDPOINT` instead of connection string
- ✅ Uses `DefaultAzureCredential` for managed identity
- ✅ Deployment.yaml already configured with endpoint and client ID
- ⚠️ **Docker image needs to be rebuilt** with the new code

## Expected Log Output

After rebuilding and deploying, you should see:

```
⚠️  WARNING: SSL certificate verification is DISABLED (testing only!)
Using managed identity for authentication
Managed Identity Client ID: ebf4922a-8d3d-4731-8bb9-baa56d432cdb
✅ Configured Node.js default HTTPS agent with CA certificates...
Created Azure App Configuration client using managed identity
App Configuration Endpoint: https://aks-appconfig-12.azconfig.io
Successfully fetched configuration: App:Message = Hello from Azure App Config!
Server is running at http://localhost:3000
```

**NOT** the old error about connection string!

