# Azure Container Registry (ACR) Setup Script for PowerShell
# This script helps you set up ACR and configure access for AKS

# Colors for output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Error { Write-Host $args -ForegroundColor Red }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }

Write-Success "=== Azure Container Registry Setup ==="
Write-Host ""

# Check if Azure CLI is installed
try {
    $null = az --version 2>&1
} catch {
    Write-Error "Error: Azure CLI is not installed."
    Write-Host "Install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

# Check if logged in
try {
    $null = az account show 2>&1
} catch {
    Write-Warning "Not logged in to Azure. Logging in..."
    az login
}

# Get user input
$RESOURCE_GROUP = Read-Host "Enter Resource Group name (default: Mike)"
if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    $RESOURCE_GROUP = "Mike"
}

$ACR_NAME = Read-Host "Enter ACR name (must be globally unique, lowercase, alphanumeric only)"
if ([string]::IsNullOrWhiteSpace($ACR_NAME)) {
    Write-Error "Error: ACR name is required"
    exit 1
}

$LOCATION = Read-Host "Enter Azure region (default: eastus)"
if ([string]::IsNullOrWhiteSpace($LOCATION)) {
    $LOCATION = "eastus"
}

$SKU = Read-Host "Enter ACR SKU [Basic/Standard/Premium] (default: Basic)"
if ([string]::IsNullOrWhiteSpace($SKU)) {
    $SKU = "Basic"
}

Write-Host ""
Write-Success "Configuration:"
Write-Host "  Resource Group: $RESOURCE_GROUP"
Write-Host "  ACR Name: $ACR_NAME"
Write-Host "  Location: $LOCATION"
Write-Host "  SKU: $SKU"
Write-Host ""

$confirm = Read-Host "Continue? (y/n)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    exit 1
}

# Step 1: Create ACR
Write-Host ""
Write-Success "[1/5] Creating Azure Container Registry..."
az acr create `
  --resource-group $RESOURCE_GROUP `
  --name $ACR_NAME `
  --sku $SKU `
  --location $LOCATION `
  --output none

Write-Success "✓ ACR created successfully"

# Step 2: Login to ACR
Write-Host ""
Write-Success "[2/5] Logging in to ACR..."
az acr login --name $ACR_NAME
Write-Success "✓ Logged in to ACR"

# Step 3: Build and push image
Write-Host ""
Write-Success "[3/5] Building Docker image..."
docker build -t "${ACR_NAME}.azurecr.io/azure-app-config-app:latest" .

Write-Host ""
Write-Success "[4/5] Pushing image to ACR..."
docker push "${ACR_NAME}.azurecr.io/azure-app-config-app:latest"
Write-Success "✓ Image pushed successfully"

# Step 4: Configure AKS access
Write-Host ""
Write-Success "[5/5] Configuring AKS access..."
$hasAks = Read-Host "Do you have an existing AKS cluster? (y/n)"
if ($hasAks -eq "y" -or $hasAks -eq "Y") {
    $AKS_CLUSTER_NAME = Read-Host "Enter AKS cluster name"
    if (-not [string]::IsNullOrWhiteSpace($AKS_CLUSTER_NAME)) {
        Write-Warning "Attaching ACR to AKS cluster..."
        az aks update `
          --name $AKS_CLUSTER_NAME `
          --resource-group $RESOURCE_GROUP `
          --attach-acr $ACR_NAME `
          --output none
        Write-Success "✓ ACR attached to AKS cluster"
        Write-Success "✓ AKS can now pull images from ACR without additional secrets"
    }
} else {
    Write-Warning "Skipping AKS configuration. You can attach ACR later with:"
    Write-Host "  az aks update --name <cluster-name> --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME"
}

# Summary
Write-Host ""
Write-Success "=== Setup Complete ==="
Write-Host ""
Write-Host "ACR Details:"
Write-Host "  Name: $ACR_NAME"
Write-Host "  Login Server: $ACR_NAME.azurecr.io"
Write-Host "  Image: $ACR_NAME.azurecr.io/azure-app-config-app:latest"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Update k8s/deployment.yaml:"
Write-Host "     Replace <YOUR_ACR_NAME> with: $ACR_NAME"
Write-Host ""
Write-Host "  2. If AKS is attached, remove imagePullSecrets from deployment.yaml"
Write-Host ""
Write-Host "  3. Deploy to AKS:"
Write-Host "     kubectl apply -f k8s/deployment.yaml"
Write-Host "     kubectl apply -f k8s/service.yaml"
Write-Host ""
Write-Host "  4. Verify image in ACR:"
Write-Host "     az acr repository show-tags --name $ACR_NAME --repository azure-app-config-app --output table"
Write-Host ""

