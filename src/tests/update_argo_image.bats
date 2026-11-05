# Runs src/scripts/update_argo_image.sh against a local bare repository standing in for the ArgoCD tenants repository.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../scripts/update_argo_image.sh"
    cd "$BATS_TEST_TMPDIR"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

    git init -q --bare remote.git
    git -C remote.git symbolic-ref HEAD refs/heads/master
    git clone -q remote.git seed 2>/dev/null
    WriteManifest seed/argocd/services/overlays/dev/svc-a/version.yaml trading-svc-a:1.0.1-test
    WriteManifest seed/argocd/services/overlays/dev/svc-b/version.yaml trading-svc-a:1.0.1-test
    WriteManifest seed/argocd/base/dev/svc-a/deployment.yaml trading-svc-a:1.0.1-test
    git -C seed add -A
    git -C seed commit -qm init
    git -C seed push -q origin HEAD:master
    git clone -q remote.git tradeart-tenants

    export FULL_VERSION=1.0.42-test
    export PARAM_ARGO_REPO_DIR=tradeart-tenants
    export PARAM_ARGO_SERVICE_NAMES=svc-a
    export PARAM_IMAGE_REPOSITORY=trading-svc-a
    export PARAM_DEPLOYMENT_TYPE=global
    export PARAM_DEPLOY_TARGET=dev
    export PARAM_GLOBAL_MANIFEST_PATH="argocd/services/overlays/dev/{service}/version.yaml"
    export PARAM_TENANTED_MANIFEST_PATH="argocd/base/dev/{service}/deployment.yaml"
    export PARAM_PUSH_MAX_ATTEMPTS=3
}

WriteManifest() {
    mkdir -p "$(dirname "$1")"
    printf 'image: 178636341549.dkr.ecr.eu-central-1.amazonaws.com/%s\n' "$2" > "$1"
}

# Pushes an unrelated service's tag change from another clone, as a parallel deploy would.
PushParallelDeploy() {
    rm -rf "$BATS_TEST_TMPDIR/other"
    git clone -q "$BATS_TEST_TMPDIR/remote.git" "$BATS_TEST_TMPDIR/other"
    WriteManifest "$BATS_TEST_TMPDIR/other/argocd/services/overlays/dev/svc-other/version.yaml" "trading-svc-other:$RANDOM"
    git -C "$BATS_TEST_TMPDIR/other" add -A
    git -C "$BATS_TEST_TMPDIR/other" commit -qm "parallel deploy"
    git -C "$BATS_TEST_TMPDIR/other" push -q origin HEAD:master
}

RemoteFile() {
    git -C remote.git show "master:$1"
}

@test '1: Sets the image tag and pushes it' {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pushed image tag 1.0.42-test on attempt 1."* ]]
    [[ "$(RemoteFile argocd/services/overlays/dev/svc-a/version.yaml)" == *"trading-svc-a:1.0.42-test" ]]
    [ "$(git -C remote.git log -1 --format=%s master)" == "Deploy trading-svc-a 1.0.42-test to dev" ]
}

@test '2: Sets the image tag of every listed service' {
    export PARAM_ARGO_SERVICE_NAMES="svc-a, svc-b"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$(RemoteFile argocd/services/overlays/dev/svc-a/version.yaml)" == *":1.0.42-test" ]]
    [[ "$(RemoteFile argocd/services/overlays/dev/svc-b/version.yaml)" == *":1.0.42-test" ]]
}

@test '3: Uses the tenanted manifest for a tenanted deployment' {
    export PARAM_DEPLOYMENT_TYPE=tenanted
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$(RemoteFile argocd/base/dev/svc-a/deployment.yaml)" == *":1.0.42-test" ]]
    [[ "$(RemoteFile argocd/services/overlays/dev/svc-a/version.yaml)" == *":1.0.1-test" ]]
}

@test '4: Does not commit when the image tag is already set' {
    export FULL_VERSION=1.0.1-test
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"is already set, so there is nothing to commit."* ]]
    [ "$(git -C remote.git rev-list --count master)" -eq 1 ]
}

@test '5: Fails when the manifest has no image of the repository' {
    export PARAM_IMAGE_REPOSITORY=trading-svc-missing
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Image tag 1.0.42-test was not set in"* ]]
}

@test '6: Fails when the manifest does not exist' {
    export PARAM_ARGO_SERVICE_NAMES=svc-missing
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist."* ]]
}

@test '7: Retries on the new head when a parallel deploy pushed first' {
    PushParallelDeploy
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Push attempt 1/3 was rejected"* ]]
    [[ "$output" == *"Pushed image tag 1.0.42-test on attempt 2."* ]]
    [[ "$(RemoteFile argocd/services/overlays/dev/svc-a/version.yaml)" == *":1.0.42-test" ]]
    [ "$(git -C remote.git log -1 --format=%s master~1)" == "parallel deploy" ]
}

@test '8: Retries when a parallel deploy lands during the push' {
    # The pre-push hook pushes a parallel deploy after this push has read the remote head, on the first two pushes only.
    cat > tradeart-tenants/.git/hooks/pre-push << EOF
#!/bin/bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
count=\$(cat "$BATS_TEST_TMPDIR/pushes" 2>/dev/null || echo 0)
echo \$((count + 1)) > "$BATS_TEST_TMPDIR/pushes"
if [ "\$count" -lt 2 ]; then
    $(declare -f WriteManifest PushParallelDeploy)
    BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" PushParallelDeploy
fi
EOF
    chmod +x tradeart-tenants/.git/hooks/pre-push
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pushed image tag 1.0.42-test on attempt 3."* ]]
    [ "$(git -C remote.git rev-list --count master)" -eq 4 ]
}

@test '9: Fails once the push attempts are exhausted' {
    export PARAM_PUSH_MAX_ATTEMPTS=1
    PushParallelDeploy
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not push image tag 1.0.42-test after 1 attempts."* ]]
}

@test '10: Does not retry a push that failed for another reason' {
    git -C tradeart-tenants remote set-url origin "$BATS_TEST_TMPDIR/missing.git"
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not retrying."* ]]
    [[ "$output" != *"Push attempt"* ]]
}
