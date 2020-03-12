#! /bin/bash
source "$GN_PARENT_DIR/install/install_functions.sh"

# param : schema.table
function table_exists() {
    pg_query "SELECT to_regclass('"$1"');"
}

function get_latest_migration_number() {
    pg_query "SELECT max(migration_number) FROM gn_commons.t_migrations WHERE install_date IS NOT NULL;"
}

function get_migration_scripts_to_apply() {
    latest_migration_number=$(get_latest_migration_number | xargs)
    latest_migration_number=${latest_migration_number:-0}

    ls "$GN_MIGRATION_SCRIPTS_DIR"/update_to_*.sql -1 | gawk 'match($0, /update_to_([A-Z]{2})_([0-9]+)/, a) {print a[2], $0}' | sort | cut -d" " -f2 | tail -n +$((latest_migration_number+1))
}

function apply_missing_migrations() {
    export PGPASSWORD="$GN_POSTGRES_PASSWORD";
    get_migration_scripts_to_apply | xargs cat | psql -t -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -1 -v ON_ERROR_STOP=1 -f -  2>&1 | tee >> $GN_LOG_DIR/migrate.log
    return ${PIPESTATUS[0]};
}


  