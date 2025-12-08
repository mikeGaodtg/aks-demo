# PowerShell script to build and push Docker image to Docker Hub
# Usage: .\build-and-push.ps1 [DOCKER_USERNAME] [IMAGE_NAME] [TAG]

param(
    [string]$DockerUsername = "wsztg008",
    [string]$ImageName = "app-config",
    [string]$Tag = "latest"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Docker Build and Push Script ===" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is running
Write-Host "Checking Docker daemon..." -ForegroundColor Yellow
try {
    docker info | Out-Null
    Write-Host "✓ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Full image name
$FullImageName = "${DockerUsername}/${ImageName}:${Tag}"
$FullImageNameLatest = "${DockerUsername}/${ImageName}:latest"

Write-Host "Image will be tagged as: $FullImageName" -ForegroundColor Cyan
Write-Host ""

# Build the Docker image
Write-Host "Building Docker image..." -ForegroundColor Yellow
docker build -t $FullImageName -t $FullImageNameLatest .

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Docker build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Docker image built successfully" -ForegroundColor Green
Write-Host ""

# Check if user is logged in to Docker Hub
Write-Host "Checking Docker Hub login status..." -ForegroundColor Yellow
$dockerConfig = "$env:USERPROFILE\.docker\config.json"
if (Test-Path $dockerConfig) {
    $config = Get-Content $dockerConfig | ConvertFrom-Json
    if ($config.auths.'https://index.docker.io/v1/') {
        Write-Host "✓ Already logged in to Docker Hub" -ForegroundColor Green
    } else {
        Write-Host "⚠ Not logged in to Docker Hub. Please login:" -ForegroundColor Yellow
        Write-Host "  docker login" -ForegroundColor Cyan
        Write-Host ""
        $login = Read-Host "Do you want to login now? (y/n)"
        if ($login -eq "y" -or $login -eq "Y") {
            docker login
            if ($LASTEXITCODE -ne 0) {
                Write-Host "✗ Docker login failed!" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "Skipping push. You can push manually later with:" -ForegroundColor Yellow
            Write-Host "  docker push $FullImageName" -ForegroundColor Cyan
            exit 0
        }
    }
} else {
    Write-Host "⚠ Not logged in to Docker Hub. Please login:" -ForegroundColor Yellow
    Write-Host "  docker login" -ForegroundColor Cyan
    Write-Host ""
    $login = Read-Host "Do you want to login now? (y/n)"
    if ($login -eq "y" -or $login -eq "Y") {
        docker login
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ Docker login failed!" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Skipping push. You can push manually later with:" -ForegroundColor Yellow
        Write-Host "  docker push $FullImageName" -ForegroundColor Cyan
        exit 0
    }
}

# Push the image to Docker Hub
Write-Host ""
Write-Host "Pushing image to Docker Hub..." -ForegroundColor Yellow
docker push $FullImageName

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Docker push failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Image pushed successfully to Docker Hub" -ForegroundColor Green
Write-Host ""
Write-Host "=== Build and Push Complete ===" -ForegroundColor Cyan
Write-Host "Image: $FullImageName" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Deploy to Kubernetes: .\deploy-to-k8s.ps1" -ForegroundColor Cyan
Write-Host "2. Check logs: kubectl logs -f deployment/azure-app-config-app" -ForegroundColor Cyan

