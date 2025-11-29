# README.md

## WordPress & Microservice ECS Infrastructure on AWS

This project deploys a production-ready, highly available WordPress application and custom Node.js microservice on AWS ECS Fargate with Application Load Balancer, RDS MySQL database, and AWS Secrets Manager integration using Terraform.

### Architecture Overview

The infrastructure includes:
- **ECS Fargate** cluster running WordPress and Node.js microservice in private subnets
- **Application Load Balancer** with SSL/TLS termination and host-based routing
- **RDS MySQL** database in private subnets with automated backups
- **AWS Secrets Manager** for secure credential storage
- **Auto-scaling** based on CPU and memory utilization
- **VPC** with public/private subnets across multiple availability zones
- **Route53** DNS records with ACM SSL certificates

## Prerequisites

Before starting, ensure you have:

### 1. AWS Account Setup
- Active AWS account with appropriate permissions
- AWS CLI installed and configured with credentials
- IAM user with `AdministratorAccess` or equivalent permissions[1]

### 2. Development Tools
```bash
# Install Terraform (>= 1.0)
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads

# Install Docker
brew install docker  # macOS
# or download from https://www.docker.com/products/docker-desktop

# Install AWS CLI (>= 2.0)
brew install awscli  # macOS
# or download from https://aws.amazon.com/cli/

# Install Node.js (>= 18.0)
brew install node  # macOS
```

### 3. Domain Name
- Registered domain name (can be registered through Route53 or external registrar)
- Access to DNS management for the domain

### 4. AWS Resources to Create First
- S3 bucket for Terraform state storage
- DynamoDB table for state locking
- Route53 Hosted Zone for your domain

## Step-by-Step Implementation Guide

### Step 1: Clone and Prepare the Project

```bash
# Create project directory
mkdir terraform-ecs-wordpress
cd terraform-ecs-wordpress

# Create microservice directory
mkdir -p microservice

# Copy all Terraform files from the template
# (main.tf, variables.tf, outputs.tf, vpc.tf, security_groups.tf, 
#  rds.tf, secrets.tf, ecs.tf, alb.tf, autoscaling.tf, iam.tf)

# Copy microservice files
# (microservice/app.js, microservice/package.json, microservice/Dockerfile)
```

### Step 2: Configure AWS Backend for Terraform State

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-east-1

# Enable versioning on the bucket
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

Update `main.tf` backend configuration with your bucket name:
```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "wordpress-ecs/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

### Step 3: Set Up Domain and SSL Certificate

```bash
# Create Route53 Hosted Zone (if not already exists)
aws route53 create-hosted-zone \
  --name themangoking.au \
  --caller-reference $(date +%s)

# Note the NameServers from the output and update your domain registrar

# Request ACM certificate for wildcard domain
aws acm request-certificate \
  --domain-name "*.themangoking.au" \
  --subject-alternative-names "themangoking.au" \
  --validation-method DNS \
  --region us-east-1

# Get certificate ARN
aws acm list-certificates --region us-east-1

# Describe certificate to get validation records
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id \
  --region us-east-1
```

Create CNAME records in Route53 for certificate validation:
```bash
# The output will show validation CNAME records
# Add these to your Route53 Hosted Zone either via console or CLI

aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://cert-validation.json
```

Example `cert-validation.json`:
```json
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "_abc123.themangoking.au",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "_xyz456.acm-validations.aws."}]
    }
  }]
}
```

Wait for certificate validation (usually 5-10 minutes):
```bash
aws acm wait certificate-validated \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id \
  --region us-east-1
```

### Step 4: Build and Push Microservice Docker Image

```bash
# Navigate to microservice directory
cd microservice

# Install dependencies locally to test
npm install

# Test the application locally
node app.js
# Visit http://localhost:3000 and http://localhost:3000/health

# Create ECR repository
aws ecr create-repository \
  --repository-name wordpress-microservice \
  --region us-east-1

# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build Docker image
docker build -t wordpress-microservice .

# Tag the image
docker tag wordpress-microservice:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/wordpress-microservice:latest

# Push to ECR
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/wordpress-microservice:latest

# Verify the image
aws ecr describe-images \
  --repository-name wordpress-microservice \
  --region us-east-1

cd ..
```

### Step 5: Configure Terraform Variables

Create `terraform.tfvars` file:
```hcl
# AWS Configuration
aws_region      = "us-east-1"
project_name    = "wordpress-ecs"
environment     = "production"

# Networking
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# Domain and SSL
domain_name     = "themangoking.au"
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"

# Container Images
wordpress_image    = "wordpress:latest"
microservice_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/wordpress-microservice:latest"

# Database Configuration
db_name         = "wordpressdb"
db_username     = "wpuser"
db_password     = "YourSecurePassword123!"  # Use a strong password
rds_instance_class = "db.t3.micro"

# ECS Service Configuration
wordpress_desired_count    = 2
microservice_desired_count = 2
```

**Security Note**: For production, use environment variables or AWS Secrets Manager for sensitive values instead of hardcoding in `terraform.tfvars`.

### Step 6: Initialize Terraform

```bash
# Initialize Terraform (downloads providers and modules)
terraform init

# Expected output:
# - Initializing the backend (S3)
# - Initializing provider plugins (AWS)
# - Terraform has been successfully initialized!
```

### Step 7: Validate and Plan Infrastructure

```bash
# Format Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate

# Review the execution plan
terraform plan -out=tfplan

# Review the plan carefully:
# - Check resource counts (should create ~50+ resources)
# - Verify VPC and subnet configurations
# - Confirm RDS settings (instance type, multi-AZ)
# - Check security group rules
# - Verify ECS task definitions
# - Confirm ALB and target group settings
```

### Step 8: Deploy Infrastructure

```bash
# Apply the Terraform configuration
terraform apply tfplan

# This will take approximately 15-20 minutes
# Progress will show resource creation in real-time

# Resources created in order:
# 1. VPC and networking (subnets, IGW, NAT gateways, route tables)
# 2. Security groups
# 3. RDS database instance
# 4. Secrets Manager secret
# 5. IAM roles and policies
# 6. ECS cluster
# 7. Application Load Balancer
# 8. Target groups
# 9. ECS task definitions
# 10. ECS services
# 11. Auto-scaling policies

# Monitor the apply process for any errors
```

### Step 9: Configure Route53 DNS Records

After successful deployment, get the ALB DNS name:
```bash
# Get ALB DNS name from Terraform output
ALB_DNS=$(terraform output -raw alb_dns_name)
echo $ALB_DNS

# Get Hosted Zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name themangoking.au \
  --query "HostedZones[0].Id" \
  --output text | cut -d'/' -f3)
```

Create DNS records for WordPress and microservice:
```bash
# Create Route53 A record for wordpress subdomain
cat > wordpress-dns.json <<EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "wordpress.themangoking.au",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "$(aws elbv2 describe-load-balancers \
          --query "LoadBalancers[?DNSName=='$ALB_DNS'].CanonicalHostedZoneId" \
          --output text)",
        "DNSName": "$ALB_DNS",
        "EvaluateTargetHealth": true
      }
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://wordpress-dns.json

# Create Route53 A record for microservice subdomain
cat > microservice-dns.json <<EOF
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "microservice.themangoking.au",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "$(aws elbv2 describe-load-balancers \
          --query "LoadBalancers[?DNSName=='$ALB_DNS'].CanonicalHostedZoneId" \
          --output text)",
        "DNSName": "$ALB_DNS",
        "EvaluateTargetHealth": true
      }
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://microservice-dns.json
```

### Step 10: Verify Deployment

```bash
# Check ECS cluster status
aws ecs describe-clusters \
  --clusters wordpress-ecs-cluster \
  --region us-east-1

# Check ECS services
aws ecs list-services \
  --cluster wordpress-ecs-cluster \
  --region us-east-1

# Check running tasks
aws ecs list-tasks \
  --cluster wordpress-ecs-cluster \
  --region us-east-1

# Check RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier wordpress-ecs-mysql \
  --region us-east-1 \
  --query "DBInstances[0].DBInstanceStatus"

# Check ALB health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw wordpress_target_group_arn)

# Test DNS resolution (wait 2-5 minutes for DNS propagation)
nslookup wordpress.themangoking.au
nslookup microservice.themangoking.au
```

### Step 11: Access Your Applications

```bash
# Access WordPress
open https://wordpress.themangoking.au

# Access Microservice
curl https://microservice.themangoking.au
# Expected response:
# {
#   "message": "Hello from Microservice",
#   "version": "1.0.0",
#   "hostname": "...",
#   "timestamp": "..."
# }

# Check microservice health
curl https://microservice.themangoking.au/health
# Expected response:
# {
#   "status": "healthy",
#   "timestamp": "..."
# }

# Verify HTTP to HTTPS redirect
curl -I http://wordpress.themangoking.au
# Should return 301 redirect to https://
```

### Step 12: Monitor and Troubleshoot

```bash
# View ECS service events
aws ecs describe-services \
  --cluster wordpress-ecs-cluster \
  --services wordpress-ecs-wordpress-service \
  --region us-east-1 \
  --query "services[0].events[0:5]"

# View CloudWatch logs
aws logs tail /ecs/wordpress-ecs --follow

# Check auto-scaling policies
aws application-autoscaling describe-scaling-policies \
  --service-namespace ecs \
  --region us-east-1

# View RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=wordpress-ecs-mysql \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-east-1
```
