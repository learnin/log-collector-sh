#!/bin/sh
set -u

oneTimeSetUp() {
  . ../agent/functions.sh
}

testIsOracleAuditLogFile() {
  # 11.2.0/11.1.0.7/10.2.0.5以降のOracle監査ログファイル名フォーマット
  # <インスタンス名>_<プロセス名>_<プロセス番号>_<シリアル番号>.<拡張子>
  isOracleAuditLogFile ORCL_pmon_12345_0987654321.aud
  assertTrue "新フォーマット(aud)" $?
  isOracleAuditLogFile ORCL_pmon_12345_0987654321.xml
  assertTrue "新フォーマット(xml)" $?

  # <プロセス名>_<プロセス番号>.<拡張子>
  isOracleAuditLogFile pmon_12345.aud
  assertTrue "旧フォーマット(aud)" $?
  isOracleAuditLogFile pmon_12345.xml
  assertTrue "旧フォーマット(xml)" $?
}

testIsActiveOracleAuditLogFile() {
  pid=$$

  # 生きていない
  isActiveOracleAuditLogFile ORCL_pmon_0_0987654321.aud
  assertFalse "生きていない(新フォーマット)" $?
  isActiveOracleAuditLogFile pmon_0.aud
  assertFalse "生きていない(旧フォーマット)" $?

  # 生きているがファイルは開いていない
  isActiveOracleAuditLogFile ORCL_pmon_${pid}_0987654321.aud
  assertFalse "生きているがファイルは開いていない(新フォーマット)" $?
  isActiveOracleAuditLogFile pmon_${pid}.aud
  assertFalse "生きているがファイルは開いていない(旧フォーマット)" $?

  # 生きていてファイルも開いている
  perl filelock.pl tmp/ORCL_pmon_ _0987654321.aud 3 &
  bgpid=$!
  isActiveOracleAuditLogFile tmp/ORCL_pmon_${bgpid}_0987654321.aud
  assertTrue "生きていてファイルも開いている(新フォーマット)" $?
  sleep 3
  rm -f tmp/ORCL_pmon_${bgpid}_0987654321.aud

  perl filelock.pl tmp/pmon_ .aud 3 &
  bgpid=$!
  isActiveOracleAuditLogFile tmp/pmon_${bgpid}.aud
  assertTrue "生きていてファイルも開いている(旧フォーマット)" $?
  sleep 3
  rm -f tmp/pmon_${bgpid}.aud
}

testIsRunning() {
  pidfile=tmp/`basename $0`.pid

  # pidfileがなく、2重起動もされていない
  rm -f $pidfile
  isRunning tmp
  assertFalse "pidfileがなく、2重起動もされていない" $?

  # 2重起動中
  rm -f $pidfile
  ./dummy_`basename $0` $pidfile 2 &
  sleep 1
  isRunning tmp
  assertTrue "2重起動中" $?
  sleep 1

  # pidfileがあるが、2重起動はされていない
  isRunning tmp
  assertFalse "pidfileがあるが、2重起動はされていない" $?
}

. ./shunit2/src/shunit2
