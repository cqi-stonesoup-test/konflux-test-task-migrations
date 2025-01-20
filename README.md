# konflux-test-task-migrations

## Requirements

- Fork of [konflux-ci/build-definitions](https://github.com/konflux-ci/build-definitions/)
- Fork of [konflux-ci/mintmaker](https://github.com/konflux-ci/mintmaker/)
- Fork of [konflux-ci/mintmaker-renovate-image](https://github.com/konflux-ci/mintmaker-renovate-image/)
- Fork of [konflux-ci/infra-deployments](https://github.com/konflux-ci/infra-deployments)
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
    ./hack/bootstrap-cluster.sh preview
    ```
    - No need to wait for all components synchronized to the cluster. Testing can start as long as the application-api and mintmaker become healthy.
- Create secret under `mintmaker` namespace
    ```bash
    make mintmaker/create-pac-secret
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

Update PR: https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/3 https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/4

### Add a task to pipeline

Commit: https://github.com/tkdchen/build-definitions/commit/ad1ab70ae8cc9364ced1a979a20afd0890390f0f

Update PR: https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/5

### Remove a task from pipeline

Create a new task in build-definitions:

```bash
mkdir -p task/greeting/0.1 || :
cat >task/greeting/0.1/greeting.yaml <<EOF
apiVersion: tekton.dev/v1
kind: Task
metadata:
  labels:
    app.kubernetes.io/version: "0.1"
    build.appstudio.redhat.com/build_type: "docker"
  annotations:
    tekton.dev/pipelines.minVersion: "0.12.1"
    tekton.dev/tags: "image-build, appstudio"
  name: greeting
spec:
  steps:
  - name: step-1
    image: registry.access.redhat.com/ubi9/ubi-minimal:9.5-1734497536@sha256:94b434a29a894129301f6ff52dbddb19422fc800a109170c634b056da8cd704f
    script: |
      echo "Hello Cloud Native."
EOF
git add task/greeting/0.1/greeting.yaml
git commit -m "Add new task greeting"
QUAY_NAMESPACE=mytestworkload SKIP_BUILD=1 SKIP_INSTALL=1 TEST_TASKS="greeting" ./hack/build-and-push.sh
```

Ensure repository `quay.io/mytestworkload/task-greeting` is public.

Create a migration to add the new task to pipeline:

```bash
mkdir -p task/summary/0.2/migrations/
IFS=. read -r major minor patch < <(
    yq '.metadata.labels."app.kubernetes.io/version"' task/summary/0.2/summary.yaml
)
patch=$((patch+1))
new_version="${major}.${minor}.${patch}"
yq -i "(.metadata.labels.\"app.kubernetes.io/version\") |= \"${new_version}\"" task/summary/0.2/summary.yaml
digest=$(skopeo inspect --format '{{.Digest}}' docker://quay.io/mytestworkload/task-greeting:0.1)
cat >"task/summary/0.2/migrations/${new_version}.sh" <<EOF
#!/usr/bin/env bash
set -e
pipeline_file="\$1"
bundle_ref=quay.io/mytestworkload/task-greeting:0.1@${digest}
yq -i "
.spec.tasks += {
    \"name\": \"greeting\",
    \"taskRef\": {
        \"resolver\": \"bundles\",
        \"params\": [
            {\"name\": \"name\", \"value\": \"greeting\"},
            {\"name\": \"kind\", \"value\": \"task\"},
            {\"name\": \"bundle\", \"value\": \"\${bundle_ref}\"}
        ]
    }
}
" \\
"\$pipeline_file"
EOF

git add \
    task/summary/0.2/summary.yaml \
    "task/summary/0.2/migrations/${new_version}.sh"
git commit -m "Add task greeting to pipeline"

QUAY_NAMESPACE=mytestworkload SKIP_BUILD=1 SKIP_INSTALL=1 TEST_TASKS="summary" ./hack/build-and-push.sh
```

Trigger Mintmaker and merge the update pull request.

Create a migration to remove greeting task from pipeline:

```bash
mkdir -p task/greeting/0.2/migrations || :

cp task/greeting/0.1/greeting.yaml task/greeting/0.2/greeting.yaml
yq -i "(.metadata.labels.\"app.kubernetes.io/version\") |= \"0.2.1\"" task/greeting/0.2/greeting.yaml

echo "Bump a new version for removing this task from pipeline." >task/greeting/0.2/MIGRATION.md

cat >task/greeting/0.2/migrations/0.2.1.sh <<EOF
#!/usr/bin/env bash
set -e
pipeline_file="\$1"
yq -i "del(.spec.tasks[] | select(.name == \"greeting\"))" "\$pipeline_file"
EOF

git add \
    task/greeting/0.2/greeting.yaml \
    task/greeting/0.2/MIGRATION.md \
    task/greeting/0.2/migrations/0.2.1.sh
git commit -m "Bump a new version to remove task greeting from pipeline"

QUAY_NAMESPACE=mytestworkload SKIP_BUILD=1 SKIP_INSTALL=1 TEST_TASKS="greeting" ./hack/build-and-push.sh
```

Trigger Mintmaker and check update pull request.

- Update PR: https://github.com/cqi-stonesoup-test/konflux-test-task-migrations/pull/8
