#!/bin/bash
set -e

[[ $# -ne 1 ]] && exit 2

RECIPE_NAME=$1

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`
IMAGE_PATH=`( cd "$SCRIPT_PATH/../images" && pwd -P )`

[[ ! -f $SCRIPT_PATH/$RECIPE_NAME.def ]] && exit 1

singularity build --fakeroot --fix-perms -F $IMAGE_PATH/$RECIPE_NAME.sif $SCRIPT_PATH/$RECIPE_NAME.def
