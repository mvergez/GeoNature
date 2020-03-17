
START_RED="\033[0;31m"
START_ORANGE="\033[0;33m"
START_GREEN="\033[0;32m"
NC="\033[0m"

function get_path_to_script(){
    source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do # resolve $source until the file is no longer a symlink
        dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source" # if $source was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    echo $source
}


# Generate a few default paths
ROOT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
TEST_DIR="${ROOT_DIR}/integration_tests"
CONFIG_FILE="${ROOT_DIR}/settings.ini"


function generate_config () {
    # Generate config files
    get_var
    echo "Generate configuration" >&2
    CONF_DIR=/etc/geonature
    for f in "geonature-db.conf"; do
        envsubst <$CONF_DIR/$f.init >$CONF_DIR/$f
    done
}

get_config () {
    #read settings and set envvar
    source "$1"
    export $(grep -v "^#" "$1" | cut -d= -f1)
    #TODO afficher les valeurs de settings et demander si on continue avec ça
}

prompt_yes_no(){
    while true; do
        read -p "$1 [Y/N]" yn
        case $yn in
            [Yy]* ) echo "true"; break;;
            [Nn]* ) echo "false"; break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

function pg_query(){
    export PGPASSWORD=$GN_POSTGRES_PASSWORD
    psql -t -h $GN_POSTGRES_HOST -U $GN_POSTGRES_USER -d $GN_POSTGRES_DB -c "$1"
}
