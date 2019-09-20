terraform {
  required_version = "= 0.12.7"
}

provider "aws" {
  region  = "us-west-2"
  version = "~> 2.28.1"
}

resource "aws_service_discovery_private_dns_namespace" "simpleapp" {
  name = var.namespace
  vpc = module.vpc-core.vpc_id
}
resource "aws_appmesh_mesh" "mesh" {
  name = var.mesh_name
  spec {
    egress_filter {
      type = "ALLOW_ALL"
    }
  }
}
resource "aws_appmesh_virtual_router" "api_vr" {
  name      = "api-vr"
  mesh_name = aws_appmesh_mesh.mesh.id
  spec {
    listener {
      port_mapping {
        port     = 80
        protocol = "http"
      }
    }
  }
}
resource "aws_appmesh_route" "api_route" {
  name                = "api-route"
  mesh_name           = aws_appmesh_mesh.mesh.id
  virtual_router_name = aws_appmesh_virtual_router.api_vr.name
  spec {
    http_route {
      match {
        prefix = "/"
      }
      action {
        weighted_target {
          virtual_node = aws_appmesh_virtual_node.api_2.name
          weight = 1
        }
//        weighted_target {
//          virtual_node = aws_appmesh_virtual_node.api_2.name
//          weight = 5
//        }
      }
    }
  }
}

resource "aws_appmesh_virtual_service" "api" {
  mesh_name = aws_appmesh_mesh.mesh.id
  name = "api.${aws_service_discovery_private_dns_namespace.simpleapp.name}"
  spec {
    provider {
          virtual_router {
            virtual_router_name = aws_appmesh_virtual_router.api_vr.name
          }
    }
  }
}







module "vpc-core" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "2.15.0"
  name                 = "app-mesh-canary"
  enable_dns_hostnames = "true"
  enable_dns_support   = "true"
  cidr                 = "10.30.0.0/16"
  azs = [
    "us-west-2a",
    "us-west-2b",
  ]
  public_subnets = [
    "10.30.0.0/24",
    "10.30.1.0/24",
  ]
  // TODO: add if testing out the ec2 ECS with private subnets (You'll need some proxy from the public subnet)
//  private_subnets = [
//    "10.30.10.0/24",
//    "10.30.11.0/24",
//  ]
  tags = {
    Owner       = "app-mesh"
    Environment = terraform.workspace
  }
}
// FOR EC2 backed
//module "hosts" {
//  source = "./ec2-ecs"
//  cluster_name = aws_ecs_cluster.main.name
//  security_group = aws_security_group.lb.id
//  subnets = list(module.vpc-core.public_subnets[0],module.vpc-core.public_subnets[1])
//  type = "public"
//}
//
//module "hostsprivate" {
//  source = "./ec2-ecs"
//  cluster_name = aws_ecs_cluster.main.name
//  security_group = aws_security_group.lb.id
//  subnets = list(module.vpc-core.private_subnets[0],module.vpc-core.private_subnets[1])
//  type = "private"
//}

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



// TODO: put back on only 80 once everything works
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

// TODO: only allows the security group from the load balancer
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

// TODO: add back to the gateway - disabled while testing since it just gets in a bad loop if the gateway task has issuess
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

// Task iam and execution roles
resource "aws_iam_role" "task_iam_role" {
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Principal": {
        "Service": ["ecs-tasks.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
  POLICY
}
resource "aws_iam_role_policy_attachment" "task_iam_policy_cw" {
  role = aws_iam_role.task_iam_role.id
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}
resource "aws_iam_role_policy_attachment" "task_iam_policy_xray" {
  role = aws_iam_role.task_iam_role.id
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
resource "aws_iam_role_policy_attachment" "task_iam_policy_envoy" {
  role = aws_iam_role.task_iam_role.id
  policy_arn = "arn:aws:iam::aws:policy/AWSAppMeshEnvoyAccess"
}
resource "aws_iam_role_policy_attachment" "task_iam_policy_appmesh" {
  role = aws_iam_role.task_iam_role.id
  policy_arn = "arn:aws:iam::aws:policy/AWSAppMeshFullAccess"
}


resource "aws_iam_role" "ecs_task_execution" {
  name = "ecs-task-exec-role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["sts:AssumeRole"],
      "Principal": {
        "Service": ["ecs-tasks.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
  POLICY
}
resource "aws_iam_role_policy" "ecs_task_execution_policy" {
  name   = "ecs-task-exec-policy"
  role   = aws_iam_role.ecs_task_execution.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": {
    "Effect": "Allow",
    "Action": [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "appmesh:*"
    ],
    "Resource": ["*"]
  }
}
POLICY
}

// Gateway node
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
    backend {
      virtual_service {
        virtual_service_name = aws_appmesh_virtual_service.api.name
      }
    }
    listener {
      port_mapping {
        port     = 80
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

module "gateway" {
  source = "./api"
  name = "gateway"
  mesh = aws_appmesh_mesh.mesh.name
  mesh_node = aws_appmesh_virtual_node.gateway.name
  image = var.gateway_image
  log_name = aws_cloudwatch_log_group.ecs_log.name
  task_exec_arn = aws_iam_role.ecs_task_execution.arn
  task_arn = aws_iam_role.task_iam_role.arn
  namespace_id = aws_service_discovery_private_dns_namespace.simpleapp.id
  cluster_id = aws_ecs_cluster.main.id
  task_sg_id = aws_security_group.ecs_tasks.id
  subnets = list(module.vpc-core.public_subnets[0],module.vpc-core.public_subnets[1])
  launch_type = "FARGATE"
}

// api node-1
resource "aws_appmesh_virtual_node" "api_1" {
  name      = "api"
  mesh_name = aws_appmesh_mesh.mesh.id
  spec {
    logging {
      access_log {
        file {
          path = "/dev/stdout"
        }
      }
    }
    listener {
      health_check {
        path = "/"
        port = 80
        healthy_threshold = 2
        interval_millis = 30000
        protocol = "http"
        timeout_millis = 5000
        unhealthy_threshold = 2
      }
      port_mapping {
        port     = 80
        protocol = "http"
      }
    }
    service_discovery {
      dns {
        hostname = "api.${aws_service_discovery_private_dns_namespace.simpleapp.name}"
      }
    }
  }
}
module "api_1" {
  source = "./api"
  name = "api"
  mesh = aws_appmesh_mesh.mesh.name
  mesh_node = aws_appmesh_virtual_node.api_1.name
  image = var.node_1_image
  log_name = aws_cloudwatch_log_group.ecs_log.name
  task_exec_arn = aws_iam_role.ecs_task_execution.arn
  task_arn = aws_iam_role.task_iam_role.arn
  namespace_id = aws_service_discovery_private_dns_namespace.simpleapp.id
  cluster_id = aws_ecs_cluster.main.id
  task_sg_id = aws_security_group.ecs_tasks.id
  subnets = list(module.vpc-core.public_subnets[0],module.vpc-core.public_subnets[1])
  launch_type = "FARGATE"
}

// api node-2
resource "aws_appmesh_virtual_node" "api_2" {
  name      = "api-2"
  mesh_name = aws_appmesh_mesh.mesh.id
  spec {
    logging {
      access_log {
        file {
          path = "/dev/stdout"
        }
      }
    }
    listener {
      health_check {
        path = "/"
        port = 80
        healthy_threshold = 2
        interval_millis = 30000
        protocol = "http"
        timeout_millis = 5000
        unhealthy_threshold = 2
      }
      port_mapping {
        port     = 80
        protocol = "http"
      }
    }
    service_discovery {
      dns {
        hostname = "api-2.${aws_service_discovery_private_dns_namespace.simpleapp.name}"
      }
    }
  }
}
module "api_2" {
  source = "./api"
  name = "api-2"
  mesh = aws_appmesh_mesh.mesh.name
  mesh_node =  aws_appmesh_virtual_node.api_2.name
  image = var.node_2_image
  log_name = aws_cloudwatch_log_group.ecs_log.name
  task_exec_arn = aws_iam_role.ecs_task_execution.arn
  task_arn = aws_iam_role.task_iam_role.arn
  namespace_id = aws_service_discovery_private_dns_namespace.simpleapp.id
  cluster_id = aws_ecs_cluster.main.id
  task_sg_id = aws_security_group.ecs_tasks.id
  subnets = list(module.vpc-core.public_subnets[0],module.vpc-core.public_subnets[1])
  launch_type = "FARGATE"
}




