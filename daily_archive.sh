#!/bin/bash
# sakura cloud daily archive script by CLES

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

DESCRIPTION="daily autobackup"
MAX_SLEEP_SECS=1800
SLEEP_INTERVAL=30

cmd_check(){ which $1 > /dev/null 2>&1 || ( echo "$1 command not found" && exit 5 ) }

logger(){
  if [ "$#" -ne 0 ] ; then
    echo "`date "+%Y-%m-%d %H:%M:%S"` [$$]: $@"
  fi
}

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
  sa_api "/disk" "GET" "" - | json Disks | json -a ID Name
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

sleep_until_archive_is_available(){
  TTL=$(( $SECONDS + $MAX_SLEEP_SECS ))
  while [ "`archive_availability $1`" != "available" ] ; do
    logger "waiting..."
    sleep 30

    if [ "$TTL" -le "$SECONDS" ]; then
      logger "[ERROR] Timed out!: $1"
      return 1
    fi
  done
  return 0
}

delete_archive(){
  if [ "$#" -ne 1 ] ; then
    return 1
  fi
  sa_api "/archive/${1}" "DELETE" "" -
  return $?
}

###### MAIN Routine #####

cmd_check curl
cmd_check json

SEC_TOKEN="`json token < ./config.json`"
SEC_SECRET="`json secret < ./config.json`"
SC_ZONE="`json zone < ./config.json`"

logger "===== START ====="
TIMESTAMP="`date "+%Y%m%d"`"

logger "get_disk_list()"
get_disk_list | while read DISK_ID DISK_NAME ; do
  logger "----- START: $DISK_ID ($DISK_NAME) -----"
  TMP_PREFIX="$RANDOM"
  TMP_ARCHIVE_JSON="${TMP_PREFIX}.archive.json"
  logger "archive:$TMP_ARCHIVE_JSON"

  logger "create_archive()"
  create_archive "${DISK_NAME}-${TIMESTAMP}" "$DISK_ID" "$TMP_ARCHIVE_JSON" "$DESCRIPTION"
  chmod 600 "$TMP_ARCHIVE_JSON"
  read ARCHIVE_ID ARVHIVE_NAME < <( json -a Archive.ID Archive.Name < $TMP_ARCHIVE_JSON )
  if [ -z "$ARCHIVE_ID" ]; then
    logger "ARCHIVE_ID is null"
    continue
  else
    logger "ARCHIVE_ID: $ARCHIVE_ID"
  fi

  sleep_until_archive_is_available "$ARCHIVE_ID"
  ARCHIVE_STATUS=$?

  if [ "$ARCHIVE_STATUS" -eq 0 ] ; then
    get_old_archive_list "$DISK_ID" "$ARCHIVE_ID" "$DESCRIPTION" | while read OLD_ARCHIVE_ID OLD_ACHIVE_NAME ; do
      logger "deleting old archive: $OLD_ARCHIVE_ID $OLD_ACHIVE_NAME"
      logger `delete_archive "$OLD_ARCHIVE_ID"`
    done
  else
    logger "[ERROR] Failed to create archive."
    logger "delete_archive()"
    logger `delete_archive "$ARCHIVE_ID"`
  fi

  rm -rf "$TMP_ARCHIVE_JSON"
  logger "----- END: $DISK_ID ($DISK_NAME) -----"
done

logger "===== END ====="
