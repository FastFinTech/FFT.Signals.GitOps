terraform {
  required_version = "1.0.11"
  required_providers {
    aws = {
      version = "3.63.0"
    }
    kubernetes = {
      version = "2.6.1"
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
  region = var.aws_region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.signals.endpoint
  token                  = data.aws_eks_cluster_auth.signals.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.signals.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.signals.certificate_authority.0.data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
      command     = "aws"
    }
  }
}

provider "eventstorecloud" {
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "aws_eks_cluster" "signals" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "signals" {
  name = local.cluster_name
}

locals {
  kubernetes_version   = "1.20"
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

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name                 = "signals-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = local.private_subnet_cidrs
  public_subnets       = local.public_subnet_cidrs
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "redis" {
  source  = "umotif-public/elasticache-redis/aws"
  version = "~> 2.1.0"

  name_prefix           = "signals"
  number_cache_clusters = 1
  node_type             = "cache.t3.small"

  engine_version           = "6.x"
  port                     = 6379
  maintenance_window       = "mon:03:00-mon:04:00"
  snapshot_window          = "04:00-06:00"
  snapshot_retention_limit = 7

  # automatic_failover_enabled = true
  at_rest_encryption_enabled = false
  transit_encryption_enabled = false
  # auth_token                 = "1234567890asdfghjkl"

  apply_immediately = true
  family            = "redis6.x"
  description       = "Signals elasticache redis."

  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]

  parameter = [
    {
      name  = "repl-backlog-size"
      value = "16384"
    }
  ]

  tags = {
  }
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

resource "aws_security_group" "worker_group_mgmt_two" {
  name_prefix = "worker_group_mgmt_two"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "192.168.0.0/16",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  vpc_id          = module.vpc.vpc_id
  cluster_name    = local.cluster_name
  cluster_version = local.kubernetes_version
  subnets         = module.vpc.public_subnets # TODO: change back to private
  enable_irsa     = true
  tags = {
  }


  workers_group_defaults = {
    root_volume_type = "gp2"
    public_ip        = true                      # TODO: remove
    subnets          = module.vpc.public_subnets # TODO: remove
  }

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t2.small"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 2
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
      public_ip                     = true                      # TODO: remove
      subnets                       = module.vpc.public_subnets # TODO: remove
    }
  ]
}

# # Almost worked, but created an internal load balancer
# module "alb_ingress_controller" {
#   source  = "iplabs/alb-ingress-controller/kubernetes"
#   version = "3.4.0"
#   #enabled = "true"

#   # providers = {
#   #   kubernetes = "eks"
#   # }

#   k8s_cluster_type = "eks"
#   k8s_namespace    = "kube-system"

#   aws_region_name  = var.aws_region
#   k8s_cluster_name = local.cluster_name
#   aws_alb_ingress_controller_version ="2.3.0"
# }

