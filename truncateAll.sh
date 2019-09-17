#!/bin/bash

# Copyright 2019 Linagora
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

# Usage ./turncateAll.sh $1
# Where $1 is the keyspace where to drop all data
# Note: cqlsh needs to be installed

printUsage() {
   echo "Usage : "
   echo "./turncateAll.sh KEYSPACE"
   echo "    KEYSPACE: the keyspace where to drop all data"
   echo ""
   echo "Note: cqlsh needs to be installed"
   exit 1
}

# Validate arguments
if [ -z "$1" ]; then
    printUsage
fi
if ! [ -z "$2" ]; then
    printUsage
fi
KEYSPACE=$1

# Checking cqlsh presence
./check_dependencies.sh cqlsh
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
  exit 1
fi

# Warn about the desctructive action we are about to take
echo "About to drop all data in $KEYSPACE keyspace"
echo "We are nice, you have 5 seconds to CTRL+C if needed..."
sleep 5

# Drop all data in specified keyspace
for table in `cqlsh -e "USE $KEYSPACE; DESCRIBE TABLES;"`; do
    echo "TRUNCATE ${KEYSPACE}.${table};"
    cqlsh -e "TRUNCATE ${KEYSPACE}.${table};"
done
