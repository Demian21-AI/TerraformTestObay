# Azure Terraform Backend Setup Script
# This script creates a service principal, resource group, and storage account for Terraform state management

$ErrorActionPreference = "Stop"

# Configuration variables
$RESOURCE_GROUP_NAME = if ($env:RESOURCE_GROUP_NAME) { $env:RESOURCE_GROUP_NAME } else { "terraform-state-rg" }
$STORAGE_ACCOUNT_NAME = if ($env:STORAGE_ACCOUNT_NAME) { $env:STORAGE_ACCOUNT_NAME } else { "tfstate$((Get-Date).ToFileTimeUtc())" }
$CONTAINER_NAME = if ($env:CONTAINER_NAME) { $env:CONTAINER_NAME } else { "tfstate" }
$LOCATION = if ($env:LOCATION) { $env:LOCATION } else { "eastus" }
$SP_NAME = if ($env:SP_NAME) { $env:SP_NAME } else { "terraform-sp" }

Write-Host "=== Azure Terraform Backend Setup ===" -ForegroundColor Cyan
Write-Host "Resource Group: $RESOURCE_GROUP_NAME"
Write-Host "Storage Account: $STORAGE_ACCOUNT_NAME"
Write-Host "Container: $CONTAINER_NAME"
Write-Host "Location: $LOCATION"
Write-Host "Service Principal: $SP_NAME"
Write-Host ""

# Get subscription ID
Write-Host "Getting subscription ID..."
$SUBSCRIPTION_ID = (az account show --query id -o tsv)
Write-Host "Subscription ID: $SUBSCRIPTION_ID"

# Create or use existing service principal
Write-Host ""
Write-Host "Checking for existing service principal..."
$EXISTING_SP = (az ad sp list --display-name $SP_NAME --query '[0].appId' -o tsv 2>$null)

if ($EXISTING_SP) {
    Write-Host "Service principal '$SP_NAME' already exists"
    $CLIENT_ID = $EXISTING_SP
    $TENANT_ID = (az account show --query tenantId -o tsv)

    # Reset credentials for existing SP
    Write-Host "Resetting credentials for existing service principal..."
    $SP_OUTPUT = (az ad sp credential reset --id $CLIENT_ID --output json) | ConvertFrom-Json
    $CLIENT_SECRET = $SP_OUTPUT.password

    # Ensure Contributor role is assigned
    Write-Host "Ensuring Contributor role assignment..."
    try {
        az role assignment create --assignee $CLIENT_ID --role Contributor --scope "/subscriptions/$SUBSCRIPTION_ID" 2>$null
    } catch {
        Write-Host "Role assignment already exists or failed (this may be ok)"
    }
} else {
    Write-Host "Creating new service principal..."
    $SP_OUTPUT = (az ad sp create-for-rbac --name $SP_NAME --role Contributor --scopes "/subscriptions/$SUBSCRIPTION_ID" --output json 2>&1)

    if ($SP_OUTPUT -match "ERROR") {
        Write-Host "Error creating service principal:" -ForegroundColor Red
        Write-Host $SP_OUTPUT
        exit 1
    }

    $SP_JSON = $SP_OUTPUT | ConvertFrom-Json
    $CLIENT_ID = $SP_JSON.appId
    $CLIENT_SECRET = $SP_JSON.password
    $TENANT_ID = $SP_JSON.tenant
}

Write-Host "Service Principal ready"
Write-Host "Client ID: $CLIENT_ID"

# Wait for service principal propagation
Write-Host ""
Write-Host "Waiting for service principal to propagate..."
Start-Sleep -Seconds 30

# Create resource group if it doesn't exist
Write-Host ""
Write-Host "Creating resource group..."
try {
    az group create --name $RESOURCE_GROUP_NAME --location $LOCATION 2>$null | Out-Null
} catch {
    Write-Host "Resource group already exists"
}

# Create storage account
Write-Host ""
Write-Host "Creating storage account..."
az storage account create `
    --name $STORAGE_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP_NAME `
    --location $LOCATION `
    --sku Standard_LRS `
    --encryption-services blob `
    --https-only true `
    --min-tls-version TLS1_2

# Get storage account key
Write-Host ""
Write-Host "Retrieving storage account key..."
$STORAGE_ACCOUNT_KEY = (az storage account keys list `
    --resource-group $RESOURCE_GROUP_NAME `
    --account-name $STORAGE_ACCOUNT_NAME `
    --query '[0].value' -o tsv)

# Create blob container
Write-Host ""
Write-Host "Creating blob container..."
az storage container create `
    --name $CONTAINER_NAME `
    --account-name $STORAGE_ACCOUNT_NAME `
    --account-key $STORAGE_ACCOUNT_KEY

# Grant service principal Storage Blob Data Contributor role on storage account
Write-Host ""
Write-Host "Granting service principal access to storage account..."
$STORAGE_ACCOUNT_ID = (az storage account show `
    --name $STORAGE_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP_NAME `
    --query id -o tsv)

try {
    az role assignment create `
        --assignee $CLIENT_ID `
        --role "Storage Blob Data Contributor" `
        --scope $STORAGE_ACCOUNT_ID 2>$null
} catch {
    Write-Host "Storage role assignment already exists or failed (this may be ok)"
}

# Output configuration
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Save these credentials securely:"
Write-Host ""
Write-Host "ARM_CLIENT_ID=$CLIENT_ID"
Write-Host "ARM_CLIENT_SECRET=$CLIENT_SECRET"
Write-Host "ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
Write-Host "ARM_TENANT_ID=$TENANT_ID"
Write-Host ""
Write-Host "Terraform Backend Configuration:"
Write-Host ""
Write-Host @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_NAME"
    container_name       = "$CONTAINER_NAME"
    key                  = "terraform.tfstate"
  }
}
"@
Write-Host ""
Write-Host "To use with Terraform, set these environment variables:"
Write-Host ""
Write-Host "`$env:ARM_CLIENT_ID=`"$CLIENT_ID`""
Write-Host "`$env:ARM_CLIENT_SECRET=`"$CLIENT_SECRET`""
Write-Host "`$env:ARM_SUBSCRIPTION_ID=`"$SUBSCRIPTION_ID`""
Write-Host "`$env:ARM_TENANT_ID=`"$TENANT_ID`""
Write-Host ""
Write-Host "Or save to a .env.azure file (add to .gitignore!):"
Write-Host ""

# Create .env.azure file
@"
ARM_CLIENT_ID=$CLIENT_ID
ARM_CLIENT_SECRET=$CLIENT_SECRET
ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
ARM_TENANT_ID=$TENANT_ID
"@ | Out-File -FilePath ".env.azure" -Encoding UTF8

Write-Host "Credentials saved to .env.azure"
Write-Host ""
Write-Host "To use in GitHub Actions, add these as repository secrets:"
Write-Host "- ARM_CLIENT_ID"
Write-Host "- ARM_CLIENT_SECRET"
Write-Host "- ARM_SUBSCRIPTION_ID"
Write-Host "- ARM_TENANT_ID"
