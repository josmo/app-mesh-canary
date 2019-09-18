terraform {
  required_version = "= 0.12.7"
}

provider "aws" {
  region  = "us-west-2"
  version = "~> 2.28.1"
}
resource "aws_service_discovery_private_dns_namespace" "simpleapp" {
  name = "local"
  vpc = module.vpc-core.vpc_id
}
resource "aws_appmesh_mesh" "mesh" {
  name = "app-mesh"
  spec {
    egress_filter {
      type = "ALLOW_ALL"
    }
  }
}
//resource "aws_appmesh_virtual_router" "api_vr" {
//  name      = "api-vr"
//  mesh_name = aws_appmesh_mesh.mesh.id
//  spec {
//    listener {
//      port_mapping {
//        port     = 80
//        protocol = "http"
//      }
//    }
//  }
//}
//resource "aws_appmesh_route" "api_route" {
//  name                = "api-route"
//  mesh_name           = aws_appmesh_mesh.mesh.id
//  virtual_router_name = aws_appmesh_virtual_router.api_vr.name
//  spec {
//
//    tcp_route {
//      action {
//        weighted_target {
//          virtual_node = aws_appmesh_virtual_node.api_1.name
//          weight = 1
//        }
//      }
//    }
//
//  }
//}


//resource "aws_appmesh_virtual_service" "api" {
//  mesh_name = aws_appmesh_mesh.mesh.id
//  name = "api.${aws_service_discovery_private_dns_namespace.simpleapp.name}"
//  spec {
//    provider {
//      //      virtual_node {
//      //        virtual_node_name = aws_appmesh_virtual_node.api_1.name
//      //      }
//      virtual_router {
//        virtual_router_name = aws_appmesh_virtual_router.api_vr.name
//      }
//    }
//  }
//}

resource "aws_appmesh_virtual_node" "gateway" {
  name      = "gateway"
  mesh_name = aws_appmesh_mesh.mesh.id
  spec {
    logging {
      access_log {
        file {
          path = "/dev/stdout"
        }
      }
    }
//    backend {
//      virtual_service {
//        virtual_service_name = aws_appmesh_virtual_service.api.name
//      }
//    }

    listener {
      health_check {
        path = "/"
        port = 9999
        healthy_threshold = 5
        interval_millis = 30000
        protocol = "http"
        timeout_millis = 5000
        unhealthy_threshold = 2
      }
      port_mapping {
        port     = 9999
        protocol = "http"
      }
    }
    service_discovery {
      dns {
        hostname = "gateway.${aws_service_discovery_private_dns_namespace.simpleapp.name}"
      }
    }
  }
}

//resource "aws_appmesh_virtual_node" "api_1" {
//  name      = "api-1"
//  mesh_name = aws_appmesh_mesh.mesh.id
//  spec {
//    logging {
//      access_log {
//        file {
//          path = "/dev/stdout"
//        }
//      }
//    }
//    listener {
//      health_check {
//        path = "/"
//        port = 80
//        healthy_threshold = 5
//        interval_millis = 30000
//        protocol = "http"
//        timeout_millis = 5000
//        unhealthy_threshold = 2
//      }
//      port_mapping {
//        port     = 80
//        protocol = "http"
//      }
//    }
//    service_discovery {
//      dns {
//        hostname = "api.${aws_service_discovery_private_dns_namespace.simpleapp.name}"
//      }
//    }
//  }
//}

module "vpc-core" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "2.15.0"
  name                 = "app-mesh-canary"
  enable_dns_hostnames = "true"
  enable_dns_support   = "true"
  enable_appmesh_envoy_management_endpoint = true
  appmesh_envoy_management_endpoint_security_group_ids = [aws_security_group.lb.id]
  cidr                 = "10.30.0.0/16"
  azs = [
    "us-west-2a",
    "us-west-2b",
    "us-west-2c",
  ]
  public_subnets = [
    "10.30.0.0/24",
    "10.30.1.0/24",
    "10.30.2.0/24",
  ]
  private_subnets = [
    "10.30.10.0/24",
    "10.30.11.0/24",
    "10.30.12.0/24",
  ]
  tags = {
    Owner       = "app-mesh"
    Environment = terraform.workspace
  }
}
module "hosts" {
  source = "./ec2-ecs"
  cluster_name = aws_ecs_cluster.main.name
  security_group = aws_security_group.lb.id
  subnets = list(module.vpc-core.public_subnets[0],module.vpc-core.public_subnets[1],module.vpc-core.public_subnets[2])
  type = "public"
}

module "hostsprivate" {
  source = "./ec2-ecs"
  cluster_name = aws_ecs_cluster.main.name
  security_group = aws_security_group.lb.id
  subnets = list(module.vpc-core.private_subnets[0],module.vpc-core.private_subnets[1],module.vpc-core.private_subnets[2])
  type = "private"
}

resource "aws_iam_role" "ecs-service-role" {
  name                = "ecs-service-role"
  path                = "/"
  assume_role_policy  = data.aws_iam_policy_document.ecs-service-policy.json
}

resource "aws_iam_role_policy_attachment" "ecs-service-role-attachment" {
  role       = aws_iam_role.ecs-service-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

data "aws_iam_policy_document" "ecs-service-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}




resource "aws_security_group" "lb" {
  name        = "tf-ecs-alb"
  description = "controls access to the ALB"
  vpc_id      = module.vpc-core.vpc_id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "tf-ecs-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = module.vpc-core.vpc_id

  ingress {
    protocol        = "-1"
    from_port       = 0
    to_port         = 0
    security_groups = [aws_security_group.lb.id]
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//resource "aws_alb" "main" {
//  name            = "tf-ecs-api-load"
//  subnets         = [data.terraform_remote_state.infra_base.outputs.subneta,data.terraform_remote_state.infra_base.outputs.subnetb,data.terraform_remote_state.infra_base.outputs.subnetc]
//  security_groups = [aws_security_group.lb.id]
//}

//resource "aws_alb_target_group" "app" {
//  name        = "tf-ecs-chat"
//  port        = 80
//  protocol    = "HTTP"
//  vpc_id      = data.terraform_remote_state.infra_base.outputs.vpc_id
//  target_type = "ip"
//}

//resource "aws_alb_listener" "front_end" {
//  load_balancer_arn = aws_alb.main.id
//  port              = "80"
//  protocol          = "HTTP"
//
//  default_action {
//    target_group_arn = aws_alb_target_group.app.id
//    type             = "forward"
//  }
//}

resource "aws_cloudwatch_log_group" "ecs_log" {
  name = "ecs-log"
  retention_in_days = 3
}

resource "aws_ecs_cluster" "main" {
  name = "tf-ecs-cluster"
}
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecs-task-exec-role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
  POLICY
}
resource "aws_iam_role_policy" "ecs_role_policy" {
  name   = "ecs-task-exec-policy"
  role   = aws_iam_role.ecs_task_execution.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": {
    "Effect": "Allow",
    "Action": "*",
    "Resource": ["*"]
  }
}
POLICY
}
resource "aws_ecs_task_definition" "gateway" {
  family                   = "gateway"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE", "EC2"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn = aws_iam_role.ecs_task_execution.arn
  proxy_configuration {
    type = "APPMESH"
    container_name = "envoy"
    properties = {
      AppPorts         = 9999
      EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
      IgnoredUID       = 1337
      ProxyEgressPort  = 15001
      ProxyIngressPort = 15000
    }
  }
//freeflyer/wetty
  container_definitions = <<DEFINITION
[
  {
    "cpu": 125,
    "image": "freeflyer/wetty",
    "memory": 256,
    "name": "app",
    "networkMode": "awsvpc",
    "essential" : true,
    "environment": [
    { "name": "WETTY_PORT", "value": "9999"}
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.ecs_log.name}",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "gateway"
        }
      },
    "dependsOn" : [{ "containerName" : "envoy", "condition": "HEALTHY"}],
    "portMappings": [
      {
        "containerPort": 9999,
        "hostPort": 9999
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
    { "name": "APPMESH_VIRTUAL_NODE_NAME", "value": "mesh/${aws_appmesh_mesh.mesh.name}/virtualNode/${aws_appmesh_virtual_node.gateway.name}"},
    {
      "name": "ENABLE_ENVOY_XRAY_TRACING",
      "value": "1"
    },
    {
      "name": "ENABLE_ENVOY_STATS_TAGS",
      "value": "1"
    }
    ],
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
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.ecs_log.name}",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "gateway-envoy"
        }
      },
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
      "awslogs-group": "${aws_cloudwatch_log_group.ecs_log.name}",
      "awslogs-region": "us-west-2",
      "awslogs-stream-prefix": "gateway-xray"
    }
  }
}
]
DEFINITION
}
resource "aws_service_discovery_service" "gateway" {
  name = "gateway"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.simpleapp.id
    dns_records {
      ttl = 10
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }

}

resource "aws_ecs_service" "gateway" {
  name            = "tf-ecs-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = 1
  launch_type     = "EC2"
  network_configuration {
//    assign_public_ip = true
    security_groups = [aws_security_group.ecs_tasks.id]
    subnets         = [module.vpc-core.private_subnets[0],module.vpc-core.private_subnets[1],module.vpc-core.private_subnets[2]]
  }
  service_registries {
    registry_arn = aws_service_discovery_service.gateway.arn
  }
//  load_balancer {
//    target_group_arn = aws_alb_target_group.app.arn
//    container_name   = "app"
//    container_port   = 80
//  }
//
//  depends_on = [
//    aws_alb_listener.front_end,
//  ]
  depends_on = [aws_service_discovery_service.gateway]
}




//module "api_1" {
//  source = "./api"
//  name = "api"
//  mesh = aws_appmesh_mesh.simple.name
//  mesh_node = aws_appmesh_virtual_node.api_1.name
////  image = "tutum/hello-world"
//  image = "karthequian/helloworld:latest"
//  log_name = aws_cloudwatch_log_group.ecs_log.name
//  task_exec_arn = aws_iam_role.ecs_task_execution.arn
//  namespace_id = aws_service_discovery_private_dns_namespace.simpleapp.id
//  cluster_id = aws_ecs_cluster.main.id
//  task_sg_id = aws_security_group.ecs_tasks.id
//  subnets = list(data.terraform_remote_state.infra_base.outputs.subneta,data.terraform_remote_state.infra_base.outputs.subnetb,data.terraform_remote_state.infra_base.outputs.subnetc)
//}

//module "api_2" {
//  source = "./api"
//  name = "api-2"
//  mesh = aws_appmesh_mesh.simple.name
//  mesh_node =  aws_appmesh_virtual_node.api_2.name
//  image = "karthequian/helloworld:latest"
////  image = "tutum/hello-world"
//  log_name = aws_cloudwatch_log_group.ecs_log.name
//  task_exec_arn = aws_iam_role.ecs_task_execution.arn
//  namespace_id = aws_service_discovery_private_dns_namespace.simpleapp.id
//  cluster_id = aws_ecs_cluster.main.id
//  task_sg_id = aws_security_group.ecs_tasks.id
//  subnets = list(data.terraform_remote_state.infra_base.outputs.subneta,data.terraform_remote_state.infra_base.outputs.subnetb,data.terraform_remote_state.infra_base.outputs.subnetc)
//}




