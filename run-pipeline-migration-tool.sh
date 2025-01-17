#!/usr/bin/env bash

current=${1:?Missing the old task bundle}
new=${2:?Missing the new task bundle}

current_value=${current#*:}
current_value=${current_value%@*}

new_value=${new#*:}
new_value=${new_value%@*}

upgrades="[{
    \"depName\": \"${current%%:*}\",
    \"currentValue\": \"${current_value}\",
    \"currentDigest\": \"${current##*@}\",
    \"newValue\": \"${new_value}\",
    \"newDigest\": \"${new##*@}\",
    \"depTypes\": [\"tekton-bundle\"],
    \"packageFile\": \".tekton/build-pipeline.yaml\",
    \"parentDir\": \".tekton\"
}]"

export PMT_LOCAL_TEST=1
pipeline-migration-tool --cache-dir /tmp/pmt-cache -u "$upgrades"