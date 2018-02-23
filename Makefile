
INSTANCE_NAME :=
IMAGE := debian-9-stretch-v20180206
IMAGE_PROJECT := debian-cloud

PROJECT_ID :=
ZONE := europe-west1-d
MACHINE_TYPE := n1-standard-2

CONF_SH := serverconf.sh
CONF_JSON := serverconf.json
ifneq ("$(wildcard serverconf-secret.json)","")
  CONF_JSON := serverconf-secret.json
endif

WORLD_CONF := worldserver.conf
AUTH_CONF := authserver.conf
CONF_FILES := $(WORLD_CONF) $(AUTH_CONF)

TC_GIT_SRC_URL := https://raw.githubusercontent.com/TrinityCore/TrinityCore/3.3.5/

MAPDATA_BUCKET :=
MAPDATA_KEY := mapdata-secret.key
MAPDATA_KEY_NAME := tc-mapdata-source
MAPDATA_KEY_DISPLAY := Read-only bucket object viewer for TrinityCore mapdata source

BOOT_DISK_SIZE := 20GB

ADMIN_RANGES := 127.0.0.1

-include secret.mk

.PHONY: create destroy clean firewall update-metadata conf conf-dist

check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
        $(error Undefined $1$(if $2, ($2))$(if $(value @), \
                required by target `$@')))

conf: $(CONF_FILES)

conf-dist: $(addsuffix .dist,$(CONF_FILES))

$(CONF_FILES): $(CONF_SH)
%.conf: %.conf.in
	env -i bash -c 'source $(CONF_SH) && envsubst < $<' \
		| sed -e 's/^#.*$$//' -e '/^$$/d' -e 's/^\([A-Za-z0-9\.]*\)\s*=\s*/\1 = /' > $@

%.conf.dist:
	curl -o $@ $(TC_GIT_SRC_URL)/src/server/$(patsubst %.conf.dist,%,$@)/$@

$(CONF_SH): $(CONF_JSON)
	jq -r 'to_entries|map("export \(.key)=\"\(.value|tostring)\"")|.[]' $< > $@

$(MAPDATA_KEY):
	@:$(call check_defined, PROJECT_ID, Google Cloud project ID)
	gcloud iam service-accounts create "$(MAPDATA_KEY_NAME)" \
		--display-name "$(MAPDATA_KEY_DISPLAY_NAME)"
	gcloud iam service-accounts list
	gcloud iam service-accounts keys create \
		--iam-account "$(MAPDATA_KEY_NAME)@$(PROJECT_ID).iam.gserviceaccount.com" $@
	gcloud iam service-accounts keys list \
		--iam-account "$(MAPDATA_KEY_NAME)@$(PROJECT_ID).iam.gserviceaccount.com"
	gcloud projects add-iam-policy-binding "$(PROJECT_ID)" \
		--member "serviceAccount:$(MAPDATA_KEY_NAME)@$(PROJECT_ID).iam.gserviceaccount.com" \
		--role "roles/storage.objectViewer"

create: $(AUTH_CONF) $(WORLD_CONF) $(MAPDATA_KEY)
	@:$(call check_defined, PROJECT_ID, Google Cloud project ID)
	@:$(call check_defined, INSTANCE_NAME, Google Cloud compute instance VM name)
	@:$(call check_defined, MAPDATA_BUCKET, Google Cloud storage bucket name containing Data/*.MPQ files)
	gcloud compute instances create $(INSTANCE_NAME) \
		--project $(PROJECT_ID) \
		--image $(IMAGE) \
		--image-project $(IMAGE_PROJECT) \
		--zone $(ZONE) \
		--machine-type $(MACHINE_TYPE) \
		--boot-disk-size $(BOOT_DISK_SIZE) \
		--tags worldserver,authserver,buildserver \
		--metadata mapdata-bucket=$(MAPDATA_BUCKET) \
		--metadata-from-file startup-script=startup-script.sh,worldserver-conf=$(WORLD_CONF),authserver-conf=$(AUTH_CONF),mapdata-key=$(MAPDATA_KEY)

update-metadata: $(AUTH_CONF) $(WORLD_CONF) $(MAPDATA_KEY)
	@:$(call check_defined, PROJECT_ID, Google Cloud project ID)
	@:$(call check_defined, INSTANCE_NAME, Google Cloud compute instance VM name)
	@:$(call check_defined, MAPDATA_BUCKET, Google Cloud storage bucket name containing Data/*.MPQ files)
	gcloud compute instances add-metadata $(INSTANCE_NAME) \
		--project $(PROJECT_ID) \
		--zone $(ZONE) \
		--metadata mapdata-bucket=$(MAPDATA_BUCKET) \
		--metadata-from-file startup-script=startup-script.sh,worldserver-conf=$(WORLD_CONF),authserver-conf=$(AUTH_CONF),mapdata-key=$(MAPDATA_KEY)

destroy:
	@:$(call check_defined, PROJECT_ID, Google Cloud project ID)
	@:$(call check_defined, INSTANCE_NAME, Google Cloud compute instance VM name)
	gcloud compute instances delete --project $(PROJECT_ID) $(INSTANCE_NAME)

firewall:
	@:$(call check_defined, PROJECT_ID, Google Cloud project ID)
	@:$(call check_defined, ADMIN_RANGES, administrative CIDR ranges to trust allow remote console and SOAP API connections)
	gcloud compute firewall-rules create --project $(PROJECT_ID) \
		--allow=tcp:3724 \
		--description="TrinithCore authentication server" \
		--target-tags=authserver trinitycore-authserver
	gcloud compute firewall-rules create --project $(PROJECT_ID) \
		--allow=tcp:8085-8089 \
		--description="TrinithCore world server" \
		--target-tags=worldserver trinitycore-worldserver
	gcloud compute firewall-rules create --project $(PROJECT_ID) \
		--allow=tcp:1119 \
		--description="TrinithCore BattleNet RealID" \
		--target-tags=authserver trinitycore-battlenet-realid
	gcloud compute firewall-rules create --project $(PROJECT_ID) \
		--allow=tcp:7878 --source-ranges=$(ADMIN_RANGES) \
		--description="TrinithCore SOAP API" \
		--target-tags=worldserver trinitycore-soap-api
	gcloud compute firewall-rules create --project $(PROJECT_ID) \
		--allow=tcp:3443 --source-ranges=$(ADMIN_RANGES) \
		--description="TrinithCore remote console" \
		--target-tags=worldserver trinitycore-remote-console
	gcloud compute firewall-rules list --project $(PROJECT_ID)

clean:
	$(RM) $(CONF_SH) $(CONF_FILES) $(addsuffix .dist,$(CONF_FILES))

