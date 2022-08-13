#!/bin/bash
set -e

IMAGE_NAME=$1

## | -------------------------- paths ------------------------- |

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`
REPO_PATH=`( cd "$SCRIPT_PATH/.." && pwd -P )`

## | ------------------------ embedding ----------------------- |

singularity sif add --datatype 4 --partfs 2 --parttype 4 --partarch 2 --groupid 1 \
	$REPO_PATH/images/$IMAGE_NAME.sif $REPO_PATH/overlays/$IMAGE_NAME.img
