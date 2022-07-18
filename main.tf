provider "aws" {
  region = "eu-west-1"
}

data "aws_organizations_organization" "this" {}

locals {
  all_accounts_names            = [for account in toset(data.aws_organizations_organization.this.accounts) : account.name]
  all_accounts_map              = zipmap(local.all_accounts_names, tolist(toset(data.aws_organizations_organization.this.accounts)))
  non_management_accounts_names = [for account in toset(data.aws_organizations_organization.this.non_master_accounts) : account.name]
  non_management_accounts_map   = zipmap(local.non_management_accounts_names, tolist(toset(data.aws_organizations_organization.this.non_master_accounts)))
}

module "sso" {
  source = "kayode/sso/aws"
  permission_sets = {
    AdministratorAccess = {
      description      = "Provides full access to AWS services and resources.",
      session_duration = "PT2H",
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    },
    ViewOnlyAccess = {
      description      = "View resources and basic metadata across all AWS services.",
      session_duration = "PT2H",
      managed_policies = ["arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"]
    },
    PowerUserAccess = {
      description      = "View resources and basic metadata across all AWS services.",
      managed_policies = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    },
    EKSAdminAccess = {
      description = "Allow full EKS and read only access across all AWS resources.",
      # Can use Managed Policies and Inline policies in the same permission set
      managed_policies = ["arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"]
      inline_policy    = data.aws_iam_policy_document.EKSAdmin.json
      tags             = { "foo" = "bar" },
    }
  }
  account_assignments = [
    {
      principal_name = "management"
      principal_type = "GROUP"
      permission_set = "AdministratorAccess"
      account_ids    = [for account in local.all_accounts_map : account.id]
    },
    {
      principal_name = "admins"
      principal_type = "GROUP"
      permission_set = "AdministratorAccess"
      account_ids    = [for account in local.non_management_accounts_map : account.id]
    },
    {
      principal_name = "forbes"
      principal_type = "USER"
      permission_set = "PowerUserAccess"
      account_ids    = [for account in local.non_management_accounts_map : account.id if contains(var.security_accounts, account.name)]
    },
    {
      principal_name = "developers"
      principal_type = "GROUP"
      permission_set = "ViewOnlyAccess"
      account_ids    = [for account in local.non_management_accounts_map : account.id if contains(var.developer_readonly_accounts, account.name)]
    },
    {
      principal_name = "developers"
      principal_type = "GROUP"
      permission_set = "EKSAdminAccess"
      account_ids    = [for account in local.non_management_accounts_map : account.id if contains(var.developer_workload_accounts, account.name)]
    },
  ]
}

data "aws_iam_policy_document" "EKSAdmin" {
  statement {
    sid       = "AllowEKS"
    actions   = ["eks:*"]
    resources = ["*"]
  }
  statement {
    sid       = "AllowPassRole"
    actions   = ["iam:PassRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com"]
    }
  }
}