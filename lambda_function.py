import boto3

ecs = boto3.client('ecs')

def lambda_handler(event, context):
    cluster = "ollama-cluster"
    service = "ollama-service"
    action = event.get("action", "start")

    if action == "start":
        ecs.update_service(cluster=cluster, service=service, desiredCount=1)
        return {"message": "Ollama service started"}

    elif action == "stop":
        ecs.update_service(cluster=cluster, service=service, desiredCount=0)
        return {"message": "Ollama service stopped"}
