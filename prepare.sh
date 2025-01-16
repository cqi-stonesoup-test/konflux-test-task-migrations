#!/usr/bin/env bash

set -euo pipefail

: "${LIST_REPO_STATUS:=}"

if [ -n "$LIST_REPO_STATUS" ]; then
    cd "$HOME/code/konflux/mintmaker-renovate-image" || exit 1
    echo "$HOME/code/konflux/mintmaker-renovate-image:  $(git branch --show-current)"
    cd "$HOME/code/konflux/mintmaker" || exit 1
    echo "$HOME/code/konflux/mintmaker:                 $(git branch --show-current)"
    cd "$HOME/code/konflux/build-definitions" || exit 1
    echo "$HOME/code/konflux/build-definitions:         $(git branch --show-current)"
    cd "$HOME/code/konflux/infra-deployments" || exit 1
    echo "$HOME/code/konflux/infra-deployments:         $(git branch --show-current)"
    exit 0
fi

# Custom Mintmaker image and build-definitions fork are required for setting up a Konflux cluster.

NOW=$(date --iso-8601=seconds | sed -e 's/:/_/g' -e 's/+/-/')
declare -r NOW

declare -r CONFIG_DATA_FILE=/tmp/konflux-infra-deployments-config-data.yaml

save_config() {
    local -r key=${1:?Missing key of the config.}
    local -r value=${2:?Missing value of the config.}
    echo "$key: $value" >>"$CONFIG_DATA_FILE"
}

# Output the value to stdout
read_config() {
    local -r key=${1:?Missing key of the config.}
    if ! yq -e ".${key}" "$CONFIG_DATA_FILE"; then
        echo "error: key $key is not found from config data $CONFIG_DATA_FILE."
        exit 1
    fi
}

ensure_on_a_topic_branch() {
    if [ "$(git branch --show-current)" == "main" ]; then
        echo "error: working on main branch now. Checkout to another branch." >&2
        exit 1
    fi
}

run() {
    echo "🔨 $*"
    "$@"
}

show_summary() {
    echo "################### summary ###################"
    echo
    cat "$CONFIG_DATA_FILE"
}

trap 'show_summary' EXIT ERR


############## Build and push mintmaker-renovate image ##############

: "${MINTMAKER_RENOVATE_IMAGE_REPO_DIR:="$HOME/code/konflux/mintmaker-renovate-image"}"
declare -r MINTMAKER_RENOVATE_IMAGE_REPO_DIR

echo "🔺 entering ${MINTMAKER_RENOVATE_IMAGE_REPO_DIR}"
cd "$MINTMAKER_RENOVATE_IMAGE_REPO_DIR" || exit 1
ensure_on_a_topic_branch

MINTMAKER_RENOVATE_REVISION=$(git rev-parse HEAD)
declare -r MINTMAKER_RENOVATE_REVISION

MINTMAKER_RENOVATE_IMAGE=quay.io/mytestworkload/mintmaker-renovate-image:${MINTMAKER_RENOVATE_REVISION}-${NOW}
declare -r MINTMAKER_RENOVATE_IMAGE

save_config mintmaker-renovate-repo "${MINTMAKER_RENOVATE_IMAGE_REPO_DIR}"
save_config mintmaker-renovate-branch "$(git branch --show-current)"
save_config mintmaker-renovate-revision "$MINTMAKER_RENOVATE_REVISION"
save_config mintmaker-renovate-image "$MINTMAKER_RENOVATE_IMAGE"

run podman build -t "$MINTMAKER_RENOVATE_IMAGE" .
run podman push "$MINTMAKER_RENOVATE_IMAGE"


############## Build and push mintmaker image ##############

: "${MINTMAKER_IMAGE_REPO_DIR:="$HOME/code/konflux/mintmaker"}"
declare -r MINTMAKER_IMAGE_REPO_DIR

echo "🔺 entering ${MINTMAKER_IMAGE_REPO_DIR}"
cd "$MINTMAKER_IMAGE_REPO_DIR" || exit 1
ensure_on_a_topic_branch

# Update mintmaker-renovate-image into the manager Deployment
sed -i "s|^\( \+mintmaker.appstudio.redhat.com/renovate-image\): .\+$|\1: ${MINTMAKER_RENOVATE_IMAGE}|" \
    config/manager/manager.yaml

git diff
git add config/manager/manager.yaml
git commit -m "Update custom mintmaker-renovate-image reference - ${NOW}"
remote_url=$(git config list | awk -F= '/^remote.origin.url=/ {print $2}')
declare -r remote_url
echo "🔨 Push local changes to ${remote_url}"
git push --force origin HEAD

MINTMAKER_REVISION=$(git rev-parse HEAD)
declare -r MINTMAKER_REVISION

MINTMAKER_IMAGE=quay.io/mytestworkload/mintmaker:${MINTMAKER_REVISION}-${NOW}
declare -r MINTMAKER_IMAGE

save_config mintmaker-repo "${MINTMAKER_IMAGE_REPO_DIR}"
save_config mintmaker-branch "$(git branch --show-current)"
save_config mintmaker-revision "$MINTMAKER_REVISION"
save_config mintmaker-image "$MINTMAKER_IMAGE"

run podman build -t "$MINTMAKER_IMAGE" .
run podman push "$MINTMAKER_IMAGE"


############## Build and push tasks and pipelines from build-definitions fork ##############

: "${BUILD_DEFINITIONS_FORK:="$HOME/code/konflux/build-definitions"}"
declare -r BUILD_DEFINITIONS_FORK

echo "🔺 entering ${BUILD_DEFINITIONS_FORK}"
cd "$BUILD_DEFINITIONS_FORK" || exit 1
ensure_on_a_topic_branch

TASKS_TO_BUILD=$(yq '.spec.tasks[].name' pipelines/template-build/template-build.yaml)
declare -r TASKS_TO_BUILD

echo "🔨 build and push tasks: $TASKS_TO_BUILD"

# BUILD_TAG=  # Created automatically by the script
QUAY_NAMESPACE=mytestworkload \
TEST_REPO_NAME=build-definitions-bundles-test-builds \
SKIP_BUILD=1 \
SKIP_INSTALL=1 \
TEST_TASKS="$TASKS_TO_BUILD" \
./hack/build-and-push.sh

save_config build-definitions-repo "${BUILD_DEFINITIONS_FORK}"
save_config build-definitions-branch "$(git branch --show-current)"


############## Update infra-deployments ##############

: "${INFRA_DEPLOYMENTS_REPO:="$HOME/code/konflux/infra-deployments"}"
declare -r INFRA_DEPLOYMENTS_REPO

echo "🔺 entering ${INFRA_DEPLOYMENTS_REPO}"
cd "$INFRA_DEPLOYMENTS_REPO" || exit 1
ensure_on_a_topic_branch

save_config infra-deployments-repo "${INFRA_DEPLOYMENTS_REPO}"
save_config infra-deployments-branch "$(git branch --show-current)"

# Lines added previously might remain there, just delete them.
echo "🔺 Configure MINTMAKER_* environment"

# Save the original to show diff at the end of the script
cp ./hack/preview.env ./hack/preview.env.orig

sed -i "s|^\(export MINTMAKER_IMAGE_REPO\)=.*$|\1=${MINTMAKER_IMAGE%:*}|" ./hack/preview.env
sed -i "s|^\(export MINTMAKER_IMAGE_TAG\)=.*$|\1=${MINTMAKER_IMAGE#*:}|" ./hack/preview.env
sed -i "s|^\(export MINTMAKER_PR_SHA\)=.*$|\1=${MINTMAKER_REVISION}|" ./hack/preview.env

echo "🔺 Update Mintmaker development layer"

yq -i ".resources |= [
\"../base\",
\"https://github.com/tkdchen/mintmaker/config/default?ref=${MINTMAKER_REVISION}\",
\"https://github.com/tkdchen/mintmaker/config/renovate?ref=${MINTMAKER_REVISION}\"
]" ./components/mintmaker/development/kustomization.yaml

yq -i ".images |= [{
\"name\": \"${MINTMAKER_IMAGE%:*}\",
\"newName\": \"${MINTMAKER_IMAGE%:*}\",
\"newTag\": \"${MINTMAKER_IMAGE#*:}\"
}]" ./components/mintmaker/development/kustomization.yaml

echo "🔺 Update Mintmaker staging layer"

yq -i ".resources |= [
\"../../base\",
\"../../base/external-secrets\",
\"https://github.com/tkdchen/mintmaker/config/default?ref=${MINTMAKER_REVISION}\",
\"https://github.com/tkdchen/mintmaker/config/renovate?ref=${MINTMAKER_REVISION}\"
]" \
./components/mintmaker/staging/base/kustomization.yaml

yq -i ".images |= [
{
    \"name\": \"${MINTMAKER_IMAGE%:*}\",
    \"newName\": \"${MINTMAKER_IMAGE%:*}\",
    \"newTag\": \"${MINTMAKER_IMAGE#*:}\"
},
{
    \"name\": \"${MINTMAKER_RENOVATE_IMAGE%:*}\",
    \"newName\": \"${MINTMAKER_RENOVATE_IMAGE%:*}\",
    \"newTag\": \"${MINTMAKER_RENOVATE_IMAGE#*:}\"
}
]" \
./components/mintmaker/staging/base/kustomization.yaml

echo "🔺 Update build pipeline config"
BUILD_PIPELINE_CONFIG_FILE=$(mktemp --suffix=-build-pipeline-config)
trap 'rm $BUILD_PIPELINE_CONFIG_FILE' EXIT ERR

yq '.data."config.yaml"' \
    ./components/build-service/base/build-pipeline-config/build-pipeline-config.yaml \
    >"$BUILD_PIPELINE_CONFIG_FILE"

BUNDLE_VALUES_ENV="${BUILD_DEFINITIONS_FORK}/bundle_values.env"
if [ -f "$BUNDLE_VALUES_ENV" ]; then
    source "$BUNDLE_VALUES_ENV"  # for accessing the CUSTOM_* pipeline bundles
else
    echo "error: missing bundle_values.env created by build-and-push.sh" >&2
    exit 1
fi

yq -i "
(.pipelines[] | select(.name == \"docker-build-oci-ta\") | .bundle)
|= \"${CUSTOM_DOCKER_BUILD_OCI_TA_PIPELINE_BUNDLE}\"
" "$BUILD_PIPELINE_CONFIG_FILE"

yq -i "(.data.\"config.yaml\") |= \"$(cat "$BUILD_PIPELINE_CONFIG_FILE")\"" \
    ./components/build-service/base/build-pipeline-config/build-pipeline-config.yaml

echo
echo "⚒️ $INFRA_DEPLOYMENTS_REPO"
git status
git add \
    components/mintmaker/development/kustomization.yaml \
    components/mintmaker/staging/base/kustomization.yaml

diff -u ./hack/preview.env ./hack/preview.env.orig

echo "##############  Config data #################"
cat "$CONFIG_DATA_FILE"
