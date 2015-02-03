#!/bin/bash
# sakura cloud img backup script by CLES

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

BACKUP_DIR=/path/to/backup/dir
DESCRIPTION="ftp autobackup"
MAX_SLEEP_SECS=3600
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

###### MAIN Routine #####

cmd_check curl
cmd_check json
cmd_check xz

SEC_TOKEN="`json token < ./config.json`"
SEC_SECRET="`json secret < ./config.json`"
SC_ZONE="`json zone < ./config.json`"

logger "===== START ====="
TIMESTAMP="`date "+%Y%m%d%H%M%S"`"

logger "get_disk_list()"
get_disk_list | while read DISK_ID DISK_NAME ; do
  logger "----- START: $DISK_ID ($DISK_NAME) -----"
  TMP_PREFIX="$RANDOM"
  TMP_ARCHIVE_JSON="${TMP_PREFIX}.archive.json"
  TMP_FTP_JSON="${TMP_PREFIX}.ftp.json"
  logger "archive:$TMP_ARCHIVE_JSON"
  logger "ftp:$TMP_FTP_JSON"

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
    logger "open_ftp()"
    open_ftp "$ARCHIVE_ID" "$TMP_FTP_JSON"
    chmod 600 "$TMP_FTP_JSON"
    read FTP_SERVER FTP_USER FTP_PASS < <( json -a FTPServer.HostName FTPServer.User FTPServer.Password < $TMP_FTP_JSON )
    sleep 30

    logger "Data transfer started"
    curl -u "${FTP_USER}:${FTP_PASS}" --keepalive-time 60 --retry 10 --ftp-ssl --disable-epsv -o >( xz -zc > $BACKUP_DIR/${DISK_NAME}-${TIMESTAMP}.xz) "ftp://${FTP_SERVER}/archive.img"
    FTP_STATUS=$?
    echo $FTP_STATUS >> "$BACKUP_DIR/${DISK_NAME}-${TIMESTAMP}_status.txt"
    if [ $FTP_STATUS -eq 0 ] ; then
      logger "File transfer completed"
    else
      logger "FTP Error: exit code -> $FTP_STATUS"
    fi

    logger "close_ftp()"
    logger `close_ftp "$ARCHIVE_ID"`
    sleep 30
  else
    logger "[ERROR] Failed to create archive."
  fi

  logger "delete_archive()"
  logger `delete_archive "$ARCHIVE_ID"`

  rm -f "$TMP_ARCHIVE_JSON" "$TMP_FTP_JSON"
  logger "----- END: $DISK_ID ($DISK_NAME) -----"
done

logger "===== END ====="
