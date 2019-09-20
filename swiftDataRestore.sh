#!/bin/bash

# Usage ./swiftDataRestore.sh $1
# Where $1 is the keyspace where to restore all data
# Note: cqlsh needs to be installed

# Copyright 2019 Linagora
# From the original work of: 
# Copyright 2016 Applied Infrastructure, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Configuration
# -------------
CASSDATA="/var/lib/cassandra/data"

# Usage
# -----
function usage() {
    echo "Usage: $0 -h"
    echo "       $0 -k <keyspace name> [-k <keyspace name> ...] -b <bucket name>"
    echo "    -h,--help                          Print usage and exit"
    echo "    -k,--keyspace <keyspace name>      REQUIRED: the keyspace where to restore the data (can restore multiple keyspaces)"
    echo "    -b,--bucket <bucket name>          REQUIRED: The bucket name where the snapshot is stored on swift"
    exit 0
}

# Validate Input/Environment
# --------------------------
# Great sample getopt implementation by Cosimo Streppone
# https://gist.github.com/cosimo/3760587#file-parse-options-sh
SHORT='hk:b:'
LONG='help,keyspace:,bucket:'
OPTS=$( getopt -o $SHORT --long $LONG -n "$0" -- "$@" )

if [ $? -gt 0 ]; then
    # Exit early if argument parsing failed
    echo "Error parsing command arguments" >&2
    exit 1
fi

eval set -- "$OPTS"
while true; do
    case "$1" in
        -h|--help) usage;;
        -k|--keyspace) KEYSPACES+=("$2"); shift 2;;
        -b|--bucket) BUCKET="$2"; shift 2;;
        --) shift; break;;
        *) echo "Error processing command arguments" >&2; exit 1;;
    esac
done

# KEYSPACES is absolutely required
if [ "$KEYSPACES" == "" ]; then
    echo "You must provide keyspace(s) name(s)\n"
    exit 1
fi
# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    echo "You must provide a bucket name\n"
    exit 1
fi

# Checking dependencies
./check_dependencies.sh nodetool swift cqlsh
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
    exit 1
fi

# Need write access to local directory to download snapshot package
if [ ! -w $CASSDATA ]; then
    echo "You must have write access to the cassandra data directory $CASSDATA"
    exit 1
fi

# Do restore of each keyspace
for keyspace in ${KEYSPACES[@]}; do
    echo "Restoring data stored in ${BUCKET} into ${keyspace}"

    swift download $BUCKET -p "$keyspace/" -D $CASSDATA
    chown -R cassandra:cassandra "$CASSDATA/$keyspace"

    for table in `cqlsh -e "USE $keyspace; DESCRIBE TABLES;"`; do
        echo "Refreshing ${table}"
        nodetool refresh ${keyspace} ${table}
    done

    echo "Data successfully restored from ${BUCKET} into ${keyspace}"
done
