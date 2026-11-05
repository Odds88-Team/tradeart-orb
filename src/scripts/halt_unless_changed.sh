#!/bin/bash
# Halts the job, without failing it, when no file under PARAM_PATHS changed in the commits this pipeline brings in.
# On master, staging and release those are the commits of the last merge (the diff against the first parent), on any other
# branch every commit since it left master, so each pipeline of a branch covers everything the branch touched.
# When the revision to compare against cannot be determined, the job carries on rather than risk skipping a change.
set -eo pipefail

read -ra WATCHED_PATHS <<< "$PARAM_PATHS"

BaseRevision() {
    case "$CIRCLE_BRANCH" in
        master | staging | release)
            git rev-parse -q --verify "HEAD^1"
            ;;
        *)
            git fetch -q origin master && git merge-base HEAD FETCH_HEAD
            ;;
    esac
}

HaltUnlessChanged() {
    if [ ${#WATCHED_PATHS[@]} -eq 0 ]; then
        echo "No paths to watch, carrying on."
        return 0
    fi
    local base changed
    if ! base=$(BaseRevision); then
        echo "Could not determine the revision to compare against, carrying on."
        return 0
    fi
    # --no-renames lists both sides of a rename, and spares a blobless clone from fetching blobs to detect it.
    changed=$(git diff --name-only --no-renames "$base" HEAD -- "${WATCHED_PATHS[@]}")
    if [ -n "$changed" ]; then
        echo "Changed under ${WATCHED_PATHS[*]} since ${base:0:7}:"
        echo "$changed"
        return 0
    fi
    echo "Nothing under ${WATCHED_PATHS[*]} changed since ${base:0:7}, halting the job."
    circleci-agent step halt
}

HaltUnlessChanged
