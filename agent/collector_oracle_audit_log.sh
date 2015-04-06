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

# Solaris の sh の内部 test コマンドは -nt をサポートしていないため、
# そういった比較を行う場合は、/bin/test を使用する。
testCmd=test
if [ `uname` = 'SunOS' ]; then
  testCmd=/bin/test
fi

# 監査ログファイルが更新されているかの判別を test -nt で行うため、
# 前回収集日時管理ファイルの更新日時を管理ファイルの内容の日時で更新
if [ -f $LAST_COLLECT_DATETIME_FILE ]; then
  last_collect_datetime=`cat $LAST_COLLECT_DATETIME_FILE`
else
  last_collect_datetime="200001010000.00"
fi
touch -t $last_collect_datetime $LAST_COLLECT_DATETIME_FILE

# 処理開始
now=`date '+%Y%m%d%H%M.%S'`
# $now の時刻に秒単位で同時に出力される監査ログエントリが複数レコードあった場合に
# 一部だけが転送されてしまい、かつ次回の処理対象からも漏れてしまうことを防止するため1秒待つ
sleep 1

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

  # 監査ログファイルの更新日時 > 前回収集日時 の場合は転送
  if $testCmd $targetFilePath -nt $LAST_COLLECT_DATETIME_FILE; then
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
      rm -f $endFilePath
      continue
    fi
    rm -f $endFilePath
  fi

  # 既に解放されているログファイルだった場合は削除
  if [ $logFileStatus = "inactive" ]; then
    rm -f $targetFilePath
  fi
done
exec 0<&9 9<&-

if [ $hasError = "true" ]; then
  exit 1
fi

# 前回収集日時管理ファイルを更新
echo $now > $LAST_COLLECT_DATETIME_FILE

exit 0
