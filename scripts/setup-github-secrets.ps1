# Script to create Azure Service Principal and configure GitHub Secrets
# for Terraform CI/CD pipeline

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Azure Service Principal & GitHub Secrets Setup"
Write-Host "========================================="
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..."

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Azure CLI is not installed. Please install it first." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Error: GitHub CLI is not installed. Please install it first." -ForegroundColor Red
    exit 1
}

# Check if logged in to Azure
try {
    az account show | Out-Null
} catch {
    Write-Host "Error: Not logged in to Azure. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

# Check if logged in to GitHub
try {
    gh auth status 2>&1 | Out-Null
} catch {
    Write-Host "Error: Not logged in to GitHub. Please run 'gh auth login' first." -ForegroundColor Red
    exit 1
}

Write-Host "✓ All prerequisites met" -ForegroundColor Green
Write-Host ""

# Get subscription name
Write-Host "Available Azure subscriptions:"
az account list --output table

Write-Host ""
$subscriptionName = Read-Host "Enter your Azure subscription name"

if ([string]::IsNullOrWhiteSpace($subscriptionName)) {
    Write-Host "Error: Subscription name cannot be empty." -ForegroundColor Red
    exit 1
}

Write-Host "Setting subscription to: $subscriptionName"
az account set --subscription $subscriptionName

# Get subscription details
$subscriptionId = (az account show | ConvertFrom-Json).id
Write-Host "✓ Subscription ID: $subscriptionId" -ForegroundColor Green
Write-Host ""

# Service Principal name
$ServicePrincipleName = "TerraformSP"
Write-Host "Creating Service Principal: $ServicePrincipleName"

# Check if service principal already exists
$existingSP = (az ad sp list --display-name $ServicePrincipleName --query "[0].appId" -o tsv 2>$null)

if ($existingSP) {
    Write-Host ""
    Write-Host "⚠️  Service Principal '$ServicePrincipleName' already exists." -ForegroundColor Yellow
    $recreate = Read-Host "Do you want to delete and recreate it? (y/N)"

    if ($recreate -eq 'y' -or $recreate -eq 'Y') {
        Write-Host "Deleting existing Service Principal..."
        az ad sp delete --id $existingSP
        Write-Host "✓ Deleted existing Service Principal" -ForegroundColor Green
    } else {
        Write-Host "Error: Cannot proceed with existing Service Principal. Please use a different name or delete it manually." -ForegroundColor Red
        exit 1
    }
}

# Create Service Principal
Write-Host "Creating new Service Principal with Contributor role..."
$sp = (az ad sp create-for-rbac --name $ServicePrincipleName --role Contributor --scopes "/subscriptions/$subscriptionId" | ConvertFrom-Json)

$AppId = $sp.appId
$Password = $sp.password
$Tenant = $sp.tenant

Write-Host "✓ Service Principal created successfully" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal Details:"
Write-Host "  AppId: $AppId"
Write-Host "  Password: ********"
Write-Host "  Tenant: $Tenant"
Write-Host ""

# Set GitHub Secrets
Write-Host "Setting GitHub Secrets..."
Write-Host ""

gh secret set ARM_CLIENT_ID --body $AppId
Write-Host "✓ Set ARM_CLIENT_ID" -ForegroundColor Green

gh secret set ARM_CLIENT_SECRET --body $Password
Write-Host "✓ Set ARM_CLIENT_SECRET" -ForegroundColor Green

gh secret set ARM_TENANT_ID --body $Tenant
Write-Host "✓ Set ARM_TENANT_ID" -ForegroundColor Green

gh secret set ARM_SUBSCRIPTION_ID --body $subscriptionId
Write-Host "✓ Set ARM_SUBSCRIPTION_ID" -ForegroundColor Green

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "========================================="
Write-Host ""
Write-Host "GitHub Secrets have been configured for:"
$repo = (gh repo view --json nameWithOwner | ConvertFrom-Json).nameWithOwner
Write-Host $repo
Write-Host ""
Write-Host "You can now use the Terraform GitHub Actions workflow."
Write-Host ""
Write-Host "To test locally, set these environment variables:"
Write-Host ""
Write-Host "`$env:ARM_CLIENT_ID=`"$AppId`""
Write-Host "`$env:ARM_CLIENT_SECRET=`"$Password`""
Write-Host "`$env:ARM_TENANT_ID=`"$Tenant`""
Write-Host "`$env:ARM_SUBSCRIPTION_ID=`"$subscriptionId`""
Write-Host ""
