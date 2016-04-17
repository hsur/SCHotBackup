#!/bin/bash
# sakura cloud daily archive script by CLES

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

DESCRIPTION="daily autobackup"
MAX_SLEEP_SECS=1800
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

CONFIG="./config.json"
if [ -n "$1" ] ; then
    CONFIG="$1"
fi

read SEC_TOKEN SEC_SECRET SC_ZONE < <( json -a token secret zone < $CONFIG )
if [ -n "$REGION" ] ; then
    SC_ZONE="$REGION"
fi

logger "===== START ====="
TIMESTAMP="`date "+%Y%m%d"`"

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
