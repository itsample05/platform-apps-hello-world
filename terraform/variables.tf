variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "app_name" {
  type    = string
  default = "test"
}

variable "cluster_name" {
  type        = string
  description = "Shared ECS cluster name that can host multiple application services"
  default     = "platform-test-cluster"
}

variable "container_image" {
  type    = string
  default = "public.ecr.aws/nginx/nginx:latest"
}

variable "github_repository" {
  type        = string
  description = "owner/repository allowed to deploy"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
