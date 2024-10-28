terraform {
  required_version = ">=1.5.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.72.0"
    }
  }
  backend "s3" {
    bucket         = "terraform-state-files-0110"
    key            = "delete-snapshot-on-ami-deregister/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf_state_file_locking" # The table must have a partition key named LockID with type of String. If not configured, state locking will be disabled.
  }
}
provider "aws" {
  region = var.aws_region
}

resource "aws_iam_role" "lambda_role" {
  name               = "terraform_delete_snapshot_on_ami_deregister_role"
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
  name   = "terraform_delete_snapshot_on_ami_deregister_policy"
  path   = "/"
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
                    "ec2:Describe*",
                    "ec2:DeleteSnapshot"
                ],
                "Resource": "*"
            }
        ]
        
    }
    EOF
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/python/delete-snapshot-on-ami-deregister.py"
  output_path = "${path.module}/python/delete-snapshot-on-ami-deregister.zip"
}

resource "aws_lambda_function" "lambda_function" {
  filename      = "${path.module}/python/delete-snapshot-on-ami-deregister.zip"
  function_name = "delete-snapshot-on-ami-deregister"
  role          = aws_iam_role.lambda_role.arn
  handler       = "delete-snapshot-on-ami-deregister.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  depends_on = [
    aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role
  ]
}

resource "aws_cloudwatch_event_rule" "rule" {
  name          = "ami-termination-event-capture"
  description   = "Capture AMI termination event"
  event_pattern = <<EOF
      {
        "source": ["aws.ec2"],
        "detail-type": ["EC2 AMI State Change"],
        "detail": {
          "State": ["deregistered"]
        }
      }
      EOF
}

resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.rule.name
  target_id = "delete-snapshot-on-ami-deregister"
  arn       = aws_lambda_function.lambda_function.arn
  depends_on = [ aws_cloudwatch_event_rule.rule, aws_lambda_function.lambda_function ]
}

resource "aws_lambda_permission" "trigger" {
  statement_id = "AllowExecustionFromEventbridge"
  action       = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal    = "events.amazonaws.com"
  source_arn   = aws_cloudwatch_event_rule.rule.arn
  depends_on = [ aws_cloudwatch_event_rule.rule, aws_lambda_function.lambda_function ]
}

output "terraform_aws_role_output" {
  value = aws_iam_role.lambda_role.name
}

output "terraform_aws_lambda_role_arn_outpur" {
  value = aws_iam_role.lambda_role.arn
}
