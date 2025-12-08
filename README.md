# Azure App Configuration Website

A Node.js web server that fetches and displays configuration values from Azure App Configuration.

## Setup

1. Install dependencies:
   ```
   npm install
   ```

2. **Authentication Options:**

   **Option A: Connection String (Local Development)**
   
   Create a `.env` file in the root directory with your Azure App Configuration connection string:
   ```
   AZURE_APP_CONFIG_CONNECTION_STRING=Endpoint=https://aks-appconfig-12.azconfig.io;Id=...;Secret=...
   ```
   
   **To get your connection string:**
   - Go to Azure Portal
   - Navigate to your App Configuration resource: `aks-appconfig-12` (Resource Group: `Mike`)
   - Go to "Access keys" or "Configuration Explorer"
   - Copy the connection string

   **Option B: Managed Identity (Recommended for AKS)**
   
   For AKS deployments, use managed identity instead of connection strings. See `MANAGED_IDENTITY_SETUP.md` for setup instructions.
   
   The code automatically uses `DefaultAzureCredential` which supports:
   - Managed Identity (when running in Azure)
   - Environment variables (for local development)
   - Azure CLI (for local development)

3. Make sure you have a configuration key `App:Message` set in your Azure App Configuration.

4. Start the server:
   ```
   npm start
   ```

5. Open your browser and navigate to:
   ```
   http://localhost:3000
   ```

You should see the value from Azure App Configuration displayed on the page!

## Configuration

- **Key**: `App:Message`
- **Config App**: `aks-appconfig-12`
- **Resource Group**: `Mike`

The configuration value is cached and refreshed every 30 seconds automatically.

## Docker

### Create a Private Repository on Docker Hub

1. Go to [Docker Hub](https://hub.docker.com/)
2. Click "Repositories" → "Create Repository"
3. Enter repository name: `azure-app-config-app` (or your preferred name)
4. **Select "Private"** (important for security)
5. Click "Create"

### Build the Docker Image

```bash
docker build -t your-dockerhub-username/azure-app-config-app:latest .
```

Replace `your-dockerhub-username` with your Docker Hub username.

### Authentication Options

#### Option 1: Using Password (Simple but less secure)
```bash
docker login
# Enter your Docker Hub username and password when prompted
```

#### Option 2: Using Access Token (Recommended - More Secure)
1. Go to Docker Hub → Account Settings → Security
2. Click "New Access Token"
3. Give it a name (e.g., "azure-app-config-token")
4. Copy the token (you'll only see it once!)
5. Use the token as password when logging in:
   ```bash
   docker login
   # Username: your-dockerhub-username
   # Password: <paste your access token>
   ```

#### Option 3: Login with Token Directly
```bash
echo "YOUR_ACCESS_TOKEN" | docker login --username your-dockerhub-username --password-stdin
```

### Push to Private Docker Hub Repository

1. Login to Docker Hub (using one of the methods above)

2. Push the image:
   ```bash
   docker push your-dockerhub-username/azure-app-config-app:latest
   ```

### Pull and Run from Private Docker Hub Repository

**Important:** You must be logged in to pull from a private repository and pass the connection string at runtime:

```bash
# Login first
docker login

# Pull the image
docker pull your-dockerhub-username/azure-app-config-app:latest

# Run the container with environment variable
docker run -d -p 3000:3000 -e AZURE_APP_CONFIG_CONNECTION_STRING="your_connection_string" --name my-test-container your-dockerhub-username/azure-app-config-app:latest
```

**Note:** 
- Replace `your_connection_string` with your actual Azure App Configuration connection string
- The app runs on port 3000 inside the container
- Use `-p 8080:3000` if you want to access it on port 8080 on your host machine
- Use `-d` for detached mode (runs in background) or `-it` for interactive mode

### Run the Docker Container

```bash
docker run -d -p 3000:3000 -e AZURE_APP_CONFIG_CONNECTION_STRING="your_connection_string" your-dockerhub-username/azure-app-config-app:latest
```

## Security Notes

### IP-Based Access Control

**Docker Hub Limitations:**
- Docker Hub does **NOT** support IP-based access restrictions natively
- Private repositories require authentication (username/password or access token)
- Only authenticated users with access can pull private images

### Alternative Solutions for IP Restrictions

If you need IP-based access control, consider:

1. **Private Container Registry with IP Restrictions:**
   - Azure Container Registry (ACR) - supports IP firewall rules
   - AWS ECR - supports VPC endpoints
   - Google Container Registry - supports IAM and network policies

2. **Network-Level Security:**
   - Use VPN or private networks
   - Deploy behind a firewall
   - Use Kubernetes Network Policies (if deploying to AKS/Kubernetes)

3. **Access Token Best Practices:**
   - Use access tokens instead of passwords (more secure)
   - Rotate tokens regularly
   - Use different tokens for different environments
   - Never commit tokens to version control

