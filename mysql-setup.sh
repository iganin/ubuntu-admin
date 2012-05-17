#!/bin/bash
#
# Setup MySQL.

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script is designed to run as root'
    exit
fi

# Ask for root password
read -s -p 'Specify password to set for MySQL root account: '
echo ''

# Install MySQL
echo 'Installing MySQL packages'
DEBIAN_FRONTEND=noninteractive apt-get -yq install mysql-server >> tmp/logfile
if [ $? -ne 0 ]; then
    echo 'Failed to install mysql-server package'
    exit $?
fi

# Set root password
mysql -u root << EOF
update mysql.user set password = password('$REPLY') where user='root';
flush privileges;
EOF
if [ $? -ne 0 ]; then
    echo 'Failed to set root password for MySQL'
    exit $?
fi

# Remember password for system root user to that 'sudo -H' will give access
cat > /root/.my.cnf << EOF
[client]
user = root
password = $REPLY
EOF
chown root:root /root/.my.cnf
chmod 600 /root/.my.cnf

# Set up backup
echo 'Schedule backup'
cp mysql-backup.sh /usr/local/sbin/mysql-backup.sh
chmod 750 /usr/local/sbin/mysql-backup.sh
crontab -l 2> /dev/null | grep -q mysql-backup.sh
if [ $? -ne 0 ]; then
    crontab -l 2> /dev/null | (cat; echo '25 23 * * * /usr/local/sbin/mysql-backup.sh') | crontab -
fi

# Get version for display purposes
MYSQLVER=$(mysqld --version)
[[ $MYSQLVER =~ Ver\ ([0-9.]+) ]]
MYSQLVER=${BASH_REMATCH[1]}

echo "MySQL version $MYSQLVER installed successfully"

