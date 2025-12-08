# Docker Hub Private Repository Security Guide

## Overview

This guide explains how to secure your Docker images using private Docker Hub repositories and authentication methods.

## Private Repository Setup

### Creating a Private Repository

1. Log in to [Docker Hub](https://hub.docker.com/)
2. Navigate to **Repositories** → **Create Repository**
3. Fill in:
   - **Name**: `azure-app-config-app` (or your choice)
   - **Visibility**: Select **Private** ⚠️ (This is important!)
4. Click **Create**

## Authentication Methods

### Method 1: Password Authentication (Basic)

**Pros:** Simple to use  
**Cons:** Less secure, can be compromised if password is weak

```bash
docker login
# Enter username and password when prompted
```

### Method 2: Access Token (Recommended) ✅

**Pros:** More secure, can be revoked, scoped permissions  
**Cons:** Requires token management

**Steps:**
1. Go to Docker Hub → **Account Settings** → **Security**
2. Click **New Access Token**
3. Name it (e.g., "production-deploy-token")
4. Set permissions (Read & Write for push/pull)
5. **Copy the token immediately** (you won't see it again!)
6. Use it as password:
   ```bash
   docker login
   # Username: your-username
   # Password: <paste access token>
   ```

**Or use directly:**
```bash
echo "YOUR_ACCESS_TOKEN" | docker login --username your-username --password-stdin
```

### Method 3: Environment Variable (For CI/CD)

```bash
export DOCKER_USERNAME="your-username"
export DOCKER_TOKEN="your-access-token"
echo $DOCKER_TOKEN | docker login --username $DOCKER_USERNAME --password-stdin
```

## IP-Based Access Control

### Docker Hub Limitations

⚠️ **Important:** Docker Hub does **NOT** support IP-based access restrictions natively.

- Private repositories require authentication (username/password or token)
- Anyone with valid credentials can access from any IP
- No built-in IP whitelist/blacklist feature

### Alternatives for IP Restrictions

#### Option 1: Azure Container Registry (ACR)

If you're using Azure, ACR supports IP firewall rules:

```bash
# Create ACR
az acr create --resource-group Mike --name your-acr-name --sku Basic

# Add IP rule (example)
az acr network-rule add --name your-acr-name --ip-address YOUR_IP_ADDRESS
```

#### Option 2: Network-Level Security

- **VPN**: Require VPN connection to access registry
- **Private Network**: Deploy registry in private network
- **Firewall Rules**: Configure firewall at infrastructure level
- **Kubernetes Network Policies**: If using AKS/Kubernetes

#### Option 3: Use Access Tokens with Limited Scope

- Create separate tokens for different environments
- Revoke tokens if compromised
- Monitor access logs in Docker Hub

## Best Practices

### 1. Use Access Tokens Instead of Passwords
- More secure
- Can be revoked without changing password
- Can have limited permissions

### 2. Rotate Tokens Regularly
- Change tokens every 90 days
- Use different tokens for dev/staging/production

### 3. Never Commit Credentials
- Use environment variables
- Use secret management (Azure Key Vault, AWS Secrets Manager)
- Use `.dockerignore` to exclude `.env` files

### 4. Limit Token Permissions
- Use read-only tokens for pull operations
- Use read-write tokens only when needed for push

### 5. Monitor Access
- Check Docker Hub audit logs regularly
- Set up alerts for unusual access patterns

## Example: Secure Deployment Workflow

```bash
# 1. Create access token in Docker Hub (web UI)

# 2. Store token securely (environment variable or secret manager)
export DOCKER_TOKEN="your-token-here"

# 3. Login using token
echo $DOCKER_TOKEN | docker login --username your-username --password-stdin

# 4. Build and push
docker build -t your-username/azure-app-config-app:latest .
docker push your-username/azure-app-config-app:latest

# 5. On deployment server, login and pull
docker login
docker pull your-username/azure-app-config-app:latest
```

## Troubleshooting

### "unauthorized: authentication required"
- Make sure you're logged in: `docker login`
- Verify repository name matches exactly
- Check if repository is private (requires authentication)

### "denied: requested access to the resource is denied"
- Verify you have access to the private repository
- Check if you're using the correct username
- Ensure access token has correct permissions

### "pull access denied"
- Repository might be private - ensure you're authenticated
- Verify repository name and tag are correct
- Check if your account has access to the repository

