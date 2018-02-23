
.PHONY: create destroy

INSTANCE_NAME = azuremyst
IMAGE := debian-9-stretch-v20180206
IMAGE_PROJECT := debian-cloud
ZONE := europe-west1-d
MACHINE_TYPE := n1-standard-2

serverconf.sh: serverconf.json
	jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' $^ > $@

serverconf.json: serverconf.json.example
	cp $^ $@

create:
	gcloud compute instances create $(INSTANCE_NAME) \
		--image $(IMAGE) \
		--image-project $(IMAGE_PROJECT) \
		--zone $(ZONE) \
		--machine-type $(MACHINE_TYPE) \
		--tags worldserver,authserver,buildserver \
		--metadata-from-file startup-script=startup-script.sh

destroy:
	gcloud compute instances delete $(INSTANCE_NAME)

