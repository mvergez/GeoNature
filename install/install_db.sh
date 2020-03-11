#!/bin/bash

# On set une variable qui dit qu'on est en mode .sh
export INSTALL_ENV="sh"

currentdir=${PWD##*/}
parentdir="$(dirname "$(pwd)")"
export APP_DIR=$parentdir

if [ $currentdir != "install" ]
then
    echo "Please run the script from the install directory"
    exit
fi

cd ../
# Make sure root cannot run our script
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

set -e

# A factoriser
####################
# PARTIE VARIABLES #
####################
  
# export POSTGRES_HOST=$db_host
# export POSTGRES_PORT=$db_port
# export POSTGRES_USER=$user_pg
# export POSTGRES_PASSWORD=$user_pg_pass
# export POSTGRES_DB=$db_name
# export POSTGRES_LOCALE=$my_local
# export NOMENCLATURE_LANGUAGE=$default_language
# export LOCAL_SRID=$srid_local
# read -p 'Add UsersHub sample data [true] or [false]: ' ADD_USERSHUB_SAMPLE_DATA
# export ADD_USERSHUB_SAMPLE_DATA=$ADD_USERSHUB_SAMPLE_DATA
# read -p 'Populate ref_geo with french municipalities [true] or [false]: ' REFGEO_MUNICIPALITY
# export REFGEO_MUNICIPALITY=$REFGEO_MUNICIPALITY
# read -p 'Populate ref_geo with french grids (1*1km, 5*5km, 10*10km) [true] or [false]: ' REFGEO_GRID
# export REFGEO_GRID=$REFGEO_GRID
# read -p 'Populate ref_geo with french dem (mnt with 250 m grid) [true] or [false]: ' REFGEO_DEM
# export REFGEO_DEM=$REFGEO_DEM
# read -p 'Vectorize dem (improve performance but take time) [true] or [false]: ' REFGEO_VECTORISE_DEM
# export REFGEO_VECTORISE_DEM=$REFGEO_VECTORISE_DEM
# read -p 'Add geonature sample data [true] or [false]: ' SAMPLE_DATA
# export SAMPLE_DATA=$SAMPLE_DATA

if [ $INSTALL_ENV = "sh" ]
then
    . install_db_functions.sh
    CONFIG_FILE=config/settings.ini
    if [ -f "$CONFIG_FILE" ]
    then
        #read settings and set envvar
        source "$CONFIG_FILE"
        export $(grep -v "^#" "$CONFIG_FILE" | cut -d= -f1)
        #TODO afficher les valeurs de settings et demander si on continue avec ça

    else
        echo "config/settings.ini file doesn't exist. Create and populate it before continue."
        exit 1
    fi

elif [ $INSTALL_ENV = "deb" ]
then
    function get_var () {
        db_get geonature-db/POSTGRES_PORT
        export POSTGRES_PORT="$RET"
        db_get geonature-db/POSTGRES_USER
        export POSTGRES_USER="$RET"
        db_get geonature-db/POSTGRES_PASSWORD
        export POSTGRES_PASSWORD="$RET"
        export POSTGRES_HOST="localhost"
        db_get geonature-db/POSTGRES_DB
        export POSTGRES_DB="$RET"
        db_get geonature-db/POSTGRES_LOCALE
        export POSTGRES_LOCALE="$RET"
        db_get geonature-db/NOMENCLATURE_LANGUAGE
        export NOMENCLATURE_LANGUAGE="$RET"
        db_get geonature-db/LOCAL_SRID
        export LOCAL_SRID="$RET"
        db_get geonature-db/ADD_USERSHUB_SAMPLE_DATA
        export ADD_USERSHUB_SAMPLE_DATA="$RET"
        db_get geonature-db/REFGEO_MUNICIPALITY
        export REFGEO_MUNICIPALITY="$RET"
        db_get geonature-db/REFGEO_GRID
        export REFGEO_GRID="$RET"
        db_get geonature-db/REFGEO_DEM
        export REFGEO_DEM="$RET"
        db_get geonature-db/REFGEO_VECTORISE_DEM
        export REFGEO_VECTORISE_DEM="$RET"
        db_get geonature-db/SAMPLE_DATA
        export SAMPLE_DATA="$RET"
    }

    function generate_config () {
        # Generate config files
        get_var
        echo "Generate configuration" >&2
        CONF_DIR=/etc/geonature
        for f in "geonature-db.conf"; do
            envsubst <$CONF_DIR/$f.init >$CONF_DIR/$f
        done
    }

    . /usr/share/debconf/confmodule
    . /usr/share/geonature/geonature-db/install_db_functions.sh

    # Environnement settings
    export SCRIPT_PATH=/usr/share/geonature/geonature-db/sql
    export LOG_PATH=/var/log/geonature/geonature-db

    # PG settings
    if [ -f /usr/share/debconf/confmodule ]; then
        db_version 2.0
        db_input high geonature-db/POSTGRES_PORT || true
        db_input high geonature-db/POSTGRES_USER || true
        db_input high geonature-db/POSTGRES_PASSWORD || true
        db_go
    fi
    get_var

else
    echo "Pas d'environnement d'installation identifié"
    exit 1
fi

prepare_path

if database_exists ${POSTGRES_DB}
then
    echo "Database exists we don't have to drop it. Choise migrate, drop it manualy or change database name."
fi

if ! database_exists ${POSTGRES_DB}
then
    create_database
fi

# Suppression des fichiers : on ne conserve que les fichiers compressés
echo "Cleaning files..."
rm tmp/geonature/*.sql
rm tmp/usershub/*.sql
rm tmp/taxhub/*.txt
rm tmp/taxhub/*.sql
rm tmp/taxhub/*.csv
rm tmp/habref/*.csv
rm tmp/habref/*.pdf
rm tmp/habref/*.sql
rm tmp/nomenclatures/*.sql
