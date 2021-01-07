#!/bin/bash
currentdir=${PWD##*/}
parentdir="$(dirname "$(pwd)")"
if [ $currentdir != 'install' ]
then
    echo 'Please run the script from the install directory'
    exit
fi

cd ../
# Make sure root isnt running the script
if [ "$(id -u)" == "0" ]; then
   echo "This script must NOT be run as root" 1>&2
   exit 1
fi

. config/settings.ini

if [ ! -d 'tmp' ]
then
  mkdir tmp
fi

if [ ! -d 'tmp/geonature/' ]
then
  mkdir tmp/geonature
fi

if [ ! -d 'var' ]
then
  mkdir var
fi

if [ ! -d 'var/log' ]
then
  mkdir var/log
  chmod -R 775 var/log/
fi

function database_exists () {
    # /!\ Will return false if psql can't list database. Edit your pg_hba.conf
    # as appropriate.
    if [ -z $1 ]
        then
        # Argument is null
        return 0
    else
        # Grep DB name in the list of databases
        sudo -u postgres -s -- psql -tAl | grep -q "^$1|"
        return $?
    fi
}

function write_log() {
    echo -e $1
    echo "" &>> var/log/install_db.log
    echo "" &>> var/log/install_db.log
    echo "--------------------" &>> var/log/install_db.log
    echo -e $1 &>> var/log/install_db.log
    echo "--------------------" &>> var/log/install_db.log
}

# DESC: Validate we have superuser access as root (via sudo if requested)
# ARGS: $1 (optional): Set to any value to not attempt root access via sudo
# OUTS: None
# SOURCE: https://github.com/ralish/bash-script-template/blob/stable/source.sh
function check_superuser() {
    local superuser
    if [[ ${EUID} -eq 0 ]]; then
        superuser=true
    elif [[ -z ${1-} ]]; then
        if command -v "sudo" > /dev/null 2>&1; then
            echo 'Sudo: Updating cached credentials ...'
            local test_euid
            test_euid="$(sudo -H -- "${BASH}" -c 'printf "%s" "${EUID}"')"
            if [[ ${test_euid} -eq 0 ]]; then
                superuser=true
            else
                echo "Sudo: Couldn't acquire credentials ..."
            fi
        else
			echo "Missing dependency: sudo"
        fi
    fi

    if [[ -z ${superuser-} ]]; then
        echo 'Unable to acquire superuser credentials.'
        return 1
    fi

    echo 'Successfully acquired superuser credentials.'
    return 0
}

echo "Asking for superuser righ via sudo..."
check_superuser

if database_exists "${db_name}"; then
    if $drop_apps_db; then
        echo "Close all Postgresql conections on GeoNature DB"
        query=("SELECT pg_terminate_backend(pg_stat_activity.pid) "
            "FROM pg_stat_activity "
            "WHERE pg_stat_activity.datname = '${db_name}' "
            "AND pid <> pg_backend_pid() ;")
        sudo -n -u "postgres" -s psql -d "postgres" -c "${query[*]}"

        echo "Drop database..."
        sudo -n -u "postgres" -s dropdb "${db_name}"
    else
        echo "Database exists but the settings file indicates that we don't have to drop it."
    fi
fi

if ! database_exists "${db_name}"; then
    sudo sed -e "s/datestyle =.*$/datestyle = 'ISO, DMY'/g" -i /etc/postgresql/*/main/postgresql.conf
    sudo service postgresql restart
    echo "--------------------" &> var/log/install_db.log
    write_log "Creating GeoNature database..."
    sudo -n -u postgres -s createdb -O $user_pg $db_name -T template0 -E UTF-8 -l $my_local

    write_log "Adding default PostGIS extension"
    sudo -n -u postgres -s psql -d $db_name -c "CREATE EXTENSION IF NOT EXISTS postgis;" &>> var/log/install_db.log

    write_log "Extracting PostGIS version"
    postgis_full_version=$(sudo -n -u postgres -s psql -d "${db_name}" -c "SELECT PostGIS_Version();")
    postgis_short_version=$(echo "${postgis_full_version}" | sed -n 's/^\s*\([0-9]*\.[0-9]*\)\s.*/\1/p')
    write_log "PostGIS full version:\n ${postgis_full_version}"
    write_log  "PostGIS short version extract: '${postgis_short_version}'"

    write_log "Adding Raster PostGIS extension if necessary"
    postgis_required_version="3.0"
    if [[ "$(printf '%s\n' "${postgis_required_version}" "${postgis_short_version}" | sort -V | head -n1)" = "${postgis_required_version}" ]]; then
        write_log "PostGIS version greater than or equal to ${postgis_required_version} --> adding Raster extension"
        sudo -n -u postgres -s psql -d $db_name -c "CREATE EXTENSION IF NOT EXISTS postgis_raster;" &>> var/log/install_db.log
    else
        write_log "PostGIS version lower than ${postgis_required_version} --> do nothing"
    fi

    write_log "Adding other use PostgreSQL extensions"
    sudo -n -u postgres -s psql -d $db_name -c "CREATE EXTENSION IF NOT EXISTS hstore;" &>> var/log/install_db.log
    sudo -n -u postgres -s psql -d $db_name -c "CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog; COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';" &>> var/log/install_db.log
    sudo -n -u postgres -s psql -d $db_name -c 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";' &>> var/log/install_db.log
    sudo -n -u postgres -s psql -d $db_name -c "CREATE EXTENSION IF NOT EXISTS pg_trgm with schema pg_catalog;" &>> var/log/install_db.log

    # Mise en place de la structure de la BDD et des données permettant son fonctionnement avec l'application
    echo "GRANT..."
    cp data/grant.sql tmp/geonature/grant.sql
    sudo sed -i "s/MYPGUSER/$user_pg/g" tmp/geonature/grant.sql
    write_log 'GRANT'
    sudo -n -u postgres -s psql -d $db_name -f tmp/geonature/grant.sql &>> var/log/install_db.log
fi
