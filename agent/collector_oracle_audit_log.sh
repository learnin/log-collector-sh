#!/bin/sh
set -u

# Solaris 10 の sh 及び Red Hat Enterprise Linux/CentOS の bash で実行することを想定

if [ -n "$1" ]; then
  . ./"$1"
else
  . ./config.profile
fi

. ./functions.sh

# 2重起動チェック
if isRunning $TMP_DIR; then
  echo "this script is already running"
  exit 0
fi

hasError="false"
prefix=`hostname`_`date '+%Y%m%d%H%M%S'`_
targetFileList=${TMP_DIR}/target_file_list.txt

ls ${TARGET_LOG_DIR}/*.aud > $targetFileList 2> /dev/null
ls ${TARGET_LOG_DIR}/*.xml >> $targetFileList 2> /dev/null

exec 9<&0 < $targetFileList
while read targetFilePath
do
  isOracleAuditLogFile $targetFilePath
  if [ $? -ne 0 ]; then
    continue
  fi
  logFileStatus="active"
  isActiveOracleAuditLogFile $targetFilePath
  if [ $? -ne 0 ]; then
    logFileStatus="inactive"
  fi

  # ログファイルを転送
  targetFileName=`basename $targetFilePath`
  doFtpPut $targetFilePath ${FTP_DIR}/${prefix}${targetFileName} ${TMP_DIR}/ftp.log $FTP_SUCCESS_MSG
  if [ $? -ne 0 ]; then
    echo "ftp Error. file=${targetFilePath}"
    hasError="true"
    continue
  fi

  # 転送完了通知用ファイルを転送
  endFilePath=${TMP_DIR}/${prefix}`echo $targetFileName | awk -F . '{print $1}'`.end
  touch $endFilePath
  endFileName=`basename $endFilePath`
  doFtpPut $endFilePath ${FTP_DIR}/${endFileName} ${TMP_DIR}/ftp.log $FTP_SUCCESS_MSG
  if [ $? -ne 0 ]; then
    echo "ftp Error. file=${endFilePath}"
    hasError="true"
    continue
  fi

  # 既に解放されているログファイルだった場合は削除
  if [ $logFileStatus = "inactive" ]; then
    rm -f $targetFilePath
    rm -f $endFilePath
  fi
done
exec 0<&9 9<&-

if [ $hasError = "true" ]; then
  exit 1
fi
exit 0
