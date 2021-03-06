#!/bin/bash
#
# Add a new site to Nginx running ASP.NET under Mono.
# Recommends umask 0027 for future file editing.

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script is designed to run as root'
    exit
fi

# Check arguments
if [ $# -lt 2 ]; then
    echo 'Syntax: nginx-add-mono <site-name> <domain>[:<port>] [<user-name>]'
    exit
fi

source "${0%/*}/nginx-common.sh"

# Ensure requirements are installed
apt-get -yq install mono-fastcgi-server4 >> tmp/logfile
if [ $? -ne 0 ]; then
    echo 'Could not install Mono'
    exit
fi

# Determine site information. Separate domain name and port from second argument.
SITENAME=$1
SITEPORT=${2#*:}
SITEDOMAIN=${2%:*}
CGIPORT=9901
if [ "$SITEPORT" == "$SITEDOMAIN" ]; then
    SITEPORT=80
fi

# Determine site directory and user
if [ $# -eq 2 ]; then
    DESTDIR=/srv/www/$1
    SITE_USER=$SUDO_USER
    SITE_GROUP='www-data'
    RUN_AS_USER='www-data'
else
    prepare_user $3

    DESTDIR=$HOMEDIR/$1
    SITE_USER=$3
    SITE_GROUP='www-data'
    RUN_AS_USER=$3
fi

# Create destination directories
if [ -d "$DESTDIR" ]; then
    echo "Site directory $DESTDIR already exists. Script will not continue."
    exit 1
fi
mkdir -p "$DESTDIR/public"
mkdir "$DESTDIR/logs"

# Create Mono upstart
tee /etc/init/mono-$RUN_AS_USER.conf > /dev/null << EOF
description "Mono ASP.NET for user $RUN_AS_USER"
start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [!2345]
respawn
setuid $RUN_AS_USER
exec /usr/bin/fastcgi-mono-server4 /applications=/:$DESTDIR/public /socket=tcp:127.0.0.1:$CGIPORT
EOF
start mono-$RUN_AS_USER
if [ $? -ne 0 ]; then
    echo 'Could not start the Mono FastCGI process. Will continue to create Nginx configuration anyway.'
fi

# Create nginx configuration
tee /etc/nginx/sites/$1.conf > /dev/null << EOF
server {
    listen $SITEPORT;
    server_name $SITEDOMAIN;
    access_log $DESTDIR/logs/$1.access.log;
    error_log $DESTDIR/logs/error.log;
    root $DESTDIR/public;
    index index.aspx index.html;

    location / {
        try_files \$uri \$uri/ /index.aspx;
    }

    location ~ .aspx\$ {
        fastcgi_split_path_info ^(.+\.aspx)(.*)\$;
        fastcgi_pass 127.0.0.1:$CGIPORT;
        fastcgi_index index.aspx;
        fastcgi_param SCRIPT_FILENAME $DESTDIR/public\$fastcgi_script_name;
        fastcgi_param HTTP_SITE_NAME "$SITENAME";
        include fastcgi_params;
    }
}
EOF
chmod 0660 /etc/nginx/sites/$1.conf

# Copy template files
cp -R "$(dirname $0)/nginx-mono-template/." $DESTDIR

# Set permissions
chown -R $SITE_USER:$SITE_GROUP $DESTDIR
chmod -R 0750 $DESTDIR
find $DESTDIR -type d -exec chmod 2750 {} \;

# Check that nginx is happy with configuration
nginx -t
if [ $? -ne 0 ]; then
    echo 'Nginx reported error in configuration'
    exit
fi
nginx -s reload

echo "Created Mono site $1 successfully at $DESTDIR"

