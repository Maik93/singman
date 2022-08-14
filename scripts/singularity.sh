#!/bin/bash
set -e

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "$0: \"${last_command}\" command failed with exit code $?"' ERR

usage() {
    echo
    echo "Usage: `basename $0` [-o|--overlay] [-w|--write] [-d|--debug] [--dry-run] [-f|--fakeroot] [-c|--contained] image_name"
    echo "The following are mutually exclusive:"
    echo "  o,overlay   load persistant overlay (overlay can be created with scripts/create_overlay.sh)."
    echo "  w,writable  run it as --writable (works with sandbox containers, image can be converted with scripts/convert_sandbox.sh)."
    echo
    echo "  d,debug     print debug infos while building the actual singularity command."
    echo "    dry-run   print the singularity command instead of running it."
    echo "  f,fakeroot  be superuser inside the container."
    echo "  c,contained isolate from the HOST's home."
    echo "  h,help      help and usage message."
    echo
    echo "Positional arguments:"
    echo "  image_name  use '<file>.sif' for normal container, or use '<folder>' for sandbox container."
    echo
}

## | ----------------------- script args ---------------------- |

DEBUG=false
while getopts ":owcdfh-:" arg; do
    # support long options: https://stackoverflow.com/a/28466267/519360
    if [ "$arg" = "-" ]; then   # long option: reformulate arg and OPTARG
        arg="${OPTARG%%=*}"       # extract long option name
        OPTARG="${OPTARG#$arg}"   # extract long option argument (may be empty)
        OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
    fi
    case $arg in
    o | overlay)   OVERLAY=true;;
    w | writable)  WRITABLE=true;;
    c | contained) CONTAINED=true;;
    d | debug)     DEBUG=true;;
        dry-run)   DRY_RUN=true;;
    f | fakeroot)  FAKEROOT=true;;
    h | help)      echo "Singularity main wrapper."; usage; exit 0;;

    ??*) echo "Illegal option --$arg" >&2; usage; exit 1;;    # bad long option
    \?)  echo "Unknown option: -$OPTARG" >&2; usage; exit 1;; # bad short option
    :)   echo "Missing option argument for -$OPTARG" >&2; usage; exit 1;;
    esac
done

# get positional arguments
shift $(($OPTIND - 1))
CONTAINER_NAME=$1
OVERLAY_NAME="${CONTAINER_NAME%.sif}.img" # remove '.sif' extension and add an '.img' extension

[[ -z $CONTAINER_NAME ]] && echo "Missing required image_name." >&2 && usage && exit 1

if [ $# -eq 1 ]; then
    ACTION="run"
else
    ACTION=$2
fi

## | -------------------- configure paths --------------------- |

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`

IMAGES_PATH=`( cd "$SCRIPT_PATH/../images" && pwd -P )`
OVERLAYS_PATH=`( cd "$SCRIPT_PATH/../overlays" && pwd -P )`
# MOUNT_PATH=`( cd "$SCRIPT_PATH/../mount" && pwd -P )`

## | ------------------ advanced user config ------------------ |

CLEAN_ENV=true  # true: will clean the shell environment before runnning container

# define what should be mounted from the host to the container
# [TYPE], [SOURCE (host)], [DESTINATION (container)]
MOUNTS=(
    # mount local directory inside the container
    # "type=bind" "$MOUNT_PATH" "/host"
)

KEEP_ROOT_PRIVS=false # true: let root keep privileges in the container
DETACH_TMP=true       # true: do NOT mount host's /tmp

## | --------------------- arguments setup -------------------- |

CONTAINER_PATH=$IMAGES_PATH/$CONTAINER_NAME

# check container existance: it can be a '*.sif' file or a directory
if [[ ! -e $CONTAINER_PATH ]]; then
    echo "$CONTAINER_PATH does not exist"
    exit 1
fi

if ${WRITABLE:-false} && ${OVERLAY:-false}; then
    echo "Cannot be true both WRITABLE and OVERLAY"
    exit 1
fi

OVERLAY_ARG=""
if ${OVERLAY:-false}; then
    if [ ! -f $OVERLAYS_PATH/$OVERLAY_NAME ]; then
        echo "Overlay file does not exist, initialize it with the 'create_overlay.sh' script"
        exit 1
    fi

    OVERLAY_ARG="-o $OVERLAYS_PATH/$OVERLAY_NAME"
    $DEBUG && echo "Debug: using overlay"
fi

WRITABLE_ARG=""
if ${WRITABLE:-false}; then
    if [[ ! -d $CONTAINER_PATH ]]; then
        echo "$CONTAINER_PATH should be a sandbox directory, image can be converted with scripts/convert_sandbox.sh"
        exit 1
    fi
    WRITABLE_ARG="--writable"
    $DEBUG && echo "Debug: running as writable"
fi

CONTAINED_ARG=""
if ${CONTAINED:-false}; then
    CONTAINED_ARG="--home /tmp/singularity/home:/home/$USER"
    $DEBUG && echo "Debug: running as contained"
fi

KEEP_ROOT_PRIVS_ARG=""
if $KEEP_ROOT_PRIVS; then
    KEEP_ROOT_PRIVS_ARG="--keep-privs"
    $DEBUG && echo "Debug: keep root privs"
fi

FAKE_ROOT_ARG=""
if ${FAKEROOT:-false}; then
    FAKE_ROOT_ARG="--fakeroot"
    $DEBUG && echo "Debug: fake root"
fi

CLEAN_ENV_ARG=""
if $CLEAN_ENV; then
    CLEAN_ENV_ARG="-e"
    $DEBUG && echo "Debug: clean env"
fi

DETACH_TMP_ARG=""
if $DETACH_TMP; then
    TMP_PATH="/tmp/singularity/tmp"
    DETACH_TMP_ARG="--bind $TMP_PATH:/tmp"
    [ ! -d /tmp/singularity/tmp ] && mkdir "$TMP_PATH"
    $DEBUG && echo "Debug: detaching tmp from the host"
fi

# there are multiple ways of detecting that you are running nvidia GPUs:
NVIDIA_COUNT_1=$( lspci | grep -i -e "vga.*nvidia" | wc -l )
NVIDIA_COUNT_2=$( command -v nvidia-smi >> /dev/null 2>&1 && (nvidia-smi -L | grep -i "gpu" | wc -l) || echo 0 )

NVIDIA_ARG=""
if [ "$NVIDIA_COUNT_1" -ge "1" ] || [ "$NVIDIA_COUNT_2" -ge "1" ]; then

    # check if nvidia is active
    NVIDIA_NOT_ACTIVE=$( command -v nvidia-smi >> /dev/null 2>&1 && ( nvidia-smi | grep -i "NVIDIA-SMI has failed" | wc -l ) || echo 0 )

    if [ "$NVIDIA_NOT_ACTIVE" -ge "1" ]; then
        $DEBUG && echo "Debug: nvidia GPU detected, however, the driver is not active. Starting without using nvidia."
    else
        NVIDIA_ARG="--nv"
        $DEBUG && echo "Debug: using nvidia (nvidia counts: $NVIDIA_COUNT_1, $NVIDIA_COUNT_2)"
    fi
fi

if ${DRY_RUN:-false}; then
    $DEBUG && echo "Debug: dry run"
    EXEC_CMD="echo"
else
    EXEC_CMD="eval"
fi

## | -------------------- set mount points -------------------- |

MOUNT_ARG=""
if ! ${WRITABLE:-false}; then
    # prepare the mounting points, resolve the full paths
    for ((i=0; i < ${#MOUNTS[*]}; i++)); do
        ((i%3==0)) && TYPE[$i/3]="${MOUNTS[$i]}"
        ((i%3==1)) && SOURCE[$i/3]=$( realpath -e "${MOUNTS[$i]}" )
        ((i%3==2)) && DESTINATION[$i/3]=$( realpath -m "${MOUNTS[$i]}" )
    done

    # detect if the installed singularity uses the new --mount commnad
    singularity_help_mount=$( singularity run --help | grep -e "--mount" | wc -l )

    if [ "$singularity_help_mount" -ge "1" ]; then
        for ((i=0; i < ${#TYPE[*]}; i++)); do
            MOUNT_ARG="$MOUNT_ARG --mount ${TYPE[$i]},source=${SOURCE[$i]},destination=${DESTINATION[$i]}"
        done
    else
        for ((i=0; i < ${#TYPE[*]}; i++)); do
            MOUNT_ARG="$MOUNT_ARG --bind ${SOURCE[$i]}:${DESTINATION[$i]}:rw"
        done
    fi
fi

## | --------------------- run singularity -------------------- |

if [[ "$ACTION" == "run" ]]; then
    [ ! -z "$@" ] && shift
    CMD="${@}"
    $DEBUG && echo "Debug: ACTION run -> CMD is $CMD"
elif [[ $ACTION == "exec" ]]; then
    shift; shift
    CMD="/bin/bash -c '${@}'"
    $DEBUG && echo "Debug: ACTION exec -> CMD is $CMD"
elif [[ $ACTION == "shell" ]]; then
    CMD=""
    $DEBUG && echo "Debug: ACTION shell"
else
    echo "Action is missing"
    exit 1
fi

export SINGULARITYENV_DISPLAY=$DISPLAY

HOSTNAME=${CONTAINER_NAME%.sif} # remove trailing '.sif'
HOSTNAME=${HOSTNAME//_/-} # substitute all '_' with '-'

$EXEC_CMD singularity $ACTION \
    --hostname ${HOSTNAME^^} \
    $NVIDIA_ARG \
    $OVERLAY_ARG \
    $CONTAINED_ARG \
    $WRITABLE_ARG \
    $CLEAN_ENV_ARG \
    $FAKE_ROOT_ARG \
    $KEEP_ROOT_PRIVS_ARG \
    $MOUNT_ARG \
    $DETACH_TMP_ARG \
    $CONTAINER_PATH \
    $CMD
