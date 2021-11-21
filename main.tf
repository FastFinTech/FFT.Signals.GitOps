terraform {
  required_version = "1.0.11"
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

provider "eventstorecloud" {
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {}

data "aws_eks_cluster" "signals" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "signals" {
  name = module.eks.cluster_id
}

# data "aws_eks_cluster" "signals" {
#   name = "signals"
# }

# data "aws_eks_cluster_auth" "signals" {
#   name = "signals"
# }

locals {
  cluster_name = "signals"
  public_subnet_cidrs     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  num_subnets             = min(length(local.public_subnet_cidrs), length(data.aws_availability_zones.available.names))
  # public_subnet_ids       = aws_subnet.signals_public.*.id
  # private_subnet_ids      = aws_subnet.signals_private.*.id
  # public_route_table_ids  = aws_route_table.signals_public.*.id
  # private_route_table_ids = aws_route_table.signals_private.*.id
  # redis_connection_string = "${aws_elasticache_cluster.signals.cache_nodes.0.address}:6379"
  redis_connection_string = "${module.redis.elasticache_replication_group_primary_endpoint_address}:6379"
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
  source = "umotif-public/elasticache-redis/aws"
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
  # at_rest_encryption_enabled = true
  # transit_encryption_enabled = true
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
    Project = "Test"
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
  cluster_name    = local.cluster_name
  cluster_version = "1.20"
  subnets         = module.vpc.private_subnets

  tags = {
  }

  vpc_id = module.vpc.vpc_id

  workers_group_defaults = {
    root_volume_type = "gp2"
  }

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t2.small"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 2
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
    {
      name                          = "worker-group-2"
      instance_type                 = "t2.medium"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_two.id]
    },
  ]
}

# resource "aws_vpc" "signals" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_support   = true
#   enable_dns_hostnames = true
#   tags = {
#     Name = "signals"
#   }
# }

# resource "aws_internet_gateway" "signals" {
#   vpc_id = aws_vpc.signals.id
#   tags = {
#     "Name" = "signals"
#   }
# }

# resource "aws_subnet" "signals_private" {
#   count                = local.num_subnets
#   vpc_id               = aws_vpc.signals.id
#   cidr_block           = element(local.private_subnet_cidrs, count.index)
#   availability_zone_id = element(data.aws_availability_zones.available.zone_ids, count.index)
#   tags = {
#     "Name"                            = "signals-private-${count.index}"
#     "kubernetes.io/cluster/signals"   = "shared"
#     "kubernetes.io/role/internal-elb" = "1"
#   }
# }

# resource "aws_subnet" "signals_public" {
#   count                   = local.num_subnets
#   vpc_id                  = aws_vpc.signals.id
#   cidr_block              = element(local.public_subnet_cidrs, count.index)
#   availability_zone_id    = element(data.aws_availability_zones.available.zone_ids, count.index)
#   map_public_ip_on_launch = true
#   tags = {
#     "Name"                          = "signals-public-${count.index}"
#     "kubernetes.io/cluster/signals" = "shared"
#     "kubernetes.io/role/elb"        = "1"
#   }
# }

# resource "aws_route_table" "signals_private" {
#   vpc_id = aws_vpc.signals.id
#   tags = {
#     "Name" = "signals-private"
#   }
# }

# resource "aws_route_table" "signals_public" {
#   vpc_id = aws_vpc.signals.id
#   tags = {
#     "Name" = "signals-public"
#   }
# }

# resource "aws_route_table_association" "signals_private" {
#   count          = local.num_subnets
#   subnet_id      = element(aws_subnet.signals_private.*.id, count.index)
#   route_table_id = element(aws_route_table.signals_private.*.id, count.index)
# }

# resource "aws_route_table_association" "signals_public" {
#   count          = local.num_subnets
#   subnet_id      = element(aws_subnet.signals_public.*.id, count.index)
#   route_table_id = element(aws_route_table.signals_public.*.id, count.index)
# }

# resource "aws_route" "public_internet_gateway" {
#   route_table_id         = aws_route_table.signals_public.id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_internet_gateway.signals.id
#   timeouts {
#     create = "5m"
#   }
# }

# resource "aws_route" "public_internet_gateway_ipv6" {
#   route_table_id              = aws_route_table.signals_public.id
#   destination_ipv6_cidr_block = "::/0"
#   gateway_id                  = aws_internet_gateway.signals.id
#   timeouts {
#     create = "5m"
#   }
# }

# resource "aws_elasticache_subnet_group" "signals" {
#   name       = "signals-redis-subnet"
#   subnet_ids = aws_subnet.signals_private.*.id
# }

# resource "aws_elasticache_cluster" "signals" {
#   cluster_id           = "signals"
#   engine               = "redis"
#   node_type            = "cache.t2.micro"
#   num_cache_nodes      = 1
#   parameter_group_name = "default.redis6.x"
#   engine_version       = "6.x"
#   port                 = 6379
#   availability_zone    = data.aws_availability_zones.available.names[0]
#   subnet_group_name    = aws_elasticache_subnet_group.signals.name
# }

# ###############################################
# #        EKS
# ###############################################

# resource "aws_iam_role" "eks" {
#   name = "eks-cluster-role"

#   assume_role_policy = <<POLICY
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Principal": {
#         "Service": "eks.amazonaws.com"
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
# POLICY
# }

# resource "aws_iam_role_policy_attachment" "eks1" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
#   role       = aws_iam_role.eks.name
# }

# resource "aws_iam_role_policy_attachment" "eks2" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
#   role       = aws_iam_role.eks.name
# }

# resource "aws_eks_cluster" "signals" {
#   name     = "signals"
#   role_arn = aws_iam_role.eks.arn

#   vpc_config {
#     subnet_ids = aws_subnet.signals_public.*.id
#   }

#   # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
#   # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
#   depends_on = [
#     aws_iam_role_policy_attachment.eks1,
#     aws_iam_role_policy_attachment.eks2,
#   ]
# }

# ## EKS Node Group

# resource "aws_iam_role" "signals-node" {
#   name = "signals-node"
#   assume_role_policy = jsonencode({
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = {
#         Service = "ec2.amazonaws.com"
#       }
#     }]
#     Version = "2012-10-17"
#   })
# }

# resource "aws_iam_role_policy_attachment" "signals-node-1" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
#   role       = aws_iam_role.signals-node.name
# }

# resource "aws_iam_role_policy_attachment" "signals-node-2" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
#   role       = aws_iam_role.signals-node.name
# }

# resource "aws_iam_role_policy_attachment" "signals-node-3" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#   role       = aws_iam_role.signals-node.name
# }


# resource "aws_eks_node_group" "signals" {
#   cluster_name    = aws_eks_cluster.signals.name
#   node_group_name = "signals"
#   node_role_arn   = aws_iam_role.signals-node.arn
#   subnet_ids      = local.public_subnet_ids # TODO: Go back to private when redis connection testing is finished.
#   instance_types  = ["t2.micro"]

#   scaling_config {
#     min_size     = 1
#     max_size     = 1
#     desired_size = 1
#   }

#   update_config {
#     max_unavailable = 1
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.signals-node-1,
#     aws_iam_role_policy_attachment.signals-node-2,
#     aws_iam_role_policy_attachment.signals-node-3,
#   ]
# }

resource "kubernetes_secret" "ghcr" {
  type = "kubernetes.io/dockerconfigjson"
  metadata {
    name = "ghcr" # name of the secret as specified by "my-secret" in the command line above
  }

  data = {
    ".dockerconfigjson" = <<DOCKER
{
  "auths": {
    "ghcr.io": {
      "auth":"${base64encode("${var.ghcr_username}:${var.ghcr_token}")}"
    }
  }
}
DOCKER
  }
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
          name = "ghcr"
        }
        container {
          image = "ghcr.io/fastfintech/signalserver:latest" # 'latest' tag also sets image_pull_policy = "Always"
          name  = "signalserver"
          env {
            name  = "EventStore__ConnectionString"
            value = local.eventstore_connection_string
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

