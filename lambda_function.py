import boto3
import time
import requests
import json
import os

# AWS Clients
ecs_client = boto3.client("ecs")
ec2_client = boto3.client("ec2")

# Environment Variables (Set in AWS Lambda)
ECS_CLUSTER = os.getenv("ECS_CLUSTER", "ollama-cluster")
ECS_TASK_DEF = os.getenv("ECS_TASK_DEF", "ollama-task")
SUBNETS = os.getenv("SUBNETS", "").split(",")
SECURITY_GROUPS = os.getenv("SECURITY_GROUPS", "").split(",")

def get_running_task():
    """Check if a running Fargate task exists."""
    response = ecs_client.list_tasks(cluster=ECS_CLUSTER, desiredStatus="RUNNING")
    if response["taskArns"]:
        return response["taskArns"][0]
    return None

def start_fargate_task():
    """Start a new ECS Fargate task and return its ARN."""
    response = ecs_client.run_task(
        cluster=ECS_CLUSTER,
        launchType="FARGATE",
        taskDefinition=ECS_TASK_DEF,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": SUBNETS,
                "securityGroups": SECURITY_GROUPS,
                "assignPublicIp": "ENABLED"
            }
        }
    )

    if response["tasks"]:
        return response["tasks"][0]["taskArn"]
    else:
        raise Exception("Failed to start Fargate task")

def get_public_ip(task_arn):
    """Retrieve the public IP of the running task."""
    task_info = ecs_client.describe_tasks(cluster=ECS_CLUSTER, tasks=[task_arn])
    
    if not task_info["tasks"]:
        raise Exception("Task not found")
    
    eni_id = task_info["tasks"][0]["attachments"][0]["details"][1]["value"]

    eni_info = ec2_client.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
    return eni_info["NetworkInterfaces"][0]["Association"]["PublicIp"]

def query_ollama(public_ip, user_query):
    """Send the user query to the running Ollama instance."""
    url = f"http://{public_ip}:11434/api/generate"
    payload = {"query": user_query}

    response = requests.post(url, json=payload)
    return response.json()

def lambda_handler(event, context):
    """Main Lambda handler function."""
    # Extract user query
    user_query = event.get("query", "Hello, Ollama!")

    # Check for existing running task
    task_arn = get_running_task()

    if not task_arn:
        print("No running tasks found. Starting a new Fargate task...")
        task_arn = start_fargate_task()
        time.sleep(30)  # Wait for the task to start

    # Get Public IP
    public_ip = get_public_ip(task_arn)

    # Forward the query to Ollama
    response = query_ollama(public_ip, user_query)

    return {
        "statusCode": 200,
        "body": json.dumps(response)
    }
