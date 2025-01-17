#!/usr/bin/env bash

set -e

cd $HOME/code/konflux/infra-deployments || exit 1

if [ ! -f "./hack/preview.env" ]; then
    echo "infra-deployments is not configured. Copy the preview-template.env" >&2
    exit 1
fi

source ./hack/preview.env

if [ -z "$PAC_GITHUB_APP_PRIVATE_KEY" ]; then
    echo "PAC_GITHUB_APP_PRIVATE_KEY is not configured." >&2
    exit 1
fi

if [ -z "$PAC_GITHUB_APP_ID" ]; then
    echo "PAC_GITHUB_APP_ID is not configured." >&2
    exit 1
fi

if oc get secret pipelines-as-code-secret -n mintmaker >/dev/null 2>&1; then
    oc delete secret pipelines-as-code-secret -n mintmaker 
fi

oc create secret generic pipelines-as-code-secret \
    -n mintmaker \
    --from-literal github-private-key="$(base64 -d <<<"${PAC_GITHUB_APP_PRIVATE_KEY}")" \
    --from-literal github-application-id="${PAC_GITHUB_APP_ID}"