terraform {
  required_version = "1.0.8"
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
}

# Get access to the effective Account ID, User ID, and ARN in which Terraform is authorized.
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "signals" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "signals" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
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

# Accept network peering request from Eventstore cloud
#resource "aws_vpc_peering_connection_accepter" "eventstore" {
#  vpc_peering_connection_id = var.eventstore_peering.vpc_peering_connection_id
#  auto_accept               = true
#  tags = {
#    Side = "Accepter"
#  }
#}

# Setup the route to the EventStore cloud in the routing tables that are associated with the public subnets
#resource "aws_route" "eventstore-public" {
#  #target = module.vpc
#  for_each                  = toset(module.vpc.public_route_table_ids)
#  route_table_id            = each.key
#  destination_cidr_block    = var.eventstore_peering.destination_cidr_block
#  vpc_peering_connection_id = var.eventstore_peering.vpc_peering_connection_id
#}

# Setup the route to the EventStore cloud in the routing tables that are associated with the private subnets
#resource "aws_route" "eventstore-private" {
#  for_each                  = toset(module.vpc.private_route_table_ids)
#  route_table_id            = each.key
#  destination_cidr_block    = var.eventstore_peering.destination_cidr_block
#  vpc_peering_connection_id = var.eventstore_peering.vpc_peering_connection_id
#}

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

# Equivalent to:
# kubectl create secret docker-registry my-secret --docker-server=DOCKER_REGISTRY_SERVER --docker-username=DOCKER_USER --docker-password=DOCKER_PASSWORD
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret#example-usage-docker-config
resource "kubernetes_secret" "container_registry" {
  metadata {
    name = "docker-cfg" # name of the secret as specified by "my-secret" in the command line above
  }

  data = {
    ".dockerconfigjson" = <<DOCKER
{
  "auths": {
    "${var.container_registry.host}": {
      "auth": "${base64encode("${var.container_registry.username}:${var.container_registry.password}")}"
    }
  }
}
DOCKER
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_deployment" "signalserver" {
  metadata {
    name = "signalserver"
    labels = {
      app = "signalserver"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "signalserver"
      }
    }
    template {
      metadata {
        labels = {
          app = "signalserver"
        }
      }
      spec {
        image_pull_secrets {
          name = "docker-cfg"
        }
        container {
          image = "ghcr.io/fastfintech/signalserver:latest" #latest tag also sets image_pull_policy = "Always"
          name  = "signalserver"
          env {
            name  = "EventStore__ConnectionString"
            value = local.eventstore_connection_string #output.eventstore_connectionstring #"esdb://${eventstorecloud_managed_cluster.signals.dns_name}:2113"
          }
          env {
            name  = "Redis__ConnectionString"
            value = local.redis_connection_string
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "signalserver" {
  metadata {
    name = "signalserver"
  }
  spec {
    selector = {
      app = "signalserver"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}