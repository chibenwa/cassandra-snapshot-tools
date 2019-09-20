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
KEYSPFILE="cassandra.keyspace"
SNAPSFILE="cassandra.snapshot"
HOSTSFILE="cassandra.hostname"
DATESFILE="cassandra.snapdate"

# Functions
# ---------
function parse_yaml() {
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

function usage() {
    printf "Usage: $0 -h\n"
    printf "       $0 -k <keyspace name> [-k <keyspace name> ...] -b <bucket name> [-y <cassandra.yaml file>]\n"
    printf "    -h,--help                          Print usage and exit\n"
    printf "    -v,--version                       Print version information and exit\n"
    printf "    -k,--keyspace <keyspace name>      REQUIRED: The name of the keyspace to snapshot (can add multiple keyspaces)\n"
    printf "    -b,--bucket <bucket name>          REQUIRED: The bucket name where the snapshot will be stored\n"
    printf "    -y,--yaml <cassandra.yaml file>    Alternate cassandra.yaml file\n"
    exit 0
}

function version() {
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

# Validate Input/Environment
# --------------------------
# Great sample getopt implementation by Cosimo Streppone
# https://gist.github.com/cosimo/3760587#file-parse-options-sh
SHORT='hvk:y:b:'
LONG='help,version,keyspace:,yaml:,no-timestamp,bucket:'
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
        -b|--bucket) BUCKET="$2"; shift 2;;
        -y|--yaml) INPYAML="$2"; shift 2;;
        --) shift; break;;
        *) printf "Error processing command arguments\n" >&2; exit 1;;
    esac
done


# KEYSPACES is absolutely required
if [ "$KEYSPACES" == "" ]; then
    printf "You must provide keyspace(s) name(s)\n"
    exit 1
fi
# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    printf "You must provide a bucket name\n"
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
    # Take the snapshot
    nodetool snapshot --tag ${BUCKET} ${keyspace}

    # Attempt to locate data directory and keyspace files
    YAMLLIST="${INPYAML:-$( find "$DSECFG" "$ASFCFG" -type f -name cassandra.yaml 2>/dev/null ) }"

    for yaml in $YAMLLIST; do
        if [ -r "$yaml" ]; then
            eval $( parse_yaml "$yaml" )
            # Search each data directory in the YAML
            for directory in ${data_file_directories_[@]}; do
                if [ -d "$directory/$keyspace" ]; then
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
            printf "    $dir/$keyspace\n"
        done
        exit 1
    fi

    eval $( parse_yaml "$YAMLFILE" )

    # Write temp command file for Cassandra CLI
    printf "desc keyspace $keyspace;\n" > $CLITMPFILE

    # Pull Snapshot
    # --------------------
    SEARCH=$( find "${DATADIR}/${keyspace}" -type d -name "${BUCKET}" )

    if [ -z "$SEARCH" ]; then
        printf "No snapshots found with name ${BUCKET}\n"
        [ "$DUMPDIR" != "/" ] && rm -rf "$DUMPDIR"
        exit 1
    else
        printf "Using provided snapshot name ${BUCKET}\n"
    fi

    # Pull new/existing snapshot
    SNAPDIR="snapshots/$BUCKET"
    SCHEMA="schema-$keyspace-$TIMESTAMP.cdl"

    for dir in $( find "$DATADIR" -regex ".*/$SNAPDIR/[^\.]*.db" ); do
        NEWDIR=$( sed "s|${DATADIR}||" <<< $( dirname $dir ) | \
                    awk -F / '{print "/"$2"/"$3}' )
        FILENAME=$(basename $dir)
        swift upload $BUCKET $dir --object-name "$NEWDIR/$FILENAME"
    done

    # Backup the schema
    # -----------------
    printf "$keyspace" > "$DUMPDIR/$keyspace.$KEYSPFILE"
    printf "$BUCKET" > "$DUMPDIR/$keyspace.$SNAPSFILE"
    printf "$HOSTNAME" > "$DUMPDIR/$keyspace.$HOSTSFILE"
    printf "$DATESTRING" > "$DUMPDIR/$keyspace.$DATESFILE"
    cqlsh $CASIP -k $keyspace -f $CLITMPFILE | tail -n +2 > "$DUMPDIR/$SCHEMA"
    RC=$?

    if [ $? -gt 0 ] && [ ! -s "$DUMPDIR/$SCHEMA" ]; then
        printf "Schema backup failed for keyspace $keyspace\n"
        [ "$DUMPDIR" != "/" ] && rm -rf "$DUMPDIR"
        exit 1
    fi

    rm -f $CLITMPFILE
    printf "Successfully uploaded snapshot for keyspace ${keyspace}\n"
    nodetool clearsnapshot -t ${BUCKET} ${keyspace}
done

for file in $( dir "$DUMPDIR" ); do
    swift upload $BUCKET "$DUMPDIR/$file" --object-name $file
done

[ "$DUMPDIR" != "/" ] && rm -rf "$DUMPDIR"
printf "Backup successfully uploaded\n"

# Fin.
