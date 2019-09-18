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

# Name: ./dataSwift.sh 
# Note: * curl needs to be installed
#       * tmpauth is used at the moment for swift authentication (test setup)
#
# To do: * add a check if container exists or not, and create in case not
#        * check if file exist or not?
#        * verify response status of download and manage errors?
#        * check auth in prod

function usage() {
    echo "Usage: $0 command [options]"
    echo
    echo "Commands:"
    echo "  upload - upload file to Swift"
    echo "  download - download file from Swift"
    echo
    echo "Options:"
    echo "  -h,--help                          Print usage and exit"
    echo "  -e,--endpoint <swift_endpoint>     REQUIRED: The name of the Swift endpoint for auth"
    echo "  -u,--username <swift_username>     REQUIRED: The user name for auth"
    echo "  -t,--tenant <swift_tenantname>     REQUIRED: The tenant name for auth"
    echo "  -c,--creds <swift_credentials>     REQUIRED: The credentials for auth"
    echo "  -b,--bucket <switf_container>      REQUIRED: The bucket in Swift where the file will be stored"
    echo "  -f,--file <file>                   REQUIRED: The file to upload to Swift"
    exit 0
}


function upload() {
    # Upload file
    echo "About to upload $FILE to object storage"

    STATUS=$(curl -i -T $FILE -X PUT -H "X-Auth-Token: $AUTH_TOKEN" $STORAGE_URL/$BUCKET/$FILE | grep HTTP | awk {'print $2'} | sed -n '2p')

    if [[ "$STATUS" != "201" ]]; then
        echo "Error while trying to store $FILE to the object storage."
        exit 1
    fi

    echo "$FILE has been uploaded successfully to object storage"
}


function download() {
    # Download file
    echo "About to download $FILE from object storage"

    curl -s -S -X GET -H "X-Auth-Token: $AUTH_TOKEN" $STORAGE_URL/$BUCKET/$FILE -O

    echo "$FILE has been downloaded successfully from object storage"
}


if [[ -z "$1" || "$1" != "download" && "$1" != "upload" ]]; then
    usage
fi

COMMAND=$1

SHORT='he:u:t:c:b:f:'
LONG='help,endpoint:,username:,tenant:,creds:,bucket:,file:'
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
        -e|--endpoint) ENDPOINT="$2"; shift 2;;
        -u|--username) USERNAME="$2"; shift 2;;
        -t|--tenant) TENANTNAME="$2"; shift 2;;
        -c|--creds) CREDENTIALS="$2"; shift 2;;
        -b|--bucket) BUCKET="$2"; shift 2;;
        -f|--file) FILE="$2"; shift 2;;
        --) shift; break;;
        *) echo "Error processing command arguments" >&2; exit 1;;
    esac
done

# ENDPOINT is absolutely required
if [ "$ENDPOINT" == "" ]; then
    echo "You must provide a Swift endpoint for authentication"
    exit 1
fi
# USERNAME is absolutely required
if [ "$USERNAME" == "" ]; then
    echo "You must provide a Swift user name for authentication"
    exit 1
fi
# TENANTNAME is absolutely required
if [ "$TENANTNAME" == "" ]; then
    echo "You must provide a Swift tenant name for authentication"
    exit 1
fi
# CREDENTIALS is absolutely required
if [ "$CREDENTIALS" == "" ]; then
    echo "You must provide the Swift credentials for authentication"
    exit 1
fi
# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    echo "You must provide the container in Swift where the file will be stored"
    exit 1
fi
# FILE is absolutely required
if [ "$FILE" == "" ]; then
    echo "You must provide the file to upload"
    exit 1
fi

# Checking required dependencies
./check_dependencies.sh curl awk grep echo
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
    exit 1
fi

# Authenticate and parse response
shopt -s extglob # Required to trim whitespace; see below

echo "About to authenticate towards $ENDPOINT"

while IFS=':' read key value; do
    # trim whitespace in "value"
    value=${value##+([[:space:]])}; value=${value%%+([[:space:]])}

    case "$key" in
        X-Storage-Url) STORAGE_URL="$value"
                ;;
        X-Auth-Token) AUTH_TOKEN="$value"
                ;;
        HTTP*) read PROTO RESPONSE_CODE MSG <<< "$key{$value:+:$value}"
                ;;
     esac
done < <(curl -i -H "X-Auth-User: $TENANTNAME:$USERNAME" -H "X-Auth-Key: $CREDENTIALS" $ENDPOINT)

if [[ "$RESPONSE_CODE" != "200" ]]; then
    echo "Error $RESPONSE_CODE while trying to authenticate to the Swift server. Verify your credentials or the connection"
    exit 1
fi

if [[ "$COMMAND" == "upload" ]]; then
    upload
else
    download
fi
