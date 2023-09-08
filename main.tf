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


resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "ec2-slack-notification-code-"
}

resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.bucket.id
  key    = "ec2_slack_notification.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = filemd5(data.archive_file.lambda_zip.output_path)
}

# CloudFormation Resources

resource "aws_cloudformation_stack_set" "organization_stack_set" {
  name = "EC2-Slack-Notification"

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
      "DeploymentLambdaRole": {
        "Type": "AWS::IAM::Role",
        "Properties": {
          "AssumeRolePolicyDocument": {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Principal": {
                  "Service": [
                    "lambda.amazonaws.com"
                  ]
                },
                "Action": [
                  "sts:AssumeRole"
                ]
              }
            ]
          },
          "Path": "/",
          "ManagedPolicyArns": [
            "arn:aws:iam::aws:policy/service-role/AWSLambdaExecute"
          ],
          "Policies": [
            {
              "PolicyName": "LambdaExecutionPolicy",
              "PolicyDocument": {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Effect": "Allow",
                    "Action": [
                      "ec2:Describe*"
                    ],
                    "Resource": [
                      "*"
                    ]
                  }
                ]
              }
            }
          ]
        }
      EC2NotifierLambdaFunction = {
        Type = "AWS::Lambda::Function"
        Properties = {
          Handler = "slack_notifier.lambda_handler"
          Role = { "Fn::GetAtt": [ "NotificationLambdaRole", "Arn"] },
          Code = {
            S3Bucket = aws_s3_bucket.bucket.id
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
      CloudWatchEventRule = {
        Type = "AWS::Events::Rule"
        Properties = {
          ScheduleExpression = "cron(0 9 * * ? *)"
          Targets = [{
            Arn = {
              "Fn::GetAtt" = ["EC2NotifierLambdaFunction", "Arn"]
            }
            Id = "EC2NotifierLambdaFunction"
          }]
        }
      }
      MyLambdaPermission = {
        Type = "AWS::Lambda::Permission"
        Properties = {
          Action = "lambda:InvokeFunction"
          Principal = "events.amazonaws.com"
          FunctionName = {
            "Fn::GetAtt" = ["EC2NotifierLambdaFunction", "Arn"]
          }
          SourceArn = {
            "Fn::GetAtt" = ["CloudWatchEventRule", "Arn"]
          }
        }
      }
    }
  })
}

resource "aws_cloudformation_stack_set_instance" "stack_set_instance" {
  deployment_targets {
      organizational_unit_ids = [data.aws_organizations_organization.current_org.roots[0].id]
    }

  region         = var.region
  stack_set_name = aws_cloudformation_stack_set.organization_stack_set.name
}
