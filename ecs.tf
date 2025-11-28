resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = var.environment
  }
}

# WordPress Task Definition
resource "aws_ecs_task_definition" "wordpress" {
  family                   = "${var.project_name}-wordpress"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "wordpress"
    image     = var.wordpress_image
    essential = true

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "WORDPRESS_DB_HOST"
        value = aws_db_instance.wordpress.address
      },
      {
        name  = "WORDPRESS_DB_NAME"
        value = var.db_name
      }
    ]

    secrets = [
      {
        name      = "WORDPRESS_DB_USER"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
      },
      {
        name      = "WORDPRESS_DB_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "wordpress"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = {
    Name        = "${var.project_name}-wordpress-task"
    Environment = var.environment
  }
}

# Microservice Task Definition
resource "aws_ecs_task_definition" "microservice" {
  family                   = "${var.project_name}-microservice"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "microservice"
    image     = var.microservice_image
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "microservice"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
  }])

  tags = {
    Name        = "${var.project_name}-microservice-task"
    Environment = var.environment
  }
}

# WordPress ECS Service
resource "aws_ecs_service" "wordpress" {
  name            = "${var.project_name}-wordpress-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = var.wordpress_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wordpress.arn
    container_name   = "wordpress"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.https,
    aws_db_instance.wordpress
  ]

  tags = {
    Name        = "${var.project_name}-wordpress-service"
    Environment = var.environment
  }
}

# Microservice ECS Service
resource "aws_ecs_service" "microservice" {
  name            = "${var.project_name}-microservice-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.microservice.arn
  desired_count   = var.microservice_desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.microservice.arn
    container_name   = "microservice"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.https]
}

  tags = {
    Name        = "${var.project_name}-microservice-service"
    Environment = var.environment
  }
}