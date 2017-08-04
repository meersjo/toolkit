#!/bin/bash
# Backup mysql databases per database, including authentication


Storage=/data/mysql-dumps

Machine=$1
if [[ "$Machine" == '' ]]; then
  >&2 echo "Must specify hostname"
  exit 10
fi

User=${2:-backup}
Password=${3:-defaultpassword}

CurDate=`date +%Y%m%d-%H%M%S`
Lockfile="/tmp/mysql-backup-$Machine.lock"
Tempdir=/tmp/mysql-dumps
Mysql="mysql -h$Machine -u$User -p$Password"
MysqlDump="mysqldump -h$Machine -u$User -p$Password --opt --routines --triggers --hex-blob --events --quote-names --allow-keywords --max_allowed_packet=1G"

## Check connectivity
mysqladmin -h"$Machine" -u"$User" -p"$Password" ping
if [[ $? != 0 ]]; then
  >&2 echo "ERROR: cannot reach host $Machine"
  exit 10
fi

## Atomic lock
( set -C; echo $CurDate > $Lockfile ) 2> /dev/null
if [ $? != "0" ]; then
  >&2 echo "Lock File exists - exiting"
  exit 1
fi
# Normally, the lockfile will have been renamed to lastrun for use with the next differential.
# This ensures that it's gone if the script exits abnormally.
trap "rm -f $Lockfile" EXIT

# cleanup old backup
rm -rf $Tempdir/$Machine

#Create local directory
mkdir -p $Tempdir/$Machine/$CurDate
if [[ $? != 0 ]]; then
  >&2 echo "Failed to create directory $Tempdir/$Machine/$CurDate"
  exit 10
fi

# Dump all databases
for Database in `$Mysql -se 'show databases' | grep -v 'information_schema' | grep -v 'performance_schema'`; do
  (
    tNonTransactional=`$Mysql -sse "select count(engine) from information_schema.tables where engine != 'InnoDB' and table_schema = '${Database}'"`
    if [[ $tNonTransactional -eq 0 ]]; then
      # Fully transactional (InnoDB) database, we can use --single-transaction
      MysqlDumpOpts='--single-transaction'
    else
      echo -n "Database ${Database} on ${Machine} contains ${tNonTransactional} non-InnoDB tables. "
      echo "This forces a full lock during bacup. Maybe we can do something about that?"
      # Database contains non-InnoDB tables, lock all affected tables
      MysqlDumpOpts='--lock-tables'
    fi

    $MysqlDump $MysqlDumpOpts "$Database" | gzip >> $Tempdir/$Machine/$CurDate/$Database.sql.gz
    if [[ $? != 0 ]]; then
      >&2 echo "Failed to dump $Database contents to $Tempdir/$Machine/$CurDate/$Database.sql.gz"
    fi
  ) &
done; wait

# Dump authentication info per db
for db in $($Mysql -se 'show databases' | grep -v 'information_schema' | grep -v 'performance_schema'); do 
  (
    for user in $($Mysql -se "select distinct concat('\`', user, '\`', '@', '\`', host, '\`') from mysql.db where db = '$db'"); do 
      $Mysql -se "show grants for $user" 2>$Tempdir/$Machine/grant.tmp | egrep "(ON *.*|ON \`$db\`)" >> $Tempdir/$Machine/$CurDate/$db.auth.sql
      if [[ $? != 0 ]]; then
        if ! grep "The MySQL server is running with the --skip-grant-tables option" $Tempdir/$Machine/grant.tmp >/dev/null; then
          >&2 echo "Failed to dump $db authentication info to $Tempdir/$Machine/$CurDate/$db.auth.sql"
        fi
      fi
    done
  ) &
done; wait
rm -f $Tempdir/$Machine/grant.tmp

# Dump global authentification info
for user in $($Mysql -se "select distinct concat('\`', user, '\`', '@', '\`', host, '\`') from mysql.user where select_priv = 'Y'"); do 
  $Mysql -se "show grants for $user" 2>$Tempdir/$Machine/grant.tmp | grep 'ON *.*'
done >> $Tempdir/$Machine/$CurDate/GLOBAL.auth.sql
if [[ $? != 0 ]]; then
  if ! grep "The MySQL server is running with the --skip-grant-tables option" $Tempdir/$Machine/grant.tmp >/dev/null; then
    >&2 echo "Failed to dump global authentication info to $Tempdir/$Machine/$CurDate/GLOBAL.auth.sql"
  fi
fi

# move into place
mkdir -p "$Storage/$Machine"
mv "$Tempdir/$Machine/$CurDate" "$Storage/$Machine/"
if [[ $? != 0 ]]; then
  >&2 echo "Move failed"
fi
