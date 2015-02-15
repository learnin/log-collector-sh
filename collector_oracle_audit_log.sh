#!/bin/sh

. config.profile

canIUse() {
  type $1 >/dev/null 2>&1
  return $?
}

# TODO 2重起動チェック

mputCmd="mput"
shouldTransferFileCount=0

uname=`uname`
prefix=`hostname`_`date '+%Y%m%d%H%M%S'`_

targetFileList=${TMP_DIR}/target_file_list.txt
ls ${TARGET_LOG_DIR}/*.aud > $targetFileList
ls ${TARGET_LOG_DIR}/*.xml >> $targetFileList

while read targetFileName; do
  md5file=${TMP_DIR}/${targetFileName}.end

  if canIUse md5sum; then
    md5sum $targetFileName > $md5file
  elif canIUse digest; then
    digest -a md5 $targetFileName > $md5file
  else
    echo "neither md5sum nor digest command is not found."
    exit 1
  fi
  mputCmd="${mputCmd} ${targetFileName} ${md5file}"
  shouldTransferFileCount=`expr $shouldTransferFileCount + 2`
done < $targetFileList

nmapCmd='nmap $0 '${prefix}'$0'

ftpLog=${TMP_DIR}/ftp.log

ftp -inv <<EOF > $ftpLog
open $FTP_HOST
user $FTP_USER $FTP_PASSWORD
binary
cd $FTP_DIR
$nmapCmd
$mputCmd
bye
EOF

if [ `grep -c "$FTP_SUCCESS_MSG" $ftpLog` -ne $shouldTransferFileCount ]; then
  echo "ftp Error"
  exit 1
fi
if [ `egrep -c "^4|^6" $ftpLog` -ne 0 ]; then
  echo "ftp Error"
  exit 1
fi

while read targetFileName; do
  # Oracle監査ログファイル名フォーマット
  # 11.2.0/11.1.0.7/10.2.0.5以降は
  # <インスタンス名>_<プロセス名>_<プロセス番号>_<シリアル番号>.<拡張子>
  # それ以前は
  # <プロセス名>_<プロセス番号>.<拡張子>
  length=`echo $targetFileName | awk -F"_" '{print NF}'`
  if [ $length -eq 4 ]; then
    oraclePid=`echo $targetFileName | awk -F"_" '{print $3}'`
  elif [ $length -eq 2 ]; then
    oraclePid=`echo $targetFileName | awk -F"_" '{print $2}' | awk -F"." '{print $1}'`
  fi
  if [ `ps -p $oraclePid | wc -l` -eq 1 ]; then
    # 1行だけ = ヘッダー行のみ = プロセスは生きていないので削除する。
    rm -f $targetFileName
  else
    # プロセスが存在してもPIDがリサイクルされているだけの可能性があるため、
    # そのプロセスがこのログを開いているか確認する。
    if canIUse lsof; then
      if [ `lsof -p $oraclePid | grep -c $targetFileName` -eq 0 ]; then
        rm -f $targetFileName
      fi
    elif canIUse pfiles; then
      if [ `pfiles $oraclePid | grep -c $targetFileName` -eq 0 ]; then
        rm -f $targetFileName
      fi
    fi
  fi
done < $targetFileList

exit 0
