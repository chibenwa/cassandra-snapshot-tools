#!/bin/bash

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
PROGNAME="swiftDataSchemaRestore.sh"
LOADDIR="$( pwd )/${PROGNAME}.tmp${RANDOM}"

# Usage
# -----
function usage {
    echo "Usage: $0 -h"
    echo "       $0 -b <bucket_name> [-k <keyspace_name> ...]"
    echo "    -h,--help                                 Print usage and exit"
    echo "    -a,--address <ip_address>                 REQUIRED: The ip address of the cassandra node to load data into"
    echo "    -b,--bucket <bucket_name>                 REQUIRED: The bucket name where the snapshot is stored on swift"
    echo "    -k,--keyspace <keyspace_name>             The keyspace where to restore the data (can restore multiple keyspaces)"
    echo
    echo "    Note: You need at least to pass as a parameter a keyspace load schema and data!"
    exit 0
}


# Validate Input/Environment
# --------------------------
# Great sample getopt implementation by Cosimo Streppone
# https://gist.github.com/cosimo/3760587#file-parse-options-sh
SHORT='hk:b:a:'
LONG='help,keyspace:,bucket:address:'
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
        -a|--address) CASIP="$2"; shift 2;;
        --) shift; break;;
        *) echo "Error processing command arguments" >&2; exit 1;;
    esac
done

# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    echo "You must provide a bucket name"
    exit 1
fi
# KEYSPACES is required
if [[ "$KEYSPACES" == "" ]]; then
    printf "You must provide at least a keyspace"
    exit 1
fi
# CASIP is absolutely required
if [ "$CASIP" == "" ]; then
    echo "You must provide a bucket name"
    exit 1
fi

# Checking dependencies
./check_dependencies.sh nodetool swift cqlsh
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
    exit 1
fi

# Need write access to local directory to download snapshot package
if [ ! -w $( pwd ) ]; then
    printf "You must have write access to the current directory $( pwd )\n"
    exit 1
fi

# Create temporary working directory.  Yes, deliberately avoiding mktemp
if [ ! -d "$LOADDIR" ] && [ ! -e "$LOADDIR" ]; then
    mkdir -p "$LOADDIR"
else
    printf "Error creating temporary directory $LOADDIR"
    exit 1
fi

# Load schema and data of each keyspace
for keyspace in ${KEYSPACES[@]}; do 
    # Download and load schema first
    echo "About to restore the schema for $keyspace"

    FILE=$(swift list $BUCKET -p "$keyspace-" | grep .cdl)
    swift download $BUCKET $FILE
    cqlsh $CASIP -e "SOURCE './$FILE'"
    rm -f $FILE

    echo "Schema successfully restored for $keyspace"

    # Load keyspace data
    echo "Restoring data stored in ${BUCKET} into ${keyspace}"

    swift download $BUCKET -p "$keyspace" -D $LOADDIR

    for columnfamily in `ls "${LOADDIR}/${keyspace}"`; do
        sstableloader -d $CASIP "${LOADDIR}/${keyspace}/${columnfamily}"
    done

    echo "Data successfully restored from ${BUCKET} into ${keyspace}"
done

[ "$LOADDIR" != "/" ] && rm -rf "$LOADDIR"
