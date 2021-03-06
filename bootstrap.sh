#!/bin/bash
RESULT=$(which yum > /dev/null 2>&1)
NO_YUM=$?

RESULT=$(which apt-get > /dev/null 2>&1)
NO_APT=$?

RHEL7=0

RESULT=$(cat /etc/*-release | grep -e "CentOS\|RedHat" | grep 7)
if (( $? == 0 )); then
	RHEL7=1
fi

if (( $NO_YUM == 1 && $NO_APT == 1));
then
	echo "No Yum or Apt detected, your system is unsupported... please install the required packages manually."
	exit
fi

if (( $NO_YUM == 0 ));
then
	yum -y install postgresql php php-pgsql rsyslog rsyslog-pgsql apache2 postgresql-server mlocate git
	if (( $? == 1 ));
	then
		echo "Some error occured, please check and run the script again..."
		exit
	fi
fi

if (( $NO_APT == 0 ));
then
	apt-get install postgresql php php-pgsql rsyslog rsyslog-pgsql apache2 postgresql-server mlocate git
	if (( $? == 1 ));
	then
		echo "Some error occured, please check and run the script again..."
		exit
	fi
fi

echo
echo

echo "Cloning Audiocodes Syslog Tool..."
git clone https://github.com/niekvlessert/audiocodes_syslog_tool
echo "Basic initialisation of Postgres..."
#service postgresql initdb
postgresql-setup initdb
echo "Allow short open tag in /etc/php.ini..."
sed -i 's/short_open_tag = Off/short_open_tag = On/g' /etc/php.ini
echo "Allow postgres connections more loosely..."
sed -i "s/\#listen_addresses = 'localhost'*/listen_addresses = '\*'        /g" /var/lib/pgsql/data/postgresql.conf
sed -i 's/host    all             all             127.0.0.1\/32            ident/host    all             all             127.0.0.1\/32            trust/g' /var/lib/pgsql/data/pg_hba.conf
sed -i 's/local   all             all                                     ident/local   all             all                                     trust/g' /var/lib/pgsql/data/pg_hba.conf

RESULT=$(which systemctl > /dev/null 2>&1)
if (( $? == 0 ));
then
	echo "Restarting postgres"
	systemctl restart postgresql
	echo "Starting webserver"
	systemctl start httpd
else
	/etc/init.d/postgresql restart
	/etc/init.d/httpd restart
fi
if (( $NO_YUM == 0 ));
then
	chkconfig postgresql on
fi

if (( $RHEL7 == 1 ));
then
	firewall-cmd --permanent --add-service=syslog > /dev/null 2>&1
	firewall-cmd --permanent --add-service=http > /dev/null 2>&1
	firewall-cmd --reload > /dev/null 2>&1
	echo "RHEL7/CentOS 7 detected... adding firewall rule using firewall-cmd"
else
	echo "Adding a line to the IPTables to allow syslog information on UDP port 514..."
	iptables -D INPUT -p udp --dport 514 -j ACCEPT > /dev/null 2>&1
	iptables -I INPUT -p udp --dport 514 -j ACCEPT
	echo "Adding a line to the IPTables to allow http on TCP port 80..."
	iptables -D INPUT -p tcp --dport 80 -j ACCEPT > /dev/null 2>&1
	iptables -I INPUT -p tcp --dport 80 -j ACCEPT
	iptables-save > /dev/null 2>&1
fi

echo "Disabling SELinux..."
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

cd audiocodes_syslog_tool
php maintenance.php install
