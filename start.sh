#!/bin/bash
usage ()
{
     echo
     echo "Usage:    ./setup.sh [ARGUMENT]"
     echo
     echo "Arguments:"
     echo "    run                   - Auto start all services or install wizard in case of initial setup"
     echo "    link                  - Create symlinks default folders to /data"
     echo "    metronome               - Configure metronome from config"
     echo "    ssl                   - Configure SSL using your certs"
     echo "    fail2ban              - Configure Fail2ban"
     echo
     exit
}

generate_dn()
{
    echo $(hostname -d) | sed 's/^/dc=/g' | sed 's/[\.]/,dc=/g'
}

chk_var () {
   var=$(sh -c "echo $(echo \$$1)")
   [ -z "$var" ] && export "$1"="$2"
}

load_defaults()
{
    chk_var  TZ                    "utc"
    chk_var  FAIL2BAN              true
    chk_var  KOLAB_DN              `generate_dn`
    chk_var  BIND_USER             'uid=kolab-service,ou=Special Users,dc=example,dc=org'
    chk_var  BIND_PASS             "password"
    chk_var  GROUPS_MODE           "public"
}

get_config()
{
    while IFS="=" read var val
    do
        if [[ $var == \[*] ]]
        then
            section=`echo "$var" | tr -d "[] "`
        elif [[ $val ]]
        then
            if [[ $val == "random" ]]
            then
		random_pwd="$(cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 16; echo)"	# gen pass
                eval $section"_"$var=$random_pwd
		sed -i --follow-symlinks "/\(^"$var"=\).*/ s//\1"$random_pwd"/ " $1	#save generated pass to settings.ini
            else
                eval $section"_"$var="$val"
            fi
        fi
    done < $1
    chmod 600 /etc/settings.ini
}

set_timezone()
{
    if [ -f /usr/share/zoneinfo/$TZ ]; then 
        rm -f /etc/localtime && ln -s /usr/share/zoneinfo/$TZ /etc/localtime
    fi
}

dir=(
    /etc/settings.ini
    /etc/fail2ban
    /etc/my.cnf
    /etc/metronome
    /etc/supervisord.conf
    /var/lib/metronome
    /var/log/metronome
    /etc/ssl
    /etc/pki
    /var/log/messages
    /var/log/supervisor
)


move_dirs()
{
    echo "info:  start moving lib and log folders to /data volume"

    for i in "${dir[@]}"; do mkdir -p /data$(dirname $i) ; done
    for i in "${dir[@]}"; do mv $i /data$i; done

    echo "info:  finished moving lib and log folders to /data volume"
}

link_dirs()
{
    echo "info:  start linking default lib and log folders to /data volume"

    for i in "${dir[@]}"; do rm -rf $i && ln -s /data$i $i ; done
 
    echo "info:  finished linking default lib and log folders to /data volume"
}

configure_metronome()
{
    echo "info:  start configuring Metronome"

    sed -r -i \
        -e "s/example\.org/$(hostname -d)/g" \
        -e '/bind_dn /c\        bind_dn = '\'$kolab_bind_username\'"," \
        -e '/bind_password /c\        bind_password = '\'$kolab_bind_password\'"," \
        -e '/ hostname *=/c\       hostname       = '\'$kolab_hostname\'',' \
        -e "s/dc=[^\']*/$domain_dn/g" \
        /etc/metronome/metronome.cfg.lua \
        /etc/metronome/ldap.cfg.lua

    if [ $metronome_kolab_authentification = "false" ] ; then
        sed -r -i -e '/^[^--]*authentication.*ldap2/s/^/--/' \
                  -e '/^[^--]*storage.*vcard = "ldap"/s/^/--/' \
        /etc/metronome/metronome.cfg.lua
    fi

    if [ $metronome_kolab_intergration = "false" ] ; then
        sed -i --follow-symlinks '/^[^;]*kolabgr/s/^/;/' /etc/supervisord.conf
    fi

    if [ $metronome_all_groups_is_public = "false" ] ; then
    sed -i -e '/show_all_groups = /c\        show_all_groups = false,' \
        /etc/metronome/metronome.cfg.lua \
        /etc/metronome/ldap.cfg.lua
    fi

    echo "info:  finished configuring Metronome"

}

configure_ssl()
{
    if [ -f /etc/pki/tls/certs/$(hostname -f).crt ] ; then
        echo "warn:  SSL already configured, but that's nothing wrong, run again..."
    fi
    echo "info:  start configuring SSL"
    cat > /tmp/update_ssl_key_message.txt << EOF


# Please paste here your SSL ___PRIVATE KEY___. Lines starting
# with '#' will be ignored, and an empty message aborts
# updating SSL-certificates procedure.
EOF
    cat > /tmp/update_ssl_crt_message.txt << EOF


# Please paste here your SSL ___CERTIFICATE___. Lines starting
# with '#' will be ignored, and an empty message aborts
# updating SSL-certificates procedure.
EOF

    cat > /tmp/update_ssl_ca_message.txt << EOF


# Please paste here your SSL ___CA-CERTIFICATE___. Lines starting
# with '#' will be ignored, and an empty message aborts
# updating SSL-certificates procedure.
EOF

    if [ -f /etc/pki/tls/private/$(hostname -f).key ] ; then
	cat /etc/pki/tls/private/$(hostname -f).key /tmp/update_ssl_key_message.txt > /tmp/update_ssl_$(hostname -f).key
    else
	cat /tmp/update_ssl_key_message.txt > /tmp/update_ssl_$(hostname -f).key
    fi

    if [ -f /etc/pki/tls/certs/$(hostname -f).crt ] ; then
	cat /etc/pki/tls/certs/$(hostname -f).crt /tmp/update_ssl_crt_message.txt > /tmp/update_ssl_$(hostname -f).crt
    else
	cat /tmp/update_ssl_crt_message.txt > /tmp/update_ssl_$(hostname -f).crt
    fi
    if [ -f /etc/pki/tls/certs/$(hostname -f)-ca.pem ] ; then
	cat /etc/pki/tls/certs/$(hostname -f)-ca.pem /tmp/update_ssl_ca_message.txt > /tmp/update_ssl_$(hostname -f)-ca.pem
    else
	cat /tmp/update_ssl_ca_message.txt > /tmp/update_ssl_$(hostname -f)-ca.pem
    fi

    vi /tmp/update_ssl_$(hostname -f).key
    vi /tmp/update_ssl_$(hostname -f).crt
    vi /tmp/update_ssl_$(hostname -f)-ca.pem

    if [ "$(grep -c -v -E "^#|^$" /tmp/update_ssl_$(hostname -f).key)" != "0" ] || [ "$(grep -c -v -E "^#|^$" /tmp/update_ssl_$(hostname -f).crt)" != "0" ] || [ "$(grep -c -v -E "^#|^$" /tmp/update_ssl_$(hostname -f)-ca.pem)" != "0" ] ; then
        grep -v -E "^#|^$" /tmp/update_ssl_$(hostname -f).key > /etc/pki/tls/private/$(hostname -f).key
        grep -v -E "^#|^$" /tmp/update_ssl_$(hostname -f).crt > /etc/pki/tls/certs/$(hostname -f).crt
        grep -v -E "^#|^$" /tmp/update_ssl_$(hostname -f)-ca.pem > /etc/pki/tls/certs/$(hostname -f)-ca.pem

        # Create certificate bundles
        cat /etc/pki/tls/certs/$(hostname -f).crt /etc/pki/tls/private/$(hostname -f).key /etc/pki/tls/certs/$(hostname -f)-ca.pem > /etc/pki/tls/private/$(hostname -f).bundle.pem
        cat /etc/pki/tls/certs/$(hostname -f).crt /etc/pki/tls/certs/$(hostname -f)-ca.pem > /etc/pki/tls/certs/$(hostname -f).bundle.pem
        cat /etc/pki/tls/certs/$(hostname -f)-ca.pem > /etc/pki/tls/certs/$(hostname -f).ca-chain.pem
        # Set access rights
        chown -R root:metronome /etc/pki/tls/private
        chmod 600 /etc/pki/tls/private/$(hostname -f).key
        chmod 750 /etc/pki/tls/private
        chmod 640 /etc/pki/tls/private/*
        # Add CA to system’s CA bundle
        cat /etc/pki/tls/certs/$(hostname -f)-ca.pem >> /etc/pki/tls/certs/ca-bundle.crt

        # Configuration metronome for SSL
        sed -r -i \
            -e '/certificate =/c\    certificate = "/etc/pki/tls/certs/'$(hostname -f)'.bundle.pem";' \
            -e '/key =/c\    key = "/etc/pki/tls/private/'$(hostname -f)'.key";' \
            /etc/metronome/metronome.cfg.lua

    else 
        echo "error: input of certifacte or private key or ca-sertificate is blank, skipping..."
    fi

    rm -rf /tmp/update_ssl*
    echo "info:  finished configuring SSL"
}

configure_fail2ban()
{
    if [ "$(grep -c "metronome" /etc/fail2ban/jail.conf)" == "0" ] ; then
        echo "info:  start configuring Fail2ban"

        # Uncoment fail2ban
        sed -i --follow-symlinks '/^;.*fail2ban/s/^;//' /etc/supervisord.conf

        echo "info:  finished configuring Fail2ban"
    else
        echo "warn:  Fail2ban already configured, skipping..."
    fi
}

setup_wizard ()
{
    vi /etc/settings.ini
    get_config /etc/settings.ini
    # Main
    if [ $main_configure_metronome = "true" ] ; then configure_metronome ; fi
    if [ $main_configure_ssl = "true" ] ; then configure_ssl ; fi
    if [ $main_configure_fail2ban = "true" ] ; then configure_fail2ban ; fi
    # Print parameters
}

run ()
{
     if [ -f /data/etc/metronome/metronome.cfg.lua ] ; then
     
         echo "info:  Metronome installation detected on /data volume, run relinkink..."
         link_dirs
         
         echo "info:  Starting services"
         /usr/bin/supervisord
     
     else
     
          while true; do
             read -p "warn:  Metronome data not detected on /data volume, this is first installation(yes/no)? " yn
             case $yn in
                 [Yy]* ) move_dirs; link_dirs; setup_wizard; break;;
                 [Nn]* ) echo "info:  Installation canceled"; exit;;
                 * ) echo "Please answer yes or no.";;
             esac
         done
     
     fi
}

set_timezone

if [ -f /data/etc/settings.ini ]; then get_config /data/etc/settings.ini; fi

case "$1" in
    "run")      run ;;
    "metronome")  configure_metronome ;;
    "ssl")      configure_ssl ;;
    "fail2ban") configure_fail2ban ;;
    "link")     link_dirs ;;
    *)          usage ;;
esac
