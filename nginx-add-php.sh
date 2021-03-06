#!/bin/bash
#
# Add a new site to Nginx running php.
# Recommends umask 0027 for future file editing.

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    echo 'This script is designed to run as root'
    exit
fi

# Check arguments
if [ $# -lt 2 ]; then
    echo 'Syntax: nginx-add-php.sh <site-name> <domain>[:<port>] [<user-name>] [<dest-dir>]'
    exit
fi

source "${0%/*}/nginx-common.sh"

# Determine site information. Separate domain name and port from second argument.
SITENAME=$1
SITEPORT=${2#*:}
SITEDOMAIN=${2%:*}
if [ "$SITEPORT" == "$SITEDOMAIN" ]; then
    SITEPORT=80
fi

# Determine site directory and user
if [ $# -eq 2 ]; then
    DESTDIR=/srv/www/$1
    SITE_USER=$SUDO_USER
    SITE_GROUP='www-data'
    RUN_AS_USER='www-data'
    SOCKET_PATH='/var/run/php5-fpm.sock'
else
    if [ $3 == 'www-data' ]; then
        DESTDIR=/srv/www/$1
        SITE_USER=$SUDO_USER
        SITE_GROUP='www-data'
        RUN_AS_USER='www-data'
        SOCKET_PATH='/var/run/php5-fpm.sock'
    else
        prepare_user $3
        DESTDIR=$HOMEDIR/$1
        SITE_USER=$3
        SITE_GROUP='www-data'
        RUN_AS_USER=$3
        SOCKET_PATH="/var/run/php5-fpm-$RUN_AS_USER.sock"

        # Create php5-fpm configuration
        if [ ! -f /etc/php5/fpm/pool.d/$RUN_AS_USER.conf ]; then
            tee /etc/php5/fpm/pool.d/$RUN_AS_USER.conf > /dev/null << EOF
[www-$RUN_AS_USER]
listen = $SOCKET_PATH
user = $RUN_AS_USER
group = $SITE_GROUP
pm = dynamic
pm.max_children = 2
pm.start_servers = 1
pm.min_spare_servers = 1
pm.max_spare_servers = 1
EOF
        /etc/init.d/php5-fpm restart
        fi
    fi

    # Possibly set a specific destination directory for the site
    if [ $# -eq 4 ]; then
        DESTDIR=$(readlink -f "$4")
    fi
fi

# Create destination directories
sub_dirs=(public logs)
for subdir in "${sub_dirs[@]}"; do
    if [ ! -d "$DESTDIR/$subdir" ]; then
        mkdir -p "$DESTDIR/$subdir"
    fi
done

# Create nginx configuration
# Rename any existing file before creating the new one
if [ -f /etc/nginx/sites/$1.conf ]; then
    mv /etc/nginx/sites/$1.conf /etc/nginx/sites/$1.conf.old
fi
tee /etc/nginx/sites/$1.conf > /dev/null << EOF
server {
    listen $SITEPORT;
    server_name $SITEDOMAIN;
    access_log $DESTDIR/logs/$1.access.log;
    error_log $DESTDIR/logs/error.log;
    root $DESTDIR/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php;
    }

    location ~ .php\$ {
        fastcgi_split_path_info ^(.+\.php)(.*)\$;
        fastcgi_pass unix:$SOCKET_PATH;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $DESTDIR/public\$fastcgi_script_name;
        fastcgi_param SITE_NAME "$SITENAME";
        include fastcgi_params;
    }
}
EOF

# If there was an existing file, append it to the configuration with prepended
# hash characters at the beginning of each row to make them commented out. Only append
# if the files differ.
if [ -f /etc/nginx/sites/$1.conf.old ]; then
    diff --brief /etc/nginx/sites/$1.conf.old /etc/nginx/sites/$1.conf > /dev/null
    if [ $? -ne 0 ]; then
        sed -r 's/^.+$/#\0/' /etc/nginx/sites/$1.conf.old >> /etc/nginx/sites/$1.conf
    fi
    rm /etc/nginx/sites/$1.conf.old
fi

# Set permissions for configuration file
chmod 0660 /etc/nginx/sites/$1.conf

# Copy template files
cp -R "$(dirname $0)/nginx-php-template/." $DESTDIR

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

echo "Created Php site $1 successfully at $DESTDIR"

