#!/usr/bin/env bash
set -e
pipeline_file=$1
if ! yq -e '.spec.tasks[] | select(.name == "clone") | .params[] | select(.name == "depth" and .value == "1")' "$pipeline_file"
then
    yq -i '(.spec.tasks[] | select(.name == "clone") | .params) += [{"name": "depth", "value": "1"}]' "$pipeline_file"
fi
