variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "wordpress-ecs"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for SSL"
  type        = string
}

variable "wordpress_image" {
  description = "WordPress Docker image"
  type        = string
  default     = "wordpress:latest"
}

variable "microservice_image" {
  description = "Microservice Docker image (ECR repository)"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "wordpressdb"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "wpuser"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "wordpress_desired_count" {
  description = "Desired count of WordPress tasks"
  type        = number
  default     = 2
}

variable "microservice_desired_count" {
  description = "Desired count of microservice tasks"
  type        = number
  default     = 2
}
