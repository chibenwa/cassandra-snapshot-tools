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
function usage {
    echo "Usage: $0 -h"
    echo "       $0 -b <bucket_name> [-k <keyspace_name> ...] [-t <keyspace_name.table_name> ...]"
    echo "    -h,--help                                 Print usage and exit"
    echo "    -b,--bucket <bucket_name>                 REQUIRED: The bucket name where the snapshot is stored on swift"
    echo "    -k,--keyspace <keyspace_name>             The keyspace where to restore the data (can restore multiple keyspaces)"
    echo "    -t,--table <keyspace_name.table_name>     Single table to restore data (can restore multiple tables)"
    echo
    echo "    Note: You need at least to pass as a parameter a keyspace or a table to backup!"
    exit 0
}

# Refresh tables
# Usage: refresh <keyspace> <table>
function refresh {
    echo "Refreshing $1.$2"
    nodetool refresh $1 $2
}

# Restore keyspaces and tables
function do_restore {
    if [ -z "$1" ]; then
        printf "Error. Should provide a keyspace or table name to do a snapshot"
        exit 1
    fi

    FORMAT_NAME=$1
    KEYSPACE=$(echo "$FORMAT_NAME" | awk -F . '{print $1}')
    TABLE=$(echo "$FORMAT_NAME" | awk -F . '{print $2}')

    echo "Restoring data stored in ${BUCKET} into ${FORMAT_NAME}"

    swift download $BUCKET -p "$KEYSPACE/$TABLE" -D $CASSDATA
    chown -R cassandra:cassandra "$CASSDATA/$KEYSPACE"

    if [[ "$TABLE" == "" ]]; then
        for table in `cqlsh -e "USE $KEYSPACE; DESCRIBE TABLES;"`; do
            refresh $KEYSPACE $table
        done
    else
        refresh $KEYSPACE $TABLE
    fi

    echo "Data successfully restored from ${BUCKET} into ${FORMAT_NAME}"
}

# Validate Input/Environment
# --------------------------
# Great sample getopt implementation by Cosimo Streppone
# https://gist.github.com/cosimo/3760587#file-parse-options-sh
SHORT='hk:b:t:'
LONG='help,keyspace:,bucket:,table:'
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
        -t|--table) TABLES+=("$2"); shift 2;;
        -b|--bucket) BUCKET="$2"; shift 2;;
        --) shift; break;;
        *) echo "Error processing command arguments" >&2; exit 1;;
    esac
done

# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    echo "You must provide a bucket name"
    exit 1
fi
# KEYSPACES or TABLES is required
if [[ "$KEYSPACES" == "" && "$TABLES" == "" ]]; then
    printf "You must provide at least a keyspace or a table name"
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
    do_restore $keyspace
done

# Do restore of each table
for table in ${TABLES[@]}; do
    do_restore $table
done
