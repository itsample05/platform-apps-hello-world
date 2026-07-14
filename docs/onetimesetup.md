## 🛠️ One-Time Setup (AWS Infrastructure & GitHub)

Before the CI/CD pipeline can deploy to AWS, the infrastructure and GitHub OIDC integration must be bootstrapped once from your local machine. This creates the required AWS resources and securely configures GitHub Actions to deploy without storing long-lived AWS credentials.

---

### 1. Prerequisites & Configure Variables

Ensure the following are installed and configured:

- AWS CLI (authenticated with an account that can create IAM, VPC, ALB, ECS, etc.)
- Terraform 1.x+
- Git
- Docker

Copy the Terraform variables example file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Update the values:

```hcl
aws_region        = "us-east-1"
app_name          = "hello-world"
cluster_name      = "platform-apps-dev-cluster"
container_image   = "YOUR_DOCKERHUB_USERNAME/hello-world-app:bootstrap" #  or give public.ecr.aws/nginx/nginx:latest
github_repository = "YOUR_GITHUB_USERNAME/YOUR_REPOSITORY"
```

> 💡 **Bootstrap Image**
>
The nginx/bootstrap image allows ECS to create the initial service before the CI/CD pipeline publishes the first application image.Subsequent deployment then overrides the bootstrap image with the actual docker image during CD deployment.

---

### 2. Provision AWS Infrastructure

Navigate to the Terraform directory and provision the infrastructure.

```bash
cd terraform

terraform init
terraform validate
terraform plan -out=tfplan

# Review the execution plan carefully.

terraform apply tfplan
```

This provisions:

- VPC
- Public & Private Subnets
- NAT Gateway
- Application Load Balancer
- ECS Cluster & Service
- IAM Roles
- GitHub OIDC Provider
- CloudWatch Log Group

---

### 3. Configure GitHub Integration

Run the bootstrap helper script from the repository root:

```bash
bash scripts/bootstrap.sh dev
```

The script verifies the IAM role and writes a ready-to-commit configuration file at [`.github/deployments/production.json`](../.github/deployments/production.json). Commit it on a branch and open a pull request. Do not add credentials to this file.

If `container_image` is a Docker Hub image such as `my-docker-user/hello-world:bootstrap`, bootstrap uses `my-docker-user` automatically. If it is an ECR image, another registry, or does not include a namespace, bootstrap prompts for the Docker Hub username used by CD.

Next, configure the following GitHub Actions credentials:

**Repository → Settings → Secrets and variables → Actions**

#### Secrets

| Name | Description |
|------|-------------|
| `DOCKERHUB_TOKEN` | Docker Hub Personal Access Token with push permissions |

#### Reviewed deployment configuration

The following non-secret values are committed in `.github/deployments/<environment>.json` and are read by the deployment workflow. Any change should go through a pull request:

| JSON field | Description |
|------|-------------|
| `environment` | GitHub environment name and configuration filename |
| `app_name` | Canonical application identifier generated from Terraform; it must match the Maven `artifactId` |
| `dockerhub_username` | Docker Hub username/namespace |
| `aws_deploy_role_arn` | IAM role ARN created by Terraform |
| `aws_region`, `ecs_cluster`, `ecs_service`, `ecs_task_family` | Deployment target values |

`application_url` is an informational Terraform output; it is not needed by the workflow.

To add the remaining promotion environments, apply their Terraform configurations and generate their files:

```bash
bash scripts/bootstrap.sh int
bash scripts/bootstrap.sh production
```

The CD workflow deploys `dev` after a push to `main`, then promotes the same immutable image to `int` and `production` in order. In GitHub **Settings → Environments**, create `int` and `production` and configure their required reviewers. Each job pauses until the required approval is granted.

---

### 4. In **Settings → Pages**, choose **GitHub Actions** as the build source.
### 5. Push a feature branch, open a PR into `main`, and merge once checks pass. The `main` workflow publishes the image and deploys it. Grab the public URL from the Terraform output `application_url`

