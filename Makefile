
.PHONY: mintmaker/trigger
mintmaker/trigger:
	oc -n mintmaker apply -f trigger-mintmaker.yaml

.PHONY: mintmaker/delete-DependencyUpdateCheck-cr
mintmaker/delete-DependencyUpdateCheck-cr:
	oc -n mintmaker delete DependencyUpdateCheck $(shell yq '.metadata.name' trigger-mintmaker.yaml)


.PHONY: onboard
onboard:
	oc apply -f konflux-components.yaml


.PHONY: prepare
prepare:
	bash prepare.sh


.PHONY: mintmaker/create-pac-secret
mintmaker/create-pac-secret:
	bash mintmaker-create-pac-secret.sh
