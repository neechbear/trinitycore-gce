#!/usr/bin/env bash

set -Eexuo pipefail

main () {
  export DEBIAN_FRONTENT=noninteractive

  [[ -e ~root/startup-script.sh.bak ]] \
    || curl -sSL -o /root/startup-script.sh.bak -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/startup-script"

  export GCSFUSE_REPO="gcsfuse-$(lsb_release -c -s)"
  echo "deb http://packages.cloud.google.com/apt $GCSFUSE_REPO main" \
    | tee /etc/apt/sources.list.d/gcsfuse.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  apt-get update
  apt-get install -y gcsfuse

  id -g trinity || groupadd -r trinity
  id -u trinity || useradd -r -g trinity -G trinity,systemd-journal \
    -d /opt/trinitycore -s /bin/bash trinity
  mkdir -pv ~trinity/{mapdata-source,server}
  mkdir -pv ~trinity/server/{bin,etc,run,log}

  curl -sSL -o ~trinity/mapdata.key -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/mapdata-key"

  bucket="$(curl -sSL -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/mapdata-bucket")"
  if [[ -n "$bucket" ]] && ! grep -q "^$bucket" /etc/fstab ; then
    echo "$bucket $(echo ~trinity)/mapdata-source gcsfuse ro,user,uid=trinity,gid=trinity,implicit_dirs,key_file=$(echo ~trinity)/mapdata.key" \
      >> /etc/fstab
  fi

  cat << 'EOF' > /etc/systemd/system/worldserver.service
[Unit]
Description=worldserver
Requires=authserver.service
    
[Service]
ExecStart=/opt/trinitycore/server/bin/worldserver
WorkingDirectory=/opt/trinitycore/server/bin
Restart=always
RestartSec=60
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=trinity
User=trinity
Group=trinity
    
[Install]
WantedBy=multi-user.target
EOF

  cat << 'EOF' > /etc/systemd/system/authserver.service
[Unit]
Description=authserver

[Service]
ExecStart=/opt/trinitycore/server/bin/authserver
Restart=always
RestartSec=60
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=trinity
User=trinity
Group=trinity

[Install]
WantedBy=multi-user.target
EOF

  cat << 'EOF' > ~trinity/generate-mapdata.sh
#!/usr/bin/env bash
set -Euo pipefail
shopt -s extdebug

dir_min_fcnt() {
  declare path="$1"
  declare count="$2"
  [[ $(find "$path" -type f 2>/dev/null | wc -l) -ge $count ]]
}

main () {
  declare input="$1"
  declare output="$2"
  pushd "$output"
  mkdir -p "${output%/}"/{mmaps,vmaps}

  # dbc, maps
  mapextractor -i "$input" -o "$output" -e 7 -f 0
  if dir_min_fcnt "$output/maps" 5700 && \
     dir_min_fcnt "$output/dbc" 240; then
    echo "Map extraction succeeded."
  else
    echo "Map extraction may have failed."
  fi

  # vmaps
  vmap4extractor -l -d "${input%/}/Data"
  vmap4assembler "${output%/}/Buildings" "${output%/}/vmaps"
  if dir_min_fcnt "$output/vmaps" 9800; then
    echo "Visual map (vmap) extraction succeeded."
  else
    echo "Visual map (vmap) may have failed."
  fi

  # mmaps
  if [[ ! -d "${output%/}/vmaps" ]]; then
    echo "Movement map (mmap) generation requires that visual map" \
         "(vmap) generation to completed first."
  fi
  mmaps_generator
  if dir_min_fcnt "$output/vmaps" 3600; then
    echo "Movement map (mmap) extraction succeeded."
  else
    echo "Movement map (mmap) may have failed."
  fi
  popd
}

main "$@"
EOF

  cat << 'EOF' > ~trinity/update.sh
#!/usr/bin/env bash
set -Eexvuo pipefail

get_tdb_url () {
  declare tag="${1:-TDB}"
  curl -sSL ${GITHUB_USER:+"-u$GITHUB_USER:$GITHUB_PASS"} \
    "${GITHUB_API:-https://api.github.com}/repos/${GITHUB_REPO:-TrinityCore/TrinityCore}/releases" \
    | jq -r "( [
                .[] | select(
                .tag_name | contains( \"$tag\" ) )
                .assets[] .browser_download_url
              ] | max )"
}

main () {
  # Install packages.
  export DEBIAN_FRONTENT=noninteractive
  if [[ $EUID -eq 0 ]] ; then
    apt-get update
    apt-get install -y jq git clang cmake make gcc g++ libmariadbclient-dev libssl1.0-dev \
      libbz2-dev libreadline-dev libncurses-dev libboost-all-dev mysql-server p7zip moreutils
    update-alternatives --install /usr/bin/cc cc /usr/bin/clang 100
    update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang 100
    systemctl stop mysql.service || :
    systemctl disable mysql.service || :
  fi

  # Clone source repository.
  if [[ ! -e ~trinity/TrinityCore ]] ; then
    git clone --branch 3.3.5 --single-branch \
      https://github.com/TrinityCore/TrinityCore.git ~trinity/TrinityCore
  fi

  # Download database SQL.
  # TODO: Should we download this directly into ~trinity/server/bin instead?
  if ! compgen -G ~trinity/server/bin/"TDB_*.sql" ; then
    mkdir -pv ~trinity/TrinityCore/sql ~trinity/server/bin || :
    pushd ~trinity/TrinityCore/sql/
    # https://github.com/TrinityCore/TrinityCore/releases/download/TDB735.00/TDB_full_735.00_2018_02_19.7z
    curl -sSLO "$(get_tdb_url)"
    7zr x -y TDB_full_*.7z
    find . -name 'TDB_*.sql' -type f -exec ln -v '{}' ~trinity/server/bin/ \;
    popd
  fi

  # Pull the latest source.
  git -C ~trinity/TrinityCore checkout 3.3.5
  git -C ~trinity/TrinityCore fetch --all
  git -C ~trinity/TrinityCore reset --hard origin/3.3.5
  #git -C ~trinity/TrinityCore pull
  find ~trinity/TrinityCore/sql -iname '*.sql' -exec sed -i 's/ ENGINE=MyISAM/ ENGINE=InnoDB/g; s/ ROW_FORMAT=FIXED//g;' '{}' \;

  # Build and install.
  mkdir -pv ~trinity/TrinityCore/build
  cd ~trinity/TrinityCore/build
  cmake ../ -DCMAKE_INSTALL_PREFIX=$(echo ~trinity)/server -DTOOLS=1 -DWITH_WARNINGS=1
  make
  make install

  # (Re-)install configuration.
  for daemon in worldserver authserver ; do
    curl -o ~trinity/server/etc/${daemon}.conf -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${daemon}-conf"
    if [[ ! -s ~trinity/server/etc/$daemon.conf ]] ; then
      cp -pv ~trinity/server/etc/$daemon.conf{.dist,}
    fi
  done

  # Rebuild mapdata.
  if [[ ! -d ~trinity/server/data ]] || \
    journalctl -q -u worldserver -p info -b --since yesterday \
      | grep -q 'please re-extract the maps'
  then
    if     ! compgen -G ~trinity/"mapdata-source/*/*.MPQ" \
        && ! mountpoint ~trinity/mapdata-source ]] ; then
      mount ~trinity/mapdata-source
    fi
    if compgen -G ~trinity/"mapdata-source/*/*.MPQ" ; then
      [[ ! -e ~trinity/server/data-old ]] || rm -Rfv ~trinity/server/data-old
      [[ ! -e ~trinity/server/data ]] || mv ~trinity/server/data{,-old}
      mkdir -pv ~trinity/server/data
      export PATH="$PATH:$(echo ~trinity)/server/bin"
      ~trinity/generate-mapdata.sh ~trinity/mapdata-source ~trinity/server/data
      umount ~trinity/mapdata-source
    fi
  fi

  # Correct file permissions.
  if [[ $EUID -eq 0 ]] ; then
    chown -R trinity:trinity ~trinity/server/{run,log}
  fi
}

main "$@"
EOF

  cat << 'EOF' > /etc/cron.d/refresh-trinitycore
0 3 * * * root ~trinity/update.sh 2>&1 | logger -i -p daemon.info -t refresh-trinirycore
0 8 * * * root systemctl restart authserver.service 2>&1 | logger -i -p daemon.info -t restart-authserver
0 8 * * * root systemctl restart authserver.service 2>&1 | logger -i -p daemon.info -t restart-worldserver
0 0 1 * * root rm -Rf ~trinity/TrinityCore/build/ 2>&1 | logger -i -p daemon.info -t rm-build-trinirycore
EOF

  chmod 0754 ~trinity/*.sh
  ~trinity/update.sh
  systemctl daemon-reload
  systemctl start authserver.service
  systemctl start worldserver.service
}

main "$@"
