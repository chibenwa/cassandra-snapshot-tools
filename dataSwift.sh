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
# Note: * swift client needs to be installed and configured to connect to your object storage.
#          => see sample file in resources/object-storage.conf.swift.sample for variables to be exported.

function usage() {
    echo "Usage: $0 command [options]"
    echo
    echo "Commands:"
    echo "  upload - upload file to Swift"
    echo "  download - download file from Swift"
    echo
    echo "Options:"
    echo "  -h,--help                          Print usage and exit"
    echo "  -b,--bucket <switf_container>      REQUIRED: The bucket in Swift where the file will be stored/downloaded"
    echo "  -f,--file <file>                   REQUIRED: The file to upload/download"
    echo
    echo "Notes:"
    echo "  * You need to have swift client installed and be authenticated to your object storage first"
    exit 0
}

function upload() {
    # Upload file
    echo "About to upload $FILE to object storage"

    swift upload $BUCKET $FILE

    echo "$FILE has been uploaded successfully to object storage"
}


function download() {
    # Download file
    echo "About to download $FILE from object storage"

    swift download $BUCKET $FILE
    
    echo "$FILE has been downloaded successfully from object storage"
}

if [[ -z "$1" || "$1" != "download" && "$1" != "upload" ]]; then
    usage
fi

COMMAND=$1

SHORT='hb:f:'
LONG='help,bucket:,file:'
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
        -b|--bucket) BUCKET="$2"; shift 2;;
        -f|--file) FILE="$2"; shift 2;;
        --) shift; break;;
        *) echo "Error processing command arguments" >&2; exit 1;;
    esac
done

# BUCKET is absolutely required
if [ "$BUCKET" == "" ]; then
    echo "You must provide the container in Swift where the file will be stored/downloaded"
    exit 1
fi
# FILE is absolutely required
if [ "$FILE" == "" ]; then
    echo "You must provide the file to upload/download"
    exit 1
fi

# Checking required dependencies
./check_dependencies.sh swift
RETVAL=$?
if [[ "$RETVAL" != "0" ]]; then
    exit 1
fi

if [[ "$COMMAND" == "upload" ]]; then
    upload
else
    download
fi
