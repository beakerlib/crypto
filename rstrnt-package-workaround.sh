#!/bin/bash

tmp_dir=$(mktemp -d)

shift
operation=$1
shift 
packages=$*

if [[ "$operation" == "remove" ]]; then

    dnf remove -y $packages
    
elif [[ "$operation" == "install" ]]; then

    pushd $tmp_dir 
    dnf install --downloadonly -y --downloaddir . --skip-broken $packages
    rpm -ihv --nodigest --nofiledigest --nodeps *.rpm
    popd
fi

rm -rf $tmp_dir
