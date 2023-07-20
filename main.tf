terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.1"
    }
  }
}

variable "slack_webhook_url" {
  description = "The Slack webhook URL"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "s3_bucket" {
  description = "The S3 bucket where the zipped Lambda function will be uploaded"
  type        = string
  default     = "ec2-slack-notification"
}

provider "aws" {
  region = var.region
}

data "aws_organizations_organization" "current_org" {}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir = "./lambda_code"
  output_path = "${path.module}/ec2_slack_notification.zip"
}

# S3 bucket to hold the lambda code

resource "aws_s3_bucket_object" "object" {
  bucket = var.s3_bucket
  key    = "ec2_slack_notification.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = filemd5(data.archive_file.lambda_zip.output_path)
}

# IAM Resources

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com",
        },
        Effect = "Allow",
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaExecute"
}

resource "aws_iam_role_policy" "lambda_ec2_query_policy" {
  name = "lambda_ec2_query_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ec2:Describe*"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# CloudFormation Resources

resource "aws_cloudformation_stack_set" "organization_stack_set" {
  name = "EC2 Slack Notification"

  #call_as = "DELEGATED_ADMIN"
  permission_model = "SERVICE_MANAGED"

  parameters = {
    ParameterKey   = "SlackWebhookURL"
    ParameterValue = var.slack_webhook_url
    UsePreviousValue = false
  }

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description = "EC2 Slack Notification using Lambda and CloudWatch Event"
    Parameters = {
      SlackWebhookURL = {
        Description = "The Slack webhook URL"
        Type = "String"
      }
    }
    Resources = {
      MyLambdaFunction = {
        Type = "AWS::Lambda::Function"
        Properties = {
          Handler = "index.handler"
          Role = aws_iam_role.lambda_role.arn
          Code = {
            S3Bucket = var.s3_bucket
            S3Key = aws_s3_bucket_object.object.key
          }
          Runtime = "python3.8"
          Environment = {
            Variables = {
              SLACK_WEBHOOK_URL = {
                Ref = "SlackWebhookURL"
              }
            }
          }
        }
      }
      MyCloudWatchEventRule = {
        Type = "AWS::Events::Rule"
        Properties = {
          ScheduleExpression = "cron(0 9 * * ? *)"
          Targets = [{
            Arn = {
              "Fn::GetAtt" = ["MyLambdaFunction", "Arn"]
            }
            Id = "MyLambdaFunction"
          }]
        }
      }
      MyLambdaPermission = {
        Type = "AWS::Lambda::Permission"
        Properties = {
          Action = "lambda:InvokeFunction"
          Principal = "events.amazonaws.com"
          FunctionName = {
            "Fn::GetAtt" = ["MyLambdaFunction", "Arn"]
          }
          SourceArn = {
            "Fn::GetAtt" = ["MyCloudWatchEventRule", "Arn"]
          }
        }
      }
    }
  })
}

resource "aws_cloudformation_stack_set_instance" "stak_set_instance" {
  deployment_targets {
      organizational_unit_ids = [data.aws_organizations_organization.current_org.roots[0].id]
    }

  region         = var.region
  stack_set_name = aws_cloudformation_stack_set.organization_stack_set.name
}