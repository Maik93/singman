#!/bin/bash
set -e

[[ $# -lt 1 ]] && exit 2

RECIPE_NAME=$1

if [[ $# -eq 2 ]]; then
	IMAGE_NAME=$2
else
	IMAGE_NAME=$1
fi

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`
IMAGE_PATH=`( cd "$SCRIPT_PATH/../images" && pwd -P )`

[[ ! -f $SCRIPT_PATH/$RECIPE_NAME.def ]] && exit 1

singularity build --fakeroot --fix-perms -F $IMAGE_PATH/$IMAGE_NAME.sif $SCRIPT_PATH/$RECIPE_NAME.def
