resource "aws_ecs_task_definition" "api" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = 256
  memory                   = "512"
  execution_role_arn       = var.task_exec_arn
  task_role_arn = var.task_exec_arn
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

  container_definitions = <<DEFINITION
[
  {
    "image": "${var.image}",
    "name": "app",
    "networkMode": "awsvpc",
    "essential" : true,
    "dependsOn" : [{ "containerName" : "envoy", "condition": "HEALTHY"}],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${var.log_name}",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "${var.name}"
        }
      },
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80
      }
    ]
  },
  {
    "name": "envoy",
    "image": "111345817488.dkr.ecr.us-west-2.amazonaws.com/aws-appmesh-envoy:v1.11.1.1-prod",
    "user": "1337",
    "essential": true,
    "ulimits": [
     {
        "name": "nofile",
        "hardLimit": 15000,
        "softLimit": 15000
     }
    ],
    "environment": [
    { "name": "APPMESH_VIRTUAL_NODE_NAME", "value": "mesh/${var.mesh}/virtualNode/${var.mesh_node}"},
    { "name": "ENVOY_LOG_LEVEL", "value": "debug" },
    {
      "name": "ENABLE_ENVOY_XRAY_TRACING",
      "value": "1"
    },
    {
      "name": "ENABLE_ENVOY_STATS_TAGS",
      "value": "1"
    }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${var.log_name}",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "${var.name}-envoy"
        }
      },
    "portMappings": [
        {
          "containerPort": 9901,
          "hostPort": 9901,
          "protocol": "tcp"
        },
        {
          "containerPort": 15000,
          "hostPort": 15000,
          "protocol": "tcp"
        },
        {
          "containerPort": 15001,
          "hostPort": 15001,
          "protocol": "tcp"
        }
      ],

    "healthCheck": {
       "command": [ "CMD-SHELL", "curl -s http://localhost:9901/server_info | grep state | grep -q LIVE" ],
       "interval": 5,
       "retries": 3,
       "startPeriod": 10,
       "timeout": 2
     }
  },
{
  "name": "xray-daemon",
  "image": "amazon/aws-xray-daemon",
  "user": "1337",
  "essential": true,
  "cpu": 32,
  "memoryReservation": 256,
  "portMappings": [
    {
      "hostPort": 2000,
      "containerPort": 2000,
      "protocol": "udp"
    }
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "${var.log_name}",
      "awslogs-region": "us-west-2",
      "awslogs-stream-prefix": "${var.name}-xray"
    }
  }
}
]
DEFINITION
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
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_service" "api" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "EC2"
  service_registries {
    registry_arn = aws_service_discovery_service.app.arn
  }
  network_configuration {
//    assign_public_ip = true
    security_groups = [var.task_sg_id]
    subnets         = var.subnets
  }
}