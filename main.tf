terraform {
  required_version = "1.0.10"
  required_providers {
    aws = {
      version = "3.63.0"
    }
    kubernetes = {
      version = "2.5.1"
    }
    eventstorecloud = {
      source  = "EventStore/eventstorecloud"
      version = "~>1.5.0"
    }
  }
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "FastFinTech"
    workspaces {
      name = "FFT-Signals"
    }
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
      "0.0.0.0/0" # TODO: Remove
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
      "0.0.0.0/0" # TODO: Remove
    ]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.10.0"

  name                 = "signals-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/signals" = "shared"
    "kubernetes.io/role/elb"        = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/signals"   = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "eks" {
  source                          = "terraform-aws-modules/eks/aws"
  cluster_name                    = "signals"
  cluster_version                 = "1.17"
  subnets                         = module.vpc.public_subnets # TODO: Change this back to private subnets after solving connectivity to redis
  version                         = "17.22.0"
  cluster_create_timeout          = "1h"
  cluster_endpoint_private_access = true

  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t2.small"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
  ]

  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
  map_roles                            = var.map_roles
  map_users                            = var.map_users
  map_accounts                         = var.map_accounts
}
