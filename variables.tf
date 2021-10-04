variable "region" {
  default     = "us-east-2"
  description = "AWS region"
}

variable "cluster_name" {
  description = "Name of the EKS master nodes (control plane) cluster."
  default     = "eks-signals"
}

variable "eventstore_peering" {
  description = "Values describing the network peering connection for the eventstore cloud database."
  type = object({
    vpc_peering_connection_id = string
    destination_cidr_block    = string
  })
  default = {
    vpc_peering_connection_id = "pcx-0cd9271fe520fc5c5"
    destination_cidr_block    = "172.29.98.0/24"
  }
}

variable "eventstore_connection_string" {
  description = "Connection string for the EventStore db."
  type        = string
  default     = "esdb://c5alb55o0aem0po049fg.mesdb.eventstore.cloud:2113"
}

variable "map_accounts" {
  description = "Additional AWS account numbers to add to the aws-auth configmap."
  type        = list(string)
  default = [
  ]
}

variable "map_roles" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = [
  ]
}

variable "map_users" {
  description = "Additional IAM users to add to the aws-auth configmap."
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))

  default = [
  ]
}

variable "container_registry" {
  description = "Contains information to pull docker container images."
  type = object({
    host     = string
    username = string
    password = string
  })
  #sensitive = true
}