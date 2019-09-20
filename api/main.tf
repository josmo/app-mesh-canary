resource "aws_ecs_task_definition" "api" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE", "EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.task_exec_arn
  task_role_arn = var.task_arn
  proxy_configuration {
    type = "APPMESH"
    container_name = "envoy"
    properties = {
      AppPorts         = "80"
      EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
      IgnoredUID       = "1337"
      ProxyEgressPort  = "15001"
      ProxyIngressPort = "15000"
    }
  }
  container_definitions = data.template_file.container_definitions.rendered
}


resource "aws_service_discovery_service" "app" {
  name = var.name
  dns_config {
    namespace_id = var.namespace_id
    dns_records {
      ttl = 10
      type = "A"
    }
  }
}

resource "aws_ecs_service" "api" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = var.launch_type

  service_registries {
    registry_arn = aws_service_discovery_service.app.arn
  }
  network_configuration {
    assign_public_ip = true
    security_groups = [var.task_sg_id]
    subnets         = var.subnets
  }
}