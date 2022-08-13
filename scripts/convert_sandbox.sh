#!/bin/bash
set -e

## | -------------------------- paths ------------------------- |

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`
IMAGES_PATH=`( cd "$SCRIPT_PATH/../images" && pwd -P )`

## | ----------------------- script args ---------------------- |

TO_SANDBOX=true # set to false to reverse the direction
while getopts ":n:r" arg; do
    case $arg in
		n) IMAGE_NAME="${OPTARG}";;
		r) TO_SANDBOX=false;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1;;
        :)  echo "Missing option argument for -$OPTARG" >&2; usage; exit 1;;
    esac
done
[[ -z $IMAGE_NAME ]] && exit 1

## | -------------------------- build ------------------------- |

if $TO_SANDBOX; then
  echo "building --sandbox image"
  singularity build --fakeroot --sandbox $IMAGES_PATH/$IMAGE_NAME/ $IMAGES_PATH/$IMAGE_NAME.sif
else
  singularity build --fakeroot $IMAGES_PATH/$IMAGE_NAME.sif $IMAGES_PATH/$IMAGE_NAME/
fi
