import os
import json
import boto3
import requests
from datetime import datetime, timedelta

def send_slack_message(slack_webhook_url, slack_message):
  print('>send_slack_message:slack_message:'+slack_message)

  slack_payload = {
      'text': slack_message
  }

  print('>send_slack_message:posting message to slack channel')
  response = requests.post(slack_webhook_url, json.dumps(slack_payload))
  response_json = response.text  # convert to json for easy handling
  print('>send_slack_message:response after posting to slack:'+str(response_json))

def get_current_account_id():
    sts_client = boto3.client('sts')
    identity = sts_client.get_caller_identity()
    account_id = identity['Account']
    return account_id

def find_running_ec2instances():
  regions = ['us-east-1', 'us-east-2', 'us-west-1', 'us-west-2', 'ap-south-1', 'ap-northeast-1', 'ap-northeast-2', 'ap-northeast-3',
             'ap-southeast-1', 'ap-southeast-2', 'ca-central-1', 'eu-central-1', 'eu-west-1', 'eu-west-2', 'eu-west-3', 'eu-north-1', 'sa-east-1']

  acccount_id = get_current_account_id()
  notification_message = f'The following EC2 instance(s) are currently running in {acccount_id}: \n'
  slack_webhook_url = os.environ['SLACK_WEBHOOK_URL']

  # find running instances in each of the regions
  total_running_ec2_instances = 0

  for region in regions:
    client = boto3.client("ec2", region_name=region)
    running_ec2_instances = client.describe_instances(
        Filters=[
            {
                'Name': 'instance-state-name',
                'Values': [
                    'running'
                ]
            }

        ],
        MaxResults=1000,
    )
    num_running_ec2_instances = len(running_ec2_instances['Reservations'])

    if num_running_ec2_instances > 0:
        # there is at least one running instance in this region
        total_running_ec2_instances += num_running_ec2_instances

        for instance in running_ec2_instances['Reservations']:
            ec2_info = 'InstanceType:' + instance['Instances'][0]['InstanceType']
            
            # determine how many days this instance has been running
            launch_time = instance['Instances'][0]['LaunchTime']
            current_time = datetime.utcnow()
            days_running = (current_time - launch_time).days
            ec2_info += ' DaysRunning:' + str(days_running)
            

            try:
               ec2_info += ' SSHKeyName:' + instance['Instances'][0]['KeyName']
            except:
                print('>find_running_ec2instances:no ssh key name found')

            # find the name of this instance, if it exists
            ec2_instance_name = ''
            try:
                tags = instance['Instances'][0]['Tags']

                # find a tag with Key == Name. This will contain the instance name. If no such tag exists then the name for this instance will be reported as blank
                for tag in tags:
                    if tag['Key'] == 'Name':
                        ec2_instance_name = tag['Value']
            except:
                ec2_instance_name = ''  # if no tags were found, leave ec2 instance name as blank

            ec2_info = 'Region:' + region + ' Name:' + ec2_instance_name + ' ' + ec2_info

            print('>find_running_ec2instances:running ec2 instance found:' + str(ec2_info))
            notification_message += ec2_info + '\n'

    print('>find_running_ec2instances:Number of running ec2-instances[' + region + ']:'+str(num_running_ec2_instances))

  print('>find_running_ec2instances:Total number of running ec2_instances[all regions]:'+str(total_running_ec2_instances))
  print('>find_running_ec2instances:Slack notification message:' + notification_message)
  if total_running_ec2_instances > 0:
      send_slack_message(slack_webhook_url, notification_message)

  return total_running_ec2_instances


def lambda_handler(event, context):
  num_running_instances = find_running_ec2instances()
  return {
      'statusCode': 200,
      'body': json.dumps('Number of EC2 instances currently running in all regions:' + str(num_running_instances))
  }