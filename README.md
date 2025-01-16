# konflux-test-task-migrations

Requirements:

- Fork of konflux-ci/build-definitions
- Fork of konflux-ci/mintmaker
- Fork of konflux-ci/mintmaker-renovate-image
- Fork of konflux-ci/infra-deployments
- OpenShift cluster

Steps:

- To prepare the testing environment, run `prepare.sh`.
- Ensure infra-deployments is configured properly in the `hack/preview.env`.
    - Note that, GitHub App must be configured via variables `PAC_GITHUB_APP_*`.
- Bootstrap the cluster: `./hack/bootstrap-cluster.sh preview`
    - No need to wait for all components synchronized to the cluster as long as the application-api and mintmaker become healthy.
- Create secret under `mintmaker` namespace.

    ```bash
    cd path/to/infra-deployments
    source ./hack/preview.env
    oc create secret generic pipelines-as-code-secret \
        -n mintmaker \
        --from-literal github-private-key="$(echo $PAC_GITHUB_APP_PRIVATE_KEY | base64 -d)" \
        --from-literal github-application-id="$PAC_GITHUB_APP_ID"
    ```

- Install your GitHub App to the Component repository.
- Onboard this repository to Konflux by creating Application and Component CR: `make onboard`
- Trigger Mintmaker reconcilation: `make mintmaker/trigger`
- Check whether update PR includes expected updates.
