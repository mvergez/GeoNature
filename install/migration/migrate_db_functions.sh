#! /bin/bash
source "$GN_PARENT_DIR/install/install_functions.sh"

# Test if a table exists in database or not
# param : schema.table
# return : table name if exists or null if not
function table_exists() {
    pg_query "SELECT to_regclass('"$1"');"
}

function request_current_database_version_number() {
    pg_query "SELECT max(migration_number) FROM gn_commons.t_migrations WHERE install_date IS NOT NULL;"
}

function get_database_current_version () {
    database_current_version=$(request_current_database_version_number | xargs)
    database_current_version=${database_current_version:-0}
    export CURRENT_DATABASE_VERSION=$database_current_version
}

function get_migration_scripts_to_apply() {
    get_database_current_version
    ls "$GN_MIGRATION_SCRIPTS_DIR"/update_to_*.sql -1 | gawk 'match($0, /update_to_([A-Z]{2})_([0-9]+)/, a) {print a[2], $0}' | sort -n | cut -d" " -f2 | tail -n +$((CURRENT_DATABASE_VERSION+1))
}

function get_target_version_number() {
    ls /home/gil/geonature2/data/migrations/update_to_*.sql -1 | gawk 'match($0, /update_to_([A-Z]{2})_([0-9]+)/, a) {print a[2], $0}' | sort -n | cut -d" " -f2 | tail -n 1 | cut -d _ -f4 |cut -d . -f1
}

function apply_migrations() {
    # First test if database support this script
    if [ -n $(table_exists gn_commons.t_migration) ];then
        printf "${START_RED}FATAL : Gloups ! Your database isn't ready to migrate with this script.\n"
        printf "You have migrate manualy. See the release note.${NC}\n"
        exit 1
    fi

    # Compare current and target database versions
    get_database_current_version
    target_version=$(get_target_version_number)
    echo "Current database version : $CURRENT_DATABASE_VERSION"
    echo "Target database version : $target_version"
    if (( "$target_version" == "$CURRENT_DATABASE_VERSION" ));then
        printf "${START_ORANGE}NOTICE : Database is already up to date. Nothing to do.${NC}\n"
        exit 0
    fi
    
    export PGPASSWORD="$GN_POSTGRES_PASSWORD";
    # Prepare SQL file with all update files to apply
    echo "--MIGRATION--" > tmp_migrate.sql
    (echo "BEGIN;"; get_migration_scripts_to_apply | xargs cat) >> tmp_migrate.sql; echo "COMMIT;" >> tmp_migrate.sql
    
    # Prepare log file
    echo "------------------" > $GN_LOG_DIR/migrate.log
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
        echo "ROLLBACK;"  >> $GN_LOG_DIR/migrate.log # fictif pour clarifier les logs. Le rollback est fait par psql si erreur (à vérifier)
        echo "ROLLBACK"
        printf "${START_RED}Houps a error occured (see above).\nFor Detail, have a look to the log file here : '$GN_LOG_DIR/migrate.log'.\nYou have to execute update file(s) manualy and one by one.${NC}\n"
        echo "Nothing has changed."
    fi

    # Set log after migration
    echo "" >> $GN_LOG_DIR/migrate.log
    echo "------------------" >> $GN_LOG_DIR/migrate.log
    get_database_current_version
    echo "Numéro de version de la base après migration = $CURRENT_DATABASE_VERSION"  >> $GN_LOG_DIR/migrate.log
    echo "Numéro de version de la base après migration = $CURRENT_DATABASE_VERSION"

    # Cleanning
    rm tmp_migrate.sql
}
