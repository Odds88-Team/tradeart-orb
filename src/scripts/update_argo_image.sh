#!/bin/bash
# Sets the PARAM_IMAGE_REPOSITORY image tag to FULL_VERSION in the manifest of every service in PARAM_ARGO_SERVICE_NAMES,
# then commits and pushes it to the ArgoCD repository cloned into PARAM_ARGO_REPO_DIR.
# The tenants repositories are shared by every service pipeline, so a push that loses the race against another deploy
# is retried on the new remote head, up to PARAM_PUSH_MAX_ATTEMPTS times.
set -eo pipefail

: "${FULL_VERSION:?FULL_VERSION is not set, run inject_version_data first}"
MAX_ATTEMPTS="${PARAM_PUSH_MAX_ATTEMPTS:-3}"
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -i $HOME/.ssh/id_rsa_1}"

ManifestPath() {
    local template="$PARAM_TENANTED_MANIFEST_PATH"
    if [ "$PARAM_DEPLOYMENT_TYPE" = "global" ]; then
        template="$PARAM_GLOBAL_MANIFEST_PATH"
    fi
    echo "${template//\{service\}/$1}"
}

SetImageTag() {
    local service file
    for service in "${SERVICES[@]}"; do
        if [ -z "$service" ]; then
            continue
        fi
        file=$(ManifestPath "$service")
        echo "Updating image for: $service ($file)"
        if [ ! -f "$file" ]; then
            echo "Manifest $file does not exist."
            return 1
        fi
        sed -i -r "s/${PARAM_IMAGE_REPOSITORY}\:(.+)/${PARAM_IMAGE_REPOSITORY}\:${FULL_VERSION}/" "$file"
        if ! grep -qF "${PARAM_IMAGE_REPOSITORY}:${FULL_VERSION}" "$file"; then
            echo "Image tag $FULL_VERSION was not set in $file."
            return 1
        fi
    done
}

# Lost races show up as a non-fast-forward rejection, or as a failed ref lock when the other push lands mid-push.
IsLostRace() {
    printf '%s' "$1" | grep -qE '\[rejected\]|cannot lock ref|failed to update ref'
}

UpdateArgoImage() {
    echo "Deployment type: $PARAM_DEPLOYMENT_TYPE"
    IFS=',' read -ra SERVICES < <(printf '%s\n' "${PARAM_ARGO_SERVICE_NAMES// /}")
    cd "$PARAM_ARGO_REPO_DIR"
    git config user.email "tradeart_dev@yolo.com"
    git config user.name "CircleCI"
    local branch attempt push_output
    branch=$(git rev-parse --abbrev-ref HEAD)

    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        SetImageTag
        git add -A
        if git diff --cached --quiet; then
            echo "Image tag $FULL_VERSION is already set, so there is nothing to commit."
            return 0
        fi
        git commit -q -m "Deploy $PARAM_IMAGE_REPOSITORY $FULL_VERSION to $PARAM_DEPLOY_TARGET"

        if push_output=$(git push origin "HEAD:$branch" 2>&1); then
            echo "$push_output"
            echo "Pushed image tag $FULL_VERSION on attempt $attempt."
            return 0
        fi
        echo "$push_output"
        if ! IsLostRace "$push_output"; then
            echo "Push failed for a reason other than a concurrent update, not retrying."
            return 1
        fi
        echo "Push attempt $attempt/$MAX_ATTEMPTS was rejected because $branch has new commits, re-applying the tag on the new head."
        git fetch -q origin "$branch"
        git reset -q --hard FETCH_HEAD
    done

    echo "Could not push image tag $FULL_VERSION after $MAX_ATTEMPTS attempts."
    return 1
}

UpdateArgoImage
