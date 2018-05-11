#!/bin/bash


# #############################################################################
# Settings
#
certificatePrefix="nginx-proxy-app.com"
hostsFile=/etc/hosts
hostsIP="127.0.0.1"

BLUE="\033[00;94m"
GREEN="\033[00;92m"
RED="\033[00;31m"
RESTORE="\033[0m"
YELLOW="\033[00;93m"
ROOT_DIR=$(pwd)


# #############################################################################
# Kills all running containers of an image
#
clean() {

    echo -e "${GREEN}"
    echo -e "++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "+ Cleaning docker images                        "
    echo -e "++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "${RESTORE}"

    if [[ -z $ENVIRONMENT ]]; then
        ENVIRONMENT="development"
    fi

    composeFileName="docker-compose.yml"
    if [[ $ENVIRONMENT != "" ]]; then
        composeFileName="docker-compose.$ENVIRONMENT.yml"
    fi

    if [[ ! -f $composeFileName ]]; then
        echo -e "${RED}Environment '$ENVIRONMENT' is not a valid parameter. File '$composeFileName' does not exist. ${RESTORE}\n"
    else
        docker-compose -f $composeFileName down --rmi all

        # Remove any dangling images (from previous builds)
        danglingImages=$(docker images -q --filter 'dangling=true')
        if [[ ! -z $danglingImages ]]; then
        docker rmi -f $danglingImages
        fi

        rtn=$?
        if [ "$rtn" != "0" ]; then
            echo -e "${RED}An error occurred${RESTORE}"
            exit $rtn
        fi

        echo -en "${YELLOW}Removed docker images${RESTORE}\n"
    fi
}


# #############################################################################
# Runs docker-compose
#
compose () {

    echo -e "${GREEN}"
    echo -e "++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "+ Composing docker images                       "
    echo -e "++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "${RESTORE}"

    if [[ -z $ENVIRONMENT ]]; then
        ENVIRONMENT="development"
    fi

    composeFileName="docker-compose.yml"
    if [[ $ENVIRONMENT != "development" ]]; then
        composeFileName="docker-compose.$ENVIRONMENT.yml"
    fi

    if [[ ! -f $composeFileName ]]; then
        echo -e "${RED}Environment '$ENVIRONMENT' is not a valid parameter. File '$composeFileName' does not exist. ${RESTORE}\n"
    else

        echo -e "${YELLOW}Building the image...${RESTORE}\n"
        docker-compose -f $composeFileName build

        echo -e "${YELLOW}Creating the container...${RESTORE}\n"
        docker-compose -f $composeFileName kill
        docker-compose -f $composeFileName up -d

    fi

    rtn=$?
    if [ "$rtn" != "0" ]; then
        echo -e "${RED}An error occurred${RESTORE}"
        exit $rtn
    fi
}


# #############################################################################
# Setup Nginx.
#
setupNginx () {

    echo -e "${GREEN}"
    echo -e "++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "+ Setting up service                            "
    echo -e "++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "${RESTORE}"


    # remove existing certificates
    echo -e "${YELLOW} Removing existings certificates... ${RESTORE}"
    sudo security delete-certificate -c edutacity.com /Library/Keychains/System.keychain

    # generate key
    openssl \
        genrsa \
        -out certs/$certificatePrefix.key \
        4096

    # generate csr request
    openssl \
        req \
        -new \
        -sha256 \
        -out certs/$certificatePrefix.csr \
        -key certs/$certificatePrefix.key \
        -config openssl-san.conf

    #generate certIficate from csr request
    openssl \
        x509 \
        -req \
        -days 3650 \
        -in certs/$certificatePrefix.csr \
        -signkey certs/$certificatePrefix.key \
        -out certs/$certificatePrefix.crt \
        -extensions req_ext \
        -extfile openssl-san.conf

    # generate pem
    cat certs/$certificatePrefix.crt certs/$certificatePrefix.key > certs/$certificatePrefix.pem

    # install certIficate
    if [ -f certs/$certificatePrefix.crt ]; then
        echo -e "${YELLOW} Installing certificate... ${RESTORE}"
        sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain certs/$certificatePrefix.crt
    else
        echo -e "${RED} An error occurred while generating the certificate: certs/$certificatePrefix.crt ${RESTORE}"
    fi

    # openssl req -text -noout -in nginx-proxy-app.com.csr # DEBUG 

    # Write Hosts


}


# #############################################################################
# Removes a hostname
#
function removeHost() {
    if [ -n "$(grep $HOSTNAME /etc/hosts)" ]
    then
        echo "$HOSTNAME Found in your $ETC_HOSTS, Removing now...";
        sudo sed -i".bak" "/$HOSTNAME/d" $ETC_HOSTS
    else
        echo "$HOSTNAME was not found in your $ETC_HOSTS";
    fi
}


# #############################################################################
# Adds a host name
#
# $1 hostname
#
function addHost() {
    HOSTNAME=$1
    HOSTS_LINE="$hostsIP\t$HOSTNAME"
    if [ -n "$(grep $HOSTNAME /etc/hosts)" ]
        then
            echo "$HOSTNAME already exists : $(grep $HOSTNAME $ETC_HOSTS)"
        else
            echo "Adding $HOSTNAME to your $ETC_HOSTS";
            sudo -- sh -c -e "echo '$HOSTS_LINE' >> /etc/hosts";

            if [ -n "$(grep $HOSTNAME /etc/hosts)" ]
                then
                    echo "$HOSTNAME was added succesfully \n $(grep $HOSTNAME /etc/hosts)";
                else
                    echo "Failed to Add $HOSTNAME, Try again!";
            fi
    fi
}


# #############################################################################
# Shows the usage for the script
#
showUsage () {

    echo -e "${YELLOW}"
    echo -e "Usage: project-tasks.sh [COMMAND]"
    echo -e "    Orchestrates various jobs for the project"
    echo -e ""
    echo -e "Commands:"
    echo -e "    clean: Removes the images and kills all containers based on that image."
    echo -e "    compose: Runs docker-compose."
    echo -e "    composeForDebug: Builds the image and runs docker-compose."
    echo -e "    setup: Setup the project (nginx)."
    echo -e ""
    echo -e "Environments:"
    echo -e "    development: Default environment."
    echo -e ""
    echo -e "Example:"
    echo -e "    ./project-tasks.sh compose debug"
    echo -e ""
    echo -e "${RESTORE}"

}


# #############################################################################
# Switch arguments
#
if [ $# -eq 0 ]; then
    showUsage
else
    ENVIRONMENT=$(echo -e $2 | tr "[:upper:]" "[:lower:]")

    case "$1" in
        "clean")
            clean
            ;;
        "compose")
            compose
            ;;
        "composeForDebug")
            export REMOTE_DEBUGGING="enabled"
            compose
            ;;
        "setup")
            setupNginx
            ;;
        *)
            showUsage
            ;;
    esac
fi

# #############################################################################
