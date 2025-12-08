# Comprehensive TLS/SSL Testing and Debugging Script
# This script will help identify why SSL is not working

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "TLS/SSL Testing and Debugging Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$errors = @()
$warnings = @()

# 1. Check cert-manager Installation
Write-Host "1. Checking cert-manager Installation..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$cmPods = kubectl get pods -n cert-manager 2>&1
if ($LASTEXITCODE -ne 0 -or -not ($cmPods -match "cert-manager")) {
    Write-Host "✗ cert-manager is NOT installed" -ForegroundColor Red
    $errors += "cert-manager is not installed"
    Write-Host "   Install with: kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml" -ForegroundColor Yellow
} else {
    Write-Host "✓ cert-manager is installed" -ForegroundColor Green
    kubectl get pods -n cert-manager
    Write-Host ""
    $cmReady = kubectl get pods -n cert-manager -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>&1
    if ($cmReady -match "True") {
        Write-Host "✓ cert-manager pods are ready" -ForegroundColor Green
    } else {
        Write-Host "⚠ cert-manager pods are not ready" -ForegroundColor Yellow
        $warnings += "cert-manager pods not ready"
    }
}
Write-Host ""

# 2. Check ClusterIssuer
Write-Host "2. Checking ClusterIssuer..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$issuer = kubectl get clusterissuer letsencrypt-prod 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ ClusterIssuer 'letsencrypt-prod' NOT found" -ForegroundColor Red
    $errors += "ClusterIssuer not found"
    Write-Host "   Deploy with: kubectl apply -f k8s/cert-manager-clusterissuer.yaml" -ForegroundColor Yellow
} else {
    Write-Host "✓ ClusterIssuer found" -ForegroundColor Green
    kubectl get clusterissuer letsencrypt-prod
    Write-Host ""
    $issuerReady = kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>&1
    if ($issuerReady -eq "True") {
        Write-Host "✓ ClusterIssuer is ready" -ForegroundColor Green
    } else {
        Write-Host "⚠ ClusterIssuer is not ready" -ForegroundColor Yellow
        Write-Host "   Details:" -ForegroundColor Cyan
        kubectl describe clusterissuer letsencrypt-prod | Select-String -Pattern "Status|Message|Reason" -Context 0,2
        $warnings += "ClusterIssuer not ready"
    }
}
Write-Host ""

# 3. Check Ingress Configuration
Write-Host "3. Checking Ingress Configuration..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$ingress = kubectl get ingress azure-app-config-ingress -n default 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Ingress NOT found" -ForegroundColor Red
    $errors += "Ingress not found"
} else {
    Write-Host "✓ Ingress found" -ForegroundColor Green
    kubectl get ingress azure-app-config-ingress -n default
    Write-Host ""
    
    # Check TLS annotation
    $tlsAnnotation = kubectl get ingress azure-app-config-ingress -n default -o jsonpath='{.metadata.annotations.cert-manager\.io/cluster-issuer}' 2>&1
    if ($tlsAnnotation -eq "letsencrypt-prod") {
        Write-Host "✓ cert-manager annotation is correct" -ForegroundColor Green
    } else {
        Write-Host "✗ cert-manager annotation is missing or incorrect" -ForegroundColor Red
        Write-Host "   Current value: $tlsAnnotation" -ForegroundColor Yellow
        Write-Host "   Expected: letsencrypt-prod" -ForegroundColor Yellow
        $errors += "cert-manager annotation missing"
    }
    
    # Check TLS section
    $tlsHosts = kubectl get ingress azure-app-config-ingress -n default -o jsonpath='{.spec.tls[0].hosts[*]}' 2>&1
    if ($tlsHosts) {
        Write-Host "✓ TLS hosts configured: $tlsHosts" -ForegroundColor Green
    } else {
        Write-Host "✗ TLS hosts not configured" -ForegroundColor Red
        $errors += "TLS hosts not configured"
    }
    
    # Check ingress details
    Write-Host ""
    Write-Host "Ingress Details:" -ForegroundColor Cyan
    kubectl describe ingress azure-app-config-ingress -n default | Select-String -Pattern "TLS|Host|Annotations" -Context 0,3
}
Write-Host ""

# 4. Check Certificate Resource
Write-Host "4. Checking Certificate Resource..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$cert = kubectl get certificate azure-app-config-tls -n default 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Certificate resource NOT found" -ForegroundColor Red
    Write-Host "   cert-manager should create this automatically" -ForegroundColor Yellow
    $errors += "Certificate resource not created"
    Write-Host ""
    Write-Host "   Possible reasons:" -ForegroundColor Yellow
    Write-Host "   - cert-manager not installed" -ForegroundColor White
    Write-Host "   - ClusterIssuer not ready" -ForegroundColor White
    Write-Host "   - Ingress annotation incorrect" -ForegroundColor White
    Write-Host "   - cert-manager webhook not working" -ForegroundColor White
} else {
    Write-Host "✓ Certificate resource found" -ForegroundColor Green
    kubectl get certificate azure-app-config-tls -n default
    Write-Host ""
    $certReady = kubectl get certificate azure-app-config-tls -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>&1
    if ($certReady -eq "True") {
        Write-Host "✓ Certificate is Ready!" -ForegroundColor Green
    } else {
        Write-Host "⚠ Certificate is NOT ready" -ForegroundColor Yellow
        $warnings += "Certificate not ready"
        Write-Host ""
        Write-Host "Certificate Details:" -ForegroundColor Cyan
        kubectl describe certificate azure-app-config-tls -n default | Select-String -Pattern "Status|Message|Reason|Events" -Context 0,5
    }
}
Write-Host ""

# 5. Check Certificate Request
Write-Host "5. Checking Certificate Request..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$cr = kubectl get certificaterequest -n default 2>&1
if ($LASTEXITCODE -eq 0 -and $cr -notmatch "No resources") {
    Write-Host "✓ CertificateRequest found" -ForegroundColor Green
    kubectl get certificaterequest -n default
    Write-Host ""
    $crName = (kubectl get certificaterequest -n default -o jsonpath='{.items[0].metadata.name}' 2>&1)
    if ($crName) {
        Write-Host "CertificateRequest Details:" -ForegroundColor Cyan
        kubectl describe certificaterequest $crName -n default | Select-String -Pattern "Status|Message|Reason|Events" -Context 0,5
    }
} else {
    Write-Host "⚠ No CertificateRequest found" -ForegroundColor Yellow
    Write-Host "   This might be normal if certificate is already issued" -ForegroundColor Gray
}
Write-Host ""

# 6. Check Challenges (Let's Encrypt Validation)
Write-Host "6. Checking Let's Encrypt Challenges..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$challenges = kubectl get challenge -n default 2>&1
if ($LASTEXITCODE -eq 0 -and $challenges -notmatch "No resources") {
    Write-Host "✓ Challenges found (validation in progress)" -ForegroundColor Green
    kubectl get challenge -n default
    Write-Host ""
    $challengeName = (kubectl get challenge -n default -o jsonpath='{.items[0].metadata.name}' 2>&1)
    if ($challengeName) {
        Write-Host "Challenge Details:" -ForegroundColor Cyan
        kubectl describe challenge $challengeName -n default | Select-String -Pattern "Status|State|Reason|Events" -Context 0,5
    }
} else {
    Write-Host "ℹ No active challenges" -ForegroundColor Gray
    Write-Host "   This is normal if certificate is already issued or not yet requested" -ForegroundColor Gray
}
Write-Host ""

# 7. Check TLS Secret
Write-Host "7. Checking TLS Secret..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$secret = kubectl get secret azure-app-config-tls -n default 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ TLS Secret NOT found" -ForegroundColor Red
    Write-Host "   Secret is created when certificate is issued" -ForegroundColor Yellow
    $errors += "TLS secret not found"
} else {
    Write-Host "✓ TLS Secret found" -ForegroundColor Green
    kubectl get secret azure-app-config-tls -n default
    Write-Host ""
    $secretType = kubectl get secret azure-app-config-tls -n default -o jsonpath='{.type}' 2>&1
    if ($secretType -eq "kubernetes.io/tls") {
        Write-Host "✓ Secret type is correct (kubernetes.io/tls)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Secret type is: $secretType" -ForegroundColor Yellow
    }
}
Write-Host ""

# 8. Check DNS Configuration
Write-Host "8. Checking DNS Configuration..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$ingressIP = kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>&1
if ([string]::IsNullOrWhiteSpace($ingressIP)) {
    Write-Host "✗ Cannot get ingress IP" -ForegroundColor Red
    $errors += "Cannot get ingress IP"
} else {
    Write-Host "✓ Ingress IP: $ingressIP" -ForegroundColor Green
    Write-Host ""
    
    try {
        $dnsResult = Resolve-DnsName -Name "app.mikegaohahahahagogogogo.site" -ErrorAction SilentlyContinue
        if ($dnsResult) {
            $dnsIP = $dnsResult[0].IPAddress
            Write-Host "DNS resolves to: $dnsIP" -ForegroundColor Cyan
            if ($dnsIP -eq $ingressIP) {
                Write-Host "✓ DNS correctly points to ingress IP" -ForegroundColor Green
            } else {
                Write-Host "✗ DNS does NOT point to ingress IP!" -ForegroundColor Red
                Write-Host "   DNS IP: $dnsIP" -ForegroundColor Yellow
                Write-Host "   Ingress IP: $ingressIP" -ForegroundColor Yellow
                Write-Host "   Update your DNS A record!" -ForegroundColor Yellow
                $errors += "DNS not pointing to ingress IP"
            }
        } else {
            Write-Host "✗ DNS resolution failed" -ForegroundColor Red
            $errors += "DNS resolution failed"
        }
    } catch {
        Write-Host "⚠ Could not resolve DNS: $_" -ForegroundColor Yellow
        $warnings += "DNS resolution check failed"
    }
}
Write-Host ""

# 9. Check Ingress Controller TLS Support
Write-Host "9. Checking Ingress Controller TLS Support..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$ingressSvc = kubectl get service ingress-nginx-controller -n ingress-nginx 2>&1
if ($LASTEXITCODE -eq 0) {
    kubectl get service ingress-nginx-controller -n ingress-nginx
    Write-Host ""
    $httpsPort = kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>&1
    if ($httpsPort) {
        Write-Host "✓ HTTPS port configured: $httpsPort" -ForegroundColor Green
    } else {
        Write-Host "⚠ HTTPS port not found in service" -ForegroundColor Yellow
        $warnings += "HTTPS port not configured"
    }
} else {
    Write-Host "✗ Ingress controller service not found" -ForegroundColor Red
    $errors += "Ingress controller service not found"
}
Write-Host ""

# 10. Test HTTPS Connection
Write-Host "10. Testing HTTPS Connection..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
try {
    $httpsTest = Invoke-WebRequest -Uri "https://app.mikegaohahahahagogogogo.site" -Method Head -TimeoutSec 10 -SkipCertificateCheck -ErrorAction SilentlyContinue
    if ($httpsTest.StatusCode -eq 200) {
        Write-Host "✓ HTTPS connection successful!" -ForegroundColor Green
    } else {
        Write-Host "⚠ HTTPS connection returned status: $($httpsTest.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    $errorMsg = $_.Exception.Message
    Write-Host "✗ HTTPS connection failed: $errorMsg" -ForegroundColor Red
    if ($errorMsg -match "SSL|TLS|certificate") {
        Write-Host "   This indicates an SSL/TLS certificate issue" -ForegroundColor Yellow
        $errors += "HTTPS connection failed - SSL/TLS issue"
    } elseif ($errorMsg -match "timeout|resolve") {
        Write-Host "   This indicates a network/DNS issue" -ForegroundColor Yellow
        $warnings += "HTTPS connection failed - network issue"
    }
}
Write-Host ""

# 11. Check cert-manager Logs (Recent Errors)
Write-Host "11. Checking cert-manager Logs (Recent Errors)..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
$cmPod = kubectl get pods -n cert-manager -l app.kubernetes.io/instance=cert-manager -o jsonpath='{.items[0].metadata.name}' 2>&1
if ($cmPod -and $cmPod -notmatch "error") {
    Write-Host "Recent cert-manager logs (last 20 lines with errors):" -ForegroundColor Cyan
    $logs = kubectl logs -n cert-manager $cmPod --tail=50 2>&1 | Select-String -Pattern "error|Error|ERROR|failed|Failed|FAILED" -Context 0,2
    if ($logs) {
        Write-Host $logs -ForegroundColor Red
    } else {
        Write-Host "No recent errors in cert-manager logs" -ForegroundColor Green
    }
} else {
    Write-Host "Could not retrieve cert-manager logs" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "✓ All checks passed! SSL should be working." -ForegroundColor Green
} else {
    if ($errors.Count -gt 0) {
        Write-Host "✗ ERRORS FOUND ($($errors.Count)):" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "  - $error" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    if ($warnings.Count -gt 0) {
        Write-Host "⚠ WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "  - $warning" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    Write-Host "Common Issues and Solutions:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Certificate not created:" -ForegroundColor Yellow
    Write-Host "   - Check cert-manager is installed and running" -ForegroundColor White
    Write-Host "   - Verify ClusterIssuer is ready" -ForegroundColor White
    Write-Host "   - Check ingress annotation: cert-manager.io/cluster-issuer" -ForegroundColor White
    Write-Host ""
    Write-Host "2. Certificate not ready:" -ForegroundColor Yellow
    Write-Host "   - DNS must point to ingress IP" -ForegroundColor White
    Write-Host "   - Wait 5-10 minutes for DNS propagation" -ForegroundColor White
    Write-Host "   - Check certificate request and challenges" -ForegroundColor White
    Write-Host "   - Verify port 80 is accessible (needed for HTTP-01 challenge)" -ForegroundColor White
    Write-Host ""
    Write-Host "3. DNS issues:" -ForegroundColor Yellow
    Write-Host "   - Update DNS A record: app.mikegaohahahahagogogogo.site -> $ingressIP" -ForegroundColor White
    Write-Host "   - Wait for DNS propagation (use dnschecker.org to verify globally)" -ForegroundColor White
    Write-Host ""
    Write-Host "4. Rate limiting:" -ForegroundColor Yellow
    Write-Host "   - Let's Encrypt has rate limits (50 certs/week per domain)" -ForegroundColor White
    Write-Host "   - Use staging issuer for testing: letsencrypt-staging" -ForegroundColor White
    Write-Host ""
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Fix any errors listed above" -ForegroundColor White
Write-Host "2. Re-run this script to verify fixes" -ForegroundColor White
Write-Host "3. Check certificate status: kubectl get certificate -n default" -ForegroundColor White
Write-Host "4. View detailed certificate info: kubectl describe certificate azure-app-config-tls -n default" -ForegroundColor White
Write-Host ""

