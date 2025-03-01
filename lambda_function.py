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
    """Check if an ECS Fargate task is already running."""
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

def wait_for_task(task_arn):
    """Wait until ECS task is in the RUNNING state."""
    print("Waiting for ECS task to reach RUNNING state...")
    
    for _ in range(30):  # Wait for a maximum of 150 seconds
        response = ecs_client.describe_tasks(cluster=ECS_CLUSTER, tasks=[task_arn])
        if response["tasks"] and response["tasks"][0]["lastStatus"] == "RUNNING":
            print("ECS task is now RUNNING.")
            return True
        time.sleep(5)  # Wait 5 seconds before checking again
    
    raise Exception("ECS task did not reach RUNNING state in time")

def get_public_ip(task_arn):
    """Retrieve the public IP of the running ECS task."""
    task_info = ecs_client.describe_tasks(cluster=ECS_CLUSTER, tasks=[task_arn])

    if not task_info["tasks"]:
        raise Exception("Task not found")

    eni_id = None
    for attachment in task_info["tasks"][0]["attachments"]:
        for detail in attachment["details"]:
            if detail["name"] == "networkInterfaceId":
                eni_id = detail["value"]
                break

    if not eni_id:
        raise Exception("Could not retrieve ENI ID for task")

    eni_info = ec2_client.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
    return eni_info["NetworkInterfaces"][0]["Association"]["PublicIp"]

def query_ollama(public_ip, user_query):
    """Send the user query to the running Ollama instance."""
    url = f"http://{public_ip}:11434/api/generate"
    payload = {"query": user_query}

    print(f"Sending request to Ollama at {url}...")

    for _ in range(5):  # Retry up to 5 times
        try:
            response = requests.post(url, json=payload, timeout=10)
            return response.json()
        except requests.exceptions.ConnectionError as e:
            print(f"Connection failed, retrying in 5s... {e}")
            time.sleep(5)
    
    raise Exception("Could not connect to Ollama after multiple retries")

def lambda_handler(event, context):
    """Main Lambda handler function."""
    user_query = event.get("query", "Hello, Ollama!")

    # Check if an ECS task is already running
    task_arn = get_running_task()

    if not task_arn:
        print("No running tasks found. Starting a new Fargate task...")
        task_arn = start_fargate_task()
        wait_for_task(task_arn)  # Ensure task is running before continuing

    # Get Public IP
    public_ip = get_public_ip(task_arn)

    # Forward the query to Ollama
    response = query_ollama(public_ip, user_query)

    return {
        "statusCode": 200,
        "body": json.dumps(response)
    }
