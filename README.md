# Overview

Inspired by [this blog post](https://nivleshc.wordpress.com/2021/06/27/use-aws-lambda-to-send-slack-notifications-for-running-amazon-ec2-instances/), but it has been extended to use terraform to automate the deployment across an organization.  

This repository contains terraform to deploy a lambda function across an organization.  
Each day, the lambda function is executed and it will get a list of running EC2 instances and some metadata on each instance, and post a message to the slack channel.  
This is to assist with keeping an eye on the number of running EC2 instances within an organization for cost purposes.   

# Installation instructions


## Slack instructions

* In your Slack Workspace, create a Slack channel where the notifications from the AWS Lambda function will be published (ie `aws-notifications`).
* Next, we need to create a Slack App. This will enable us to publish notifications from our AWS Lambda function.
* Go to https://api.slack.com/apps?new_app=1 and click Create New App.
* In the next screen, click From scratch.
* In the next screen, give your App a name (ie `monitoring-bot`) and pick the Workspace you want to develop your app in (choose the Workspace that you created above). Click Create App.
* In the next screen, in the left-hand side menu, Basic Information should be selected. In the right-hand side screen, click Incoming Webhooks.
* In the next screen, use the slider beside Activate Incoming Webhooks to turn it on.
* Scroll down the page and click Add New Webhook to Workspace.
* In the next screen, select the channel that you created above, for the App to publish new messages into. Click Allow.
* You will be returned to the previous screen. Confirm that the left-hand side menu has Incoming Webhooks selected. The newly created webhook will be visible in the right-hand side screen under Webhook URL. Click the Copy button under Webhook URL and save it for later use.

## AWS Instructions

* Configure the aws cli with a profile for the organization's managment account (or for a delegated admin account for CloudFormation StackSet)
* Set the `AWS_PROFILE` environment variable to the above profile name (not required if it is the default profile)
* Activate [trusted access](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-activate-trusted-access.html) for CloudFormation. This allows the stack to deployed across an organization without having to provision roles that allow cross-acccount access into each of the organization's member accounts.

## Terraform instructions


* Install [terraform cli](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
* Run `terraform init`
* Run `terraform apply`
* Input the Slack webhook URL
* Answer `yes` (or specify `-auto-approve` in the previous command) when asked if you are happy with the plan

## Notes

* Slack Webhooks do not support authentication. If you need more control over who can post to your Slack channel, you might want to consider using a Slack App with a bot token, which would allow you to use OAuth 2.0 bearer token for authentication. Note that this is a more complex solution and may not be necessary depending on your use case.
* The security of Slack webhooks comes from the obscurity and complexity of the URL itself. Anyone who possesses the webhook URL can post a message to the associated Slack channel. 
* The StackSet can be deployed from an account in the organization that is a delegated admin for CloudFormation StackSet. If you wish to do so then uncomment the `call_as = "DELEGATED_ADMIN"` line in `main.tf`.
