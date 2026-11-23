output "karpenter_role_arn" {
  value = aws_iam_role.controller.arn
}

output "node_instance_profile_name" {
  value = aws_iam_instance_profile.node.name
}

output "node_role_name" {
  value = aws_iam_role.node.name
}

output "interruption_queue_name" {
  value = aws_sqs_queue.interruption.name
}

output "system_nodepool" {
  description = "Use nodeSelector karpenter.sh/nodepool=system + toleration CriticalAddonsOnly para componentes de plataforma."
  value       = "system"
}
