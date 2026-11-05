# TradeArt Orb Project

CircleCI orb for TradeArt project.

A starter template for orb projects. Build, test, and publish orbs automatically on CircleCI with [Orb-Tools](https://circleci.com/orbs/registry/orb/circleci/orb-tools).

Additional READMEs are available in each directory.

**Meta**: This repository is open for contributions! Feel free to open a pull request with your changes. Due to the nature of this repository, it is not built on CircleCI. The Resources and How to Contribute sections relate to an orb created with this template, rather than the template itself.

## Required environment variables

Every job in this orb reads its secrets from the CircleCI **context** the consumer repo attaches to the workflow (TradeArt uses the `global` context). The table below lists everything the orb reads, and which jobs need it.

Variables not listed here (`FULL_VERSION`, `VERSION_PREFIX`, `VERSION_SUFFIX`, `NUGET_VERSION_SUFFIX`, `ENV_NAME`, `SLACK_TAG`, `*_TEMPLATE`, `COMMIT_MESSAGE`) are **computed at runtime** by `inject_version_data` / `inject_slack_templates` and must not be set in the context. CircleCI built-ins (`CIRCLE_BRANCH`, `CIRCLE_SHA1`, `CIRCLE_USERNAME`, `BASH_ENV`) are provided by the platform.

### Always required

| Variable | Used by | Purpose |
| --- | --- | --- |
| `SLACK_ACCESS_TOKEN` | **all jobs** | Slack bot token for `circleci/slack@5.1.1`; every job ends with a `slack/notify` to `odds88-circleci-notifications`. |
| `GITHUB_DEPLOY_PRIVATE_KEY` | **all jobs** | SSH deploy key for `Odds88-Team/tradeart-circleci-notifications` — Slack templates and the `users_map.json` CircleCI-user → Slack-tag map. Read by `inject_slack_templates` (in every job). |

### AWS

| Variable | Used by | Purpose |
| --- | --- | --- |
| `AWS_ACCOUNT_ID` | `docker`, `lambda_docker`, `lambda_deploy` | ECR registry host (`$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com`). |
| `AWS_DEFAULT_REGION` | `docker`, `lambda_docker`, `lambda_deploy` | Region for `aws ecr get-login-password` and `aws lambda update-function-code`. |
| `AWS_ACCESS_KEY_ID` | `docker`, `lambda_docker`, `lambda_deploy` | Not referenced literally in the orb, but required by every `aws` CLI call above (ECR login, Lambda deploy). |
| `AWS_SECRET_ACCESS_KEY` | `docker`, `lambda_docker`, `lambda_deploy` | As above. |

### ArgoCD (GitOps) deploys

| Variable | Used by | Purpose |
| --- | --- | --- |
| `DEV_CLUSTER_REPO_KEY` | `argo_deploy_dev` | SSH deploy key (write) for `Odds88-Team/tradeart-tenants`. |
| `PROD_CLUSTER_REPO_KEY` | `argo_deploy_prod` | SSH deploy key (write) for `Odds88-Team/tradeart-tenants-prod`. |

### Tests

| Variable | Used by | Purpose |
| --- | --- | --- |
| `SONAR_TOKEN` | `test`, `test-with-db` | SonarCloud token (org `odds88`) for `dotnet sonarscanner`. Not needed by `test_no_sonar`. |

### Intent Architect

| Variable | Used by | Purpose |
| --- | --- | --- |
| `GITHUB_INTENT_PRIVATE_KEY` | `intent_check` | SSH deploy key for `Odds88-Team/tradeart-intent-modules`. |
| `INTENT_USERNAME` | `intent_check` | Intent Architect account used by `intent-cli ensure-no-outstanding-changes`. |
| `INTENT_PASSWORD` | `intent_check` | Intent Architect password. |

### Notes

- **`nuget`** job — `push_nuget` runs `dotnet nuget push --source "nuget/Main"`. That source and its credentials come from the `NuGet.config` baked into the `trading-dev-core-sdk` builder image, not from a context variable. Its optional `paths` parameter (space-separated, relative to the repo root) makes the job halt without publishing, and without a Slack notification, unless one of those paths changed: on `master`/`staging`/`release` in the last merge, on any other branch since it left `master`. List everything that affects the packages, such as shared `Directory.Build.props`. `force_publish: true` skips the check; to set it from a manual run, declare a boolean pipeline parameter and pass it through, e.g. `force_publish: << pipeline.parameters.force_publish >>`.
- **`build`**, **`lambda_build`**, **`test_no_sonar`**, **`notify-approve-awaited`** need only the two always-required variables.
- **This repo's own pipeline** additionally uses `CIRCLE_CI_API_KEY` (in the `global` context) for the `PROD publish` job in [.circleci/test-deploy.yml](.circleci/test-deploy.yml). Consumer repos do not need it.
- **No longer used (removed with the Helm deploy path):** `SSH_KEY_PROD`, `DEV_K8S_ENDPOINT`, `PROD_K8S_ENDPOINT`, `DEV_CLUSTER_NAME`, `STAGING_CLUSTER_NAME`, `PROD_CLUSTER_NAME`, `TEST_CLUSTER_VALUES_NAME`, `DEV_CLUSTER_VALUES_NAME`, `STAGING_CLUSTER_VALUES_NAME`, `PROD_CLUSTER_VALUES_NAME`, `GITHUB_TERRAFORM_PRIVATE_KEY`. They can be dropped from the context once every consumer repo is on the ArgoCD-only version of the orb.

## Resources

[CircleCI Orb Registry Page](https://circleci.com/developer/orbs/orb/odds88/tradeart-orb) - The official registry page of this orb for all versions, executors, commands, and jobs described.
[CircleCI Orb Docs](https://circleci.com/docs/2.0/orb-intro/#section=configuration) - Docs for using and creating CircleCI Orbs.

### How to Publish

Create and push a tag with new version to be released. Please use properly incremented version.


For further questions/comments about this or other orbs, visit the Orb Category of [CircleCI Discuss](https://discuss.circleci.com/c/orbs).

### How to pack your orb for validation or publishing a dev version

circleci orb pack src > orb.yml

### How to validate orb on your local via circleci cli

circleci orb validate orb.yml

### How to publish dev orb from your local

* Your orb will expire in 90 days unless a new version is published on the label `dev:alpha`

circleci orb publish orb.yml odds88/tradeart-orb@dev:alpha
