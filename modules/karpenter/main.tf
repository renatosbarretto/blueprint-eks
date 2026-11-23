locals {
  discovery_tag = { "karpenter.sh/discovery" = var.cluster_name }

  # Componentes de plataforma rodam no NodePool "system" (on-demand, com taint).
  system_taint = { key = "CriticalAddonsOnly", value = "true", effect = "NoSchedule" }
}

# --- Tratamento de interrupção (Spot, rebalance, manutenção agendada, mudança de estado) ---

resource "aws_sqs_queue" "interruption" {
  name                      = local.queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid       = "AllowEventBridgeAndSQS"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

locals {
  interruption_events = {
    health_event = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
    }
    spot_interruption = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance_state_change = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name          = "${var.cluster_name}-karpenter-${replace(each.key, "_", "-")}"
  event_pattern = jsonencode(each.value)
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_events

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

# --- Controller ---

resource "kubernetes_namespace_v1" "karpenter" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = var.namespace
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  wait       = true
  timeout    = 600

  # Roda no Fargate (profile do namespace). CoreDNS também está no Fargate e sobe
  # antes (modules/eks), então dnsPolicy ClusterFirst funciona no primeiro boot.
  values = [
    yamlencode({
      replicas = var.replicas
      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = aws_sqs_queue.interruption.name
      }
      serviceAccount = {
        name = "karpenter"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.controller.arn
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.karpenter,
    aws_iam_role_policy.controller,
    aws_sqs_queue_policy.interruption,
  ]
}

resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiSelectorTerms = [
        { alias = var.ami_alias }
      ]
      # Instance profile do Terraform: o controller não precisa de iam:*InstanceProfile.
      instanceProfile            = aws_iam_instance_profile.node.name
      subnetSelectorTerms        = [{ tags = local.discovery_tag }]
      securityGroupSelectorTerms = [{ tags = local.discovery_tag }]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 1
        httpTokens              = "required"
      }
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "${var.root_volume_size_gib}Gi"
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]
      # default_tags do provider não chegam nas EC2 do Karpenter: replica aqui (custo/ownership).
      tags = var.tags
    }
  })

  # Destroy espera o finalizer (terminação das instâncias) antes de remover o controller.
  wait = true

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "nodepool_system" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "system"
    }
    spec = {
      weight = 10
      template = {
        metadata = {
          labels = { "node-role/system" = "true" }
        }
        spec = {
          taints = [local.system_taint]
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "kubernetes.io/arch", operator = "In", values = var.arch },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["5"] },
            # Mínimo 2 vCPU: com *.medium cada controller vira um nó e o overhead
            # dos DaemonSets (aws-node, kube-proxy, pod-identity, ebs-csi, ...) domina.
            { key = "karpenter.k8s.aws/instance-cpu", operator = "Gt", values = ["1"] },
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          expireAfter = "720h"
        }
      }
      limits = {
        cpu    = "32"
        memory = "128Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "10m"
        budgets             = [{ nodes = "1" }]
      }
    }
  })

  wait       = true
  depends_on = [kubectl_manifest.ec2nodeclass]
}

resource "kubectl_manifest" "nodepool_default" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = var.capacity_types },
            { key = "kubernetes.io/arch", operator = "In", values = var.arch },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["5"] },
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          expireAfter = "720h"
        }
      }
      limits = var.limits
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets             = [{ nodes = "10%" }]
      }
    }
  })

  wait       = true
  depends_on = [kubectl_manifest.ec2nodeclass]
}

# Piso de capacidade: garante 1 nó system on-demand para os addons de plataforma
# (EBS CSI, metrics-server, LBC, ...). Sem pod pendente o Karpenter não cria nó.
resource "kubernetes_namespace_v1" "bootstrap" {
  metadata {
    name = "karpenter-bootstrap"
    labels = {
      "app.kubernetes.io/name"       = "karpenter-bootstrap"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [kubectl_manifest.nodepool_system]
}

resource "kubernetes_deployment_v1" "bootstrap" {
  # checkov:skip=CKV_K8S_8: pause não serve tráfego; probes não se aplicam
  # checkov:skip=CKV_K8S_9: pause não serve tráfego; probes não se aplicam
  # checkov:skip=CKV_K8S_15: imagem com tag imutável; IfNotPresent evita pull a cada restart
  # checkov:skip=CKV_K8S_43: tag fixa da eks-distro; digest muda por arquitetura
  wait_for_rollout = false

  metadata {
    name      = "system-capacity-floor"
    namespace = kubernetes_namespace_v1.bootstrap.metadata[0].name
    labels = {
      app = "system-capacity-floor"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "system-capacity-floor"
      }
    }

    template {
      metadata {
        labels = {
          app = "system-capacity-floor"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        node_selector = {
          "karpenter.sh/nodepool" = "system"
        }

        toleration {
          key      = local.system_taint.key
          operator = "Exists"
          effect   = local.system_taint.effect
        }

        container {
          name  = "pause"
          image = "public.ecr.aws/eks-distro/kubernetes/pause:3.10"

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "10m"
              memory = "16Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 65535
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }

  depends_on = [kubectl_manifest.nodepool_system]
}

resource "null_resource" "wait_ready_node" {
  triggers = {
    nodepool  = kubectl_manifest.nodepool_system.id
    bootstrap = kubernetes_deployment_v1.bootstrap.id
  }

  # KUBECONFIG temporário: não altera o contexto do ~/.kube/config do operador.
  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG="$(mktemp)"
      trap 'rm -f "$KUBECONFIG"' EXIT
      aws eks update-kubeconfig --name "${var.cluster_name}" --region "${var.region}" >/dev/null
      echo "Aguardando >=1 nó Ready no NodePool system..."
      for i in $(seq 1 60); do
        ready="$(kubectl get nodes -l karpenter.sh/nodepool=system --no-headers 2>/dev/null | awk '$2=="Ready" {c++} END {print c+0}')"
        if [ "$${ready}" -ge 1 ]; then
          echo "Nó system Ready: $${ready}"
          exit 0
        fi
        sleep 15
      done
      echo "Timeout: nenhum nó Ready em 15m" >&2
      kubectl get nodes -o wide || true
      kubectl get nodeclaims -A || true
      kubectl -n karpenter-bootstrap get pods -o wide || true
      exit 1
    EOT
  }

  depends_on = [
    kubectl_manifest.nodepool_system,
    kubernetes_deployment_v1.bootstrap,
  ]
}
