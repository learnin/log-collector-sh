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

makeTargetFileList() {
  _makeTargetFileList_func_list=$1
  _makeTargetFileList_func_tmp_list=${TMP_DIR}/tmp_target_file_list.txt
  _makeTargetFileList_func_logDir=$2

  ls ${_makeTargetFileList_func_logDir}/*.aud > $_makeTargetFileList_func_tmp_list
  ls ${_makeTargetFileList_func_logDir}/*.xml >> $_makeTargetFileList_func_tmp_list
  while read _makeTargetFileList_func_file
  do
    if isOpened $_makeTargetFileList_func_file; then
      echo "$_makeTargetFileList_func_file closed" >> $_makeTargetFileList_func_list
    else
      echo "$_makeTargetFileList_func_file opened" >> $_makeTargetFileList_func_list
    fi
  done < $_makeTargetFileList_func_tmp_list
}

# TODO 2重起動チェック

mputCmd="mput"
shouldTransferFileCount=0

uname=`uname`
prefix=`hostname`_`date '+%Y%m%d%H%M%S'`_

targetFileList=${TMP_DIR}/target_file_list.txt

makeTargetFileList $targetFileList $TARGET_LOG_DIR

exec 9<&0 < $targetFileList
while read line
do
  fileName=`echo $line | awk '{print $1}'`
  endFile=${TMP_DIR}/${fileName}.end
  touch $endFile
  mputCmd="${mputCmd} ${fileName} ${endFile}"
  shouldTransferFileCount=`expr $shouldTransferFileCount + 2`
done
exec 0<&9 9<&-

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

while read line
do
  openStatus=`echo $line | awk '{print $2}'`
  if [ $openStatus = "closed" ]; then
    fileName=`echo $line | awk '{print $1}'`
    rm -f $fileName
done < $targetFileList

exit 0
