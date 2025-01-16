# konflux-test-task-migrations

Requirements:

- Fork of konflux-ci/build-definitions
- Fork of konflux-ci/mintmaker
- Fork of konflux-ci/mintmaker-renovate-image
- Fork of konflux-ci/infra-deployments
- OpenShift cluster

To prepare the testing environment, run `prepare.sh`.

Steps:

- Onboard this repository to Konflux by creating Application and Component CR.
- Create CR to trigger Mintmaker reconcilation.
- Check whether update PR includes expected updates.

After `./hack/bootstrap-cluster.sh preview` from infra-deployments, create secret under `mintmaker` namespace:

```bash
source ./hack/preview.env
oc create secret generic pipelines-as-code-secret \
    -n mintmaker \
    --from-literal github-private-key="$(echo $PAC_GITHUB_APP_PRIVATE_KEY | base64 -d)" \
    --from-literal github-application-id="$PAC_GITHUB_APP_ID" \
```
