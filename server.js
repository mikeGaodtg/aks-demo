// WARNING: Temporarily disable SSL verification for testing only
// DO NOT use this in production - it makes connections insecure!
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
console.log('⚠️  WARNING: SSL certificate verification is DISABLED (testing only!)');

// Ensure crypto is available globally for Azure SDK compatibility
// The Azure SDK expects crypto.randomUUID() to be available
if (typeof globalThis.crypto === 'undefined') {
  const nodeCrypto = require('crypto');
  globalThis.crypto = {
    randomUUID: () => nodeCrypto.randomUUID(),
    ...nodeCrypto.webcrypto
  };
}

require('dotenv').config();
const express = require('express');
const https = require('https');
const fs = require('fs');
const { AppConfigurationClient } = require('@azure/app-configuration');
const { DefaultAzureCredential, ManagedIdentityCredential } = require('@azure/identity');

const app = express();
const PORT = process.env.PORT || 3000;

// Azure App Configuration endpoint URL
// Format: https://<your-app-config-name>.azconfig.io
const appConfigEndpoint = process.env.AZURE_APP_CONFIG_ENDPOINT;

if (!appConfigEndpoint) {
  console.error('Error: AZURE_APP_CONFIG_ENDPOINT environment variable is not set');
  console.error('Please set AZURE_APP_CONFIG_ENDPOINT to your App Configuration endpoint URL');
  console.error('Example: https://app-config-mikegao-1');
  process.exit(1);
}

// Use managed identity inherited from the AKS node pool
// DefaultAzureCredential will automatically use the node pool's managed identity via IMDS
// No service account or Workload Identity setup needed!
console.log('=== Authentication Configuration ===');
console.log('Using Managed Identity inherited from AKS Node Pool');
console.log('DefaultAzureCredential will automatically use the node pool\'s managed identity');

// If AZURE_CLIENT_ID is provided, use it to specify which managed identity to use
// (useful if the node pool has multiple managed identities)
// Otherwise, DefaultAzureCredential will use the system-assigned or default user-assigned identity
let credential;
if (process.env.AZURE_CLIENT_ID) {
  console.log(`Using ManagedIdentityCredential with specified Client ID: ${process.env.AZURE_CLIENT_ID}`);
  credential = new ManagedIdentityCredential({
    clientId: process.env.AZURE_CLIENT_ID
  });
} else {
  console.log('Using DefaultAzureCredential (will use node pool\'s managed identity via IMDS)');
  credential = new DefaultAzureCredential();
}

// Configure Node.js to use system CA certificates
// Try multiple common paths for CA certificates
const caCertPaths = [
  '/etc/ssl/certs/ca-certificates.crt',  // Debian/Ubuntu
  '/etc/ssl/certs/ca-bundle.crt',        // Some systems
  '/etc/pki/tls/certs/ca-bundle.crt',    // RedHat/CentOS
  '/etc/ssl/ca-bundle.pem',              // Alpine (sometimes)
];

let caCerts = null;
let caCertPath = null;

// Try to find and load CA certificates
// Method 1: Try reading the bundled certificate file
for (const path of caCertPaths) {
  try {
    if (fs.existsSync(path)) {
      caCertPath = path;
      caCerts = fs.readFileSync(path);
      console.log(`Found CA certificates at: ${path}`);
      console.log(`Certificate file size: ${caCerts.length} bytes`);
      break;
    }
  } catch (err) {
    console.error(`Error reading ${path}:`, err.message);
  }
}

// Method 2: If bundled file didn't work or doesn't exist, try reading individual certs from directory
if (!caCerts && fs.existsSync('/etc/ssl/certs')) {
  try {
    const certFiles = fs.readdirSync('/etc/ssl/certs').filter(f => f.endsWith('.pem') || f.endsWith('.crt') || f.endsWith('.0'));
    if (certFiles.length > 0) {
      console.log(`Found ${certFiles.length} certificate files in /etc/ssl/certs`);
      // Try to load a few key certificates
      caCerts = [];
      for (const certFile of certFiles.slice(0, 50)) { // Limit to first 50 to avoid too many
        try {
          const cert = fs.readFileSync(`/etc/ssl/certs/${certFile}`);
          caCerts.push(cert);
        } catch (err) {
          // Skip invalid certs
        }
      }
      if (caCerts.length > 0) {
        caCertPath = '/etc/ssl/certs (multiple files)';
        caCerts = Buffer.concat(caCerts);
        console.log(`Loaded ${caCerts.length} bytes from individual certificate files`);
      }
    }
  } catch (err) {
    console.error('Error reading certificate directory:', err.message);
  }
}

// Configure Node.js's default HTTPS agent globally with CA certificates
// Also try using environment variable as fallback
if (caCerts) {
  try {
    // Method 1: Use as buffer (single file format)
    let httpsAgent = new https.Agent({
      ca: caCerts,
      rejectUnauthorized: true,
      keepAlive: true
    });
    
    // Set as default agent for all HTTPS requests
    https.globalAgent = httpsAgent;
    
    // Also set environment variable as additional fallback
    process.env.NODE_EXTRA_CA_CERTS = caCertPath;
    
    console.log(`✅ Configured Node.js default HTTPS agent with CA certificates from: ${caCertPath}`);
    console.log(`✅ Set NODE_EXTRA_CA_CERTS environment variable to: ${caCertPath}`);
  } catch (err) {
    console.error('❌ Error configuring HTTPS agent:', err.message);
    console.error('Stack:', err.stack);
  }
} else {
  console.warn('⚠️  CA certificates not found in standard locations.');
  console.warn('Checked paths:', caCertPaths);
  console.warn('⚠️  Using default Node.js certificates. This may cause SSL verification errors.');
}

// Create Azure App Configuration client using managed identity
// Note: The Azure SDK should use Node.js's https module which respects https.globalAgent
// and NODE_EXTRA_CA_CERTS environment variable
const client = new AppConfigurationClient(appConfigEndpoint, credential);
console.log('Created Azure App Configuration client using managed identity');
console.log(`App Configuration Endpoint: ${appConfigEndpoint}`);

// Log certificate configuration for debugging
console.log('Certificate configuration:');
console.log(`  NODE_EXTRA_CA_CERTS: ${process.env.NODE_EXTRA_CA_CERTS || 'not set'}`);
console.log(`  SSL_CERT_FILE: ${process.env.SSL_CERT_FILE || 'not set'}`);
console.log(`  HTTPS Agent CA: ${https.globalAgent.options?.ca ? 'configured' : 'not configured'}`);
console.log(`  HTTPS Agent: ${https.globalAgent ? 'exists' : 'missing'}`);
const configKey = 'App:Message';

// Cache the configuration value
let cachedMessage = 'Loading...';

// Function to fetch configuration from Azure App Config
async function fetchConfigValue() {
  try {
    const setting = await client.getConfigurationSetting({ key: configKey });
    cachedMessage = setting.value || 'No value found';
    console.log(`Successfully fetched configuration: ${configKey} = ${cachedMessage}`);
  } catch (error) {
    console.error('Error fetching configuration from Azure App Config:');
    console.error('Message:', error.message);
    console.error('Stack:', error.stack);
    cachedMessage = 'Error loading configuration';
  }
}

// Fetch configuration on startup
fetchConfigValue();

// Refresh configuration every 30 seconds (optional)
setInterval(fetchConfigValue, 30000);

app.get('/', async (req, res) => {
  // Optionally refresh on each request (remove if you prefer caching)
  // await fetchConfigValue();
  
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Azure App Config</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
          height: 100vh;
          margin: 0;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        h1 {
          color: white;
          font-size: 3em;
          text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
          margin-bottom: 20px;
        }
        .config-info {
          color: rgba(255, 255, 255, 0.9);
          font-size: 1.2em;
          margin-top: 20px;
          padding: 15px;
          background: rgba(255, 255, 255, 0.1);
          border-radius: 8px;
          backdrop-filter: blur(10px);
        }
        .key {
          font-weight: bold;
          color: #ffd700;
        }
      </style>
    </head>
    <body>
      <h1>${cachedMessage}</h1>
      <div class="config-info">
        <div>Key: <span class="key">${configKey}</span></div>
        <div>Config App: <span class="key">aks-appconfig-12</span></div>
        <div>Resource Group: <span class="key">Mike</span></div>
      </div>
    </body>
    </html>
  `);
});

app.listen(PORT, () => {
  console.log(`Server is running at http://localhost:${PORT}`);
  console.log('Open your browser and navigate to the URL above to see the configuration value');
  console.log(`Fetching configuration key: ${configKey}`);
});

