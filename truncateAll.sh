#!/bin/bash

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
