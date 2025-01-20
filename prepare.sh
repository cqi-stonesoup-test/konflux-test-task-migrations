#!/usr/bin/env bash

set -euo pipefail

# Custom Mintmaker image and build-definitions fork are required for setting up a Konflux cluster.

NOW=$(date --iso-8601=seconds | sed -e 's/:/_/g' -e 's/+/-/')
declare -r NOW

declare -r CONFIG_DATA_FILE=config-data.yaml
if [ -f "$CONFIG_DATA_FILE" ]; then
    rm "$CONFIG_DATA_FILE"
fi
touch "$CONFIG_DATA_FILE"

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

############## Build and push mintmaker-renovate image ##############

: "${mintmaker_renovate_git_repo:="$HOME/code/konflux/mintmaker-renovate-image"}"
declare -r mintmaker_renovate_git_repo

echo "🔺 entering ${mintmaker_renovate_git_repo}"
cd "$mintmaker_renovate_git_repo" || exit 1
ensure_on_a_topic_branch

mintmaker_renovate_git_revision=$(git rev-parse HEAD)
declare -r mintmaker_renovate_git_revision

mintmaker_renovate_image=quay.io/mytestworkload/mintmaker-renovate-image:${mintmaker_renovate_git_revision}-${NOW}
declare -r mintmaker_renovate_image

save_config mintmaker-renovate-repo "${mintmaker_renovate_git_repo}"
save_config mintmaker-renovate-branch "$(git branch --show-current)"
save_config mintmaker-renovate-revision "$mintmaker_renovate_git_revision"
save_config mintmaker-renovate-image "$mintmaker_renovate_image"

run podman build -t "$mintmaker_renovate_image" .
run podman push "$mintmaker_renovate_image"


############## Build and push mintmaker image ##############

: "${mintmaker_git_repo:="$HOME/code/konflux/mintmaker"}"
declare -r mintmaker_git_repo

echo "🔺 entering ${mintmaker_git_repo}"
cd "$mintmaker_git_repo" || exit 1
ensure_on_a_topic_branch

# Update mintmaker-renovate-image into the manager Deployment
sed -i "s|^\( \+mintmaker.appstudio.redhat.com/renovate-image\): .\+$|\1: ${mintmaker_renovate_image}|" \
    config/manager/manager.yaml

git diff
git add config/manager/manager.yaml
git commit -m "Update custom mintmaker-renovate-image reference - ${NOW}"
remote_url=$(git config list | awk -F= '/^remote.origin.url=/ {print $2}')
echo "🔨 Push local changes to ${remote_url}"
git push --force origin HEAD
unset remote_url

mintmaker_git_revision=$(git rev-parse HEAD)
declare -r mintmaker_git_revision

mintmaker_image=quay.io/mytestworkload/mintmaker:${mintmaker_git_revision}-${NOW}
declare -r mintmaker_image

save_config mintmaker-repo "${mintmaker_git_repo}"
save_config mintmaker-branch "$(git branch --show-current)"
save_config mintmaker-revision "$mintmaker_git_revision"
save_config mintmaker-image "$mintmaker_image"

run podman build -t "$mintmaker_image" .
run podman push "$mintmaker_image"


############## Build and push tasks and pipelines from build-definitions fork ##############

build_and_push_tasks_pipelines() {
    : "${build_definitions_git_repo:="$HOME/code/konflux/build-definitions"}"
    declare -r build_definitions_git_repo

    echo "🔺 entering ${build_definitions_git_repo}"
    cd "$build_definitions_git_repo" || exit 1
    ensure_on_a_topic_branch

    : "${quay_org:=mytestworkload}"

    # BUILD_TAG=  # Created automatically by the script
    QUAY_NAMESPACE="$quay_org" \
    SKIP_BUILD=1 \
    SKIP_INSTALL=1 \
    ./hack/build-and-push.sh

    save_config build-definitions-repo "${build_definitions_git_repo}"
    save_config build-definitions-branch "$(git branch --show-current)"
}

build_and_push_tasks_pipelines


############## Update infra-deployments ##############

: "${infra_deployment_git_repo:="$HOME/code/konflux/infra-deployments"}"
declare -r infra_deployment_git_repo

echo "🔺 entering ${infra_deployment_git_repo}"
cd "$infra_deployment_git_repo" || exit 1
ensure_on_a_topic_branch

save_config infra-deployments-repo "${infra_deployment_git_repo}"
save_config infra-deployments-branch "$(git branch --show-current)"

# Lines added previously might remain there, just delete them.
echo "🔺 Configure MINTMAKER_* environment"

# Save the original to show diff at the end of the script
cp ./hack/preview.env ./hack/preview.env.orig

sed -i "s|^\(export MINTMAKER_IMAGE_REPO\)=.*$|\1=${mintmaker_image%:*}|" ./hack/preview.env
sed -i "s|^\(export MINTMAKER_IMAGE_TAG\)=.*$|\1=${mintmaker_image#*:}|" ./hack/preview.env
sed -i "s|^\(export MINTMAKER_PR_SHA\)=.*$|\1=${mintmaker_git_revision}|" ./hack/preview.env

echo "🔺 Update Mintmaker development layer"

yq -i ".resources |= [
    \"../base\",
    \"https://github.com/tkdchen/mintmaker/config/default?ref=${mintmaker_git_revision}\",
    \"https://github.com/tkdchen/mintmaker/config/renovate?ref=${mintmaker_git_revision}\"
]" ./components/mintmaker/development/kustomization.yaml

yq -i ".images |= [{
    \"name\": \"quay.io/konflux-ci/mintmaker\",
    \"newName\": \"${mintmaker_image%:*}\",
    \"newTag\": \"${mintmaker_image#*:}\"
}]" ./components/mintmaker/development/kustomization.yaml

echo "🔺 Update Mintmaker staging layer"

yq -i ".resources |= [
    \"../../base\",
    \"../../base/external-secrets\",
    \"https://github.com/tkdchen/mintmaker/config/default?ref=${mintmaker_git_revision}\",
    \"https://github.com/tkdchen/mintmaker/config/renovate?ref=${mintmaker_git_revision}\"
]" \
./components/mintmaker/staging/base/kustomization.yaml

yq -i ".images |= [
{
    \"name\": \"quay.io/konflux-ci/mintmaker\",
    \"newName\": \"${mintmaker_image%:*}\",
    \"newTag\": \"${mintmaker_image#*:}\"
},
{
    \"name\": \"quay.io/konflux-ci/mintmaker-renovate-image\",
    \"newName\": \"${mintmaker_renovate_image%:*}\",
    \"newTag\": \"${mintmaker_renovate_image#*:}\"
}
]" \
./components/mintmaker/staging/base/kustomization.yaml

echo "🔺 Update build pipeline config"
build_pipeline_config_file=$(mktemp --suffix=-build-pipeline-config)
declare -r build_pipeline_config_file
trap 'rm $build_pipeline_config_file' EXIT ERR

yq '.data."config.yaml"' \
    ./components/build-service/base/build-pipeline-config/build-pipeline-config.yaml \
    >"$build_pipeline_config_file"

bundle_values_env="${build_definitions_git_repo}/bundle_values.env"
if [ -f "$bundle_values_env" ]; then
    source "$bundle_values_env"  # for accessing the CUSTOM_* pipeline bundles
else
    echo "error: missing bundle_values.env created by build-and-push.sh" >&2
    exit 1
fi

# For testing, just use the default pipeline
yq -i "
(.pipelines[] | select(.name == \"docker-build-oci-ta\") | .bundle)
|= \"${CUSTOM_DOCKER_BUILD_OCI_TA_PIPELINE_BUNDLE}\"
" "$build_pipeline_config_file"

yq -i "(.data.\"config.yaml\") |= \"$(cat "$build_pipeline_config_file")\"" \
    ./components/build-service/base/build-pipeline-config/build-pipeline-config.yaml

echo
echo "⚒️ $infra_deployment_git_repo"
git status
git add \
    components/mintmaker/development/kustomization.yaml \
    components/mintmaker/staging/base/kustomization.yaml

diff -u ./hack/preview.env ./hack/preview.env.orig

echo "##############  Config data #################"
cat "$CONFIG_DATA_FILE"
