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

