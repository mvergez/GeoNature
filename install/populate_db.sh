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
            if ! sudo -v; then
                echo "Sudo: Couldn't acquire credentials ..."
            else
                local test_euid
                test_euid="$(sudo -H -- "${BASH}" -c 'printf "%s" "${EUID}"')"
                if [[ ${test_euid} -eq 0 ]]; then
                    superuser=true
                fi
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
#check_superuser

cd backend
source venv/bin/activate
# (kwargs not supported) calling get_app with with_external_mods=False
# We need to create the app to apply the migrations without accessing the not yet created database,
# so disabling external mods which needs to be looked up in the db.
export FLASK_APP="server:get_app(None, None, False)"
flask db upgrade geonature@head \
	-x meta-sample=$add_sample_data \
	-x attribut-example=true \
	-x taxons-example=true \
	-x local-srid=$srid_local \
	-x defaultlanguage=$default_language \
	-x usershub-sample-data=true || exit 1
deactivate
cd ..


if [ "$install_sig_layers" = true ];
then
write_log "Insert default French municipalities (IGN admin-express)"
if [ ! -f 'tmp/geonature/communes_fr_admin_express_2020-02.zip' ]
then
    wget  --cache=off http://geonature.fr/data/ign/communes_fr_admin_express_2020-02.zip -P tmp/geonature
else
    echo "tmp/geonature/communes_fr_admin_express_2020-02.zip already exist"
fi
unzip tmp/geonature/communes_fr_admin_express_2020-02.zip -d tmp/geonature
sudo -n -u postgres -s psql -d $db_name -f tmp/geonature/fr_municipalities.sql &>> var/log/install_db.log
write_log "Restore $user_pg owner"
sudo -n -u postgres -s psql -d $db_name -c "ALTER TABLE ref_geo.temp_fr_municipalities OWNER TO $user_pg;" &>> var/log/install_db.log
write_log "Insert data in l_areas and li_municipalities tables"
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name -f data/core/ref_geo_municipalities.sql  &>> var/log/install_db.log
write_log "Drop French municipalities temp table"
sudo -n -u postgres -s psql -d $db_name -c "DROP TABLE ref_geo.temp_fr_municipalities;" &>> var/log/install_db.log

if [ ! -f 'tmp/geonature/departement_admin_express_2020-02.zip' ]
then
    wget  --cache=off http://geonature.fr/data/ign/departement_admin_express_2020-02.zip -P tmp/geonature
else
    echo "tmp/geonature/departement_admin_express_2020-02.zip already exist"
fi
write_log "Insert departements"
unzip tmp/geonature/departement_admin_express_2020-02.zip -d tmp/geonature

sudo -n -u postgres -s psql -d $db_name -f tmp/geonature/fr_departements.sql &>> var/log/install_db.log
write_log "Restore $user_pg owner"
sudo -n -u postgres -s psql -d $db_name -c "ALTER TABLE ref_geo.temp_fr_departements OWNER TO $user_pg;" &>> var/log/install_db.log
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name -f data/core/ref_geo_departements.sql &>> var/log/install_db.log
write_log "Drop french departements temp table"
sudo -n -u postgres -s psql -d $db_name -c "DROP TABLE ref_geo.temp_fr_departements;" &>> var/log/install_db.log
fi

if [ "$install_grid_layer" = true ];
then
write_log "Insert INPN grids"
if [ ! -f 'tmp/geonature/inpn_grids.zip' ]
then
    wget  --cache=off https://geonature.fr/data/inpn/layers/2020/inpn_grids.zip -P tmp/geonature
else
    echo "tmp/geonature/inpn_grids.zip already exist"
fi
unzip tmp/geonature/inpn_grids.zip -d tmp/geonature
write_log "Insert grid layers... (This may takes a few minutes)"
sudo -n -u postgres -s psql -d $db_name -f tmp/geonature/inpn_grids.sql &>> var/log/install_db.log
write_log "Restore $user_pg owner"
sudo -n -u postgres -s psql -d $db_name -c "ALTER TABLE ref_geo.temp_grids_1 OWNER TO $user_pg;" &>> var/log/install_db.log
sudo -n -u postgres -s psql -d $db_name -c "ALTER TABLE ref_geo.temp_grids_5 OWNER TO $user_pg;" &>> var/log/install_db.log
sudo -n -u postgres -s psql -d $db_name -c "ALTER TABLE ref_geo.temp_grids_10 OWNER TO $user_pg;" &>> var/log/install_db.log
write_log "Insert data in l_areas and li_grids tables"
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name -f data/core/ref_geo_grids.sql  &>> var/log/install_db.log
fi

if  [ "$install_default_dem" = true ];
then
write_log "Insert default French DEM (IGN 250m BD alti). (This may takes a few minutes)"
if [ ! -f 'tmp/geonature/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip' ]
then
    wget --cache=off http://geonature.fr/data/ign/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip -P tmp/geonature
else
    echo "tmp/geonature/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip already exist"
fi
      unzip tmp/geonature/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip -d tmp/geonature
#gdalwarp -t_srs EPSG:$srid_local tmp/geonature/BDALTIV2_250M_FXX_0098_7150_MNT_LAMB93_IGN69.asc tmp/geonature/dem.tif &>> var/log/install_db.log
export PGPASSWORD=$user_pg_pass;raster2pgsql -s $srid_local -c -C -I -M -d -t 5x5 tmp/geonature/BDALTIV2_250M_FXX_0098_7150_MNT_LAMB93_IGN69.asc ref_geo.dem|psql -h $db_host -U $user_pg -d $db_name  &>> var/log/install_db.log
#echo "Refresh DEM spatial index. This may take a few minutes..."
sudo -n -u postgres -s psql -d $db_name -c "REINDEX INDEX ref_geo.dem_st_convexhull_idx;" &>> var/log/install_db.log
if [ "$vectorise_dem" = true ];
then
    write_log "Vectorisation of DEM raster. This may take a few minutes..."
    sudo -n -u postgres -s psql -d $db_name -c "INSERT INTO ref_geo.dem_vector (geom, val) SELECT (ST_DumpAsPolygons(rast)).* FROM ref_geo.dem;" &>> var/log/install_db.log

    write_log "Refresh DEM vector spatial index. This may take a few minutes..."
    sudo -n -u postgres -s psql -d $db_name -c "REINDEX INDEX ref_geo.index_dem_vector_geom;" &>> var/log/install_db.log
fi
fi

# TODO: put this in alembic migration
write_log "Insert 'gn_sensitivity' data"
echo "--------------------"
if [ ! -f 'tmp/geonature/referentiel_donnees_sensibles_v13.csv' ]
then
    wget --cache=off https://geonature.fr/data/inpn/sensitivity/referentiel_donnees_sensibles_v13.csv -P tmp/geonature/
    mv tmp/geonature/referentiel_donnees_sensibles_v13.csv tmp/geonature/referentiel_donnees_sensibles.csv
else
    echo "tmp/geonature/referentiel_donnees_sensibles.csv already exist"
fi
cp data/core/sensitivity_data.sql tmp/geonature/sensitivity_data.sql
sed -i 's#'/tmp/geonature'#'$parentdir/tmp/geonature'#g' tmp/geonature/sensitivity_data.sql
echo "Insert 'gn_sensitivity' data... (This may take a few minutes)"
sudo -n -u postgres -s psql -d $db_name -f tmp/geonature/sensitivity_data.sql &>> var/log/install_db.log


if [ "$install_default_dem" = true ];
then
sudo rm tmp/geonature/BDALTIV2_250M_FXX_0098_7150_MNT_LAMB93_IGN69.asc
sudo rm tmp/geonature/IGNF_BDALTIr_2-0_ASC_250M_LAMB93_IGN69_FRANCE.html
fi

# Suppression des fichiers : on ne conserve que les fichiers compressés
echo "Cleaning files..."
rm -f tmp/geonature/*.sql
