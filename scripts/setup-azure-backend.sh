#!/bin/bash

# Azure Terraform Backend Setup Script
# This script creates a service principal, resource group, and storage account for Terraform state management

set -e -o pipefail

# Configuration variables
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-terraform-state-rg}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-tfstate$(date +%s)}"
CONTAINER_NAME="${CONTAINER_NAME:-tfstate}"
LOCATION="${LOCATION:-eastus}"
SP_NAME="${SP_NAME:-terraform-sp}"

echo "=== Azure Terraform Backend Setup ==="
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo "Container: $CONTAINER_NAME"
echo "Location: $LOCATION"
echo "Service Principal: $SP_NAME"
echo ""

# Get subscription ID
echo "Getting subscription ID..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Subscription ID: $SUBSCRIPTION_ID"

# Create or use existing service principal
echo ""
echo "Checking for existing service principal..."
EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query '[0].appId' -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_SP" ]; then
  echo "Service principal '$SP_NAME' already exists"
  CLIENT_ID="$EXISTING_SP"
  TENANT_ID=$(az account show --query tenantId -o tsv)

  # Reset credentials for existing SP
  echo "Resetting credentials for existing service principal..."
  SP_OUTPUT=$(az ad sp credential reset --id "$CLIENT_ID" --output json)
  CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.password')

  # Ensure Contributor role is assigned
  echo "Ensuring Contributor role assignment..."
  az role assignment create \
    --assignee "$CLIENT_ID" \
    --role Contributor \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    2>/dev/null || echo "Role assignment already exists or failed (this may be ok)"
else
  echo "Creating new service principal..."
  SP_OUTPUT=$(az ad sp create-for-rbac --name "$SP_NAME" --role Contributor --scopes "/subscriptions/$SUBSCRIPTION_ID" --output json 2>&1)

  if echo "$SP_OUTPUT" | grep -q "ERROR"; then
    echo "Error creating service principal:"
    echo "$SP_OUTPUT"
    exit 1
  fi

  CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.appId')
  CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.password')
  TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenant')
fi

echo "Service Principal ready"
echo "Client ID: $CLIENT_ID"

# Wait for service principal propagation
echo ""
echo "Waiting for service principal to propagate..."
sleep 30

# Create resource group if it doesn't exist
echo ""
echo "Creating resource group..."
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" 2>/dev/null || echo "Resource group already exists"

# Create storage account
echo ""
echo "Creating storage account..."
az storage account create \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --encryption-services blob \
  --https-only true \
  --min-tls-version TLS1_2

# Get storage account key
echo ""
echo "Retrieving storage account key..."
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --query '[0].value' -o tsv)

# Create blob container
echo ""
echo "Creating blob container..."
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --account-key "$STORAGE_ACCOUNT_KEY"

# Grant service principal Storage Blob Data Contributor role on storage account
echo ""
echo "Granting service principal access to storage account..."
STORAGE_ACCOUNT_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query id -o tsv)

az role assignment create \
  --assignee "$CLIENT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ACCOUNT_ID" \
  2>/dev/null || echo "Storage role assignment already exists or failed (this may be ok)"

# Output configuration
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Save these credentials securely:"
echo ""
echo "ARM_CLIENT_ID=$CLIENT_ID"
echo "ARM_CLIENT_SECRET=$CLIENT_SECRET"
echo "ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "ARM_TENANT_ID=$TENANT_ID"
echo ""
echo "Terraform Backend Configuration:"
echo ""
cat <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP_NAME"
    storage_account_name = "$STORAGE_ACCOUNT_NAME"
    container_name       = "$CONTAINER_NAME"
    key                  = "terraform.tfstate"
  }
}
EOF
echo ""
echo "To use with Terraform, export these environment variables:"
echo ""
echo "export ARM_CLIENT_ID=\"$CLIENT_ID\""
echo "export ARM_CLIENT_SECRET=\"$CLIENT_SECRET\""
echo "export ARM_SUBSCRIPTION_ID=\"$SUBSCRIPTION_ID\""
echo "export ARM_TENANT_ID=\"$TENANT_ID\""
echo ""
echo "Or save to a .env file (add to .gitignore!):"
echo ""
cat > .env.azure <<EOF
ARM_CLIENT_ID=$CLIENT_ID
ARM_CLIENT_SECRET=$CLIENT_SECRET
ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
ARM_TENANT_ID=$TENANT_ID
EOF
echo "Credentials saved to .env.azure"
echo ""
echo "To use in GitHub Actions, add these as repository secrets:"
echo "- ARM_CLIENT_ID"
echo "- ARM_CLIENT_SECRET"
echo "- ARM_SUBSCRIPTION_ID"
echo "- ARM_TENANT_ID"
