#!/bin/bash
set -e

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`

ROS_SOURCE="source /opt/ros/noetic/setup.bash"

PROGRAM="~/.local/share/JetBrains/Toolbox/apps/CLion/ch-0/213.6777.58/bin/clion.sh"

$SCRIPT_PATH/singularity.sh $1 exec "$ROS_SOURCE && $PROGRAM > /dev/null 2>&1 &"
