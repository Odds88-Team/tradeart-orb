# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`odds88/tradeart-orb` — the CircleCI orb that holds every TradeArt build/deploy pipeline step. It contains no application code; it is authored in *unpacked* form under [src/](src/) and packed into a single `orb.yml` at publish time (`orb.yml` is gitignored — never commit it).

Consumer repositories import this orb and compose its jobs into their own workflows, so **any change here affects every TradeArt service pipeline**. Treat parameter renames, removals, and default changes as breaking.

## Common commands

```bash
circleci orb pack src > orb.yml                       # pack unpacked source into a single orb
circleci orb validate orb.yml                         # validate the packed orb locally
circleci orb publish orb.yml odds88/tradeart-orb@dev:alpha  # publish a dev version (expires in 90 days)
yamllint src                                          # config in .yamllint (relaxed, max line length 200)
bats src/tests                                        # run the BATS tests for src/scripts/*.sh
```

## Publishing

A production release is cut by pushing a tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$` (see `release-filters` in [.circleci/test-deploy.yml](.circleci/test-deploy.yml)). Current line is `v4.x`. Semantic versioning — bump major for any breaking parameter change.

The pipeline is a two-stage setup workflow:
1. [.circleci/config.yml](.circleci/config.yml) (`setup: true`) — lint, review (`RC009,RC010` excluded), pack, shellcheck, then publish a `dev:` version and hand off via `orb-tools/continue`.
2. [.circleci/test-deploy.yml](.circleci/test-deploy.yml) — runs integration tests against the just-published dev orb; on a release tag it also runs `PROD publish`.

Integration tests for new commands go into `test-deploy.yml`'s `jobs:` section and must be wired into the `test-deploy` workflow with `filters: *filters`, and added to the `requires:` list of `PROD publish` — otherwise they don't gate the release. The BATS unit tests for `src/scripts` run inside `command-test` (via `circleci/bats`), which already gates `PROD publish`, so a new `src/tests/*.bats` file needs no wiring.

## Source layout and composition model

`src/@orb.yml` is the orb root: description, display URLs, and imported orbs (`circleci/slack@5.1.1` as `slack`). At pack time each directory becomes a top-level key, with the filename as the element name (`src/jobs/build.yml` → job `build`).

- [src/executors/](src/executors/) — `default` (.NET SDK image `trading-dev-core-sdk`, tag parameterized, working dir `/mnt/ramdisk`) and `docker-builder` (`trading-dev-docker-build:4.0`, used for anything touching Docker/AWS/ArgoCD).
- [src/commands/](src/commands/) — the reusable steps that do real work.
- [src/jobs/](src/jobs/) — the public surface consumers use. Jobs are thin: pick an executor, declare parameters, call commands, then notify Slack.
- [src/scripts/](src/scripts/) — shell bodies inlined via `<<include(scripts/x.sh)>>`; the only part covered by BATS tests.

### Conventions that hold across nearly every job

- **Job = executor + parameters + commands + Slack notify.** Almost every job ends with `inject_slack_templates` followed by `slack/notify` on `event: fail` (and `event: pass` for deploys) to `odds88-circleci-notifications`. Keep that tail when adding jobs.
- **`executor_class` parameter** (default `medium`, `small` for lightweight jobs) is threaded into the executor's `resource_class`.
- **`builder_image_tag`** (default `'3.1'`) selects the `default` executor image tag; `test-with-db` uses `'5.0-db'`, `intent_check` pins `"10.0"`.
- **`inject_version_data`** must run before anything that references `$FULL_VERSION`. It writes `VERSION_PREFIX=<base_version>.<pipeline_id>`, a branch-derived `VERSION_SUFFIX` (`master` → `test`), and `FULL_VERSION=$VERSION_PREFIX-$VERSION_SUFFIX` into `$BASH_ENV`. Because these are `$BASH_ENV` exports, `$FULL_VERSION` is passed to later commands as the literal string `$FULL_VERSION`, resolved at shell time — not as a config-time value.
- **Build → Docker handoff** goes through the workspace: `build`/`lambda_build` `persist_to_workspace` the whole tree; `docker`/`lambda_docker` `attach_workspace` at `./`. Docker images are built from a `CircleDockerfile` (not `Dockerfile`) in the consumer repo, multi-arch (`linux/amd64,linux/arm64`) via buildx, pushed to ECR `178636341549.dkr.ecr.eu-central-1`.

### Branch → environment mapping

This is hardcoded in shell across several commands and is the single most important thing to keep consistent when editing them:

| Branch | Env name | Version suffix |
|---|---|---|
| `master` | TEST | `test` |
| `staging` | STAGE | `staging` |
| `release` | PROD | `release` |

Any new env-aware command must reproduce all three branches and fall back to `master` for anything else. `tradeart-circleci-notifications` is *not* env-aware: `inject_slack_templates` clones its default branch.

### External repositories the orb clones at runtime

Several commands clone sibling private repos over SSH using a deploy key echoed into `~/.ssh/id_rsa_1`:

- `Odds88-Team/tradeart-circleci-notifications` (`GITHUB_DEPLOY_PRIVATE_KEY`) — Slack message templates and the `users_map.json` CircleCI-user → Slack-tag map. Cloned by `inject_slack_templates`.
- `Odds88-Team/tradeart-tenants` / `tradeart-tenants-prod` (`DEV_CLUSTER_REPO_KEY` / `PROD_CLUSTER_REPO_KEY`) — ArgoCD GitOps repos; `update_argo_image_*` `sed`s the image tag and pushes a commit.
- `Odds88-Team/tradeart-intent-modules` (`GITHUB_INTENT_PRIVATE_KEY`) — Intent Architect modules for `intent_check`.

### Deployment

Deployment is **ArgoCD GitOps only** (`argo_deploy_dev`, `argo_deploy_prod`) — the orb never touches a cluster. It commits a new image tag to the tenants repo: `deployment_type: global` edits `argocd/services/overlays/<env>/<svc>/version.yaml`; `tenanted` edits `argocd/base/.../deployment.yaml`. `lambda_deploy` is the one exception, calling `aws lambda update-function-code` directly.

The tenants repos are shared, so parallel service pipelines regularly race each other's push. `update_argo_image_*` runs `src/scripts/update_argo_image.sh`, which retries a push that lost the race to another deploy (`push_max_attempts`, default 3) by resetting onto the new remote head and re-applying the tag edit there; any other push failure is fatal. Keep the edit idempotent and re-runnable if you change it.

The Helm push path (`helm`, `helm-tenanted`, `validate-helm`, `validate-helm-tenanted`, `connect_to_vpn`, `checkout_terraform_project`) was removed in v5 — do not reintroduce cluster-facing deploys.

### Testing jobs

`test` and `test-with-db` both `checkout` then `git fetch --no-filter --refetch`. CircleCI's checkout is a *blobless* clone (`--filter=blob:none`); without the refetch to hydrate the blobs, SonarCloud's jgit blame fails with `Missing blob`. Keep that fetch on any job running the Sonar scanner, and use the built-in `checkout` — clone orbs that rely on `$CIRCLE_REPOSITORY_URL` or `$CHECKOUT_KEY` fail, as GitHub App projects set neither. `docker_layer_caching` is opt-in (default `false`) because it bills a flat ~200 credits and these jobs run no docker build. `dotnet_test` runs the SonarCloud scanner (org `odds88`); `dotnet_test_no_sonar` / `test_no_sonar` are the fork for repos without a Sonar project. Both convert `.trx` to JUnit via `trx2junit` before `store_test_results`.
