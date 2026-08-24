output "api_endpoint" {
  description = "Invoke URL of the HTTP API"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_id" {
  description = "HTTP API identifier"
  value       = aws_apigatewayv2_api.this.id
}

output "vpc_link_id" {
  description = "VPC Link identifier"
  value       = aws_apigatewayv2_vpc_link.this.id
}

output "nlb_arn" {
  description = "ARN of the internal NLB"
  value       = aws_lb.this.arn
}

output "nlb_dns_name" {
  description = "DNS name of the internal NLB — reachable only from inside the VPC"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "Target group pods are registered into via TargetGroupBinding"
  value       = aws_lb_target_group.this.arn
}

output "target_group_binding_manifest" {
  description = "Apply this (edited for your namespace/service) to register pods with the target group"
  value       = <<-YAML
    apiVersion: elbv2.k8s.aws/v1beta1
    kind: TargetGroupBinding
    metadata:
      name: ${var.name}
      namespace: default
    spec:
      serviceRef:
        name: my-service
        port: ${var.target_port}
      targetGroupARN: ${aws_lb_target_group.this.arn}
      targetType: ip
      networking:
        ingress:
          - from:
              - securityGroup:
                  groupID: ${aws_security_group.nlb.id}
            ports:
              - protocol: TCP
                port: ${var.target_port}
  YAML
}
