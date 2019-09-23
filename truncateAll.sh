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

function usage() {
    echo "Usage: $0 -h"
    echo "       $0 [-k <keyspace name> ...] [-t <keyspace_name.table_name> ...]"
    echo "    -h,--help                          Print usage and exit"
    echo "    -k,--keyspace <keyspace name>           The keyspace where to drop all data (can drop multiple keyspaces)"
    echo "    -t,--table <keyspace_name.table_name>   Single table to drop data (can drop multiple tables)"
    echo
    echo "Note: You need at least to pass as a parameter a keyspace or a table to backup!"
    exit 0
}

# Validate Input/Environment
# --------------------------
# Great sample getopt implementation by Cosimo Streppone
# https://gist.github.com/cosimo/3760587#file-parse-options-sh
SHORT='hk:t:'
LONG='help,keyspace:,table:'
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
        --) shift; break;;
        *) echo "Error processing command arguments" >&2; exit 1;;
    esac
done

# KEYSPACES or TABLES is required
if [[ "$KEYSPACES" == "" && "$TABLES" == "" ]]; then
    printf "You must provide at least a keyspace or a table name\n"
    exit 1
fi

# Checking cqlsh presence
./check_dependencies.sh cqlsh
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
  exit 1
fi

# Warn about the desctructive action we are about to take
echo "About to drop all data in a bunch of keyspaces/tables"
echo "We are nice, you have 5 seconds to CTRL+C if needed..."
sleep 5

for keyspace in ${KEYSPACES[@]}; do
    # Drop all data in specified keyspace
    for table in `cqlsh -e "USE $keyspace; DESCRIBE TABLES;"`; do
        echo "TRUNCATE ${keyspace}.${table};"
        cqlsh -e "TRUNCATE ${keyspace}.${table};"
    done
done

for table in ${TABLES[@]}; do
    echo "TRUNCATE ${table};"
    cqlsh -e "TRUNCATE ${table};"
done
