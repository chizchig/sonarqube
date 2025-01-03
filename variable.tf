variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "ingress_rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  description = "List of ingress rules for the security group"
}

variable "egress_rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  description = "List of egress rules for the security group"
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to the security group"
  default     = {}
}

variable "security_group_name" {
  type        = string
  description = "The name of the security group for ElastiCache"
}

variable "vpc_cidr_block" {
  type = string
}

variable "external_subnet_cidr_blocks" {
  type = list(string)
}

variable "internal_subnet_cidr_blocks" {
  type = list(string)
}


variable "region" {
  type = string
}