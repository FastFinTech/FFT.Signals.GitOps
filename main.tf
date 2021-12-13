terraform {
  required_version = "1.0.11"
  required_providers {
    aws = {
      version = "3.63.0"
    }
    kubernetes = {
      version = "2.6.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.13.1"
    }
    eventstorecloud = {
      source  = "EventStore/eventstorecloud"
      version = "~>1.5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.4.1"
    }
  }
  backend "remote" {
    organization = "FastFinTech"
    workspaces {
      name = "fft-signals"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.signals.endpoint
  token                  = data.aws_eks_cluster_auth.signals.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.signals.endpoint
  token                  = data.aws_eks_cluster_auth.signals.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.signals.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.signals.token
    # load_config_file       = false
    # exec {
    #   api_version = "client.authentication.k8s.io/v1alpha1"
    #   args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    #   command     = "aws"
    # }
  }
}

provider "eventstorecloud" {
  organization_id = var.esc_org_id
  token           = var.esc_token
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "aws_eks_cluster" "signals" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "signals" {
  name = module.eks.cluster_id
}

locals {
  kubernetes_version   = "1.21"
  cluster_name         = "signals"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  num_subnets          = min(length(local.public_subnet_cidrs), length(data.aws_availability_zones.available.names))
  # public_subnet_ids       = aws_subnet.signals_public.*.id
  # private_subnet_ids      = aws_subnet.signals_private.*.id
  # public_route_table_ids  = aws_route_table.signals_public.*.id
  # private_route_table_ids = aws_route_table.signals_private.*.id
  # redis_connection_string = "${aws_elasticache_cluster.signals.cache_nodes.0.address}:6379"
  redis_connection_string      = "${module.redis.elasticache_replication_group_primary_endpoint_address}:6379"
  eventstore_connection_string = "esdb://${eventstorecloud_managed_cluster.signals.dns_name}:2113"
}

