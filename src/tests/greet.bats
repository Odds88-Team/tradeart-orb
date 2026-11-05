# Runs prior to every test
setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../scripts/greet.sh"
    # Stub the CircleCI CLI so `circleci env subst` echoes its input, wherever the tests run.
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\necho "$3"\n' > "$BATS_TEST_TMPDIR/bin/circleci"
    chmod +x "$BATS_TEST_TMPDIR/bin/circleci"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test '1: Greet the world' {
    export PARAM_TO="World"
    run bash "$SCRIPT"
    [ "$output" == "Hello World!" ]
}

@test '2: Greet the world when no one is given' {
    export PARAM_TO=""
    run bash "$SCRIPT"
    [ "$output" == "Hello World!" ]
}
