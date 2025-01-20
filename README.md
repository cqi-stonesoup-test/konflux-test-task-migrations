# konflux-test-task-migrations

## Requirements

- Fork of konflux-ci/build-definitions
- Fork of konflux-ci/mintmaker
- Fork of konflux-ci/mintmaker-renovate-image
- Fork of konflux-ci/infra-deployments
- OpenShift cluster

## Configuration

- `mintmaker_renovate_git_repo`: path to the git repository of mintmaker-renovate-image.
- `mintmaker_git_repo`: path to the git repository of mintmaker.
- `build_definitions_git_repo`: path to the git repository of build-definitions.
- `infra_deployment_git_repo`: path to the git repository of infra-deployments.
- `quay_org`: the Quay.io orgnization for testing.

## Steps

- To prepare the testing environment, run `prepare.sh`.

- Commit changes made to local infra-deployments repository.

- Ensure infra-deployments is configured properly in the `hack/preview.env`.

    - Note that, GitHub App must be configured via variables `PAC_GITHUB_APP_*`.

- Bootstrap the cluster

    ```bash
    ./hack/bootstrap-cluster.sh preview`
    ```

    - No need to wait for all components synchronized to the cluster. Testing can start as long as the application-api and mintmaker become healthy.

- Create secret under `mintmaker` namespace

    ```bash
    make mintmaker/create-pac-secret`
    ```

- Install your GitHub App to the Component repository.

- Onboard this repository to Konflux by creating Application and Component CR

    ```bash
    make onboard
    ```

- Trigger Mintmaker reconcilation

    ```bash
    make mintmaker/trigger
    ```

- Check whether update PR includes expected updates.

After setting up the whole environment, when each time to test migrations:

- Make migrations for tasks
- Commit and push
- Build and push to Quay.io
- Trigger Mintmaker reconcilation `make mintmaker/trigger`

## Test Cases

All the tests are implemented with a fork of build-definitions.

### Change execution order of a task

Commit: https://github.com/tkdchen/build-definitions/commit/6854c4ed71cb7c50ae21afd7223443dba9571f31

Update PR: https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/2

### Change execution order of task `git-clone` and set a parame for task `build-container`

Commit: https://github.com/tkdchen/build-definitions/commit/3b108756bb95bece444ec7b66896157057f7d309

Update PR:

- https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/3
- https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/4

### Add a task to pipeline

Commit: https://github.com/tkdchen/build-definitions/commit/ad1ab70ae8cc9364ced1a979a20afd0890390f0f

Update PR: https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/5/files

