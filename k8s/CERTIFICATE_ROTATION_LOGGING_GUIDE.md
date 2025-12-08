# Certificate Rotation Event Logging Guide

This guide explains how to set up a sidecar container to monitor certificate rotation events and send JSON logs to Azure Storage Account.

## Architecture Overview

```
┌─────────────────────────────────────────┐
│  Pod with Sidecar Container             │
│  ┌─────────────────┐  ┌──────────────┐  │
│  │  Main App       │  │  Logging     │  │
│  │  Container      │  │  Sidecar     │  │
│  └─────────────────┘  └──────────────┘  │
│                                          │
│  Sidecar monitors:                      │
│  - Kubernetes API (Certificate events)  │
│  - Secret changes (TLS secret updates)   │
│  - cert-manager events                   │
└─────────────────────────────────────────┘
                    │
                    │ JSON Logs
                    ▼
         ┌──────────────────────┐
         │  Azure Storage       │
         │  Account (Blob)      │
         └──────────────────────┘
```

## Step-by-Step Implementation

### Step 1: Understand What to Monitor

**Certificate rotation events can be detected by monitoring:**

1. **Kubernetes Certificate Resource Changes**
   - Watch for `Certificate` resource status changes
   - Status changes from `Ready=False` to `Ready=True` indicates renewal
   - Check `status.renewalTime` field

2. **TLS Secret Updates**
   - Monitor the secret referenced in ingress (e.g., `azure-app-config-tls`)
   - Secret metadata `resourceVersion` changes indicate updates
   - Secret `data.tls.crt` and `data.tls.key` change when rotated

3. **cert-manager Events**
   - Kubernetes events related to certificates
   - Look for events like "CertificateRequestSucceeded", "CertificateIssued"

**Key Information to Log:**
- Timestamp of rotation
- Certificate name and namespace
- Old certificate expiration date
- New certificate expiration date
- Certificate domains (SANs)
- Rotation reason (scheduled renewal, manual, etc.)
- Success/failure status

---

### Step 2: Choose Your Monitoring Approach

**Option A: Watch Kubernetes API (Recommended)**
- Use Kubernetes client library (Python, Go, Node.js)
- Watch Certificate resources and Secrets
- Real-time event detection

**Option B: Poll Kubernetes API**
- Periodically check Certificate and Secret resources
- Simpler but less real-time
- Higher API load

**Option C: Use Kubernetes Events**
- Watch events in the namespace
- Filter for cert-manager related events
- Less detailed but easier to implement

---

### Step 3: Design the Sidecar Container

**Sidecar Container Requirements:**

1. **Kubernetes API Access**
   - Service account with RBAC permissions
   - Permissions needed:
     - `get`, `list`, `watch` on `certificates` resource
     - `get`, `list`, `watch` on `secrets` resource
     - `get`, `list`, `watch` on `events` resource

2. **Azure Storage Access**
   - Managed Identity or Storage Account Key
   - Azure Blob Storage SDK
   - Write permissions to storage container

3. **Monitoring Logic**
   - Watch loop for Certificate/Secret changes
   - Event detection and filtering
   - JSON log generation
   - Upload to Azure Storage

---

### Step 4: Create Service Account and RBAC

**Service Account:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cert-monitor-sa
  namespace: default
```

**ClusterRole (if monitoring across namespaces):**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cert-monitor-role
rules:
- apiGroups: ["cert-manager.io"]
  resources: ["certificates"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
```

**RoleBinding:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cert-monitor-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cert-monitor-role
subjects:
- kind: ServiceAccount
  name: cert-monitor-sa
  namespace: default
```

---

### Step 5: Design JSON Log Format

**Example JSON Log Structure:**

```json
{
  "eventType": "certificate_rotation",
  "timestamp": "2024-01-15T10:30:45Z",
  "certificate": {
    "name": "azure-app-config-tls",
    "namespace": "default",
    "domains": ["app.mikegaohahahahagogogogo.site"],
    "issuer": "letsencrypt-prod"
  },
  "rotation": {
    "reason": "scheduled_renewal",
    "oldExpiration": "2024-04-15T10:00:00Z",
    "newExpiration": "2024-07-15T10:00:00Z",
    "renewalTime": "2024-03-15T10:00:00Z"
  },
  "status": {
    "success": true,
    "message": "Certificate renewed successfully"
  },
  "metadata": {
    "podName": "app-config-deployment-xxx",
    "nodeName": "aks-nodepool-xxx",
    "clusterName": "your-aks-cluster"
  }
}
```

**Alternative: Certificate Update Event (when secret changes):**

```json
{
  "eventType": "certificate_secret_updated",
  "timestamp": "2024-01-15T10:30:45Z",
  "secret": {
    "name": "azure-app-config-tls",
    "namespace": "default",
    "resourceVersion": "12345"
  },
  "certificate": {
    "name": "azure-app-config-tls",
    "namespace": "default"
  },
  "change": {
    "type": "rotation",
    "detectedAt": "2024-01-15T10:30:45Z"
  }
}
```

---

### Step 6: Implement the Sidecar Container

**High-Level Implementation Steps:**

1. **Choose a Language/Framework:**
   - Python: `kubernetes` library, `azure-storage-blob`
   - Go: `client-go`, `azure-sdk-for-go`
   - Node.js: `@kubernetes/client-node`, `@azure/storage-blob`

2. **Main Loop Structure:**
   ```
   - Initialize Kubernetes client
   - Initialize Azure Storage client
   - Watch Certificate resources
   - Watch Secret resources (TLS secret)
   - On change detected:
     - Extract certificate information
     - Generate JSON log
     - Upload to Azure Storage
   ```

3. **Key Functions Needed:**
   - `watchCertificates()` - Watch Certificate resource
   - `watchSecret()` - Watch TLS secret
   - `detectRotation()` - Compare old vs new certificate
   - `generateLog()` - Create JSON log object
   - `uploadToStorage()` - Send to Azure Blob Storage

---

### Step 7: Set Up Azure Storage Account

**Storage Account Setup:**

1. **Create Storage Account** (if not exists):
   ```bash
   az storage account create \
     --name <storage-account-name> \
     --resource-group <resource-group> \
     --location <location> \
     --sku Standard_LRS
   ```

2. **Create Container for Logs:**
   ```bash
   az storage container create \
     --name certificate-logs \
     --account-name <storage-account-name> \
     --auth-mode login
   ```

3. **Set Up Access:**
   - **Option A: Managed Identity** (Recommended)
     - Assign "Storage Blob Data Contributor" role to managed identity
   - **Option B: Storage Account Key**
     - Store key in Kubernetes Secret
     - Mount as environment variable or file

---

### Step 8: Configure Managed Identity (Recommended)

**If using Managed Identity:**

1. **Create User-Assigned Managed Identity:**
   ```bash
   az identity create \
     --name cert-monitor-identity \
     --resource-group <resource-group>
   ```

2. **Assign Storage Role:**
   ```bash
   STORAGE_ACCOUNT_ID=$(az storage account show \
     --name <storage-account-name> \
     --resource-group <resource-group> \
     --query id -o tsv)
   
   IDENTITY_PRINCIPAL_ID=$(az identity show \
     --name cert-monitor-identity \
     --resource-group <resource-group> \
     --query principalId -o tsv)
   
   az role assignment create \
     --assignee $IDENTITY_PRINCIPAL_ID \
     --role "Storage Blob Data Contributor" \
     --scope $STORAGE_ACCOUNT_ID
   ```

3. **Configure in Deployment:**
   - Use Azure Workload Identity (if AKS supports it)
   - Or use AAD Pod Identity (legacy)

---

### Step 9: Add Sidecar to Deployment

**Deployment Structure:**

```yaml
spec:
  template:
    spec:
      serviceAccountName: cert-monitor-sa
      containers:
      - name: app-config-container
        # ... your main app container ...
      
      - name: cert-monitor-sidecar
        image: <your-registry>/cert-monitor:latest
        env:
        - name: STORAGE_ACCOUNT_NAME
          value: "<storage-account-name>"
        - name: STORAGE_CONTAINER_NAME
          value: "certificate-logs"
        - name: CERTIFICATE_NAME
          value: "azure-app-config-tls"
        - name: CERTIFICATE_NAMESPACE
          value: "default"
        - name: AZURE_CLIENT_ID
          value: "<managed-identity-client-id>"  # If using managed identity
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
```

---

### Step 10: Implement Rotation Detection Logic

**Detection Methods:**

**Method 1: Watch Certificate Resource**
```python
# Pseudocode
watch_stream = v1.list_certificate_for_all_namespaces(watch=True)
for event in watch_stream:
    if event['type'] == 'MODIFIED':
        cert = event['object']
        if cert.status.conditions:
            for condition in cert.status.conditions:
                if condition.type == 'Ready' and condition.status == 'True':
                    # Check if renewal time is recent
                    if cert.status.renewalTime:
                        # Certificate was renewed
                        log_rotation_event(cert)
```

**Method 2: Watch Secret Resource**
```python
# Pseudocode
watch_stream = v1.list_secret_for_all_namespaces(watch=True)
for event in watch_stream:
    if event['object'].metadata.name == 'azure-app-config-tls':
        if event['type'] == 'MODIFIED':
            # Secret was updated - likely certificate rotation
            old_version = previous_resource_version
            new_version = event['object'].metadata.resourceVersion
            if old_version != new_version:
                log_rotation_event(event['object'])
```

**Method 3: Compare Certificate Expiration**
```python
# Pseudocode
def check_certificate_expiration(cert_name, namespace):
    cert = get_certificate(cert_name, namespace)
    secret = get_secret(cert.spec.secretName, namespace)
    
    # Decode certificate from secret
    cert_data = decode_base64(secret.data['tls.crt'])
    expiration = extract_expiration_date(cert_data)
    
    # Compare with stored expiration
    if expiration != stored_expiration:
        log_rotation_event(cert, expiration)
        stored_expiration = expiration
```

---

### Step 11: Upload Logs to Azure Storage

**Upload Implementation:**

**Using Azure Blob Storage SDK (Python example):**
```python
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential
import json
from datetime import datetime

def upload_log_to_storage(log_data, storage_account, container, use_managed_identity=True):
    # Create blob name with timestamp
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    blob_name = f"cert-rotation-{timestamp}.json"
    
    # Initialize client
    if use_managed_identity:
        credential = DefaultAzureCredential()
        blob_service = BlobServiceClient(
            account_url=f"https://{storage_account}.blob.core.windows.net",
            credential=credential
        )
    else:
        # Use connection string or account key
        blob_service = BlobServiceClient.from_connection_string(connection_string)
    
    # Upload JSON
    blob_client = blob_service.get_blob_client(container=container, blob=blob_name)
    blob_client.upload_blob(json.dumps(log_data, indent=2), overwrite=True)
    
    return blob_name
```

---

### Step 12: Handle Edge Cases

**Consider These Scenarios:**

1. **Multiple Rotations in Short Time**
   - Deduplicate events (check if already logged)
   - Use resourceVersion or timestamp comparison

2. **Failed Rotations**
   - Log failed rotation attempts
   - Include error messages from Certificate status

3. **Initial Certificate Issuance**
   - Distinguish between first issuance and rotation
   - Use `eventType: "certificate_issued"` vs `"certificate_rotation"`

4. **Network Failures**
   - Implement retry logic for storage uploads
   - Queue logs locally if storage unavailable

5. **Pod Restarts**
   - Store last known state (use ConfigMap or local file)
   - Resume monitoring from last checkpoint

---

### Step 13: Testing Your Implementation

**Test Scenarios:**

1. **Manual Certificate Rotation:**
   ```bash
   # Delete certificate to force renewal
   kubectl delete certificate azure-app-config-tls -n default
   # cert-manager will recreate it
   # Watch for log upload
   ```

2. **Check Logs in Storage:**
   ```bash
   az storage blob list \
     --container-name certificate-logs \
     --account-name <storage-account-name> \
     --output table
   ```

3. **Verify Sidecar Logs:**
   ```bash
   kubectl logs <pod-name> -c cert-monitor-sidecar
   ```

---

### Step 14: Monitoring and Alerting (Optional)

**Additional Enhancements:**

1. **Health Check Endpoint**
   - Expose HTTP endpoint in sidecar
   - Return health status

2. **Metrics**
   - Export Prometheus metrics
   - Track rotation count, failures, etc.

3. **Alerts**
   - Alert on failed rotations
   - Alert if sidecar stops working

---

## Implementation Checklist

- [ ] Create Service Account and RBAC permissions
- [ ] Set up Azure Storage Account and container
- [ ] Configure Managed Identity (or storage key)
- [ ] Build sidecar container image
- [ ] Implement Kubernetes API watcher
- [ ] Implement rotation detection logic
- [ ] Implement JSON log generation
- [ ] Implement Azure Storage upload
- [ ] Add sidecar to deployment
- [ ] Test certificate rotation
- [ ] Verify logs in storage
- [ ] Set up monitoring/alerting (optional)

---

## Key Considerations

1. **Performance:**
   - Watch API efficiently (use field selectors if possible)
   - Batch uploads if multiple events occur

2. **Security:**
   - Use Managed Identity (preferred over keys)
   - Limit RBAC permissions to minimum required
   - Encrypt logs in storage (if sensitive)

3. **Reliability:**
   - Handle API disconnections (reconnect logic)
   - Retry failed uploads
   - Log sidecar errors for debugging

4. **Cost:**
   - Consider log retention policies
   - Compress logs if large
   - Use appropriate storage tier

---

## Alternative Approaches

**Option 1: Use Kubernetes Event Exporter**
- Deploy event-exporter to watch all events
- Filter cert-manager events
- Forward to Azure Storage

**Option 2: Use cert-manager Webhooks**
- Configure cert-manager webhook
- Intercept certificate events
- Log to storage

**Option 3: Use Azure Monitor**
- Send logs to Azure Monitor/Log Analytics
- Query and analyze there
- Export to Storage if needed

---

## Resources

- Kubernetes Python Client: https://github.com/kubernetes-client/python
- Azure Storage Blob SDK: https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/storage
- cert-manager API Reference: https://cert-manager.io/docs/reference/api-docs/
- Kubernetes Watch API: https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes

