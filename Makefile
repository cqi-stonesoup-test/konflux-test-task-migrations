
.PHONY: mintmaker/trigger
mintmaker/trigger:
	oc -n mintmaker apply -f trigger-mintmaker.yaml
	oc -n mintmaker delete DependencyUpdateCheck $(shell yq '.metadata.name' trigger-mintmaker.yaml)


.PHONY: prepare
prepare:
	bash prepare.sh

