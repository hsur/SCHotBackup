# utilities

cmd_check(){ which $1 > /dev/null 2>&1 || ( echo "$1 command not found" && exit 5 ) }

logger(){
  if [ "$#" -ne 0 ] ; then
    echo "`date "+%Y-%m-%d %H:%M:%S"` [$$]: $@"
  fi
}

usage() {
    echo "Usage: $0 [-h] [-d] [-t TagName] [config.json]" 1>&2
    exit 1
}

# sakura cloud API

sa_api(){
  if [ "$#" -ne 4 ] ; then
    return 1
  fi
  curl --user "${SEC_TOKEN}":"${SEC_SECRET}" \
    -X "${2}" \
    -d "${3}" \
    -o ${4} \
    https://secure.sakura.ad.jp/cloud/zone/${SC_ZONE}/api/cloud/1.1${1} \
    -s
  return $?
}

get_old_archive_list(){
  if [ "$#" -ne 3 ] ; then
    return 1
  fi
  sa_api "/archive" "GET" "" - | json Archives | json -C "this.Scope == 'user' && this.Description == '${3}' && this.SourceDisk.ID == '${1}' && this.ID != '${2}' " | json -a ID Name
  return ${PIPESTATUS[0]}
}

get_disk_list(){
  if [ -n "$1" ] ; then
    sa_api "/disk" "GET" "" - | json Disks | json -C "this.Tags.indexOf('$1') >= 0 && this.Tags.indexOf('$SKIP_TAG') < 0" | json -a ID Name
  else
    sa_api "/disk" "GET" "" - | json Disks | json -a ID Name
  fi
  return ${PIPESTATUS[0]}
}

create_archive(){
  if [ "$#" -ne 4 ] ; then
    return 1
  fi
  sa_api "/archive" "POST" "{'Archive':{'Name':'${1}','Description':'${4}','SourceDisk':{'ID':'${2}'}}}" $3
  return $?
}

archive_availability(){
  if [ "$#" -ne 1 ] ; then
    return 1
  fi
  sa_api "/archive/${1}" "GET" "" - | json Archive.Availability
  return ${PIPESTATUS[0]}
}

archive_status(){
  if [ "$#" -ne 1 ] ; then
    return 1
  fi
  ARCSTAT=(`sa_api "/archive/${1}" "GET" "" - | json -a Archive.SizeMB Archive.MigratedMB`)
  echo -n "${ARCSTAT[1]}/${ARCSTAT[0]}MB"
}

sleep_until_archive_is_available(){
  TTL=$(( $SECONDS + $MAX_SLEEP_SECS ))
  while [ "`archive_availability $1`" != "available" ] ; do
    sleep $SLEEP_INTERVAL
    logger "waiting... (`archive_status $1`)"

    if [ "$TTL" -le "$SECONDS" ]; then
      logger "[ERROR] Timed out!: $1"
      return 1
    fi
  done
  return 0
}

open_ftp(){
  if [ "$#" -ne 2 ] ; then
    return 1
  fi
  sa_api "/archive/${1}/ftp.json" "PUT" "" $2
  return $?
}

close_ftp(){
  if [ "$#" -ne 1 ] ; then
    return 1
  fi
  sa_api "/archive/${1}/ftp.json" "DELETE" "" -
  return $?
}

delete_archive(){
  if [ "$#" -ne 1 ] ; then
    return 1
  fi
  sa_api "/archive/${1}" "DELETE" "" -
  return $?
}
