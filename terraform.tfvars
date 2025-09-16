# terraform.tfvars.example
# Copy this file to terraform.tfvars and fill in your values

castai_api_key          = "your-castai-api-key"
castai_organization_id  = "your-organization-id"
aws_cast_user_arn      = "aws_cast_user_arn"

# Optional variables (defaults shown)
integration_name            = "AWS discovery"
castai_api_url             = "https://api.cast.ai"
role_name                  = "castai-discovery-role"
castai_integration_scope   = "ALL"  # or "AWS_COMMITMENTS"
commitments_import_status  = "INACTIVE"