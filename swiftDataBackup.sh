#!/bin/bash
# Name: swiftDataBackup.sh
# Description: Takes and Packages a keyspace snapshot to be restored to the same, or a
#              different Cassandra cluster.  Must be executed on a running
#              Cassandra node, have access to the cassandra.yaml file, and be
#              able to read the data file location(s).
#
#              A valid keyspace name is all that is required for getSnapshot
#              to run.  The script will run attempt to find cassandra.yaml in
#              the standard locations (for both DSE and ASF) or a supplied
#              location, determine the data file directory, and look for the
#              requested keyspace among all configured data file directories.
#              If a previous snapshot is not specified, a new snapshot is
#              created using "nodetool snapshot <keyspace>".  The snapshot is
#              packaged in a compressed TAR file with a copy of the schema.

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
PROGNAME="swiftDataBackup.sh"
PROGVER="1.0.1"
ASFCFG="/etc/cassandra"
DSECFG="/etc/dse/cassandra"
DUMPDIR="$( pwd )/${PROGNAME}.tmp${RANDOM}"
CLITMPFILE="${DUMPDIR}/cqlschema"
CASIP="127.0.0.1"
JMXIP="127.0.0.1"
HOSTNAME="$( hostname )"
SNAPSFILE="cassandra.snapshot"
HOSTSFILE="cassandra.hostname"
DATESFILE="cassandra.snapdate"

set -Eeuo pipefail
trap "mkdir -p /var/log/cassandra-snapshot/ && echo 'cassandra_snapshot_last_success 1' > /var/log/cassandra-snapshot/casssandra_snapshot_last_success.prom" ERR

# Functions
# ---------
function parse_yaml {
    # Basic (as in imperfect) parsing of a given YAML file.  Parameters
    # are stored as environment variables.
    local prefix=$2
    local s
    local w
    local fs
    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
        indent = length($1)/2;
        if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
        vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
        printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
        }
    }' | sed 's/_=/+=/g'
}

function usage {
    printf "Usage: $0 -h\n"
    printf "       $0 -b <bucket_name> [-k <keyspace_name> ...] [-t <keyspace_name.table_name> ...] [-y <cassandra.yaml file>]\n"
    printf "    -h,--help                               Print usage and exit\n"
    printf "    -v,--version                            Print version information and exit\n"
    printf "    -b,--bucket <bucket_name>               REQUIRED: The bucket name where the snapshot will be stored\n"
    printf "    -k,--keyspace <keyspace_name>           The name of the keyspace to snapshot (can add multiple keyspaces)\n"
    printf "    -t,--table <keyspace_name.table_name>   Single table to backup (can add multiple tables)\n"
    printf "    -y,--yaml <cassandra.yaml file>         Alternate cassandra.yaml file\n\n"
    printf "    Note: You need at least to pass as a parameter a keyspace or a table to backup!\n"
    exit 0
}

function version {
    printf "$PROGNAME version $PROGVER\n"
    printf "Cassandra snapshot packaging utility\n\n"
    printf "Copyright 2016 Applied Infrastructure, LLC\n\n"
    printf "Licensed under the Apache License, Version 2.0 (the \"License\");\n"
    printf "you may not use this file except in compliance with the License.\n"
    printf "You may obtain a copy of the License at\n\n"
    printf "    http://www.apache.org/licenses/LICENSE-2.0\n\n"
    printf "Unless required by applicable law or agreed to in writing, software\n"
    printf "distributed under the License is distributed on an \"AS IS\" BASIS,\n"
    printf "WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n"
    printf "See the License for the specific language governing permissions and\n"
    printf "limitations under the License.\n"
    exit 0
}

function do_snapshot {
    if [ -z "$1" ]; then
        printf "Error. Should provide a keyspace or table name to do a snapshot\n"
        exit 1
    fi

    FORMAT_NAME=$1
    KEYSPACE=$(echo "$FORMAT_NAME" | awk -F . '{print $1}')
    TABLE=$(echo "$FORMAT_NAME" | awk -F . '{print $2}')

    # Take the snapshot
    if [[ "$TABLE" == "" ]]; then
        nodetool snapshot --tag ${BUCKET} ${KEYSPACE}
    else
        nodetool snapshot --tag ${BUCKET} ${KEYSPACE} -cf ${TABLE}
    fi

    # Attempt to locate data directory and keyspace files
    YAMLLIST="${INPYAML:-$( find "$DSECFG" "$ASFCFG" -type f -name cassandra.yaml 2>/dev/null ) }"

    for yaml in $YAMLLIST; do
        if [ -r "$yaml" ]; then
            eval $( parse_yaml "$yaml" )
            # Search each data directory in the YAML
            for directory in ${data_file_directories_[@]}; do
                if [ -d "$directory/$KEYSPACE" ]; then
                    # Use the YAML that references the keyspace
                    DATADIR="$directory"
                    YAMLFILE="$yaml"
                    break
                fi
                # Used only when the keyspace can't be found
                TESTED="$TESTED $directory"
            done
        fi
    done

    if [ -z "$TESTED" ] && [ -z "$DATADIR" ]; then
        printf "No data directories, or no cassandra.yaml file found\n" >&2
        exit 1
    elif [ -z "$DATADIR" ] || [ -z "$YAMLFILE" ]; then
        printf "Keyspace data directory could not be found in:\n"
        for dir in $TESTED; do
            printf "    $dir/$KEYSPACE\n"
        done
        exit 1
    fi

    eval $( parse_yaml "$YAMLFILE" )

    # Write temp command file for Cassandra CLI
    printf "desc $FORMAT_NAME;\n" > $CLITMPFILE

    # Pull Snapshot
    # --------------------
    SEARCH=$( find "${DATADIR}/${KEYSPACE}" -type d -name "${BUCKET}" )

    if [ -z "$SEARCH" ]; then
        printf "No snapshots found with name ${BUCKET}\n"
        [ "$DUMPDIR" != "/" ] && rm -rf "$DUMPDIR"
        exit 1
    else
        printf "Using provided snapshot name ${BUCKET}\n"
    fi

    # Pull new/existing snapshot
    SNAPDIR="snapshots/$BUCKET"
    SCHEMA="$FORMAT_NAME-$TIMESTAMP.cdl"

    for dir in $( find "$DATADIR" -regex ".*/$SNAPDIR/[^\.]*.db" ); do
        NEWDIR=$( sed "s|${DATADIR}||" <<< $( dirname $dir ) | \
                    awk -F / '{print "/"$2"/"$3}' )
        FILENAME=$(basename $dir)
        swift upload $BUCKET $dir --object-name "$NEWDIR/$FILENAME"
    done

    # Backup the schema
    # -----------------
    cqlsh $CASIP -k $KEYSPACE -f $CLITMPFILE | tail -n +2 > "$DUMPDIR/$SCHEMA"
    RC=$?

    if [ $? -gt 0 ] && [ ! -s "$DUMPDIR/$SCHEMA" ]; then
        printf "Schema backup failed for $FORMAT_NAME\n"
        [ "$DUMPDIR" != "/" ] && rm -rf "$DUMPDIR"
        exit 1
    fi

    rm -f $CLITMPFILE
    printf "Successfully uploaded snapshot for ${FORMAT_NAME}\n"
    nodetool clearsnapshot -t ${BUCKET} ${KEYSPACE}
}

# Validate Input/Environment
# --------------------------
# Great sample getopt implementation by Cosimo Streppone
# https://gist.github.com/cosimo/3760587#file-parse-options-sh
SHORT='hvk:y:b:t:'
LONG='help,version,keyspace:,yaml:,no-timestamp,bucket:,table:'
OPTS=$( getopt -o $SHORT --long $LONG -n "$0" -- "$@" )

if [ $? -gt 0 ]; then
    # Exit early if argument parsing failed
    printf "Error parsing command arguments\n" >&2
    exit 1
fi

eval set -- "$OPTS"
while true; do
    case "$1" in
        -h|--help) usage;;
        -v|--version) version;;
        -k|--keyspace) KEYSPACES+=("$2"); shift 2;;
        -t|--table) TABLES+=("$2"); shift 2;;
        -b|--bucket) BUCKET="$2"; shift 2;;
        -y|--yaml) INPYAML="$2"; shift 2;;
        --) shift; break;;
        *) printf "Error processing command arguments\n" >&2; exit 1;;
    esac
done

# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    printf "You must provide a bucket name\n"
    exit 1
fi
# KEYSPACES or TABLES is required
if [[ "$KEYSPACES" == "" && "$TABLES" == "" ]]; then
    printf "You must provide at least a keyspace or a table name\n"
    exit 1
fi

# Verify required binaries at this point
./check_dependencies.sh awk basename cqlsh date dirname find getopt hostname mkdir rm sed tail nodetool swift
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
    exit 1
fi

# Need write access to local directory to create dump file
if [ ! -w $( pwd ) ]; then
    printf "You must have write access to the current directory $( pwd )\n"
    exit 1
fi

# Preparation
# -----------
TIMESTAMP=$( date +"%Y%m%d%H%M%S" )
DATESTRING=$( date )

# Create temporary working directory.  Yes, deliberately avoiding mktemp
if [ ! -d "$DUMPDIR" ] && [ ! -e "$DUMPDIR" ]; then
    mkdir -p "$DUMPDIR"
else
    printf "Error creating temporary directory $DUMPDIR"
    exit 1
fi

# Do backup of each keyspace
for keyspace in ${KEYSPACES[@]}; do
    do_snapshot $keyspace
done

# Do backup of each table
for table in ${TABLES[@]}; do
    do_snapshot $table
done

# Backup files with extra info
printf "$BUCKET" > "$DUMPDIR/$SNAPSFILE"
printf "$HOSTNAME" > "$DUMPDIR/$HOSTSFILE"
printf "$DATESTRING" > "$DUMPDIR/$DATESFILE"

for file in $( dir "$DUMPDIR" ); do
    swift upload $BUCKET "$DUMPDIR/$file" --object-name $file
done

[ "$DUMPDIR" != "/" ] && rm -rf "$DUMPDIR"
printf "Backup successfully uploaded\n"

mkdir -p /var/log/cassandra-snapshot/ && echo 'cassandra_snapshot_last_success 0' > /var/log/cassandra-snapshot/casssandra_snapshot_last_success.prom
# Fin.
