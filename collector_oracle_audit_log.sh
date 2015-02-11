#!/bin/sh

. config.profile

# TODO 2重起動チェック

mputCmd="mput"
shouldTransferFileCount=0

uname=`uname`
prefix=`hostname`_`date '+%Y%m%d%H%M%S'`_

# FIXME 対象ファイル名を絞る
for targetFileName in `ls $TARGET_LOG_DIR`
do
  md5file=${TMP_DIR}/${targetFileName}.end

  if [ "$uname" = 'SunOS' ]; then
    digest -a md5 $targetFileName > $md5file
  else
    md5sum $targetFileName > $md5file
  fi
  mputCmd="${mputCmd} ${targetFileName} ${md5file}"
  shouldTransferFileCount=`expr $shouldTransferFileCount + 2`
done

nmapCmd='nmap $0 '${prefix}'$0'

ftpLog=$TMP_DIR/ftp.log

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
fi
if [ `egrep -c "^4|^6" $ftpLog` -ne 0 ]; then
  echo "ftp Error"
fi

#TODO 掴まれていないログファイルの削除

exit 0
