# trinitycore

Google Compute Engine based TrinityCore 3.3.5 server.

See https://nicolaw.uk/gcloud and https://nicolaw.uk/gcp.

1. Optionally create a new GCP project.
2. Create a new SQL instance (MySQL 2nd Gen 5.7 or newer).
3. Create a suitable SQL user for TrinityCore, granting full permissions.
4. Authorise an IPv4 CIDR for your new GCE instance to access your new SQL
   instance.
6. Clone this Git repository.
5. Edit `serverconf.json` to reflect your SQL instance details.
6. Optionally customise `worldserver.conf.in` and `authserver.conf.in` to suit
   your specific requirements.
7. Create a new storage bucket.
8. Upload the World of Warcraft client `.MPQ` files into a `Data/` subdirectory
   into this bucket.
10. Deploy the new TrinityCore instance into GCE using
    `make create PROJECT_ID="your_gce_project_id" MAPDATA_BUCKET="your_gcloud_mapdata_bucket" INSTANCE_NAME="test1"`.
11. Apply firewall rules to the TrinityCore instance using
    `make firewall PROJECT_ID="your_gce_project_id" ADMIN_RANGES="1.2.3.4/28"` (substituting the example CIDR
    range for your trusted administrative subnet).
12. Telnet to the TrinityCore worldserver remote console on port `3443` to
    create new accounts. The default account credentials are usually `trinity`
    and `trinity`, (refer to the TrinityCore documentation for more information).
13. Modify your Warcraft client `realmlist.wtf` configuration file to point at
    the IP address or hostname of your new TrinityCore instance.

## TODO

* Change from Makefile deployment to using Terraform (possibly still wrapped in
  a Makefile).
* Automate creation of SQL instance and storage bucket.
* Pre-bake the machine image using Packer? (Probably not).
* Move startup-script.sh into cloud-config to make use of write_file for
  better clarity (scripts writing scripts is far from ideal).

## See Also

* https://cloud.google.com/compute/docs/storing-retrieving-metadata
* https://cloud.google.com/storage/docs/gcs-fuse
* https://github.com/GoogleCloudPlatform/gcsfuse
* https://github.com/neechbear/trinitycore-gce
* https://github.com/neechbear/trinitycore
