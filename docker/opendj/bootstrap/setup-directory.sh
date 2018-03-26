#!/usr/bin/env bash
# Set up a directory server.
#
# Copyright (c) 2016-2018 ForgeRock AS. Use of this source code is subject to the
# Common Development and Distribution License (CDDL) that can be found in the LICENSE file

#set -x

cd /opt/opendj

echo "Setting up $BASE_DN"


INIT_OPTION="--addBaseEntry"

# If NUMBER_SAMPLE_USERS is set AND we are the first node, then generate sample users.
if [[  -n "${NUMBER_SAMPLE_USERS}" && $HOSTNAME = *"0"* ]]; then
    INIT_OPTION="--sampleData ${NUMBER_SAMPLE_USERS}"
fi



# An admin server is also a directory server.
./setup directory-server \
  -p 1389 \
  --enableStartTLS  \
  --adminConnectorPort 4444 \
  --enableStartTls \
  --ldapsPort 1636 \
  --httpPort 8080 --httpsPort 8443 \
  --baseDN "${BASE_DN}" \
  --hostname "${FQDN}" \
  --rootUserPasswordFile "${DIR_MANAGER_PW_FILE}" \
  --acceptLicense \
  --doNotStart \
   ${INIT_OPTION}  || (echo "Setup failed, will sleep for debugging"; sleep 10000)

echo "Set the global server id to $SERVER_ID"

bin/dsconfig  set-global-configuration-prop --set server-id:$SERVER_ID  --offline  --no-prompt


echo "Creating CTS backend..."
./bin/dsconfig create-backend \
          --set base-dn:o=cts \
          --set enabled:true \
          --type je \
          --backend-name ctsRoot \
          --offline \
          --no-prompt

cat >/tmp/cts.ldif <<EOF
dn: o=cts
objectClass: top
objectClass: organization
o: cts
EOF

# Need to manually import the base entry as we are offline.
bin/import-ldif --offline -n ctsRoot -F -l /tmp/cts.ldif


echo "Tuning the disk free space thresholds"

# For development you may want to tune the disk thresholds. TODO: Make this configurable
bin/dsconfig  set-backend-prop \
    --backend-name userRoot  \
    --set "disk-low-threshold:2GB"  --set "disk-full-threshold:1GB"  \
    --offline \
    --no-prompt

bin/dsconfig  set-backend-prop \
    --backend-name ctsRoot  \
    --set "disk-low-threshold:2GB"  --set "disk-full-threshold:1GB"  \
    --offline \
    --no-prompt




# Load any optional LDIF files. $1 is the directory to load from
load_ldif() {

    # If any optional LDIF files are present, load them.
    ldif=$1

    if [ -d "$ldif" ]; then
        echo "Loading LDIF files in $ldif"
        for file in "${ldif}"/*.ldif;  do
            echo "Loading $file"
            # search + replace all placeholder variables. Naming conventions are from AM.
            sed -e "s/@BASE_DN@/$BASE_DN/"  \
                -e "s/@userStoreRootSuffix@/$BASE_DN/"  \
                -e "s/@DB_NAME@/$DB_NAME/"  \
                -e "s/@SM_CONFIG_ROOT_SUFFIX@/$BASE_DN/"  <${file}  >/tmp/file.ldif

            #cat /tmp/file.ldif
            bin/ldapmodify -D "cn=Directory Manager"  --continueOnError -h localhost -p 1389 -j ${DIR_MANAGER_PW_FILE} -f /tmp/file.ldif
            # Note that currently these ldif files must be added with ldapmodify.
            #bin/import-ldif --offline -n userRoot -l /tmp/file.ldif --rejectFile /tmp/rejects.ldif
            #cat /tmp/rejects.ldif
          echo "  "
        done
    fi
}


# Run any post installation scripts for the bootstrap type.
post_install_scripts() {
    script="bootstrap/${BOOTSTRAP_TYPE}/post-install.sh"

    if [ -r "$script" ]; then
        echo "executing post install script $script"
        sh "$script"
    fi
}



# Load any optional ldif files. These fiiles need to be loaded with the server running.
bin/start-ds
load_ldif "bootstrap/userstore/ldif"
load_ldif "bootstrap/cts/ldif"
bin/stop-ds


post_install_scripts

#     --hostname $FQDN  --port 4444  --bindDN "cn=Directory Manager"  \
#     --bindPasswordFile "${DIR_MANAGER_PW_FILE}" \
