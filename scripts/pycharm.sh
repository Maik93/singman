#!/bin/bash
set -e

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`

PROGRAM="~/.local/share/JetBrains/Toolbox/apps/PyCharm-P/ch-0/213.6777.50/bin/pycharm.sh"

$SCRIPT_PATH/singularity.sh $1 exec "$PROGRAM > /dev/null 2>&1 &"
