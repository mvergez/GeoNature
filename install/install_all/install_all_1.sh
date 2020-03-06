#!/bin/bash
set -e
set -x
. install_all.ini
. /etc/os-release
OS_NAME=$ID
OS_VERSION=$VERSION_ID
OS_BITS="$(getconf LONG_BIT)"

# Test the server architecture
if [ !"$OS_BITS" == "64" ]; then
   echo "GeoNature must be installed on a 64-bits operating system ; your is $OS_BITS-bits" 1>&2
   exit 1
fi

# Format my_url to set a / at the end
if [ "${my_url: -1}" != '/' ]
then
my_url=$my_url/
fi

# Remove http:// and remove final / from $my_url to create $my_domain
# No more used actually but can be useful if we want to create a Servername in Apache configuration
my_domain=$(echo $my_url | sed -r 's|^.*\/\/(.*)$|\1|')
my_domain=$(echo $my_domain | sed s'/.$//')

# Check OS and versions
if [ "$OS_NAME" != "debian" ] && [ "$OS_NAME" != "ubuntu" ]
then
    echo -e "\e[91m\e[1mLe script d'installation n'est prévu que pour les distributions Debian et Ubuntu\e[0m" >&2
    exit 1
fi

if [ "$OS_VERSION" != "9" ] && [ "$OS_VERSION" != "10" ] && [ "$OS_VERSION" != "18.04" ] && [ "$OS_VERSION" != "16.04" ]
then
    echo -e "\e[91m\e[1mLe script d'installation n'est prévu que pour Debian 9/10 et Ubuntu 16.04/18.04\e[0m" >&2
    exit 1
fi

# Make sure this script is NOT run as root
if [ "$(id -u)" == "0" ]; then
   echo -e "\e[91m\e[1mThis script should NOT be run as root\e[0m" >&2
   echo -e "\e[91m\e[1mLancez ce script avec l'utilisateur courant : `whoami`\e[0m" >&2
   exit 1
fi


echo "############### Installation des paquets systèmes ###############"


# Updating language locale
sudo apt-get install -y locales
sudo sed -i "s/# $my_local/$my_local/g" /etc/locale.gen
sudo locale-gen $my_local
echo "export LC_ALL=$my_local" >> ~/.bashrc
echo "export LANG=$my_local" >> ~/.bashrc
echo "export LANGUAGE=$my_local" >> ~/.bashrc
source ~/.bashrc
