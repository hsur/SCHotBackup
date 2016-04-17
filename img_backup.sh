#!/bin/bash
# sakura cloud img backup script by CLES

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

BACKUP_DIR=/path/to/backup/dir
DESCRIPTION="ftp autobackup"
MAX_SLEEP_SECS=3600
SLEEP_INTERVAL=30
TARGET_GROUP=""
SKIP_TAG="SCHB-SKIP"

. _sa_api.sh

while getopts t:r:dh OPT
do
    case $OPT in
        t)  TARGET_GROUP=$OPTARG
            logger "Target Group: $OPTARG"
            ;;
        r)  REGION=$OPTARG
            logger "Target Region: $OPTARG"
            ;;
        d)  DRYRUN=1
            logger "Entering dryrun mode!"
            ;;
        h)  usage
            ;;
    esac
done

shift $((OPTIND - 1))

###### MAIN Routine #####

cmd_check curl
cmd_check json
cmd_check xz

CONFIG="./config.json"
if [ -n "$1" ] ; then
    CONFIG="$1"
fi

read SEC_TOKEN SEC_SECRET SC_ZONE < <( json -a token secret zone < $CONFIG )
if [ -n "$REGION" ] ; then
    SC_ZONE="$REGION"
fi

logger "===== START ====="
TIMESTAMP="`date "+%Y%m%d%H%M%S"`"

logger "get_disk_list()"
get_disk_list $TARGET_GROUP | while read DISK_ID DISK_NAME ; do
  logger "----- START: $DISK_ID ($DISK_NAME) -----"
  if [ -n "$DRYRUN" ]; then
    logger "*** Skipped ***"
    logger "----- END: $DISK_ID ($DISK_NAME) -----"
    continue
  fi

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
