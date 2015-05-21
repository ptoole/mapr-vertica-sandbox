#!/bin/bash

# wait for CLDB service to be running
#
echo Waiting for MapR Services to Start before configuring
maprcli node cldbmaster 2> /dev/null
while [ $? -ne 0 ] ; do
	sleep 5
	maprcli node cldbmaster 2> /dev/null
done


rpm -i /tmp/vertica.rpm
/opt/vertica/sbin/install_vertica --hosts `hostname` --dba-user-password-disabled --failure-threshold NONE --accept-eula --license CE

chkconfig vertica_agent off
chkconfig verticad off
cp -d /etc/init.d/verticad /opt/mapr/initscripts

cat > /etc/sudoers.d/mapr-vertica_conf <<DELIM
mapr ALL=(dbadmin) NOPASSWD:ALL
mapr ALL=(root) NOPASSWD:/opt/mapr/initscripts/vertica_wrapper,/opt/vertica/sbin/verticad,/bin/chown
Defaults!/opt/mapr/initscripts/vertica_wrapper !requiretty
Defaults!/opt/vertica/sbin/verticad !requiretty
Defaults!/bin/chown !requiretty
Defaults!/opt/vertica/bin/admintools !requiretty
DELIM

#
# Add Vertica to the MapR warden service management infrastructure
#
chmod a+x /opt/mapr/server/start_vertica_db.sh
chmod a+x /opt/mapr/server/test_vertica_db.sh

cat > /opt/mapr/initscripts/vertica_wrapper <<DELIM
#!/bin/bash

# Make sure VM IP is properly included in configuration
if [ \$1 = "start" ] ; then
	MYIP=\`ifconfig eth0 | grep "inet addr" | awk '{print \$2}' | cut -d: -f2\`

	VCONFIG=/opt/vertica/config/admintools.conf
	sed -i "s/^hosts.*/hosts = \$MYIP/" \$VCONFIG
	sed -i "s/node0001 = [^,]*,/node0001 = \$MYIP,/g" \$VCONFIG
	/usr/bin/sudo chown --reference=/opt/vertica/config \$VCONFIG

	[ -x /opt/mapr/server/start_vertica_db.sh ] && /opt/mapr/server/start_vertica_db.sh example 

	/usr/bin/sudo /opt/mapr/initscripts/verticad status
else
	[ \$1 = "stop" ] && /usr/bin/sudo -u dbadmin /opt/vertica/bin/admintools -t stop_db -d example --noprompts
	/usr/bin/sudo /opt/mapr/initscripts/verticad \$*
fi

exit \$?
DELIM

chmod +x /opt/mapr/initscripts/vertica_wrapper
usermod -G verticadba mapr		# so that the updating of admintools can work

cat > /opt/mapr/conf/conf.d/warden.HPVertica.conf <<DELIM
services=HPVertica:all:nfs
service.displayname="HPVertica"
service.command.start=/opt/mapr/initscripts/vertica_wrapper start
service.command.stop=/opt/mapr/initscripts/vertica_wrapper stop
service.logs.location=/vertica/data/catalog
service.command.type=BACKGROUND
service.command.monitorcommand=/opt/mapr/initscripts/vertica_wrapper status
service.depends.local=1
service.heapsize.percent=50
service.heapsize.min=2000
DELIM

chown mapr:mapr /opt/mapr/conf/conf.d/warden.HPVertica.conf

#	No longer necessary for global /vertica volume
# maprcli volume create -name vertica -path /vertica
# maprcli acl edit -type volume -name vertica -user dbadmin:fc


MAPR_HOSTNAME=`maprcli node list -columns hostname -noheader | awk '{print $1}'`

# create the data volume
maprcli volume create -name vertica.$MAPR_HOSTNAME.data -path /vertica/$MAPR_HOSTNAME/data -createparent true -localvolumehost $MAPR_HOSTNAME -replication 1

# create the temp volume
maprcli volume create -name vertica.$MAPR_HOSTNAME.tmp -path /vertica/$MAPR_HOSTNAME/tmp -createparent true -localvolumehost $MAPR_HOSTNAME -replication 1

# set permissions on the data volume
maprcli acl edit -type volume -name vertica.$MAPR_HOSTNAME.data -user dbadmin:fc
maprcli acl edit -type volume -name vertica.$MAPR_HOSTNAME.tmp -user dbadmin:fc

# disable MapR compression
hadoop mfs -setcompression off /vertica/$MAPR_HOSTNAME/data
hadoop mfs -setcompression off /vertica/$MAPR_HOSTNAME/tmp

hadoop fs -chown -R dbadmin:verticadba /vertica
mkdir /vertica
chown dbadmin:verticadba /vertica


# NOTE: the cluster name (eg demo.mapr.com) MUST match
#	the configuration in the mapr-install	.sh script that sets up the VM
#
sudo -u mapr echo localhost:/mapr/demo.mapr.com/vertica/$MAPR_HOSTNAME /vertica nolock,hard >> /opt/mapr/conf/mapr_fstab

service mapr-warden stop
sed -i "s/# chkconfig: .*/# chkconfig: 35 20 40/" /etc/init.d/mapr-warden
chkconfig mapr-warden resetpriorities

# Last, but not least, the VMDEMO build for 3.0 releases had a
# special webserver configuration that is NOT true for this build;
# we always need the https connection.
# VM_WELCOME=/opt/startup/welcome.py
# if [ -f $VM_WELCOME ] ; then
# 	sed -i "s_http://_https://_" $VM_WELCOME
#	sed -i "s_Cmd+Ctl+F2_Opt+F5_" $VM_WELCOME
# fi


