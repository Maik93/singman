#!/bin/bash
set -e

IMAGE_NAME=$1
[[ -z $IMAGE_NAME ]] && echo "Missing required image name." >&2 && exit 1

## | -------------------------- paths ------------------------- |

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`
REPO_PATH=`( cd "$SCRIPT_PATH/.." && pwd -P )`

## | ------------------------ embedding ----------------------- |

if [[ ! -f "$REPO_PATH/images/$IMAGE_NAME.sif" ]]; then
    echo "$IMAGE_NAME.sif does not exists"
    exit 1
fi

if [[ ! -f "$REPO_PATH/overlays/$IMAGE_NAME.img" ]]; then
    echo "$IMAGE_NAME.img does not exists"
    exit 1
fi

singularity sif add --datatype 4 --partfs 2 --parttype 4 --partarch 2 --groupid 1 \
    $REPO_PATH/images/$IMAGE_NAME.sif $REPO_PATH/overlays/$IMAGE_NAME.img

read -p "Remove $IMAGE_NAME.img? (y/N): " choice
if [ "$choice" = "y" ]; then
    rm $REPO_PATH/overlays/$IMAGE_NAME.img
fi
