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
