variable "aws_region" {
  default     = "us-east-2"
  description = "AWS region"
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

#variable "container_registry" {
#  description = "Contains information to pull docker container images."
#  type = object({
#    host     = string
#    username = string
#    password = string
#  })
#  #sensitive = true
#}