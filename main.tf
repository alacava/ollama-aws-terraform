provider "aws" {
  region = "us-east-1"  # Change to your desired region
}


# Create an ECS Cluster
resource "aws_ecs_cluster" "ollama_cluster" {
  name = "ollama-cluster"
}

# Create an ECR Repository for Ollama
resource "aws_ecr_repository" "ollama_repo" {
  name = "ollama"
}

# Create an ECS Task Definition
resource "aws_ecs_task_definition" "ollama_task" {
  family                   = "ollama-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "1024"
  memory                   = "2048"

  container_definitions = jsonencode([
    {
      name  = "ollama"
      image = "${aws_ecr_repository.ollama_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 11434
          hostPort      = 11434
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# Create an ECS Service (auto-start on demand)
resource "aws_ecs_service" "ollama_service" {
  name            = "ollama-service"
  cluster        = aws_ecs_cluster.ollama_cluster.id
  task_definition = aws_ecs_task_definition.ollama_task.arn
  desired_count  = 0  # Starts with 0 to launch only on demand

network_configuration {
  subnets          = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups  = [aws_security_group.ollama_sg.id]
  assign_public_ip = true
}

  launch_type = "FARGATE"
}

# Create an IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Security Group for Ollama ECS Task
resource "aws_security_group" "ollama_sg" {
  name        = "ollama-sg"
  description = "Allow inbound Ollama traffic"
  vpc_id      = aws_vpc.main.id  # ✅ Ensure this references the correct VPC

  ingress {
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Adjust this for security if needed
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}