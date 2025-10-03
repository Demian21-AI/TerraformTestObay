# Agenda: Day 3: CI/CD with GitHub Actions & DevOps Integration

## Automating Terraform

### Authenticating to Azure using Service Principle

1. Use backend for state storage (because we want to share state between runs)
2. Use service principle (because we can't log in interactively from a script running automatically)
3. Use --auto-approve (because we can't interactively answer yes)

#### Create Service Principle and Authenticate to Azure

```bash
# Create Service Principle
az account list | jq
subscriptionName="Obay Lab - Sandbox Subscription" # Change to your subscription name
echo "Setting subscription to: $subscriptionName"
az account set --subscription $subscriptionName
az account show | jq
subscriptionId=$(az account show | jq -r '.id')
echo "Subscription ID: $subscriptionId"
ServicePrincipleName="TerraformSP"
echo "Service Principle Name: $ServicePrincipleName"
sp=$(az ad sp create-for-rbac --name $ServicePrincipleName --role Contributor --scopes /subscriptions/$subscriptionId)
echo "Service Principle:"
AppId=$(echo $sp | jq -r '.appId')
Password=$(echo $sp | jq -r '.password')
Tenant=$(echo $sp | jq -r '.tenant')
echo "AppId: $AppId"
echo "Password: $Password"
echo "Tenant: $Tenant"

# Authenticate using Service Principle
az login --service-principal \
  --username "$AppId" \
  --password $Password \
  --tenant $Tenant
```

### Terraform Environment Variables
```bash
export ARM_CLIENT_ID=$AppId
export ARM_CLIENT_SECRET=$Password
export ARM_TENANT_ID=$Tenant
export ARM_SUBSCRIPTION_ID=$subscriptionId
echo "Environment variables set for Terraform"
terraform init
terraform plan -out=tfplan
terraform apply -auto-approve tfplan
terraform destroy -auto-approve
```

### Set GitHub Actions Secrets
1. Navigate to your GitHub repository.
2. Go to `Settings` > `Secrets and variables` > `Actions`.
3. Click on `New repository secret`.
4. Add the following secrets:
   - `ARM_CLIENT_ID`: Your Service Principal AppId
   - `ARM_CLIENT_SECRET`: Your Service Principal Password
   - `ARM_TENANT_ID`: Your Tenant ID
   - `ARM_SUBSCRIPTION_ID`: Your Subscription ID
5. (Optional) Add `TF_VAR_location` if you want to specify a location for your resources.
6. (Optional) Add `TF_VAR_resource_group_name` if you want to specify a resource group name.
7. (Optional) Add `TF_VAR_storage_account_name` if you want to specify a storage account name.

Command line approach:
```bashgh
gh secret set ARM_CLIENT_ID --body $AppId
gh secret set ARM_CLIENT_SECRET --body $Password
gh secret set ARM_TENANT_ID --body $Tenant
gh secret set ARM_SUBSCRIPTION_ID --body $subscriptionId
```
