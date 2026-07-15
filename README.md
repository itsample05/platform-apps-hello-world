# Hello World on Amazon ECS


A Spring Boot "Hello World" service, packaged as a container and deployed to Amazon ECS on Fargate behind a public Application Load Balancer. Every change is validated by GitHub Actions; only approved `main` builds are published to Docker Hub and rolled out to AWS.

This is the application repository. AWS infrastructure is maintained and applied separately in `platform-infra`; this repository only consumes its non-secret deployment outputs.

## Table of contents

- [Assignment coverage](#assignment-coverage)
- [Architecture](#architecture)
- [CI/CD workflow](#cicd-workflow)
- [AWS design decisions](#aws-design-decisions)
- [Prerequisites](#prerequisites)
- [One-time setup](#one-time-setup)
- [Operational notes](#operational-notes)
- [Known limitations / next steps](#known-limitations--next-steps)

## Assignment coverage

| Requirement | Where it's implemented |
| --- | --- |
| Modular, reusable workflows | [`static-analysis.yml`](.github/workflows/static-analysis.yml), [`build-and-push.yml`](.github/workflows/build-and-push.yml), [`deploy-aws.yml`](.github/workflows/deploy-aws.yml) are reusable workflows composed by [`ci.yml`](.github/workflows/ci.yml) and [`cd.yml`](.github/workflows/cd.yml) |
| Trigger on feature-branch push and main merge | `ci.yml`: any non-`main` push + PRs into `main`. `cd.yml`: pushes to `main` |
| Static code analysis | Checkstyle, SpotBugs, and JaCoCo via Maven |
| Publish analysis results to GitHub Pages | `static-analysis.yml` builds a quality dashboard and deploys it with `actions/deploy-pages`, only from `main` |
| Compile Java code | `mvn verify` in the static-analysis job |
| Build Docker image and push to Docker Hub | `build-and-push.yml`; image is built and scanned on every PR, but pushed only on merge to `main` |
| Deploy as a publicly accessible service on AWS | The ECS Fargate service and public ALB are provisioned by `platform-infra`; `deploy-aws.yml` rolls out the new image |

## Architecture

```text
Internet
   |
Public ALB (one public subnet per AZ)
   |
   +-- target group / health checks
           |
Private subnet, AZ 1       Private subnet, AZ 2
ECS Fargate task           ECS Fargate task
           |                       |
           +---- CloudWatch Logs --+

GitHub Actions -- OIDC --> AWS deployment role --> ECS service
GitHub Actions -- Docker Hub token --> Docker Hub image repository
```

`platform-infra` provisions a VPC across two Availability Zones: public subnets host the ALB, private subnets host the ECS tasks. The ALB is the only internet-facing component; tasks accept port 8080 traffic only from the ALB security group, and reach the internet outbound through a NAT gateway.

The ECS service's desired count is derived from the number of private subnets. With the supplied two-AZ network, that is two tasks, one per AZ.

## CI/CD workflow



| Event | Workflow activity | Docker Hub / AWS effect |```mermaid
flowchart LR
    A[Developer push] --> B{Branch or PR?}
    B -->|Feature branch / PR| C[CI: Maven tests and quality checks]
    C --> D[Docker build and Trivy scan]
    D --> E[No image push or AWS deployment]
    B -->|Merge to main| F[CI: tests and quality report]
    F --> G[Build, scan, and push SHA-tagged image]
    G --> H[Deploy dev]
    H --> I[Approval gate]
    I --> J[Deploy int]
    J --> K[Approval gate]
    K --> L[Deploy production]
```

| --- | --- | --- |
| Push to any non-`main` branch | Maven tests, package build, Checkstyle, SpotBugs, JaCoCo report | None — no container build, image push, or deployment |
| Pull request targeting `main` | Same Maven validation, plus a local Docker build and Trivy vulnerability scan | None — no Docker Hub login/push or deployment |
| Push or merge to `main` | Full pipeline: Maven validation, quality report published to Pages, Docker build, Trivy scan, immutable SHA-tagged image push, automatic ECS deployment to `dev`, then sequential promotion to `int` and `production` | Publishes to Docker Hub and deploys to ECS |

Image tags use the Git commit SHA, so ECS always deploys an immutable, traceable artifact. The Docker repository name is derived from the top-level Maven `artifactId` in `pom.xml` (currently `hello-world`).

The infrastructure `app_name` identifies the ECS resources and can include the environment suffix (for example, `hello-world-dev`). The Docker image name is independently derived from the Maven `artifactId` (`hello-world`), so the same image can be promoted across environments.

## AWS design decisions

- No long-lived AWS credentials in GitHub. The deploy job uses the GitHub OIDC provider provisioned by `platform-infra` and assumes a repository-scoped role.
- Segmented network. The ALB is in public subnets; ECS tasks are in private subnets with no public IP and accept inbound traffic only from the ALB security group.
- Deployment safety net. ECS deployment rollback and ALB health checks prevent an unhealthy revision from remaining in rotation.
- Least container privilege. The Docker image runs as a non-root `app` user (see `Dockerfile`).
- Immutable image, mutable capacity. GitHub Actions registers new task-definition revisions; `platform-infra` owns capacity, networking, and IAM.

## Prerequisites

- A GitHub repository with Actions enabled.
- A Docker Hub access token stored as the `DOCKERHUB_TOKEN` GitHub Actions secret.
- GitHub Pages configured to use GitHub Actions as its source.
- A completed `platform-infra` deployment whose non-secret outputs are available.

## One-time setup

Apply `platform-infra` first. Then manually copy its non-secret deployment outputs into `.github/deployments/dev.env`, using [the key-value example file](.github/deployments/dev.env.example) as the schema. Commit the resulting configuration file with this repository. See [the deployment configuration guide](docs/awsbootstrap.md) for the required values.

## Operational notes

- Deployment target values are versioned as key-value files per environment in [`.github/deployments/`](.github/deployments/), so changes are reviewed in a pull request instead of being overwritten as GitHub repository variables. Keep secrets such as `DOCKERHUB_TOKEN` in GitHub Secrets.
- A `main` release deploys in order: `dev` → `int` → `production`. Configure required reviewers in GitHub Settings → Environments for `int` and `production`; the workflow pauses at each protected environment before deployment.
- Protect `main` with the `CI` workflow as a required status check.
- Manage infrastructure changes and teardown from `platform-infra`; this repository does not contain Terraform state or infrastructure definitions.

## Known limitations / next steps

- **HTTPS.** The ALB currently only listens on port 80. Next step: ACM certificate + Route 53 record + 443 listener with an 80→443 redirect.
- **Autoscaling.** ECS desired count is fixed at 2. Next step: add an Application Auto Scaling policy based on CPU or request count.
- **Multi-AZ NAT.** One NAT gateway is a cost trade-off; production would use one per AZ for zone-resilient egress.
- **Edge protection.** No WAF or rate limiting on the ALB yet — appropriate for a demo, but worth adding for an internet-facing production service.
