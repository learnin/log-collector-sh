# Solaris 10 の sh 及び Red Hat Enterprise Linux/CentOS の bash で実行することを想定
# Solaris 10の/bin/shではローカル変数宣言localは使えないので変数名に関数名を入れている

# 引数のコマンドが使用可能(存在する)か判定する
# args: コマンド
# 戻り値: 0:使用可能 1:使用不可能
canIUse() {
  type $1 >/dev/null 2>&1
  return $?
}

# 引数で渡されたファイルがOracle監査ログファイルかどうか判定する
# args: ファイル名
# 戻り値: 0:Oracle監査ログファイル 1:Oracle監査ログファイルでない
isOracleAuditLogFile() {
  # Oracle監査ログファイル名フォーマット
  # 11.2.0/11.1.0.7/10.2.0.5以降は
  # <インスタンス名>_<プロセス名>_<プロセス番号>_<シリアル番号>.<拡張子>
  # それ以前は
  # <プロセス名>_<プロセス番号>.<拡張子>
  _isOracleAuditLogFile_length=`basename $1 | awk -F"_" '{print NF}'`
  if [ $_isOracleAuditLogFile_length -eq 4 -o $_isOracleAuditLogFile_length -eq 2 ]; then
    return 0
  fi
  return 1
}

# 引数で渡されたOracle監査ログファイルが使用中かどうか判定する
# args: Oracle監査ログファイル名
# 戻り値: 0:使用中 1:使用中でない
isActiveOracleAuditLogFile() {
  # Oracle監査ログファイル名フォーマット
  # 11.2.0/11.1.0.7/10.2.0.5以降は
  # <インスタンス名>_<プロセス名>_<プロセス番号>_<シリアル番号>.<拡張子>
  # それ以前は
  # <プロセス名>_<プロセス番号>.<拡張子>
  _isActiveOracleAuditLogFile_filepath=$1
  _isActiveOracleAuditLogFile_filename=`basename $1`
  _isActiveOracleAuditLogFile_length=`echo $_isActiveOracleAuditLogFile_filename | awk -F"_" '{print NF}'`

  if [ $_isActiveOracleAuditLogFile_length -eq 4 ]; then
    _isActiveOracleAuditLogFile_oraclePid=`echo $_isActiveOracleAuditLogFile_filename | awk -F"_" '{print $3}'`
  elif [ $_isActiveOracleAuditLogFile_length -eq 2 ]; then
    _isActiveOracleAuditLogFile_oraclePid=`echo $_isActiveOracleAuditLogFile_filename | awk -F"_" '{print $2}' | awk -F"." '{print $1}'`
  fi
  if [ `ps -p $_isActiveOracleAuditLogFile_oraclePid | wc -l` -eq 1 ]; then
    # 1行だけ = ヘッダー行のみ = プロセスは生きていない
    return 1
  fi
  # プロセスが存在してもPIDがリサイクルされているだけの可能性があるため、
  # そのプロセスがこのログを開いているか確認する。
  if canIUse lsof; then
    if [ `lsof -p $_isActiveOracleAuditLogFile_oraclePid | grep -c $_isActiveOracleAuditLogFile_filepath` -eq 0 ]; then
      return 1
    fi
  elif canIUse pfiles; then
    if [ `pfiles $_isActiveOracleAuditLogFile_oraclePid | grep -c $_isActiveOracleAuditLogFile_filepath` -eq 0 ]; then
      return 1
    fi
  fi
  return 0
}

# $FTP_USER, $FTP_PASSWORD で $FTP_HOST へ接続し、引数のファイルを put する
# ftp 応答メッセージを見て、正常/異常終了を判定する
# args: 転送元ファイルパス, 転送先ファイルパス, FTPログファイルパス, FTP成否判定用の転送成功メッセージ(一部のみでOK)
# 戻り値: 0:正常終了 1:異常終了
doFtpPut() {
  _doFtpPut_src=$1
  _doFtpPut_dest=$2
  _doFtpPut_ftpLog=$3
  _doFtpPut_success_msg=$4

  ftp -inv <<EOF > $_doFtpPut_ftpLog
open $FTP_HOST
user $FTP_USER $FTP_PASSWORD
binary
put $_doFtpPut_src $_doFtpPut_dest
bye
EOF

  if [ `grep -c "$_doFtpPut_success_msg" $_doFtpPut_ftpLog` -ne 1 ]; then
    return 1
  fi
  if [ `egrep -c "^4|^6" $_doFtpPut_ftpLog` -ne 0 ]; then
    return 1
  fi
  return 0
}

# このスクリプトがすでに実行中かどうかを判定する
# args: pidファイル出力先ディレクトリ
# 戻り値: 0:実行中 1:実行中でない
isRunning() {
  _isRunning_tmpDir=$1
  _isRunning_basename=`basename $0`
  _isRunning_pidfile=${_isRunning_tmpDir}/${_isRunning_basename}.pid

  while true
  do
    if ln -s $$ ${_isRunning_pidfile} 2> /dev/null; then
      # pidファイルシンボリックリンクが作成できた場合は実行中でない
      break
    else
      # このスクリプト名のプロセス一覧に、pidファイルのPIDが存在するかチェック
      _isRunning_pidOfPidfile=`ls -l ${_isRunning_pidfile} | awk '{print $NF}'`
      _isRunning_p=""
      for _isRunning_p in `pgrep -f ${_isRunning_basename}`
      do
        if [ $_isRunning_pidOfPidfile -eq $_isRunning_p ]; then
          return 0
        fi
      done
    fi
    rm -f $_isRunning_pidfile
  done

  # このスクリプトの終了時またはHUP、INT、QUIT、TERMシグナル受信時にpidファイルを削除する
  trap "rm -f $_isRunning_pidfile; exit 0" EXIT
  trap "rm -f $_isRunning_pidfile; exit 1" 1 2 3 15

  return 1
}
