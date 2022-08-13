#!/bin/bash
set -e

OVERLAY_NAME="$1.img"
OVERLAY_SIZE=1000 # MB

## | -------------------------- paths ------------------------- |

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`
OVERLAYS_PATH=`( cd "$SCRIPT_PATH/../overlays" && pwd -P )`

## | ------------------------- overlay ------------------------ |

# create the template for overlay file system
TEMPLATE_PATH=$( mktemp -d )
mkdir -p $TEMPLATE_PATH/upper
mkdir -p $TEMPLATE_PATH/work

dd if=/dev/zero of=$OVERLAYS_PATH/$OVERLAY_NAME bs=1M count=$OVERLAY_SIZE \
  && mkfs.ext3 -d $TEMPLATE_PATH $OVERLAYS_PATH/$OVERLAY_NAME
