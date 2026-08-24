# ─────────────────────────────────────────────────────────────────────────────
# API Gateway HTTP API → VPC Link → internal NLB → pods
#
# The NLB and its target group are owned by Terraform rather than by a
# Kubernetes Service annotation. That is deliberate: API Gateway's private
# integration needs a listener ARN at apply time, and a controller-created NLB
# does not exist until a Service is applied. Pods are attached to the target
# group afterwards with a TargetGroupBinding — see the
# `target_group_binding_manifest` output.
# ─────────────────────────────────────────────────────────────────────────────

# ── Security groups ──────────────────────────────────────────────────────────
# API Gateway's VPC Link ENIs sit in the private subnets and are the only
# source allowed to reach the NLB listener.
resource "aws_security_group" "vpc_link" {
  name        = "${var.name}-vpc-link"
  description = "API Gateway VPC Link ENIs"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpc-link" })
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_nlb" {
  security_group_id = aws_security_group.vpc_link.id
  description       = "VPC Link to the internal NLB listener"

  referenced_security_group_id = aws_security_group.nlb.id
  ip_protocol                  = "tcp"
  from_port                    = var.listener_port
  to_port                      = var.listener_port
}

resource "aws_security_group" "nlb" {
  name        = "${var.name}-nlb"
  description = "Internal NLB fronting cluster workloads"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-nlb" })
}

resource "aws_vpc_security_group_ingress_rule" "nlb_from_vpc_link" {
  security_group_id = aws_security_group.nlb.id
  description       = "Listener traffic from the API Gateway VPC Link"

  referenced_security_group_id = aws_security_group.vpc_link.id
  ip_protocol                  = "tcp"
  from_port                    = var.listener_port
  to_port                      = var.listener_port
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_pods" {
  security_group_id = aws_security_group.nlb.id
  description       = "NLB to pod IPs inside the VPC"

  cidr_ipv4   = var.vpc_cidr
  ip_protocol = "tcp"
  from_port   = var.target_port
  to_port     = var.target_port
}

# ── Internal NLB ─────────────────────────────────────────────────────────────
resource "aws_lb" "this" {
  name               = "${var.name}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.nlb.id]

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, { Name = "${var.name}-nlb" })
}

# target_type = "ip": the ALB controller registers pod IPs directly, so traffic
# skips kube-proxy and the extra hop through a node.
resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.target_port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  # Pods come and go constantly under Karpenter — drain fast
  deregistration_delay = var.deregistration_delay

  health_check {
    protocol            = var.health_check_protocol
    path                = var.health_check_protocol == "TCP" ? null : var.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = var.tags
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}

# ── HTTP API ─────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"
  description   = var.description

  dynamic "cors_configuration" {
    for_each = var.cors_configuration != null ? [var.cors_configuration] : []

    content {
      allow_origins = cors_configuration.value.allow_origins
      allow_methods = cors_configuration.value.allow_methods
      allow_headers = cors_configuration.value.allow_headers
      max_age       = cors_configuration.value.max_age
    }
  }

  tags = var.tags
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = var.name
  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  description = "Private integration to the internal NLB"

  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.this.arn

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.this.id

  timeout_milliseconds = var.integration_timeout_milliseconds
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = var.route_key
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"

  # JWT authorization at the edge — unauthenticated requests never reach the VPC
  authorization_type = var.jwt_authorizer != null ? "JWT" : "NONE"
  authorizer_id      = var.jwt_authorizer != null ? aws_apigatewayv2_authorizer.jwt[0].id : null
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  count = var.jwt_authorizer != null ? 1 : 0

  api_id           = aws_apigatewayv2_api.this.id
  name             = "${var.name}-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = var.jwt_authorizer.audience
    issuer   = var.jwt_authorizer.issuer
  }
}

# ── Stage ────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      path           = "$context.path"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
      latency        = "$context.responseLatency"
    })
  }

  # Always set a throttle — the default account limit is shared across every
  # API in the region, so one noisy API can starve the others.
  default_route_settings {
    throttling_rate_limit    = var.throttling_rate_limit
    throttling_burst_limit   = var.throttling_burst_limit
    detailed_metrics_enabled = true
  }

  tags = var.tags
}
