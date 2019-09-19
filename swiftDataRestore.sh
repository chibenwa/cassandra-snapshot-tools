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

function usage() {
    echo "Usage : "
    echo "$0 -k <keyspace name> -s <snapshot name> -b <bucket name>"
    echo "    -h,--help                          Print usage and exit"
    echo "    -k,--keyspace <keyspace name>      REQUIRED: the keyspace where to restore all data"
    echo "    -s,--snapshot <snapshot name>      REQUIRED: the snapshot tarball to restore data from on swift"
    echo "    -b,--bucket <bucket name>          REQUIRED: The bucket name where the snapshot is stored on swift"
    exit 0
}

# Validate Input/Environment
# --------------------------
# Great sample getopt implementation by Cosimo Streppone
# https://gist.github.com/cosimo/3760587#file-parse-options-sh
SHORT='hk:s:b:'
LONG='help,keyspace:,snapshot:,bucket:'
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
        -k|--keyspace) KEYSPACE="$2"; shift 2;;
        -s|--snapshot) SNAPSHOT="$2"; shift 2;;
        -b|--bucket) BUCKET="$2"; shift 2;;
        --) shift; break;;
        *) echo "Error processing command arguments" >&2; exit 1;;
    esac
done


# KEYSPACE is absolutely required
if [ "$KEYSPACE" == "" ]; then
    echo "You must provide a keyspace name\n"
    exit 1
fi
# SNAPSHOT is absolutely required
if [ "$SNAPSHOT" == "" ]; then
    echo "You must provide a snapshot name\n"
    exit 1
fi
# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    echo "You must provide a bucket name\n"
    exit 1
fi

echo "Restoring data stored in ${SNAPSHOT} into ${KEYSPACE}"

# Checking dependencies
./check_dependencies.sh nodetool cp tar rm mkdir grep cut swift
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
  exit 1
fi

# Need write access to local directory to download snapshot package
if [ ! -w $( pwd ) ]; then
    echo "You must have write access to the current directory $( pwd )"
    exit 1
fi

TEMPDIR="$( pwd )/.localDataRestore.tmp${RANDOM}"
# Remove local temp directory
[ "$TEMPDIR" != "/" ] && rm -rf "$TEMPDIR"

# Create temporary working directory
if [ ! -d "$TEMPDIR" ] && [ ! -e "$TEMPDIR" ]; then
    echo "Creating ${TEMPDIR}"
    mkdir -p "$TEMPDIR"
else
    echo "Error creating temporary directory $TEMPDIR"
    exit 1
fi

# Download snapshot package from Swift
echo "About to download $SNAPSHOT from object storage"

swift download $BUCKET $SNAPSHOT

echo "$SNAPSHOT has been downloaded successfully from object storage"

# Verify/Extract Snapshot Package
tar -tvf "$SNAPSHOT" 2>&1 | grep "$KEYSPFILE" 2>&1 >/dev/null
RC=$?
if [ $RC -gt 0 ]; then
    echo "Snapshot package $SNAPSHOT appears invalid or corrupt"
    exit 1
fi

# Extract snapshot package
tar -xf "$SNAPSHOT" --directory "$TEMPDIR"
chown -R cassandra:cassandra $TEMPDIR

for columnfamily in `ls "${TEMPDIR}/${KEYSPACE}"`; do
    TABLE=`echo "${columnfamily}" | cut -d '-' -f 1`
    echo "Copying data into ${TABLE} data directory"
    cp -p $TEMPDIR/$KEYSPACE/$columnfamily/* /var/lib/cassandra/data/$KEYSPACE/$columnfamily/.
    echo "Refreshing ${TABLE}"
    nodetool refresh ${KEYSPACE} ${TABLE}
done

# Cleanup tmp directory
rm -rf "$TEMPDIR"
# Cleanup snapshot
rm -f "$SNAPSHOT"

echo "Data successfully restored from ${SNAPSHOT} into ${KEYSPACE}"
