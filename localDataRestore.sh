#!/bin/bash

# Usage ./localDataRestore.sh $1
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

printUsage() {
   echo "Usage : "
   echo "./localDataRestore.sh SNAPSHOT_TAR KEYSPACE"
   echo "    KEYSPACE: the keyspace where to restore all data"
   echo "    SNAPSHOT_TAR: the snapshot tarball to restore data from"
   echo ""
   echo "Note: [nodetool cp tar rm mkdir grep cut] needs to be installed"
   exit 1
}

# Validate arguments
if [ -z "$1" ]; then
    printUsage
fi
if [ -z "$2" ]; then
    printUsage
fi
if ! [ -z "$3" ]; then
    printUsage
fi
SNAPPKG=$1
KEYSPACE=$2
echo "Restoring data stored in ${SNAPPKG} into ${KEYSPACE}"

# Checking nodetool cp tar presence
./check_dependencies.sh nodetool cp tar rm mkdir grep cut
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
  exit 1
fi

TEMPDIR="$( pwd )/.localDataRestore.tmp${RANDOM}"
# Remove local temp directory
[ "$TEMPDIR" != "/" ] && rm -rf "$TEMPDIR"

# Verify/Extract Snapshot Package
tar -tvf "$SNAPPKG" 2>&1 | grep "$KEYSPFILE" 2>&1 >/dev/null
RC=$?
if [ $RC -gt 0 ]; then
        echo "Snapshot package $SNAPPKG appears invalid or corrupt"
        exit 1
fi

# Create temporary working directory
if [ ! -d "$TEMPDIR" ] && [ ! -e "$TEMPDIR" ]; then
    echo "Creating ${TEMPDIR}"
    mkdir -p "$TEMPDIR"
else
    echo "Error creating temporary directory $TEMPDIR"
    exit 1
fi

# Extract snapshot package
tar -xf "$SNAPPKG" --directory "$TEMPDIR"
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

echo "Data successfully restored from ${SNAPPKG} into ${KEYSPACE}"
