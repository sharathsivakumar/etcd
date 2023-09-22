#!/usr/bin/env bash
#
# Run only e2e tests

# $ PASSES=unit ./scripts/test.sh
# $ PASSES=integration ./scripts/test.sh
#
#
# Run tests for one package
# Each pass has different default timeout, if you just run tests in one package or 1 test case then you can set TIMEOUT
# flag for different expectation
#
# $ PASSES=unit PKG=./wal TIMEOUT=1m ./scripts/test.sh
# $ PASSES=integration PKG=./clientv3 TIMEOUT=1m ./scripts/test.sh
#
# Run specified unit tests in one package
# To run all the tests with prefix of "TestNew", set "TESTCASE=TestNew ";
# to run only "TestNew", set "TESTCASE="\bTestNew\b""
#
# $ PASSES=unit PKG=./wal TESTCASE=TestNew TIMEOUT=1m ./scripts/test.sh
# $ PASSES=unit PKG=./wal TESTCASE="\bTestNew\b" TIMEOUT=1m ./scripts/test.sh
# $ PASSES=integration PKG=./client/integration TESTCASE="\bTestV2NoRetryEOF\b" TIMEOUT=1m ./scripts/test.sh
#
# KEEP_GOING_SUITE must be set to true to keep going with the next suite execution, passed to PASSES variable when there is a failure
# in a particular suite.
# KEEP_GOING_MODULE must be set to true to keep going with execution when there is failure in any module.
#
# Run code coverage
# COVERDIR must either be a absolute path or a relative path to the etcd root
# $ COVERDIR=coverage PASSES="build cov" ./scripts/test.sh
# $ go tool cover -html ./coverage/cover.out
set -e

# Consider command as failed when any component of the pipe fails:
# https://stackoverflow.com/questions/1221833/pipe-output-and-capture-exit-status-in-bash
set -o pipefail
set -o nounset

# The test script is not supposed to make any changes to the files
# e.g. add/update missing dependencies. Such divergences should be
# detected and trigger a failure that needs explicit developer's action.
export GOFLAGS=-mod=readonly
export ETCD_VERIFY=all

source ./scripts/test_lib.sh
source ./scripts/build_lib.sh

OUTPUT_FILE=${OUTPUT_FILE:-""}

if [ -n "${OUTPUT_FILE}" ]; then
  log_callout "Dumping output to: ${OUTPUT_FILE}"
  exec > >(tee -a "${OUTPUT_FILE}") 2>&1
fi

PASSES=${PASSES:-"gofmt bom dep build unit"}
KEEP_GOING_SUITE=${KEEP_GOING_SUITE:-false}
PKG=${PKG:-}
SHELLCHECK_VERSION=${SHELLCHECK_VERSION:-"v0.8.0"}

if [ -z "${GOARCH:-}" ]; then
  GOARCH=$(go env GOARCH);
fi

# determine whether target supports race detection
if [ -z "${RACE:-}" ] ; then
  if [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ]; then
    RACE="--race"
  else
    RACE="--race=false"
  fi
else
  RACE="--race=${RACE:-true}"
fi

# This options make sense for cases where SUT (System Under Test) is compiled by test.
COMMON_TEST_FLAGS=("${RACE}")
if [[ -n "${CPU:-}" ]]; then
  COMMON_TEST_FLAGS+=("--cpu=${CPU}")
fi

log_callout "Running with ${COMMON_TEST_FLAGS[*]}"

RUN_ARG=()
if [ -n "${TESTCASE:-}" ]; then
  RUN_ARG=("-run=${TESTCASE}")
fi

function build_pass {
  log_callout "Building etcd"
  run_for_modules run go build "${@}" || return 2
  GO_BUILD_FLAGS="-v" etcd_build "${@}"
  GO_BUILD_FLAGS="-v" tools_build "${@}"
}


################Run e2e tests###############################################
function e2e_pass {
  # e2e tests are running pre-build binary. Settings like --race,-cover,-cpu does not have any impact.
  # shellcheck disable=SC2068
  run_for_module "tests" go_test "./e2e/..." "keep_going" : -timeout="${TIMEOUT:-30m}" ${RUN_ARG[@]:-} "$@" || return $?
  # shellcheck disable=SC2068
  run_for_module "tests" go_test "./common/..." "keep_going" : --tags=e2e -timeout="${TIMEOUT:-30m}" ${RUN_ARG[@]:-} "$@"
}


########### MAIN ###############################################################

log_callout "Starting at: $(date)"
fail_flag=false

  if run_pass "${PASSES}" "${@}"; then
    :
  else
    fail_flag=true
  fi

if [ "$fail_flag" = true ]; then
  log_error "There was FAILURE in the test suites ran. Look above log detail"
  exit 255
fi

log_success "SUCCESS"