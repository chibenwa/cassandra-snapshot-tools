#!/bin/bash

    # Function to iterate through a list of required executables to ensure
    # they are installed and executable by the current user.
    for bin in "$@"; do
        $( which $bin >/dev/null 2>&1 ) || NOTFOUND+="$bin "
    done
    if [ ! -z "$NOTFOUND" ]; then
        printf "Error finding required executables: ${NOTFOUND}\n" >&2
        exit 1
    fi
