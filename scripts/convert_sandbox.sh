#!/bin/bash
set -e

usage() {
    echo
    echo "Usage: `basename $0` [-r] image_name"
    echo "  r,reverse   convert from sandbox directory to .sif file."
    echo "  h,help      help and usage message."
    echo
}

## | ----------------------- script args ---------------------- |

TO_SANDBOX=true
while getopts ":rh-:" arg; do
    # support long options: https://stackoverflow.com/a/28466267/519360
    if [ "$arg" = "-" ]; then   # long option: reformulate arg and OPTARG
        arg="${OPTARG%%=*}"       # extract long option name
        OPTARG="${OPTARG#$arg}"   # extract long option argument (may be empty)
        OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
    fi
    case $arg in
    r | reverse) TO_SANDBOX=false;; # set to false to reverse the direction
    h | help)    echo "Convert a .sif image to a sandbox directory and vice-versa."; usage; exit 0;;

    ??*) echo "Illegal option --$arg" >&2; usage; exit 1;; # bad long option
    \?)  echo "Unknown option: -$OPTARG" >&2; usage; exit 1;; # bad short option
    :)   echo "Missing option argument for -$OPTARG" >&2; usage; exit 1;;
    esac
done

# get positional arguments
shift $(($OPTIND - 1))
IMAGE_NAME=$1

[[ -z $IMAGE_NAME ]] && echo "Missing required positional argument." >&2 && usage && exit 1

## | -------------------------- paths ------------------------- |

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`
IMAGES_PATH=`( cd "$SCRIPT_PATH/../images" && pwd -P )`

## | ----------------------- conversion ----------------------- |

if $TO_SANDBOX; then
    echo "building --sandbox image..."
    singularity build --fakeroot --sandbox $IMAGES_PATH/$IMAGE_NAME/ $IMAGES_PATH/$IMAGE_NAME.sif
else
    echo "Updating $IMAGE_NAME.sif with sandbox image..."
    singularity build --fakeroot $IMAGES_PATH/$IMAGE_NAME.sif $IMAGES_PATH/$IMAGE_NAME/

    read -p "Remove sandbox directory? (y/N): " choice
    if [ "$choice" = "y" ]; then
        rm -rf $IMAGES_PATH/$IMAGE_NAME/
        echo "$IMAGES_PATH/$IMAGE_NAME/ sandbox directory removed"
    fi
fi
