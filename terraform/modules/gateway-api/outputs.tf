output "gateway_api_namespace" {
  description = "Namespace of Gateway API / ALB controller."
  value       = "gateway-api-system"
}

output "controller_role_arn" {
  description = "IAM role ARN of the AWS Load Balancer Controller."
  value       = aws_iam_role.gateway_api_controller.arn
}
