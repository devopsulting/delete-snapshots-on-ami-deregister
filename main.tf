terraform {
  required_version = ">=1.5.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.72.0"
    }
  }
  backend "s3" {
    bucket = "terraform-state-files-0110"
    key    = "delete-orphan-snapshots/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "tf_state_file_locking" # The table must have a partition key named LockID with type of String. If not configured, state locking will be disabled.
  }
}
provider "aws" {
  region = var.aws_region
}

resource "aws_iam_role" "lambda_role" {
  name               = "terraform_orphan_snapshots_delete_role"
  assume_role_policy = <<EOF
    {
    "Version": "2012-10-17",
    "Statement": [
        {
        "Action": "sts:AssumeRole",
        "Principal": {
            "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
        }
    ]
    }
EOF
}

resource "aws_iam_policy" "iam_policy_for_lambda" {
    name = "terraform_orphan_snapshots_delete_policy"
    path = "/"
    policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:*:*:*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeVolumeStatus",
                    "ec2:DescribeSnapshots",
                    "ec2:DeleteSnapshot"
                ],
                "Resource": "*"
            }
        ]
        
    }
    EOF
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
    role = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/python/orphan-snapshots-delete.py"
  output_path = "${path.module}/python/orphan-snapshots-delete.zip"
}

resource "aws_lambda_function" "lambda_function" {
    filename = "${path.module}/python/orphan-snapshots-delete.zip"
    function_name = "orphan-snapshots-delete"
    role = aws_iam_role.lambda_role.arn
    handler = "orphan-snapshots-delete.lambda_handler"
    runtime = "python3.12"
    timeout = 30
    depends_on = [
      aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role
    ]
}

output "terraform_aws_role_output" {
    value = aws_iam_role.lambda_role.name
}

output "terraform_aws_lambda_role_arn_outpur" {
    value = aws_iam_role.lambda_role.arn
}