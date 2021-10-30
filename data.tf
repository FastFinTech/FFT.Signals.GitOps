# Get access to the effective Account ID, User ID, and ARN in which Terraform is authorized.
data "aws_caller_identity" "current" {}

# Get information related to the "signals" eks cluster
data "aws_eks_cluster" "signals" {
  name = module.eks.cluster_id
}

# Get information related to authorization for the "signals" eks cluster
data "aws_eks_cluster_auth" "signals" {
  name = module.eks.cluster_id
}

# Get information about aws availability zones for the region that the provider is currently configured for
data "aws_availability_zones" "available" {
}
