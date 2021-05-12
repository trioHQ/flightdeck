module "operations_cluster" {
  source = "../../common/operations-platform"

  argocd_values     = concat(local.argocd_values, var.argocd_values)
  dex_extra_secrets = var.dex_extra_secrets
  dex_values        = var.dex_values
  host              = var.host

  cert_manager_values = concat(
    module.workload_values.cert_manager_values,
    var.cert_manager_values
  )

  external_dns_values = concat(
    module.workload_values.external_dns_values,
    var.external_dns_values
  )
}

module "workload_values" {
  source = "../workload-values"

  aws_namespace  = var.aws_namespace
  aws_tags       = var.aws_tags
  domain_filters = distinct(concat(var.domain_filters, [var.host]))
  k8s_namespace  = var.k8s_namespace
  oidc_issuer    = data.aws_ssm_parameter.oidc_issuer.value
}

module "argocd_service_account_role" {
  source = "../argocd-service-account-role"

  aws_namespace     = var.aws_namespace
  aws_tags          = var.aws_tags
  cluster_role_arns = var.cluster_role_arns
  k8s_namespace     = var.k8s_namespace
  oidc_issuer       = data.aws_ssm_parameter.oidc_issuer.value
}

data "aws_ssm_parameter" "oidc_issuer" {
  name = join("/", concat([""], var.aws_namespace, ["clusters", var.cluster_name, "oidc_issuer"]))
}

locals {
  argocd_values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.argocd_service_account_role.arn
        }
      }
    })
  ]
}
