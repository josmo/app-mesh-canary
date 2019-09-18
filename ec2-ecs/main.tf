resource "aws_iam_role" "ecs-instance-role" {
  name                = "ecs-instance-role-${var.type}"
  path                = "/"
  assume_role_policy  = data.aws_iam_policy_document.ecs_instance_policy.json
}

data "aws_iam_policy_document" "ecs_instance_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile-${var.type}"
  path = "/"
  role = aws_iam_role.ecs-instance-role.name
}

resource "aws_iam_role_policy" "ecs_instance_policy" {
  name   = "ecs_instance_policy"
  role   = aws_iam_role.ecs-instance-role.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": {
    "Effect": "Allow",
    "Action": [
                  "ecs:CreateCluster",
                  "ecs:DeregisterContainerInstance",
                  "ecs:DiscoverPollEndpoint",
                  "ecs:Poll",
                  "ecs:RegisterContainerInstance",
                  "ecs:StartTelemetrySession",
                  "ecs:Submit*",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents",
                  "ecr:BatchCheckLayerAvailability",
                  "ecr:BatchGetImage",
                  "ecr:GetDownloadUrlForLayer",
                  "ecr:GetAuthorizationToken",
                  "ssm:DescribeAssociation",
                  "ssm:GetDeployablePatchSnapshotForInstance",
                  "ssm:GetDocument",
                  "ssm:GetManifest",
                  "ssm:GetParameters",
                  "ssm:ListAssociations",
                  "ssm:ListInstanceAssociations",
                  "ssm:PutInventory",
                  "ssm:PutComplianceItems",
                  "ssm:PutConfigurePackageResult",
                  "ssm:UpdateAssociationStatus",
                  "ssm:UpdateInstanceAssociationStatus",
                  "ssm:UpdateInstanceInformation",
                  "ec2messages:AcknowledgeMessage",
                  "ec2messages:DeleteMessage",
                  "ec2messages:FailMessage",
                  "ec2messages:GetEndpoint",
                  "ec2messages:GetMessages",
                  "ec2messages:SendReply",
                  "cloudwatch:PutMetricData",
                  "ec2:DescribeInstanceStatus",
                  "ds:CreateComputer",
                  "ds:DescribeDirectories",
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:DescribeLogGroups",
                  "logs:DescribeLogStreams",
                  "logs:PutLogEvents",
                  "s3:PutObject",
                  "s3:GetObject",
                  "s3:AbortMultipartUpload",
                  "s3:ListMultipartUploadParts",
                  "s3:ListBucket",
                  "s3:ListBucketMultipartUploads"
      ],
    "Resource": ["*"]
  }
}
POLICY
}
resource "aws_launch_configuration" "ecs-launch-config" {
  image_id = "ami-0e434a58221275ed4"
  instance_type = "t3.medium"
  iam_instance_profile = aws_iam_instance_profile.ecs_instance_profile.name
  key_name = "drone"
  root_block_device {
    volume_size = 30
    delete_on_termination = true
  }
  security_groups = [var.security_group]
  associate_public_ip_address = "true"
  user_data = <<EOF
    #!/bin/bash
    echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config
    EOF

}
resource "aws_autoscaling_group" "ecs-autoscaling-group" {
  name                        = "auto-scalling-ecs-${var.type}"
  max_size                    = "1"
  min_size                    = "1"
  desired_capacity            = "1"
  vpc_zone_identifier         = var.subnets
  launch_configuration        = aws_launch_configuration.ecs-launch-config.name
  health_check_type           = "ELB"
}