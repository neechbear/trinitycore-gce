#!/usr/bin/env bash

set -Eexuo pipefail

main () {
  groupadd -r trinity
  useradd -r -g trinity -G trinity,systemd-journal \
    -d /opt/trinitycore -s /bin/bash trinity
  mkdir -pv /opt/trinitycore

  cat << 'EOF' > /etc/systemd/system/worldserver.service
[Unit]
Description=worldserver
Requires=authserver.service
    
[Service]
ExecStart=/opt/trinitycore/server/bin/worldserver
WorkingDirectory=/opt/trinitycore/server/bin
Restart=always
RestartSec=10
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
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=trinity
User=trinity
Group=trinity

[Install]
WantedBy=multi-user.target
EOF

  cat << 'EOF' > /opt/trinitycore/generate-mapdata.sh
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

  cat << 'EOF' > /opt/trinitycore/update.sh
#!/usr/bin/env bash
set -Eexvuo pipefail
main () {
  # install packages
  export DEBIAN_FRONTENT=noninteractive
  if [[ $EUID -eq 0 ]] ; then
    apt-get update
    apt-get install -y jq git clang cmake make gcc g++ libmariadbclient-dev libssl1.0-dev \
      libbz2-dev libreadline-dev libncurses-dev libboost-all-dev mysql-server p7zip moreutils
    update-alternatives --install /usr/bin/cc cc /usr/bin/clang 100
    update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang 100
  fi
  # clone source repository
  if [[ ! -e ~trinity/TrinityCore ]] ; then
    git clone --branch 3.3.5 --single-branch \
      https://github.com/TrinityCore/TrinityCore.git ~trinity/TrinityCore
  fi
  # download database sql
  if ! compgen -G ~trinity/TrinityCore/sql/"TDB_full_*.sql" ; then
    mkdir -pv ~trinity/TrinityCore/sql || :
    pushd ~trinity/TrinityCore/sql/
    curl -sSL \
      https://github.com/TrinityCore/TrinityCore/releases/download/TDB735.00/TDB_full_735.00_2018_02_19.7z
    7z x TDB_full_*.7z
    mv -v TDB_full_*/* .
    rmdir TDB_full_* >/dev/null 2>&1 || :
    popd
  fi
  # build and install
  mkdir -pv ~trinity/TrinityCore/build
  cd ~trinity/TrinityCore/build
  git pull
  cmake ../ -DCMAKE_INSTALL_PREFIX=$(echo ~trinity)/server -DTOOLS=1 -DWITH_WARNINGS=1
  make
  make install
  for daemon in worldserver authserver ; do
    if [[ ! -e ~trinity/server/etc/$daemon.conf ]] ; then
      cp -pv ~trinity/server/etc/$daemon.conf{.dist,}
    fi
  done
  # rebuild mapdata
  if journalctl -q -u worldserver -p info -b --since yesterday \
    | grep -q 'please re-extract the maps'
  then
    rm -Rfv ~trinity/mapdata-old || :
    mv ~trinity/mapdata ~trinity/mapdata-old || :
    mkdir -pv ~trinity/mapdata
    ~trinity/generate-mapdata.sh ~trinity/wow ~trinity/mapdata
    rm -Rfv ~trinity/mapdata-old || :
  fi
  # correct file permissions
  if [[ $EUID -eq 0 ]] ; then
    chown -Rv trinity:trinity ~trinity
  fi
}
main "$@"
EOF

  cat << 'EOF' > /etc/cron.d/refresh-trinitycore
0 5 * * * root chronic /opt/trinitycore/update.sh
EOF

  chown -R trinity:trinity /opt/trinitycore
  chmod 0754 /opt/trinitycore/*.sh
  /opt/trinitycore/update.sh
  systemctl daemon-reload
  systemctl start authserver.service
  systemctl start worldserver.service
}

main "$@"
