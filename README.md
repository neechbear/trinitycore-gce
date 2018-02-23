# trinitycore

Google Compute Engine based TrinityCore 3.3.5 server.

See https://nicolaw.uk/gcloud and https://nicolaw.uk/gcp.

```bash
gcloud compute instances create $INSTANCE_NAME \
  --image debian-9-stretch-v20180206 \
  --image-project debian-cloud \
  --zone europe-west1-d \
  --machine-type n1-standard-2 \
  --tags worldserver,authserver,buildserver \
  --metadata-from-file startup-script=startup-script.sh
```

