## Deployment configuration

AWS infrastructure and GitHub OIDC integration are provisioned in the separate `platform-infra` repository. After its `main` workflow applies infrastructure, manually copy the non-secret output values into this application's environment file. There is no bootstrap script in this repository.

Key-value files are used because Terraform output can be pasted directly in its `name = "value"` format. The workflow reads only the values it needs and does not execute the file as a shell script.

### 1. Create the dev configuration

Copy [`.github/deployments/dev.env.example`](../.github/deployments/dev.env.example) to `.github/deployments/dev.env`. Paste the matching output from the `platform-infra` apply, retaining the output names. Set `dockerhub_username` separately: it is not an infrastructure output and must be the Docker Hub namespace that publishes this application.

Commit `dev.env` to a branch and review it in a pull request. It contains deployment identifiers, not credentials.

### Required values

| Key | Source / purpose |
| --- | --- |
| `aws_region` | `platform-infra` output for the AWS Region |
| `github_deploy_role_arn` | OIDC deployment role ARN from `platform-infra` |
| `ecs_cluster_name` | ECS cluster name from `platform-infra` |
| `ecs_service_name` | ECS service name from `platform-infra` |
| `ecs_task_family` | ECS task-definition family from `platform-infra` |
| `dockerhub_username` | Docker Hub username or namespace; add manually |

To add promotion environments, apply the corresponding `platform-infra` configurations and create `.github/deployments/int.env` and `.github/deployments/production.env` using the same format.

### 2. Configure GitHub

In **Repository → Settings → Secrets and variables → Actions**, create the following secret:

| Name | Description |
| --- | --- |
| `DOCKERHUB_TOKEN` | Docker Hub personal access token with push permissions |

The CD workflow deploys `dev` after a push to `main`, then promotes the same immutable image to `int` and `production` in order. In GitHub **Settings → Environments**, create `int` and `production` and configure their required reviewers.

### 3. Enable GitHub Pages

In **Settings → Pages**, choose **GitHub Actions** as the build source.

### 4. Release

Push a feature branch, open a PR into `main`, and merge once checks pass. The `main` workflow publishes the image and deploys it. Retrieve the public URL from the `application_url` output in `platform-infra`.
