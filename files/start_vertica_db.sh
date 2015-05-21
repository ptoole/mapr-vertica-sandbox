#!/bin/bash

# Simple script to start a Vertica database (or create an empty
# one if it doesn't exist).  The script must be executed by a user
# that can sudo to the Vertica administrator.
#
# NOTE: this assumes that the MapR services (and the NFS mount
# point to the vertica data) are up and running)

DBADMIN=dbadmin
VERTICADB=${1:-sample}
ADMINTOOLS="sudo -u $DBADMIN /opt/vertica/bin/admintools"
VSQL="sudo -u $DBADMIN /opt/vertica/bin/vsql"

THIS_HOST=`/bin/hostname`


function create_new_db()
{
	LOC_SQL=/tmp/locations.sql
	rm -f $LOC_SQL
	if [ $? -ne 0 ] ; then
		LOC_SQL=/tmp/locations.sql.$$
	fi

	$ADMINTOOLS -t create_db \
		-c /vertica/data/catalog \
		-D /vertica/data/files \
		-s $THIS_HOST \
		-d $VERTICADB 

	$VSQL -c "alter resource pool general maxmemorysize '50%'"

	$VSQL -q -t -A -c "
Select  E'select add_location(\'/vertica/tmp/'
        || database_name || '/'
        || node_name
        || E'_tmp\',\''
        || node_name
        || E'\',\'TEMP\');'
  from nodes cross join databases" > $LOC_SQL

	$VSQL -q -t -A -c "
select E'select alter_location_use(\'/vertica/data/files/'
        || database_name || '/'
        || node_name
        || E'_data\',\''
        || node_name
        || E'\',\'DATA\');'
  from storage_locations cross join databases
  where location_usage ilike 'DATA,TEMP' " >> $LOC_SQL

	$VSQL -q -f $LOC_SQL

	[ $? -eq 0 ] && rm -f $LOC_SQL
}

NFS_WAIT=0
test -d /vertica/data
while [ $? -ne 0 ] ; do
	if [ $NFS_WAIT -ge 300 ] ; then
		echo "Vertica data filesystem not available after 5 minutes; aborting"
		exit 1
	fi
	sleep 5
	NFS_WAIT=$[NFS_WAIT+5]
	test -d /vertica/data
done

if [ -d /vertica/data/files/$VERTICADB ] ; then 
	$ADMINTOOLS -t db_status -s UP | grep -q -w $VERTICADB
	if [ $? -ne 0 ] ; then
			# Make sure the DB IP is valid
		NEWIP=`hostname -i`
		NEWBCAST=`ifconfig eth0 | grep "Bcast:" | awk '{print $3}' | cut -d: -f2`
		sudo -u dbadmin /opt/vertica/bin/vertica -D /vertica/data/catalog/${VERTICADB}/v_${VERTICADB}_node0001_catalog/ -E << EOVERTICA
unlock danger
set name Site v_${VERTICADB}_node0001 address $NEWIP
set name Site v_${VERTICADB}_node0001 controlAddress $NEWIP
set name Site v_${VERTICADB}_node0001 controlBroadcast $NEWBCAST
commit
exit
EOVERTICA
			# Start up the DB
		[ $? -eq 0 ] && $ADMINTOOLS -t start_db -d $VERTICADB --noprompts
	fi
else
	create_new_db
fi

$ADMINTOOLS -t db_status -s UP | grep -q -w $VERTICADB
if [ $? -eq 0 ] ; then
	echo "Vertica database $VERTICADB running"
else
	echo "Vertica database $VERTICADB NOT FOUND"
fi

