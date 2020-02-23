terraform {
  required_version = ">= 0.12.0"
  backend "s3" {
    bucket         = "eks-github-actions-terraform"
    key            = "terraform-dev.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "eks-github-actions-terraform-lock"
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "1.10.0"
}

locals {
  vpc_name             = "dev-vpc"
  vpc_cidr             = "10.42.0.0/16"
  private_subnets      = ["10.42.1.0/24", "10.42.2.0/24"]
  public_subnets       = ["10.42.11.0/24", "10.42.12.0/24"]
  cluster_name         = "dev-cluster"
  cluster_version      = "1.14"
  worker_group_name    = "worker-group-1"
  instance_type        = "t2.medium"
  asg_desired_capacity = 1
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
}

module "vpc" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc?ref=master"

  name                 = local.vpc_name
  cidr                 = local.vpc_cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = local.private_subnets
  public_subnets       = local.public_subnets
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

module "eks" {
  source           = "git::https://github.com/terraform-aws-modules/terraform-aws-eks?ref=master"
  cluster_name     = local.cluster_name
  cluster_version  = local.cluster_version
  vpc_id           = module.vpc.vpc_id
  subnets          = module.vpc.private_subnets
  write_kubeconfig = false

  worker_groups = [
    {
      name                 = local.worker_group_name
      instance_type        = local.instance_type
      asg_desired_capacity = local.asg_desired_capacity
    }
  ]

  map_accounts = var.map_accounts
  map_roles    = var.map_roles
  map_users    = var.map_users
}
