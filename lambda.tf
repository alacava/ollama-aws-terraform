# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach permissions for ECS and EC2
resource "aws_iam_policy" "lambda_ecs_policy" {
  name        = "lambda-ecs-policy"
  description = "Allow Lambda to manage ECS"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask", "ecs:DescribeTasks", "ec2:DescribeNetworkInterfaces"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_ecs_policy.arn
}

# Upload Lambda Function Code
resource "aws_lambda_function" "start_ollama_lambda" {
  filename         = "lambda.zip"  # Ensure you have lambda.zip ready
  function_name    = "startOllama"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.8"
  timeout         = 30

  environment {
  variables = {
    ECS_CLUSTER     = aws_ecs_cluster.ollama_cluster.name
    ECS_TASK_DEF    = aws_ecs_task_definition.ollama_task.family
    SUBNETS         = join(",", [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id])  # ✅ (Fix)
    SECURITY_GROUPS = aws_security_group.ollama_sg.id
  }
 }
}

# API Gateway for Lambda
resource "aws_api_gateway_rest_api" "ollama_api" {
  name        = "OllamaAPI"
  description = "API to trigger Ollama Fargate instance"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.ollama_api.id
  parent_id   = aws_api_gateway_rest_api.ollama_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.ollama_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.ollama_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.start_ollama_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "ollama_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.ollama_api.id
  stage_name  = "prod"
}

output "api_url" {
  value = aws_api_gateway_deployment.ollama_deployment.invoke_url
}
