# Runs src/scripts/halt_unless_changed.sh in a clone of a local bare repository, with circleci-agent stubbed to echo its call.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../scripts/halt_unless_changed.sh"
    cd "$BATS_TEST_TMPDIR"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

    mkdir bin
    printf '#!/bin/bash\necho "circleci-agent $*"\n' > bin/circleci-agent
    chmod +x bin/circleci-agent
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    git init -q --bare remote.git
    git -C remote.git symbolic-ref HEAD refs/heads/master
    git clone -q remote.git repo 2>/dev/null
    cd repo
    git symbolic-ref HEAD refs/heads/master
    Change Lib/a.cs
    Change Lib.Extra/a.cs
    Change Other/b.cs
    git add -A
    git commit -qm init
    git push -q origin HEAD:master

    export CIRCLE_BRANCH=master
    export PARAM_PATHS=Lib
}

Change() {
    mkdir -p "$(dirname "$1")"
    echo "$RANDOM$RANDOM" >> "$1"
}

Commit() {
    Change "$1"
    git add -A
    git commit -qm "change $1"
}

Halted() {
    [[ "$output" == *"halting the job."* ]] && [[ "$output" == *"circleci-agent step halt"* ]]
}

NotHalted() {
    [[ "$output" != *"circleci-agent"* ]]
}

@test '1: Carries on when the last commit on master changed a watched path' {
    Commit Lib/a.cs
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Lib/a.cs"* ]]
    NotHalted
}

@test '2: Halts when the last commit on master changed only other paths' {
    Commit Other/b.cs
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    Halted
}

@test '3: Does not match a sibling directory that only shares the prefix' {
    Commit Lib.Extra/a.cs
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    Halted
}

@test '4: Carries on when any one of several watched paths changed' {
    export PARAM_PATHS="Lib Other/b.cs"
    Commit Other/b.cs
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Other/b.cs"* ]]
    NotHalted
}

@test '5: Covers every commit of a merged pull request' {
    git checkout -q -b pr
    Commit Lib/a.cs
    Commit Other/b.cs
    git checkout -q master
    git merge -q --no-ff -m "Merge pull request" pr
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Lib/a.cs"* ]]
    NotHalted
}

@test '6: Treats staging and release like master' {
    Commit Other/b.cs
    for branch in staging release; do
        export CIRCLE_BRANCH=$branch
        run bash "$SCRIPT"
        [ "$status" -eq 0 ]
        Halted
    done
}

@test '7: Covers every commit since a feature branch left master' {
    export CIRCLE_BRANCH=feature
    git checkout -q -b feature
    Commit Lib/a.cs
    Commit Other/b.cs
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Lib/a.cs"* ]]
    NotHalted
}

@test '8: Ignores changes master made after a feature branch left it' {
    export CIRCLE_BRANCH=feature
    git checkout -q -b feature
    git checkout -q master
    Commit Lib/a.cs
    git push -q origin HEAD:master
    git checkout -q feature
    Commit Other/b.cs
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    Halted
}

@test '9: Carries on when there is no revision to compare against' {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not determine the revision to compare against, carrying on."* ]]
    NotHalted
}

@test '10: Carries on when no paths are given' {
    export PARAM_PATHS=""
    Commit Other/b.cs
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No paths to watch, carrying on."* ]]
    NotHalted
}
