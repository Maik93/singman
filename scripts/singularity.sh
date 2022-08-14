#!/bin/bash
set -e

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "$0: \"${last_command}\" command failed with exit code $?"' ERR

# use '<file>.sif' for normal container, or use '<folder>' for sandbox container
CONTAINER_NAME="$1"
OVERLAY_NAME="${CONTAINER_NAME%.sif}.img" # remove '.sif' extension and add an '.img' extension

if [ $# -eq 1 ]; then
    ACTION="run"
else
    ACTION=$2
fi

## | ------------------- configure the paths ------------------ |

SCRIPT_PATH=`( cd "$(dirname "$0")" && pwd -P )`

IMAGES_PATH=`( cd "$SCRIPT_PATH/../images" && pwd -P )`
OVERLAYS_PATH=`( cd "$SCRIPT_PATH/../overlays" && pwd -P )`
# MOUNT_PATH=`( cd "$SCRIPT_PATH/../mount" && pwd -P )`

## | ----------------------- user config ---------------------- |

# the following are mutually exclusive
OVERLAY=false  # true: will load persistant overlay (overlay can be created with scripts/create_overlay.sh)
WRITABLE=false # true: will run it as --writable (works with --sandbox containers, image can be converted with scripts/convert_sandbox.sh)

CONTAINED=false # true: will isolate from the HOST's home
CLEAN_ENV=true  # true: will clean the shell environment before runnning container

# define what should be mounted from the host to the container
# [TYPE], [SOURCE (host)], [DESTINATION (container)]
MOUNTS=(
    # mount local directory inside the container
    # "type=bind" "$MOUNT_PATH" "/host"
)

## | ------------------ advanced user config ------------------ |

# not supposed to be changed by a normal user
DEBUG=true            # true: print debug infos while building the actual singularity command
DRY_RUN=false         # true: print the singularity command instead of running it
KEEP_ROOT_PRIVS=false # true: let root keep privileges in the container
FAKEROOT=false        # true: be superuser inside the container
DETACH_TMP=true       # true: do NOT mount host's /tmp

## | --------------------- arguments setup -------------------- |

CONTAINER_PATH=$IMAGES_PATH/$CONTAINER_NAME

# check container existance: it can be a '*.sif' file or a directory
if [[ ! -e $CONTAINER_PATH ]]; then
    echo "$CONTAINER_PATH does not exist"
    exit 1
fi

if $WRITABLE && $OVERLAY; then
    echo "Cannot be true both WRITABLE and OVERLAY"
    exit 1
fi

OVERLAY_ARG=""
if $OVERLAY; then
    if [ ! -f $OVERLAYS_PATH/$OVERLAY_NAME ]; then
        echo "Overlay file does not exist, initialize it with the 'create_overlay.sh' script"
        exit 1
    fi

    OVERLAY_ARG="-o $OVERLAYS_PATH/$OVERLAY_NAME"
    $DEBUG && echo "Debug: using overlay"
fi

WRITABLE_ARG=""
if $WRITABLE; then
    if [[ ! -d $CONTAINER_PATH ]]; then
        echo "$CONTAINER_PATH should be a sandbox directory, image can be converted with scripts/convert_sandbox.sh"
        exit 1
    fi
    WRITABLE_ARG="--writable"
    $DEBUG && echo "Debug: running as writable"
fi

CONTAINED_ARG=""
if $CONTAINED; then
    CONTAINED_ARG="--home /tmp/singularity/home:/home/$USER"
    $DEBUG && echo "Debug: running as contained"
fi

KEEP_ROOT_PRIVS_ARG=""
if $KEEP_ROOT_PRIVS; then
    KEEP_ROOT_PRIVS_ARG="--keep-privs"
    $DEBUG && echo "Debug: keep root privs"
fi

FAKE_ROOT_ARG=""
if $FAKEROOT; then
    FAKE_ROOT_ARG="--fakeroot"
    $DEBUG && echo "Debug: fake root"
fi

CLEAN_ENV_ARG=""
if $CLEAN_ENV; then
    CLEAN_ENV_ARG="-e"
    $DEBUG && echo "Debug: clean env"
fi

if $DETACH_TMP; then
    TMP_PATH="/tmp/singularity/tmp"
    DETACH_TMP_ARG="--bind $TMP_PATH:/tmp"
    [ ! -d /tmp/singularity/tmp ] && mkdir "$TMP_PATH"
    $DEBUG && echo "Debug: detaching tmp from the host"
else
    DETACH_TMP_ARG=""
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

if $DRY_RUN; then
    EXEC_CMD="echo"
else
    EXEC_CMD="eval"
fi

## | -------------------- set mount points -------------------- |

MOUNT_ARG=""
if ! $WRITABLE; then
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
    CMD="$@"
    $DEBUG && echo "Debug: ACTION run -> CMD is $CMD"
elif [[ $ACTION == "exec" ]]; then
    shift
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

$EXEC_CMD singularity $ACTION \
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
