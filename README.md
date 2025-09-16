# CAST AI AWS Integration Terraform

This Terraform configuration automates the setup of AWS integration with CAST AI, replacing the original bash script with Infrastructure as Code.

## Features

- **Account-scoped Integration**: Creates IAM roles in the current AWS account
- **Organization-scoped Integration**: Creates IAM roles across all AWS Organization member accounts using CloudFormation StackSets
- **Scope Support**: Supports both `ALL` (ReadOnlyAccess) and `AWS_COMMITMENTS` (custom policy) scopes
- **Automatic Detection**: Automatically detects if running in AWS Organizations management account
- **API Integration**: Creates the integration in CAST AI via API call

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform installed** (>= 1.0)
3. **CAST AI account** with API key and organization ID
4. **AWS Organizations** (optional, for org-scoped deployments)

## Required AWS Permissions

### For Account-scoped Integration:
- `iam:CreateRole`
- `iam:GetRole`
- `iam:UpdateAssumeRolePolicy`
- `iam:CreatePolicy`
- `iam:GetPolicy`
- `iam:AttachRolePolicy`
- `iam:ListAttachedRolePolicies`

### For Organization-scoped Integration (Management Account):
- All account-scoped permissions plus:
- `organizations:ListAccounts`
- `organizations:DescribeOrganization`
- `organizations:ListRoots`
- `cloudformation:CreateStackSet`
- `cloudformation:UpdateStackSet`
- `cloudformation:DescribeStackSet`
- `cloudformation:CreateStackInstances`
- `cloudformation:ListStackInstances`

## Usage

1. **Clone/Copy the configuration files**

2. **Create terraform.tfvars**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan the deployment**:
   ```bash
   terraform plan
   ```

5. **Apply the configuration**:
   ```bash
   terraform apply
   ```

## Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `castai_api_key` | CAST AI API key | - | Yes |
| `castai_organization_id` | CAST AI organization ID | - | Yes |
| `aws_cast_user_arn` | AWS CAST user ARN | - | Yes |
| `integration_name` | Name for the integration | "AWS discovery" | No |
| `castai_api_url` | CAST AI API URL | "https://api.cast.ai" | No |
| `role_name` | IAM role name | "castai-discovery-role" | No |
| `castai_integration_scope` | Integration scope | "ALL" | No |
| `commitments_import_status` | Commitments import status | "INACTIVE" | No |

## Integration Scopes

### ALL Scope
- Attaches AWS managed `ReadOnlyAccess` policy
- Provides comprehensive read access to AWS resources
- Suitable for full cost optimization and resource discovery

### AWS_COMMITMENTS Scope
- Creates custom policy for Savings Plans and Reserved Instances
- Limited to commitment-related resources only
- Suitable for commitment optimization only

## Organization vs Account Scope

The configuration automatically detects if you're running in an AWS Organizations management account:

- **Management Account**: Creates organization-scoped integration with CloudFormation StackSets
- **Regular Account**: Creates account-scoped integration

## Outputs

- `iam_role_arn`: ARN of the created IAM role
- `is_management_account`: Whether this is a management account
- `integration_scope`: The configured integration scope
- `stackset_created`: Whether StackSet was created

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Note**: For organization-scoped deployments, this will also remove the StackSet and all member account roles.

## Differences from Bash Script

1. **Idempotent**: Terraform ensures resources are created only if they don't exist
2. **State Management**: Terraform tracks resource state for updates and cleanup
3. **Validation**: Input validation for scope values
4. **Dependencies**: Proper resource dependency management
5. **Outputs**: Structured outputs for integration details

## Troubleshooting

### Common Issues

1. **API Key Permissions**: Ensure your CAST AI API key has sufficient permissions
2. **AWS Organizations**: Verify you have the required Organizations permissions
3. **StackSet Deployment**: CloudFormation StackSet deployment can take time; check AWS console for progress
4. **Policy Conflicts**: If roles already exist, Terraform will update them to match the configuration

### Debugging

Enable Terraform debug logging:
```bash
export TF_LOG=DEBUG
terraform apply
```

### Manual Verification

After deployment, verify:
1. IAM role exists: `aws iam get-role --role-name castai-discovery-role`
2. Integration in CAST AI console
3. For org deployments: Check CloudFormation StackSets in AWS console