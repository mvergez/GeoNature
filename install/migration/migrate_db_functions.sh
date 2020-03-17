#! /bin/bash
source "$GN_PARENT_DIR/install/install_functions.sh"

# param : schema.table
function table_exists() {
    pg_query "SELECT to_regclass('"$1"');"
}

function get_latest_migration_number() {
    pg_query "SELECT max(migration_number) FROM gn_commons.t_migrations WHERE install_date IS NOT NULL;"
}

function set_database_current_version () {
    latest_migration_number=$(get_latest_migration_number | xargs)
    latest_migration_number=${latest_migration_number:-0}
    export CURRENT_DATABASE_VERSION=$latest_migration_number
}

function get_migration_scripts_to_apply() {
    set_database_current_version
    ls "$GN_MIGRATION_SCRIPTS_DIR"/update_to_*.sql -1 | gawk 'match($0, /update_to_([A-Z]{2})_([0-9]+)/, a) {print a[2], $0}' | sort | cut -d" " -f2 | tail -n +$((CURRENT_DATABASE_VERSION+1))
}

function apply_migrations() {
    export PGPASSWORD="$GN_POSTGRES_PASSWORD";
    # Prepare SQL file with all update files to apply
    echo "--MIGRATION--" > tmp_migrate.sql
    (echo "BEGIN;"; get_migration_scripts_to_apply | xargs cat) >> tmp_migrate.sql; echo "COMMIT;" >> tmp_migrate.sql
    
    # Prepare log file
    echo "------------------" > $GN_LOG_DIR/migrate.log
    set_database_current_version
    echo "Numéro de version de la base avant migration = $CURRENT_DATABASE_VERSION"  >> $GN_LOG_DIR/migrate.log
    echo "" >> $GN_LOG_DIR/migrate.log
    echo "Numéro de version de la base avant migration = $CURRENT_DATABASE_VERSION" 
    
    # Execute prepared sql and redirect psql message both to console and log file
    exec 3>&1 1>>$GN_LOG_DIR/migrate.log 2>&1 ; 
    psql -a -e -b -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -v ON_ERROR_STOP=1 -f tmp_migrate.sql |& tee /dev/fd/3
    # Get psql commande status
    test=${PIPESTATUS[0]}

    # Redirect all only to console
    exec 1>&3; exec 2>&3 

    # Test psql commande status
    if [ $test = 0 ];then
        printf "${START_GREEN}Success ! Database is up to date.${NC}\n"
    else
        echo "ROLLBACK;"  >> $GN_LOG_DIR/migrate.log
        echo "ROLLBACK"
        printf "${START_RED}Houps a error occured (see above).\nFor Detail, have a look to the log file here : '$GN_LOG_DIR/migrate.log'.\nYou have to execute update file(s) manualy and one by one.${NC}\n"
        echo "Nothing has changed."
    fi

    # Set log after migration
    echo "" >> $GN_LOG_DIR/migrate.log
    echo "------------------" >> $GN_LOG_DIR/migrate.log
    set_database_current_version
    echo "Numéro de version de la base après migration = $CURRENT_DATABASE_VERSION"  >> $GN_LOG_DIR/migrate.log
    echo "Numéro de version de la base après migration = $CURRENT_DATABASE_VERSION"

    # Cleanning
    rm tmp_migrate.sql
}

# function apply_missing_migrations_test() {
#     latest_migration_number=1
#     # latest_migration_number=$(get_latest_migration_number | xargs)
#     latest_migration_number=${latest_migration_number:-1}
#     # echo $latest_migration_number
#     # sqlfiles=$(ls "$GN_MIGRATION_SCRIPTS_DIR"/update_to_*.sql -1)
#     # echo $sqlfiles
#     echo "------------------" > $GN_LOG_DIR/migrate.log
#     for sqlfile in $(ls "$GN_MIGRATION_SCRIPTS_DIR"/update_to_*.sql -1 | gawk 'match($0, /update_to_([A-Z]{2})_([0-9]+)/, a) {print a[2], $0}' | sort | cut -d" " -f2 | tail -n +$((latest_migration_number+1))); do
#         globaltest=1
#         psql -a -e -b -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -c "BEGIN;" &>> $GN_LOG_DIR/migrate.log
#         echo 'BEGIN'
#         echo 'BEGIN;' &>> $GN_LOG_DIR/migrate.log
#         psql -a -e -b -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -1 -v ON_ERROR_STOP=1 -f $sqlfile |& tee $GN_LOG_DIR/migrate.log | grep 'ERREUR'; test=${PIPESTATUS[0]}
#         if [ $test -eq 0 ];then
#             echo "$sqlfile : ok !"
#             globaltest=0
#         else
#             printf "${START_RED}A error occured in '$sqlfile'.\nSee log file : '$GN_LOG_DIR/migrate.log'.\nYou have to execute update file(s) manualy and one by one.${NC}\n"
#             globaltest=1
#             break
#         fi
#         psql -a -e -b -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -c "ROLLBACK;" &>> $GN_LOG_DIR/migrate.log
#         echo 'ROLLBACK'
#     done
#     echo "globaltest : $globaltest"
#     if [ $globaltest -eq 0 ];then
#         psql -a -e -b -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -c "COMMIT;"  &>> $GN_LOG_DIR/migrate.log
#         echo "On est bon, on peut lancer l'execution"
#     else
#         psql -a -e -b -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -c "ROLLBACK;" &>> $GN_LOG_DIR/migrate.log
#         echo "Pas bon, dit que c'est annulé"
#     fi
# }
