# CAST AI AWS Integration Terraform Configuration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

# Variables
variable "castai_api_key" {
  description = "CAST AI API key"
  type        = string
  sensitive   = true
}

variable "castai_organization_id" {
  description = "CAST AI organization ID"
  type        = string
}

variable "aws_cast_user_arn" {
  description = "AWS CAST user ARN"
  type        = string
}

variable "integration_name" {
  description = "Name for the integration"
  type        = string
  default     = "AWS discovery"
}

variable "castai_api_url" {
  description = "CAST AI API URL"
  type        = string
  default     = "https://api.cast.ai"
}

variable "role_name" {
  description = "IAM role name"
  type        = string
  default     = "castai-discovery-role"
}

variable "castai_integration_scope" {
  description = "Integration scope: ALL or AWS_COMMITMENTS"
  type        = string
  default     = "ALL"
  
  validation {
    condition     = contains(["ALL", "AWS_COMMITMENTS"], var.castai_integration_scope)
    error_message = "Integration scope must be either 'ALL' or 'AWS_COMMITMENTS'."
  }
}

variable "commitments_import_status" {
  description = "Commitments import status"
  type        = string
  default     = "INACTIVE"
}

# Data sources
data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "current" {
  count = var.castai_integration_scope == "ALL" ? 1 : 0
}

data "aws_region" "current" {}

# Get organization roots using organizational units data source
data "aws_organizations_organizational_units" "roots" {
  count     = local.is_management_account ? 1 : 0
  parent_id = data.aws_organizations_organization.current[0].roots[0].id
}

# Local values
locals {
  is_management_account = var.castai_integration_scope == "ALL" && length(data.aws_organizations_organization.current) > 0 && data.aws_organizations_organization.current[0].master_account_id == data.aws_caller_identity.current.account_id
  
  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.aws_cast_user_arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.castai_organization_id
          }
        }
      }
    ]
  })

  commitments_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "savingsplans:Describe*",
          "savingsplans:List*",
          "ec2:DescribeReservedInstances",
          "ec2:DescribeReservedInstancesListings",
          "ec2:DescribeReservedInstancesModifications",
          "ec2:DescribeReservedInstancesOfferings",
          "organizations:ListAccounts",
          "organizations:DescribeOrganization",
          "account:ListRegions"
        ]
        Resource = "*"
      }
    ]
  })

  management_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "organizations:ListAccounts",
          "organizations:DescribeOrganization",
          "cloudformation:CreateStackSet",
          "cloudformation:UpdateStackSet",
          "cloudformation:DeleteStackSet",
          "cloudformation:DescribeStackSet",
          "cloudformation:ListStackInstances",
          "cloudformation:CreateStackInstances",
          "cloudformation:DeleteStackInstances",
          "cloudformation:UpdateStackInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for CAST AI Discovery
resource "aws_iam_role" "castai_discovery" {
  name               = var.role_name
  assume_role_policy = local.trust_policy

  tags = {
    Purpose = "CAST AI Discovery"
  }
}

# IAM Policy for AWS Commitments scope
resource "aws_iam_policy" "castai_commitments" {
  count = var.castai_integration_scope == "AWS_COMMITMENTS" ? 1 : 0

  name   = "castai-commitments-readonly-policy"
  policy = local.commitments_policy

  tags = {
    Purpose = "CAST AI Commitments Discovery"
  }
}

# IAM Policy for Management Account (org-scoped)
resource "aws_iam_policy" "castai_org_management" {
  count = local.is_management_account ? 1 : 0

  name   = "castai-org-management-policy"
  policy = local.management_policy

  tags = {
    Purpose = "CAST AI Organization Management"
  }
}

# Attach ReadOnlyAccess for ALL scope
resource "aws_iam_role_policy_attachment" "castai_readonly" {
  count = var.castai_integration_scope == "ALL" && !local.is_management_account ? 1 : 0

  role       = aws_iam_role.castai_discovery.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Attach custom commitments policy for AWS_COMMITMENTS scope
resource "aws_iam_role_policy_attachment" "castai_commitments" {
  count = var.castai_integration_scope == "AWS_COMMITMENTS" ? 1 : 0

  role       = aws_iam_role.castai_discovery.name
  policy_arn = aws_iam_policy.castai_commitments[0].arn
}

# Attach management policy for org-scoped integration
resource "aws_iam_role_policy_attachment" "castai_org_management" {
  count = local.is_management_account ? 1 : 0

  role       = aws_iam_role.castai_discovery.name
  policy_arn = aws_iam_policy.castai_org_management[0].arn
}

# CloudFormation StackSet for member account roles (org-scoped)
resource "aws_cloudformation_stack_set" "castai_member_roles" {
  count = local.is_management_account ? 1 : 0

  name             = "castai-discovery-roles"
  permission_model = "SERVICE_MANAGED"
  
  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  capabilities = ["CAPABILITY_NAMED_IAM"]

  parameters = {
    CastUserArn    = var.aws_cast_user_arn
    OrganizationId = var.castai_organization_id
  }

  template_body = var.castai_integration_scope == "ALL" ? jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "CAST AI discovery role for member accounts - ALL scope"
    Parameters = {
      CastUserArn = {
        Type        = "String"
        Description = "CAST AI user ARN"
      }
      OrganizationId = {
        Type        = "String"
        Description = "CAST AI organization ID"
      }
    }
    Resources = {
      CastDiscoveryRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "castai-discovery-role"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Principal = {
                  AWS = { Ref = "CastUserArn" }
                }
                Action = "sts:AssumeRole"
                Condition = {
                  StringEquals = {
                    "sts:ExternalId" = { Ref = "OrganizationId" }
                  }
                }
              }
            ]
          }
          ManagedPolicyArns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
        }
      }
    }
    Outputs = {
      RoleArn = {
        Description = "ARN of the created role"
        Value       = { "Fn::GetAtt" = ["CastDiscoveryRole", "Arn"] }
      }
    }
  }) : jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "CAST AI discovery role for member accounts - AWS_COMMITMENTS scope"
    Parameters = {
      CastUserArn = {
        Type        = "String"
        Description = "CAST AI user ARN"
      }
      OrganizationId = {
        Type        = "String"
        Description = "CAST AI organization ID"
      }
    }
    Resources = {
      CastDiscoveryRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "castai-discovery-role"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Principal = {
                  AWS = { Ref = "CastUserArn" }
                }
                Action = "sts:AssumeRole"
                Condition = {
                  StringEquals = {
                    "sts:ExternalId" = { Ref = "OrganizationId" }
                  }
                }
              }
            ]
          }
        }
      }
      CommitmentsPolicy = {
        Type = "AWS::IAM::Policy"
        Properties = {
          PolicyName = "castai-commitments-readonly-policy"
          Roles      = [{ Ref = "CastDiscoveryRole" }]
          PolicyDocument = {
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Action = [
                  "savingsplans:Describe*",
                  "savingsplans:List*",
                  "ec2:DescribeReservedInstances",
                  "ec2:DescribeReservedInstancesListings",
                  "ec2:DescribeReservedInstancesModifications",
                  "ec2:DescribeReservedInstancesOfferings",
                  "organizations:ListAccounts",
                  "organizations:DescribeOrganization",
                  "account:ListRegions"
                ]
                Resource = "*"
              }
            ]
          }
        }
      }
    }
    Outputs = {
      RoleArn = {
        Description = "ARN of the created role"
        Value       = { "Fn::GetAtt" = ["CastDiscoveryRole", "Arn"] }
      }
    }
  })

  lifecycle {
    ignore_changes = [administration_role_arn]
  }
}

# Deploy StackSet instances to all member accounts
resource "aws_cloudformation_stack_instances" "castai_member_roles" {
  count = local.is_management_account ? 1 : 0

  stack_set_name = aws_cloudformation_stack_set.castai_member_roles[0].name
  
  deployment_targets {
    organizational_unit_ids = data.aws_organizations_organization.current[0].roots[*].id
  }

  regions = [data.aws_region.current.name]

  operation_preferences {
    max_concurrent_percentage = 100
  }

  depends_on = [aws_cloudformation_stack_set.castai_member_roles]
}

# Create CAST AI Integration
resource "terraform_data" "castai_integration" {
  triggers_replace = [
    var.castai_api_key,
    var.castai_organization_id,
    aws_iam_role.castai_discovery.arn,
    var.castai_integration_scope,
    var.commitments_import_status
  ]

  provisioner "local-exec" {
    command = <<-EOT
      curl -X 'POST' \
        '${var.castai_api_url}/inventory/v1beta/organizations/${var.castai_organization_id}/cloud-asset-integrations' \
        -H 'accept: application/json' \
        -H 'X-API-Key: ${var.castai_api_key}' \
        -H 'Content-Type: application/json' \
        -d '{
          "enabled": true,
          "name": "${var.integration_name}",
          "provider": "AWS",
          "scope": "${var.castai_integration_scope}",
          "aws_credentials": {
            "assume_role_arn": "${aws_iam_role.castai_discovery.arn}"
          },
          "settings": {
            "commitments": {
              "defaultStatus": "${var.commitments_import_status}"
            }
          },
          "metadata": ${local.is_management_account ? 
            jsonencode({
              crossRoleUserArn   = var.aws_cast_user_arn
              organizationScope  = true
            }) : 
            jsonencode({
              crossRoleUserArn = var.aws_cast_user_arn
            })
          }
        }'
    EOT
  }

  depends_on = [
    aws_iam_role_policy_attachment.castai_readonly,
    aws_iam_role_policy_attachment.castai_commitments,
    aws_iam_role_policy_attachment.castai_org_management,
    aws_cloudformation_stack_instances.castai_member_roles
  ]
}

# Outputs
output "iam_role_arn" {
  description = "ARN of the created IAM role"
  value       = aws_iam_role.castai_discovery.arn
}

output "is_management_account" {
  description = "Whether this is an AWS Organizations management account"
  value       = local.is_management_account
}

output "integration_scope" {
  description = "Integration scope configured"
  value       = var.castai_integration_scope
}

output "stackset_created" {
  description = "Whether CloudFormation StackSet was created for org-wide deployment"
  value       = local.is_management_account
}