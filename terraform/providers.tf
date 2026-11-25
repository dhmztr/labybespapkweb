terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "unter"
}

variable "domain_name" {
  type        = string
  description = "Publiczna domena aplikacj"
}

variable "alert_email" {
  type        = string
  description = "Adres e-mail do alertow kosztow (AWS Budgets)"
}
