#!/bin/bash

keepdb="true"

function finish {
  if [ $keepdb = "false" ] 
  then
    drop_database
    echo "fuck it's failed !"
  fi
}

trap finish EXIT

function prepare_path (){
    mkdir -p /tmp/geonature
    mkdir -p /tmp/taxhub
    mkdir -p /tmp/nomenclatures
    mkdir -p /tmp/usershub
    mkdir -p /tmp/habref
    mkdir -p "$GN_LOG_DIR"
}

function get_sql () {
    if [ $INSTALL_ENV = "deb" ]
    then
        # TODO : organiser les scripts avec la même arborescence que pour l'usage du sh
    else
        # TODO : 
            # exporter dans des variables globales les releases UH, TH, nomenclatures ()
            # wget les scripts depuis les dépots github et les placer derrière une arborescence identique à celle du .deb
        wget https://raw.githubusercontent.com/PnEcrins/UsersHub/$USERSHUB_RELEASE/data/usershub.sql -P $GN_SQL_SCRIPTS_DIR/imported/utilisateurs
        wget https://raw.githubusercontent.com/PnEcrins/UsersHub/$USERSHUB_RELEASE/data/usershub-data.sql -P $GN_SQL_SCRIPTS_DIR/imported/utilisateurs
        wget https://raw.githubusercontent.com/PnEcrins/UsersHub/$USERSHUB_RELEASE/data/usershub-dataset.sql -P $GN_SQL_SCRIPTS_DIR/imported/utilisateurs
        wget https://raw.githubusercontent.com/PnX-SI/TaxHub/$TAXHUB_RELEASE/data/adds_for_usershub.sql -P $GN_SQL_SCRIPTS_DIR/imported/utilisateurs
    fi
    # revoir la fonction prepare_path ci-dessus en conséquence si besoin
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

function database_exists () {
    # /!\ Will return false if psql can't list database. Edit your pg_hba.conf
    # as appropriate.
    if [[ -z $1 ]]
    then
        # Argument is null
        return 0
    else
        # Grep db name in the list of database
        su postgres -c "psql -tAl | grep -q \"^$1|\""
        return $?
    fi
}

function write_log() {
    echo $1
    echo "" &>> $GN_LOG_DIR/install_db.log
    echo "" &>> $GN_LOG_DIR/install_db.log
    echo "--------------------" &>> $GN_LOG_DIR/install_db.log
    echo $1 &>> $GN_LOG_DIR/install_db.log
    echo "--------------------" &>> $GN_LOG_DIR/install_db.log
}

function create_role() {
    echo "Création de l'utilisateur '$GN_POSTGRES_USER' ..."
    su postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE ROLE $GN_POSTGRES_USER WITH LOGIN PASSWORD '$GN_POSTGRES_PASSWORD';\""
    return $?
}

function create_database () {
    keepdb="false"
    prepare_path
    echo "--------------------" &> $GN_LOG_DIR/install_db.log
    write_log "Creating GeoNature database..."
    su postgres -c "createdb -O $GN_POSTGRES_USER $GN_POSTGRES_DB -T template0 -E UTF-8 -l $GN_POSTGRES_LOCALE"
    write_log "Adding PostGIS and other use PostgreSQL extensions"
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c 'CREATE EXTENSION IF NOT EXISTS postgis;'" &>> $GN_LOG_DIR/install_db.log
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c 'CREATE EXTENSION IF NOT EXISTS hstore;'" &>> $GN_LOG_DIR/install_db.log
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c 'CREATE EXTENSION IF NOT EXISTS pg_trgm;'" &>> $GN_LOG_DIR/install_db.log
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c 'CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";'" &>> $GN_LOG_DIR/install_db.log
    
    # Mise en place de la structure de la base et des données permettant son fonctionnement avec l'application
    echo "GRANT..."
    cp $GN_SQL_SCRIPTS_DIR/grant.sql /tmp/geonature/grant.sql
    sed -i "s/MYPGUSER/$GN_POSTGRES_USER/g" /tmp/geonature/grant.sql
    write_log 'GRANT'
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -f /tmp/geonature/grant.sql" &>> $GN_LOG_DIR/install_db.log
    
    #Public functions
    write_log "Creating 'public' functions..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/public.sql  &>> $GN_LOG_DIR/install_db.log
    
    # Users schema (utilisateurs)
    write_log "Getting and creating USERS schema (utilisateurs)..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/imported/utilisateurs/usershub.sql &>> $GN_LOG_DIR/install_db.log
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/imported/utilisateurs/usershub-data.sql &>> $GN_LOG_DIR/install_db.log
    if [[ $GN_ADD_USERSHUB_SAMPLE_DATA = "true" ]]
    then
        write_log "Insertion of data for usershub..."
        # insert geonature data for usershub
        export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/imported/utilisateurs/usershub-dataset.sql &>> $GN_LOG_DIR/install_db.log
        # insert taxhub data for usershub
        export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/imported/utilisateurs/adds_for_usershub.sql &>> $GN_LOG_DIR/install_db.log
    fi

    # Taxonomie schema
    echo "Download and extract taxref file..."
    cp  $GN_SQL_SCRIPTS_DIR/taxonomie/inpn/data_inpn_taxhub.sql /tmp/taxhub/data_inpn_taxhub.sql
    array=( TAXREF_INPN_v11.zip ESPECES_REGLEMENTEES_v11.zip LR_FRANCE_20160000.zip )
    for i in "${array[@]}"
    do
      if [ ! -f "tmp/taxhub/$i" ]
      then
          wget http://geonature.fr/data/inpn/taxonomie/$i -P /tmp/taxhub
      else
          echo "$i exists"
      fi
      unzip -o /tmp/taxhub/$i -d /tmp/taxhub
    done
    echo "Getting 'taxonomie' schema creation scripts..."
    cp $GN_SQL_SCRIPTS_DIR/taxonomie/taxhubdb.sql /tmp/taxhub
    cp $GN_SQL_SCRIPTS_DIR/taxonomie/taxhubdata.sql /tmp/taxhub
    cp $GN_SQL_SCRIPTS_DIR/taxonomie/taxhubdata_atlas.sql /tmp/taxhub
    cp $GN_SQL_SCRIPTS_DIR/taxonomie/materialized_views.sql /tmp/taxhub
    write_log "Creating 'taxonomie' schema..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/taxhub/taxhubdb.sql  &>> $GN_LOG_DIR/install_db.log
    write_log "Inserting INPN taxonomic data... (This may take a few minutes)"
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -f /tmp/taxhub/data_inpn_taxhub.sql" &>> $GN_LOG_DIR/install_db.log
    write_log "Creating dictionaries data for taxonomic schema..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/taxhub/taxhubdata.sql  &>> $GN_LOG_DIR/install_db.log
    write_log "Inserting sample dataset  - atlas attributes...."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/taxhub/taxhubdata_atlas.sql  &>> $GN_LOG_DIR/install_db.log
    write_log "Creating a view that represent the taxonomic hierarchy..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/taxhub/materialized_views.sql  &>> $GN_LOG_DIR/install_db.log   

    # Habref schema
    echo "Download and extract habref file..."
    if [ ! -f '/tmp/habref/HABREF_50.zip' ]
    then
      wget https://geonature.fr/data/inpn/habitats/HABREF_50.zip -P /tmp/habref
    else
      echo HABREF_50.zip exists
    fi
    unzip -o /tmp/habref/HABREF_50.zip -d /tmp/habref
    cp $GN_SQL_SCRIPTS_DIR/occhab/habref.sql -P /tmp/habref
    cp $GN_SQL_SCRIPTS_DIR/occhab/data_inpn_habref.sql -P /tmp/habref 
    write_log "Creating 'habitat' schema..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/habref/habref.sql &>> $GN_LOG_DIR/install_db.log
    write_log "Inserting INPN habitat data..."
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB  -f /tmp/habref/data_inpn_habref.sql" &>> $GN_LOG_DIR/install_db.log

    # Nomenclatures schema
    echo "Getting 'nomenclature' schema creation scripts..."
    cp $GN_SQL_SCRIPTS_DIR/nomenclatures/nomenclatures.sql /tmp/nomenclatures
    cp $GN_SQL_SCRIPTS_DIR/nomenclatures/data_nomenclatures.sql /tmp/nomenclatures
    cp $GN_SQL_SCRIPTS_DIR/nomenclatures/nomenclatures_taxonomie.sql /tmp/nomenclatures
    cp $GN_SQL_SCRIPTS_DIR/nomenclatures/data_nomenclatures_taxonomie.sql /tmp/nomenclatures
    write_log "Creating 'nomenclatures' schema"
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/nomenclatures/nomenclatures.sql  &>> $GN_LOG_DIR/install_db.log
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/nomenclatures/nomenclatures_taxonomie.sql  &>> $GN_LOG_DIR/install_db.log
    write_log "Inserting 'nomenclatures' data..."
    sed -i "s/MYDEFAULTLANGUAGE/$NOMENCLATURE_LANGUAGE/g" /tmp/nomenclatures/data_nomenclatures.sql
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/nomenclatures/data_nomenclatures.sql  &>> $GN_LOG_DIR/install_db.log
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/nomenclatures/data_nomenclatures_taxonomie.sql  &>> $GN_LOG_DIR/install_db.log

    # Commons schema
    write_log "Creating 'commons' schema..."
    cp $GN_SQL_SCRIPTS_DIR/core/commons.sql /tmp/geonature/commons.sql
    sed -i "s/MYLOCALSRID/$LOCAL_SRID/g" /tmp/geonature/commons.sql
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/geonature/commons.sql  &>> $GN_LOG_DIR/install_db.log
    
    # Meta schema
    write_log "Creating 'meta' schema..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/meta.sql  &>> $GN_LOG_DIR/install_db.log

    # Ref_geo schema
    write_log "Creating 'ref_geo' schema..."
    cp $GN_SQL_SCRIPTS_DIR/core/ref_geo.sql /tmp/geonature/ref_geo.sql
    sed -i "s/MYLOCALSRID/$LOCAL_SRID/g" /tmp/geonature/ref_geo.sql
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/geonature/ref_geo.sql  &>> $GN_LOG_DIR/install_db.log
    if [ $GN_REFGEO_MUNICIPALITY = "true" ];
    then
        write_log "Insert default French municipalities (IGN admin-express)"
        if [ ! -f '/tmp/geonature/communes_fr_admin_express_2019-01.zip' ]
        then
            wget  --cache=off http://geonature.fr/data/ign/communes_fr_admin_express_2019-01.zip -P /tmp/geonature
        else
            echo "/tmp/geonature/communes_fr_admin_express_2019-01.zip already exist"
        fi
        unzip -o /tmp/geonature/communes_fr_admin_express_2019-01.zip -d /tmp/geonature
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -f /tmp/geonature/fr_municipalities.sql" &>> $GN_LOG_DIR/install_db.log
        write_log "Restore $GN_POSTGRES_USER owner"
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"ALTER TABLE ref_geo.temp_fr_municipalities OWNER TO $GN_POSTGRES_USER;\"" &>> $GN_LOG_DIR/install_db.log
        write_log "Insert data in l_areas and li_municipalities tables"
        export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/ref_geo_municipalities.sql  &>> $GN_LOG_DIR/install_db.log
        write_log "Drop french municipalities temp table"
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"DROP TABLE ref_geo.temp_fr_municipalities;\"" &>> $GN_LOG_DIR/install_db.log
    fi
    if [ $GN_REFGEO_GRID = "true" ];
    then
        write_log "Insert INPN grids"
        if [ ! -f '/tmp/geonature/inpn_grids.zip' ]
        then
            wget  --cache=off https://geonature.fr/data/inpn/layers/2019/inpn_grids.zip -P /tmp/geonature
        else
            echo "/tmp/geonature/inpn_grids.zip already exist"
        fi
        unzip -o /tmp/geonature/inpn_grids.zip -d /tmp/geonature
        write_log "Insert grid layers... (This may take a few minutes)"
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -f /tmp/geonature/inpn_grids.sql" &>> $GN_LOG_DIR/install_db.log
        write_log "Restore $GN_POSTGRES_USER owner"
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"ALTER TABLE ref_geo.temp_grids_1 OWNER TO $GN_POSTGRES_USER;\"" &>> $GN_LOG_DIR/install_db.log
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"ALTER TABLE ref_geo.temp_grids_5 OWNER TO $GN_POSTGRES_USER;\"" &>> $GN_LOG_DIR/install_db.log
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"ALTER TABLE ref_geo.temp_grids_10 OWNER TO $GN_POSTGRES_USER;\"" &>> $GN_LOG_DIR/install_db.log
        write_log "Insert data in l_areas and li_grids tables"
        export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/ref_geo_grids.sql  &>> $GN_LOG_DIR/install_db.log
    fi
    if  [ $GN_REFGEO_DEM = "true" ];
    then
        write_log "Insert default French DEM (IGN 250m BD alti)"
        if [ ! -f '/tmp/geonature/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip' ]
        then
            wget --cache=off http://geonature.fr/data/ign/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip -P /tmp/geonature
        else
            echo "/tmp/geonature/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip already exist"
        fi
	      unzip -o /tmp/geonature/BDALTIV2_2-0_250M_ASC_LAMB93-IGN69_FRANCE_2017-06-21.zip -d /tmp/geonature
        #gdalwarp -t_srs EPSG:$LOCAL_SRID /tmp/geonature/BDALTIV2_250M_FXX_0098_7150_MNT_LAMB93_IGN69.asc /tmp/geonature/dem.tif &>> $GN_LOG_DIR/install_db.log
        export PGPASSWORD=$GN_POSTGRES_PASSWORD;raster2pgsql -s $LOCAL_SRID -c -C -I -M -d -t 5x5 /tmp/geonature/BDALTIV2_250M_FXX_0098_7150_MNT_LAMB93_IGN69.asc ref_geo.dem|psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB  &>> $GN_LOG_DIR/install_db.log
    	#echo "Refresh DEM spatial index. This may take a few minutes..."
        su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"REINDEX INDEX ref_geo.dem_st_convexhull_idx;\"" &>> $GN_LOG_DIR/install_db.log
        if [ $REFGEO_VECTORISE_DEM = "true" ];
        then
            write_log "Vectorisation of DEM raster. This may take a few minutes..."
            su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"INSERT INTO ref_geo.dem_vector (geom, val) SELECT (ST_DumpAsPolygons(rast)).* FROM ref_geo.dem;\"" &>> $GN_LOG_DIR/install_db.log
            write_log "Refresh DEM vector spatial index. This may take a few minutes..."
            su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -c \"REINDEX INDEX ref_geo.index_dem_vector_geom;\"" &>> $GN_LOG_DIR/install_db.log
        fi
    fi

    # Imports schema
    write_log "Creating 'imports' schema..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/imports.sql  &>> $GN_LOG_DIR/install_db.log

    # Synthese schema
    write_log "Creating 'synthese' schema..."
    cp $GN_SQL_SCRIPTS_DIR/core/synthese.sql /tmp/geonature/synthese.sql
    sed -i "s/MYLOCALSRID/$LOCAL_SRID/g" /tmp/geonature/synthese.sql
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/geonature/synthese.sql  &>> $GN_LOG_DIR/install_db.log
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/synthese_default_values.sql  &>> $GN_LOG_DIR/install_db.log
    write_log "Creating commons view depending of synthese"
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/commons_synthese.sql  &>> $GN_LOG_DIR/install_db.log

    # Exports schema
    write_log "Creating 'exports' schema..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/exports.sql  &>> $GN_LOG_DIR/install_db.log

    # Monitoring schema
    write_log "Creating 'monitoring' schema..."
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -v MYLOCALSRID=$LOCAL_SRID -f $GN_SQL_SCRIPTS_DIR/core/monitoring.sql  &>> $GN_LOG_DIR/install_db.log

    # Permissions schema
    write_log "Creating 'permissions' schema"
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/permissions.sql  &>> $GN_LOG_DIR/install_db.log
    write_log "Insert 'permissions' data"
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/permissions_data.sql  &>> $GN_LOG_DIR/install_db.log

    # Sensitivity schema
    export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/sensitivity.sql  &>> $GN_LOG_DIR/install_db.log
    write_log "Insert 'gn_sensitivity' data"
    echo "--------------------"
    if [ ! -f '/tmp/geonature/181201_referentiel_donnes_sensibles.csv' ]
        then
            wget --cache=off https://geonature.fr/data/inpn/sensitivity/181201_referentiel_donnes_sensibles.csv -P /tmp/geonature
        else
            echo "/tmp/geonature/181201_referentiel_donnes_sensibles.csv already exist"
    fi
    cp $GN_SQL_SCRIPTS_DIR/core/sensitivity_data.sql /tmp/geonature/sensitivity_data.sql
    echo "Insert 'gn_sensitivity' data... (This may take a few minutes)"
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $GN_POSTGRES_DB -f /tmp/geonature/sensitivity_data.sql" &>> $GN_LOG_DIR/install_db.log

    #Installation des données exemples
    if [ "$GN_SAMPLE_DATA" = true ];
    then
        write_log "Inserting sample datasets..."
        export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f $GN_SQL_SCRIPTS_DIR/core/meta_data.sql  &>> $GN_LOG_DIR/install_db.log
        write_log "Inserting sample dataset of taxons for taxonomic schema..."
        cp $GN_SQL_SCRIPTS_DIR/taxonomie/taxhubdata_taxons_example.sql /tmp/taxhub
        export PGPASSWORD=$GN_POSTGRES_PASSWORD;psql -v ON_ERROR_STOP=1 -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -f /tmp/taxhub/taxhubdata_taxons_example.sql  &>> $GN_LOG_DIR/install_db.log
    fi

    # TODO : rm tmp sql and csv

    keepdb="true"
}

function drop_database () {
    echo "Suppression de la base..."
    su postgres -c "dropdb $GN_POSTGRES_DB"
    echo "Une erreur d'exécution est survenue, la base à été supprimée"
}
