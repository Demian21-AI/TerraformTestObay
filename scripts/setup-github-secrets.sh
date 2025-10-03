#!/bin/bash

# Script to create Azure Service Principal and configure GitHub Secrets
# for Terraform CI/CD pipeline

set -e

echo "========================================="
echo "Azure Service Principal & GitHub Secrets Setup"
echo "========================================="
echo ""

# Check prerequisites
command -v az >/dev/null 2>&1 || { echo "Error: Azure CLI is not installed. Please install it first."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "Error: GitHub CLI is not installed. Please install it first."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is not installed. Please install it first."; exit 1; }

# Check if logged in to Azure
if ! az account show >/dev/null 2>&1; then
    echo "Error: Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if logged in to GitHub
if ! gh auth status >/dev/null 2>&1; then
    echo "Error: Not logged in to GitHub. Please run 'gh auth login' first."
    exit 1
fi

echo "✓ All prerequisites met"
echo ""

# Get subscription name
echo "Available Azure subscriptions:"
az account list --output table

echo ""
read -p "Enter your Azure subscription name: " subscriptionName

if [ -z "$subscriptionName" ]; then
    echo "Error: Subscription name cannot be empty."
    exit 1
fi

echo "Setting subscription to: $subscriptionName"
az account set --subscription "$subscriptionName"

# Get subscription details
subscriptionId=$(az account show | jq -r '.id')
echo "✓ Subscription ID: $subscriptionId"
echo ""

# Service Principal name
ServicePrincipleName="TerraformSP"
echo "Creating Service Principal: $ServicePrincipleName"

# Check if service principal already exists
existingSP=$(az ad sp list --display-name "$ServicePrincipleName" --query "[0].appId" -o tsv 2>/dev/null)

if [ -n "$existingSP" ]; then
    echo ""
    echo "⚠️  Service Principal '$ServicePrincipleName' already exists."
    read -p "Do you want to delete and recreate it? (y/N): " recreate

    if [[ "$recreate" =~ ^[Yy]$ ]]; then
        echo "Deleting existing Service Principal..."
        az ad sp delete --id "$existingSP"
        echo "✓ Deleted existing Service Principal"
    else
        echo "Error: Cannot proceed with existing Service Principal. Please use a different name or delete it manually."
        exit 1
    fi
fi

# Create Service Principal
echo "Creating new Service Principal with Contributor role..."
sp=$(az ad sp create-for-rbac --name "$ServicePrincipleName" --role Contributor --scopes /subscriptions/$subscriptionId)

AppId=$(echo $sp | jq -r '.appId')
Password=$(echo $sp | jq -r '.password')
Tenant=$(echo $sp | jq -r '.tenant')

echo "✓ Service Principal created successfully"
echo ""
echo "Service Principal Details:"
echo "  AppId: $AppId"
echo "  Password: ********"
echo "  Tenant: $Tenant"
echo ""

# Set GitHub Secrets
echo "Setting GitHub Secrets..."
echo ""

gh secret set ARM_CLIENT_ID --body "$AppId"
echo "✓ Set ARM_CLIENT_ID"

gh secret set ARM_CLIENT_SECRET --body "$Password"
echo "✓ Set ARM_CLIENT_SECRET"

gh secret set ARM_TENANT_ID --body "$Tenant"
echo "✓ Set ARM_TENANT_ID"

gh secret set ARM_SUBSCRIPTION_ID --body "$subscriptionId"
echo "✓ Set ARM_SUBSCRIPTION_ID"

echo ""
echo "========================================="
echo "✅ Setup Complete!"
echo "========================================="
echo ""
echo "GitHub Secrets have been configured for:"
gh repo view --json nameWithOwner -q .nameWithOwner
echo ""
echo "You can now use the Terraform GitHub Actions workflow."
echo ""
echo "To test locally, export these environment variables:"
echo ""
echo "export ARM_CLIENT_ID=\"$AppId\""
echo "export ARM_CLIENT_SECRET=\"$Password\""
echo "export ARM_TENANT_ID=\"$Tenant\""
echo "export ARM_SUBSCRIPTION_ID=\"$subscriptionId\""
echo ""
