#!/bin/bash

# Azure Container Registry (ACR) Setup Script
# This script helps you set up ACR and configure access for AKS

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Azure Container Registry Setup ===${NC}\n"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed.${NC}"
    echo "Install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Azure. Logging in...${NC}"
    az login
fi

# Get user input
read -p "Enter Resource Group name (default: Mike): " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-Mike}

read -p "Enter ACR name (must be globally unique, lowercase, alphanumeric only): " ACR_NAME
if [ -z "$ACR_NAME" ]; then
    echo -e "${RED}Error: ACR name is required${NC}"
    exit 1
fi

read -p "Enter Azure region (default: eastus): " LOCATION
LOCATION=${LOCATION:-eastus}

read -p "Enter ACR SKU [Basic/Standard/Premium] (default: Basic): " SKU
SKU=${SKU:-Basic}

echo -e "\n${GREEN}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  ACR Name: $ACR_NAME"
echo "  Location: $LOCATION"
echo "  SKU: $SKU"
echo ""

read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Step 1: Create ACR
echo -e "\n${GREEN}[1/5] Creating Azure Container Registry...${NC}"
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku "$SKU" \
  --location "$LOCATION" \
  --output none

echo -e "${GREEN}✓ ACR created successfully${NC}"

# Step 2: Login to ACR
echo -e "\n${GREEN}[2/5] Logging in to ACR...${NC}"
az acr login --name "$ACR_NAME"
echo -e "${GREEN}✓ Logged in to ACR${NC}"

# Step 3: Build and push image
echo -e "\n${GREEN}[3/5] Building Docker image...${NC}"
docker build -t "$ACR_NAME.azurecr.io/azure-app-config-app:latest" .

echo -e "\n${GREEN}[4/5] Pushing image to ACR...${NC}"
docker push "$ACR_NAME.azurecr.io/azure-app-config-app:latest"
echo -e "${GREEN}✓ Image pushed successfully${NC}"

# Step 4: Configure AKS access
echo -e "\n${GREEN}[5/5] Configuring AKS access...${NC}"
read -p "Do you have an existing AKS cluster? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter AKS cluster name: " AKS_CLUSTER_NAME
    if [ -n "$AKS_CLUSTER_NAME" ]; then
        echo -e "${YELLOW}Attaching ACR to AKS cluster...${NC}"
        az aks update \
          --name "$AKS_CLUSTER_NAME" \
          --resource-group "$RESOURCE_GROUP" \
          --attach-acr "$ACR_NAME" \
          --output none
        echo -e "${GREEN}✓ ACR attached to AKS cluster${NC}"
        echo -e "${GREEN}✓ AKS can now pull images from ACR without additional secrets${NC}"
    fi
else
    echo -e "${YELLOW}Skipping AKS configuration. You can attach ACR later with:${NC}"
    echo "  az aks update --name <cluster-name> --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME"
fi

# Summary
echo -e "\n${GREEN}=== Setup Complete ===${NC}\n"
echo "ACR Details:"
echo "  Name: $ACR_NAME"
echo "  Login Server: $ACR_NAME.azurecr.io"
echo "  Image: $ACR_NAME.azurecr.io/azure-app-config-app:latest"
echo ""
echo "Next steps:"
echo "  1. Update k8s/deployment.yaml:"
echo "     Replace <YOUR_ACR_NAME> with: $ACR_NAME"
echo ""
echo "  2. If AKS is attached, remove imagePullSecrets from deployment.yaml"
echo ""
echo "  3. Deploy to AKS:"
echo "     kubectl apply -f k8s/deployment.yaml"
echo "     kubectl apply -f k8s/service.yaml"
echo ""
echo "  4. Verify image in ACR:"
echo "     az acr repository show-tags --name $ACR_NAME --repository azure-app-config-app --output table"
echo ""

