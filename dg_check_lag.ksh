--http://www.dbaexpert.com/blog/monitoring-the-physical-standby-with-vdataguard_stats/

#!/bin/ksh

export DB=$1
export ORACLE_SID=${DB}1
echo $ORACLE_SID
export ORAENV_ASK=NO
export PATH=/usr/local/bin:/bin:/usr/bin:$PATH

. oraenv 
. $HOME/.ORACLE_BASE 
export LOGFILE=/tmp/check_lag_${DB}.log
export FN=`echo $0 | sed s/\.*[/]// |cut -d. -f1`
. $SH/${FN}.conf

sqlplus -s /nolog <<EOF
conn / as sysdba
col name for a13
col value for a20
col unit for a30
set pages 0 head off feed off ver off echo off trims on
spool $LOGFILE
select name||'|'||value from v\$dataguard_stats where NAME IN ('transport lag', 'apply lag');
spool off
exit;
EOF

export ERROR_COUNT=$(grep -c ORA- $LOGFILE)
if [ "$ERROR_COUNT" -gt 0 ]; then
  cat $LOGFILE |mail -s "DG Transport/Apply error for $DB ... ORA- errors encountered!" DGDBAs@viscosityna.com 
fi

TLAG=$(cat $LOGFILE |grep "transport lag" |cut -d'|' -f2)
ALAG=$(cat $LOGFILE |grep "apply lag" |cut -d'|' -f2)

echo "Transport Lag: $TLAG ------ Apply Lag: $ALAG"
export T_DAYS=$(echo $TLAG |cut -d' ' -f1 |sed -e "s/\+//g")
export T_HRS=$(echo $TLAG |cut -d' ' -f2 |cut -d: -f1)
export T_MINS=$(echo $TLAG |cut -d' ' -f2 |cut -d: -f2)
echo $T_DAYS $T_HRS $T_MINS

export A_DAYS=$(echo $ALAG |cut -d' ' -f1 |sed -e "s/\+//g")
export A_HRS=$(echo $ALAG |cut -d' ' -f2 |cut -d: -f1)
export A_MINS=$(echo $ALAG |cut -d' ' -f2 |cut -d: -f2)
echo $A_DAYS $A_HRS $A_MINS

echo "HR_THRESHOLD: $HR_THRESHOLD"
export ALERT_LOG_FILE=/tmp/check_lag_${DB}.alert
[ -f "$ALERT_LOG_FILE" ] && rm $ALERT_LOG_FILE

[ "$T_DAYS" -gt 00 ] && echo "Transport Lag is greater than 1 day!!!" |tee -a $ALERT_LOG_FILE
[ "$T_HRS" -gt $HR_THRESHOLD ] && echo "Transport Lag exceeeded our threshold limit of $HR_THRESHOLD hrs .. curently behind $T_DAYS day(s) $T_HRS hrs and $T_MINS mins" |tee -a $ALERT_LOG_FILE

[ "$A_DAYS" -gt 00 ] && echo "Apply Lag is greater than 1 day!!!" |tee -a $ALERT_LOG_FILE
[ "$A_HRS" -gt $HR_THRESHOLD ] && echo "Apply Lag exceeeded our threshold limit of $HR_THRESHOLD hrs .. curently behind $A_DAYS day(s) $A_HRS hrs and $A_MINS mins" |tee -a $ALERT_LOG_FILE

[ -s $ALERT_LOG_FILE ] && {
echo "" >> $ALERT_LOG_FILE
echo "--------- MRP Sessions Running -------------" >> $ALERT_LOG_FILE
ps -ef |grep -i mrp |grep -v grep >> $ALERT_LOG_FILE
cat $ALERT_LOG_FILE |mail -s "DG Transport/Apply for $DB is behind ... behind $T_DAYS day(s) $T_HRS hrs and $T_MINS mins " DGDBAs@viscosityna.com  
}
