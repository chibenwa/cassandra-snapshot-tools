#!/bin/bash

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

# Function to iterate through a list of required executables to ensure
# they are installed and executable by the current user.
for bin in "$@"; do
    $( which $bin >/dev/null 2>&1 ) || NOTFOUND+="$bin "
done
if [ ! -z "$NOTFOUND" ]; then
    printf "Error finding required executables: ${NOTFOUND}\n" >&2
    exit 1
fi
