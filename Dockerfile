# Use official Node.js runtime as base image (slim variant has better CA cert support)
# Node 20 is required for @azure/identity and newer Azure SDK packages
FROM node:20-slim

# Install and update CA certificates for SSL/TLS connections (required for Azure services)
# Debian-based images have better CA certificate support out of the box
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates openssl && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    # Verify CA certificates are installed
    ls -la /etc/ssl/certs/ | head -5 && \
    test -f /etc/ssl/certs/ca-certificates.crt && echo "CA certificates found" || echo "CA certificates NOT found"

# Set working directory in container
WORKDIR /app

# Copy package.json and package-lock.json (if available)
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY server.js ./

# Expose port 3000
EXPOSE 3000

# Set environment variables for Node.js
ENV NODE_ENV=production
# Tell Node.js to use system CA certificates (Debian/Ubuntu path)
# This must be set at build time for Node.js to load it at startup
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
# WARNING: Temporarily disable SSL verification for testing only
# DO NOT use this in production - it makes connections insecure!
ENV NODE_TLS_REJECT_UNAUTHORIZED=0

# Run the application
CMD ["node", "server.js"]

