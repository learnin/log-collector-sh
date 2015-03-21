#!/bin/sh

. config.profile

canIUse() {
  type $1 >/dev/null 2>&1
  return $?
}

# 引数で渡されたOracle監査ログファイルが開かれているかどうか判定する
# args: Oracle監査ログファイル名
# 戻り値: 0:開かれていない 1:開かれている
isOpened() {
  # Oracle監査ログファイル名フォーマット
  # 11.2.0/11.1.0.7/10.2.0.5以降は
  # <インスタンス名>_<プロセス名>_<プロセス番号>_<シリアル番号>.<拡張子>
  # それ以前は
  # <プロセス名>_<プロセス番号>.<拡張子>

  # Solaris 10の/bin/shではローカル変数宣言localは使えないので変数名に関数名を入れている。
  # 可読性が悪いようなら別ファイルに切り出した方がいいかも。
  _isOpened_func_filename=$1
  _isOpened_func_length=`echo $_isOpened_func_filename | awk -F"_" '{print NF}'`

  if [ $_isOpened_func_length -eq 4 ]; then
    _isOpened_func_oraclePid=`echo $_isOpened_func_filename | awk -F"_" '{print $3}'`
  elif [ $_isOpened_func_length -eq 2 ]; then
    _isOpened_func_oraclePid=`echo $_isOpened_func_filename | awk -F"_" '{print $2}' | awk -F"." '{print $1}'`
  fi
  if [ `ps -p $_isOpened_func_oraclePid | wc -l` -eq 1 ]; then
    # 1行だけ = ヘッダー行のみ = プロセスは生きていない
    return 0
  fi
  # プロセスが存在してもPIDがリサイクルされているだけの可能性があるため、
  # そのプロセスがこのログを開いているか確認する。
  if canIUse lsof; then
    if [ `lsof -p $_isOpened_func_oraclePid | grep -c $_isOpened_func_filename` -eq 0 ]; then
      return 0
    fi
  elif canIUse pfiles; then
    if [ `pfiles $_isOpened_func_oraclePid | grep -c $_isOpened_func_filename` -eq 0 ]; then
      return 0
    fi
  fi
  return 1
}

doFtpPut() {
  _doFtpPut_func_src=$1
  _doFtpPut_func_dest=$2
  _doFtpPut_func_ftpLog=${TMP_DIR}/ftp.log

  ftp -inv <<EOF > $_doFtpPut_func_ftpLog
open $FTP_HOST
user $FTP_USER $FTP_PASSWORD
binary
put $_doFtpPut_func_src $_doFtpPut_func_dest
bye
EOF

  if [ `grep -c "$FTP_SUCCESS_MSG" $_doFtpPut_func_ftpLog` -ne 1 ]; then
    return 1
  fi
  if [ `egrep -c "^4|^6" $_doFtpPut_func_ftpLog` -ne 0 ]; then
    return 1
  fi
  return 0
}

# TODO 2重起動チェック

hasError="false"
prefix=`hostname`_`date '+%Y%m%d%H%M%S'`_
targetFileList=${TMP_DIR}/target_file_list.txt

ls ${TARGET_LOG_DIR}/*.aud > $targetFileList
ls ${TARGET_LOG_DIR}/*.xml >> $targetFileList

exec 9<&0 < $targetFileList
while read targetFilePath
do
  openStatus="opened"
  if isOpened $targetFilePath; then
    openStatus="closed"
  fi

  targetFileName=`basename $targetFilePath`

  doFtpPut $targetFilePath ${FTP_DIR}/${prefix}${targetFileName}
  if [ $? -ne 0 ]; then
    echo "ftp Error. file=${targetFilePath}"
    hasError="true"
    continue
  fi

  endFilePath=${TMP_DIR}/${prefix}`echo $targetFileName | awk -F . '{print $1}'`.end
  touch $endFilePath
  endFileName=`basename $endFilePath`

  doFtpPut $endFilePath ${FTP_DIR}/${endFileName}
  if [ $? -ne 0 ]; then
    echo "ftp Error. file=${endFilePath}"
    hasError="true"
    continue
  fi

  if [ $openStatus = "closed" ]; then
    rm -f $targetFilePath
    rm -f $endFilePath
  fi
done
exec 0<&9 9<&-

if [ $hasError = "true" ]; then
  exit 1
fi
exit 0
