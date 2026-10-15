# -----------------------------------------------------------------------------
# SQS queue for Karpenter interruption handling (Spot, Rebalance, Health, State)
# O controller exige que a fila exista; sem ela ocorre: NonExistentQueue
# -----------------------------------------------------------------------------

locals {
  # Nome completo da fila: base-interruption (melhor identificação e alinhado a boas práticas)
  interruption_queue_name_full = "${coalesce(var.interruption_queue_name, var.cluster_name)}-interruption"
}

resource "aws_sqs_queue" "interruption" {
  name                       = local.interruption_queue_name_full
  message_retention_seconds  = 300
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  tags = merge(var.tags, {
    "ClusterName" = var.cluster_name
  })
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid    = "AllowEventBridgeSendMessage"
    effect = "Allow"
    actions = [
      "sqs:SendMessage"
    ]
    resources = [aws_sqs_queue.interruption.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for rule in aws_cloudwatch_event_rule.interruption : rule.arn]
    }
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    actions = [
      "sqs:*"
    ]
    resources = [aws_sqs_queue.interruption.arn]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.url
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

# -----------------------------------------------------------------------------
# EventBridge rules: encaminham eventos de interrupção para a fila SQS
# -----------------------------------------------------------------------------

locals {
  interruption_events = {
    spot_interrupt = {
      description = "EC2 Spot Instance Interruption Warning"
      detail_type = "EC2 Spot Instance Interruption Warning"
      source      = "aws.ec2"
    }
    instance_rebalance = {
      description = "EC2 Instance Rebalance Recommendation"
      detail_type = "EC2 Instance Rebalance Recommendation"
      source      = "aws.ec2"
    }
    instance_state_change = {
      description = "EC2 Instance State-change Notification"
      detail_type = "EC2 Instance State-change Notification"
      source      = "aws.ec2"
    }
    health_event = {
      description = "AWS Health Event"
      detail_type = "AWS Health Event"
      source      = "aws.health"
    }
  }
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name        = "${var.cluster_name}-karpenter-${each.key}"
  description = "Karpenter interrupt: ${each.value.description}"
  event_pattern = jsonencode({
    source      = [each.value.source]
    detail-type = [each.value.detail_type]
  })

  tags = merge(var.tags, {
    "ClusterName" = var.cluster_name
  })
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_events

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}
