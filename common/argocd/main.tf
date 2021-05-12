resource "helm_release" "this" {
  chart      = var.chart_name
  name       = var.name
  namespace  = var.k8s_namespace
  repository = var.chart_repository
  version    = var.chart_version
  values     = concat(local.chart_values, var.chart_values)

  depends_on = [kubernetes_secret.argocd]
}

data "github_repository" "source" {
  for_each = var.github_repositories

  name = each.value.name
}

resource "github_repository_deploy_key" "this" {
  for_each = var.install_to_github ? var.github_repositories : {}

  key        = tls_private_key.this[each.key].public_key_openssh
  read_only  = true
  repository = each.value.name
  title      = "Argo CD"
}

resource "github_repository_webhook" "this" {
  for_each = var.install_to_github ? var.github_repositories : {}

  events     = ["push"]
  repository = each.value.name

  configuration {
    content_type = "json"
    secret       = random_id.github_secret.hex
    url          = "https://${var.host}/api/webhook"
  }
}

resource "tls_private_key" "this" {
  for_each = var.github_repositories

  algorithm = "RSA"
}

resource "kubernetes_secret" "argocd" {
  metadata {
    name      = "argocd-secret"
    namespace = var.k8s_namespace

    labels = {
      "app.kubernetes.io/name" : "argocd-secret"
      "app.kubernetes.io/part-of" : "argocd"
    }
  }

  data = merge(
    {
      "server.secretkey"      = random_id.secret_key.b64_url
      "webhook.github.secret" = random_id.github_secret.hex
    },
    var.extra_secrets
  )
}

resource "kubernetes_secret" "github" {
  for_each = var.github_repositories

  metadata {
    name      = each.key
    namespace = var.k8s_namespace
  }

  data = {
    "id_rsa"     = tls_private_key.this[each.key].private_key_pem
    "id_rsa.pub" = tls_private_key.this[each.key].public_key_openssh
  }
}

resource "random_id" "secret_key" {
  byte_length = 32
}

resource "random_id" "github_secret" {
  byte_length = 32
}

locals {
  chart_values = [
    yamlencode({
      "configs" = {
        "secret" = {
          "createSecret" = false
        }
      }
      "dex" = {
        "enabled" = false
      }
      "server" = {
        "config" = {
          "admin.enabled" = "false"
          "repositories"  = yamlencode(local.repositories)
        }
        "extraArgs" = [
          "--insecure",
          "--rootpath",
          "/argocd",
          "--basehref",
          "/argocd",
        ]
        "rbacConfig" = {
          "policy.csv" = file("${path.module}/policy.csv")
        }
      }
    })
  ]

  repositories = [
    for name, repository in data.github_repository.source:
    {
      url = repository.ssh_clone_url
      sshPrivateKeySecret = {
        key = "id_rsa"
        name = name
      }
    }
  ]
}