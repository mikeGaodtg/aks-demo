# Private Link Service Setup for Azure Front Door

This guide explains how to set up a Private Link Service (PLS) to connect your AKS application to Azure Front Door.

## Architecture Overview

```
Azure Front Door
    ↓ (Private Endpoint)
Private Link Service (PLS)
    ↓ (Internal Load Balancer)
Kubernetes Service (LoadBalancer type)
    ↓ (Direct pod selection)
Application Pods
```

**Important**: The PLS service connects **directly to pods**, not through the ClusterIP service. Both services can coexist:
- **ClusterIP service** (`azure-app-config-app-service`): For internal cluster access
- **PLS service** (`azure-app-config-pls-service`): For Front Door access via Private Link

## Prerequisites

1. AKS cluster with Azure Load Balancer Controller installed
2. A dedicated subnet for Private Link Service (PLS subnet)
3. Azure Front Door Premium (required for Private Link support)

## Step 1: Prepare the PLS Subnet

You need a dedicated subnet in your AKS VNet for the Private Link Service:

```bash
# Get your AKS VNet information
RESOURCE_GROUP="Mike"
AKS_CLUSTER_NAME="AKS-Mike1"

# Get the VNet name
VNET_NAME=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --query "networkProfile.vnetSubnetId" -o tsv | cut -d'/' -f9)

# Create a subnet for PLS (if it doesn't exist)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name pls-subnet \
  --address-prefix 10.0.3.0/24 \
  --disable-private-endpoint-network-policies false
```

**Note**: Update the subnet name and IP address in `k8s/service-pls.yaml`:
- `service.beta.kubernetes.io/azure-pls-ip-configuration-subnet`: Your subnet name
- `service.beta.kubernetes.io/azure-load-balancer-internal-ipv4`: An available IP from the subnet

## Step 2: Deploy the Private Link Service

```bash
# Apply the PLS service
kubectl apply -f k8s/service-pls.yaml

# Check the service status
kubectl get service azure-app-config-pls-service

# Wait for the LoadBalancer to get an IP
kubectl wait --for=condition=Ready service/azure-app-config-pls-service --timeout=300s
```

## Step 3: Get Private Link Service Details

After deployment, get the Private Link Service resource ID:

```bash
# Get the Private Link Service resource ID
az network private-link-service list \
  --resource-group $RESOURCE_GROUP \
  --query "[?name=='app-config-pls'].id" -o tsv
```

## Step 4: Configure Azure Front Door

1. **Create a Private Endpoint** in your Front Door Premium:
   - Go to Azure Portal → Your Front Door → Private Link
   - Create a new Private Endpoint
   - Use the Private Link Service resource ID from Step 3
   - Select the appropriate subnet in your Front Door VNet

2. **Approve the Connection**:
   - Go to Azure Portal → Your Private Link Service → Private endpoint connections
   - Approve the connection from Front Door

   OR use auto-approval by adding this annotation to the service:
   ```yaml
   service.beta.kubernetes.io/azure-pls-auto-approval: "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/privateEndpoints/..."
   ```

3. **Configure Front Door Backend**:
   - Add your Private Endpoint as a backend
   - Configure health probes and routing rules

## Step 5: Verify the Setup

```bash
# Check service status
kubectl get service azure-app-config-pls-service -o wide

# Check Private Link Service in Azure
az network private-link-service show \
  --resource-group $RESOURCE_GROUP \
  --name app-config-pls \
  --query "{Name:name, ProvisioningState:provisioningState, Alias:alias}" -o table

# Check Private Endpoint connections
az network private-link-service show \
  --resource-group $RESOURCE_GROUP \
  --name app-config-pls \
  --query "privateEndpointConnections" -o table
```

## Troubleshooting

### Issue: Service stuck in Pending

**Cause**: Subnet name or IP address might be incorrect.

**Solution**:
```bash
# Verify subnet exists
az network vnet subnet list \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --query "[].name" -o table

# Check service events
kubectl describe service azure-app-config-pls-service
```

### Issue: Private Endpoint connection not approved

**Solution**: 
- Manually approve in Azure Portal, OR
- Add auto-approval annotation with the Private Endpoint resource ID

### Issue: Cannot connect from Front Door

**Check**:
1. Private Endpoint is approved
2. Front Door backend is configured correctly
3. Health probes are working
4. Network security groups allow traffic

## Differences from Ingress

| Feature | Ingress | Private Link Service |
|---------|---------|---------------------|
| **Type** | ClusterIP + Ingress Controller | LoadBalancer (Internal) |
| **Access** | Public/Private via Ingress | Private via Private Link |
| **Connection** | Through Ingress Controller | Direct to pods |
| **Use Case** | Public web access | Private Front Door access |
| **Cost** | Lower | Higher (Front Door Premium required) |

## Notes

- The PLS service and ClusterIP service can coexist
- Both services select the same pods using the same selector
- The PLS service provides private connectivity for Front Door
- The ClusterIP service can still be used for internal cluster access

## Next Steps

1. Update subnet name and IP in `k8s/service-pls.yaml`
2. Deploy the PLS service
3. Configure Front Door Private Endpoint
4. Test connectivity from Front Door

