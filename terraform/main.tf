provider "aws" {
  region = "us-east-1"
}

# ECR Repository for Ollama Image
resource "aws_ecr_repository" "ollama_repo" {
  name = "ollama"
}

# ECS Cluster
resource "aws_ecs_cluster" "ollama_cluster" {
  name = "ollama-cluster"
}

# Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy_attachment" "ecs_task_execution_role_policy" {
  name       = "ecsTaskExecutionRolePolicy"
  roles      = [aws_iam_role.ecs_task_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "ollama_task" {
  family                   = "ollama-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "ollama-container"
    image     = "${aws_ecr_repository.ollama_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 11434
      hostPort      = 11434
      protocol      = "tcp"
    }]
  }])
}

# Security Group for ECS Service
resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-ollama-sg"

  ingress {
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to public (secure in production)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Fargate Service
resource "aws_ecs_service" "ollama_service" {
  name            = "ollama-service"
  cluster         = aws_ecs_cluster.ollama_cluster.id
  task_definition = aws_ecs_task_definition.ollama_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.public.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ollama_tg.arn
    container_name   = "ollama-container"
    container_port   = 11434
  }
}

# Load Balancer
resource "aws_lb" "ollama_lb" {
  name               = "ollama-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets           = [aws_subnet.public.id]
}

resource "aws_lb_target_group" "ollama_tg" {
  name     = "ollama-tg"
  port     = 11434
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ollama_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ollama_tg.arn
  }
}

# API Gateway for Start/Stop Service
resource "aws_apigatewayv2_api" "ollama_api" {
  name          = "OllamaAPI"
  protocol_type = "HTTP"
}

resource "aws_lambda_function" "ecs_control_lambda" {
  function_name = "ecs_control_lambda"
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"

  role          = aws_iam_role.lambda_role.arn
  filename      = "lambda_function.zip"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.ollama_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_route" "start_route" {
  api_id    = aws_apigatewayv2_api.ollama_api.id
  route_key = "POST /start"
  target    = "integrations/${aws_lambda_function.ecs_control_lambda.arn}"
}

resource "aws_apigatewayv2_route" "stop_route" {
  api_id    = aws_apigatewayv2_api.ollama_api.id
  route_key = "POST /stop"
  target    = "integrations/${aws_lambda_function.ecs_control_lambda.arn}"
}
