# redis module outputs
# https://registry.terraform.io/modules/cloudposse/elasticache-redis/aws/latest?tab=outputs
# module.redis.endpoint
# module.redis.port

module "redis" {
  source             = "cloudposse/elasticache-redis/aws"
  version            = "0.40.1"
  name               = "signals.redis"
  namespace          = "signals"
  availability_zones = data.aws_availability_zones.available.names
  stage              = "staging" # or production, etc
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.private_subnets
  cluster_size       = 1
  instance_type      = "cache.t2.micro"
  apply_immediately  = true

  # (Not available for T1/T2 instances)
  automatic_failover_enabled = false

  #engine_version             = var.engine_version #default "4.0.10"
  #family                     = var.family #default "redis4.0"
  #at_rest_encryption_enabled = false # default is false

  #Route53 DNS Zone ID default ""
  #zone_id                    = var.zone_id 

  # default is true, but you need to see https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/in-transit-encryption.html#connect-tls to use it
  # this is required if you wanna use the auth_token property
  #transit_encryption_enabled = false 

  security_group_rules = [
    {
      type                     = "egress"
      from_port                = 0
      to_port                  = 65535
      protocol                 = "-1"
      cidr_blocks              = ["0.0.0.0/0"]
      source_security_group_id = null
      description              = "Allow all outbound traffic"
    },
    {
      type                     = "ingress"
      from_port                = 0
      to_port                  = 65535
      protocol                 = "-1"
      cidr_blocks              = []
      source_security_group_id = aws_security_group.worker_group_mgmt_one.id
      description              = "Allow all inbound traffic from trusted Security Groups"
    },
  ]

  parameter = [
    {
      name  = "notify-keyspace-events"
      value = "lK"
    }
  ]
}