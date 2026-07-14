# Hello World on Amazon ECS

[![CI](https://github.com/itsample05/hello-world-cicd/actions/workflows/ci.yml/badge.svg)](https://github.com/itsample05/hello-world-cicd/actions/workflows/ci.yml)
[![CD](https://github.com/itsample05/hello-world-cicd/actions/workflows/cd.yml/badge.svg)](https://github.com/itsample05/hello-world-cicd/actions/workflows/cd.yml)

A Spring Boot "Hello World" service, packaged as a container and deployed to **Amazon ECS on Fargate** behind a public **Application Load Balancer**. Every change is validated by GitHub Actions; only approved `main` builds are published to Docker Hub and rolled out to AWS.

This repo was built as a DevOps take-home assignment covering: reusable CI/CD pipelines, static analysis published to GitHub Pages, containerization, and a secure, cost-aware AWS deployment.

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
| Modular, reusable workflows | [`static-analysis.yml`](.github/workflows/static-analysis.yml), [`build-and-push.yml`](.github/workflows/build-and-push.yml), [`deploy-aws.yml`](.github/workflows/deploy-aws.yml) are `workflow_call` reusables, composed by [`ci.yml`](.github/workflows/ci.yml) and [`cd.yml`](.github/workflows/cd.yml) |
| Trigger on feature-branch push **and** master merge | `ci.yml`: any non-`main` push + PRs into `main`. `cd.yml`: pushes to `main` |
| Static code analysis (free tooling) | Checkstyle + SpotBugs + JaCoCo via Maven |
| Publish analysis results to GitHub Pages | `static-analysis.yml` builds a quality dashboard and deploys it with `actions/deploy-pages`, only from `main` |
| Compile Java code | `mvn verify` in the static-analysis job |
| Build Docker image and push to Docker Hub | `build-and-push.yml`; image is **built and scanned on every PR**, but only **pushed on merge to `main`** |
| Deploy as a publicly accessible service on AWS | Terraform-provisioned ECS Fargate service behind a public ALB; `deploy-aws.yml` rolls out the new image |

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

Terraform provisions a VPC across two Availability Zones: public subnets host the ALB, private subnets host the ECS tasks. The ALB is the only internet-facing component; tasks accept port 8080 traffic **only** from the ALB's security group, and reach the internet outbound via a NAT gateway.

The ECS service's desired count is derived from the number of private subnets — with the supplied two-AZ network, that's **two tasks, one per AZ**. If an AZ has an outage, the desired count may be temporarily unattainable until capacity recovers, but the surviving AZ keeps serving traffic.

> **Cost note:** this uses a single NAT gateway to keep demo cost down (NAT gateways are not covered by AWS Free Tier). A production-grade design would use one NAT gateway per AZ so outbound connectivity is zone-resilient too — see [Known limitations](#known-limitations--next-steps).

## CI/CD workflow

| Event | Workflow activity | Docker Hub / AWS effect |
| --- | --- | --- |
| Push to any non-`main` branch | Maven tests, package build, Checkstyle, SpotBugs, JaCoCo report | None — no container build, image push, or deployment |
| Pull request targeting `main` | Same Maven validation, plus a **local** Docker build and Trivy vulnerability scan | None — no Docker Hub login/push, no deployment |
| Push or merge to `main` | Full pipeline: Maven validation, quality report published to Pages, Docker build, Trivy scan, immutable SHA-tagged image push, automatic ECS deployment to `dev`, then sequential promotion to `int` and `production` | Publishes to Docker Hub and deploys to ECS |

Image tags use the Git commit SHA, so ECS always deploys an immutable, traceable artifact — `latest` is a convenience tag only, never what's actually deployed. Every analysis run (including feature branches) uploads a 30-day downloadable Actions artifact even when it isn't published to Pages.

The Docker repository name is derived automatically from the top-level Maven `artifactId` in `pom.xml` (currently `hello-world`), so changing the application artifact name does not require workflow edits.

Terraform `app_name` is the canonical application identifier. The release workflow verifies that it matches the Maven `artifactId` before it publishes an image, preventing an application image from being deployed to a differently named ECS service.

## AWS design decisions

Points worth calling out for a security/efficiency review:

- **No long-lived AWS credentials in GitHub.** The deploy job authenticates via the GitHub OIDC provider (`iam.tf`) and assumes a role restricted to the configured repository, while allowing its branches and GitHub Environments.
- **Segmented network.** ALB lives in public subnets; ECS tasks live in private subnets with no public IP. The tasks' security group only accepts inbound 8080 from the ALB's security group (referenced by ID, not by CIDR).
- **Scoped `iam:PassRole`.** The GitHub deploy role can only pass the two roles ECS actually needs (execution + task role), not `*`.
- **Deployment safety net.** ECS `deployment_circuit_breaker` is enabled with automatic rollback, and the ALB health check targets `/actuator/health` so a bad deploy doesn't stay in rotation.
- **Least-container-privilege.** The Docker image runs as a non-root `app` user (see `Dockerfile`).
- **Immutable image, mutable capacity.** Terraform intentionally ignores ECS task-definition revisions (`lifecycle.ignore_changes`) since GitHub Actions registers new revisions on every deploy — Terraform still owns desired capacity, networking, and IAM.

## Prerequisites

- An AWS account with permission to perform the one-time bootstrap, plus AWS CLI credentials configured locally.
- Terraform 1.x and Git Bash or WSL.
- A GitHub repository with Actions enabled.
- A Docker Hub access token stored as the `DOCKERHUB_TOKEN` GitHub Actions secret.
- GitHub Pages configured to use **GitHub Actions** as its source.

## One-time setup

GitHub Actions can't deploy the AWS role it needs until that role exists, so the very first deployment is done locally and reviewed by hand — see [`docs/onetimesetup.md`](docs/onetimesetup.md) for the full walkthrough.

## Operational notes

- Terraform state and `terraform.tfvars` are gitignored. For team/production use, configure a remote encrypted backend (S3 + DynamoDB lock table) before sharing this infrastructure.
- Deployment target values are versioned per environment in [`.github/deployments/`](.github/deployments/), so changes are reviewed in a pull request instead of being overwritten as GitHub repository variables. Keep secrets such as `DOCKERHUB_TOKEN` in GitHub Secrets.
- A `main` release always deploys in order: `dev` → `int` → `production`. Configure required reviewers in GitHub **Settings → Environments** for `int` and `production`; the workflow pauses at each protected environment before deployment.
- Protect `main` with the `CI` workflow as a required status check so nothing merges unvalidated.
- Tear down with `terraform destroy` from `terraform/` when done, since the NAT gateway isn't Free Tier.

## Known limitations / next steps

Documented deliberately rather than discovered by accident — these are the natural next iterations for a production system:

- **HTTPS.** The ALB currently only listens on port 80. Next step: ACM certificate + Route 53 record + 443 listener with an 80→443 redirect.
- **Autoscaling.** ECS desired count is fixed at 2. Next step: `aws_appautoscaling_target`/`policy` on CPU or request count.
- **Multi-AZ NAT.** One NAT gateway today (cost tradeoff); production would use one per AZ for zone-resilient egress.
- **Edge protection.** No WAF or rate limiting on the ALB yet — reasonable for a Free Tier demo, worth adding for anything internet-facing at scale.
