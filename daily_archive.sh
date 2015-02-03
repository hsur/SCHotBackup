#!/bin/bash
# sakura cloud daily archive script by blog.cles.jp
# License: BSD 2-clause

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

SEC_TOKEN="your token"
SEC_SECRET="your secret"
DESCRIPTION="daily autobackup"

cmd_check(){ which $1 > /dev/null 2>&1 || ( echo "$1 not found" && exit 5 ) }

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
    https://secure.sakura.ad.jp/cloud/zone/is1a/api/cloud/1.1${1} \
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

delete_archive(){
  if [ "$#" -ne 1 ] ; then
    return 1
  fi
  sa_api "/archive/${1}" "DELETE" "" -
  return $?
}

###### MAIN Routine #####

cmd_check curl

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

  while [ "`archive_availability $ARCHIVE_ID`" != "available" ] ; do
    sleep 30
    logger "waiting..."
  done

  get_old_archive_list "$DISK_ID" "$ARCHIVE_ID" "$DESCRIPTION" | while read OLD_ARCHIVE_ID OLD_ACHIVE_NAME ; do
    logger "deleting old archive: $OLD_ARCHIVE_ID $OLD_ACHIVE_NAME"
    logger `delete_archive "$OLD_ARCHIVE_ID"`
  done

  rm -rf "$TMP_ARCHIVE_JSON"
  logger "----- END: $DISK_ID ($DISK_NAME) -----"
done

logger "===== END ====="
