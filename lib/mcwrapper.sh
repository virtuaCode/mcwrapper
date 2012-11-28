#! /bin/bash -

# absolutely, under no circumstances, let mcwrapper be run as root!!!!
if [[ `id -u` = 0 ]]; then
  echo "You have started mcwrapper as root." >&2
  echo "This is not recommended. Please run as an un-privilaged user." >&2
  echo "" >&2
  exit 99 # $EXIT_RUNNING_AS_ROOT
fi

MCWRAPPER_VERSION="1.5.1"

# initialize some variables about the location of mcwrapper and its support files.
pushd "$(dirname "$0")" &> /dev/null
MCWRAPPER_DIR="$PWD"
popd &> /dev/null
MCWRAPPER="$(basename "$0")"

MCWRAPPER_CONFIG_NAME="mcwrapper.conf"

#### Exit Codes

# no error
EXIT_SUCCESS=0

# generic bad exit code
EXIT_GENERIC_FAILURE=1

# bad commandline params
EXIT_BAD_PARAMS=2
EXIT_UNKNOWN_CONFIG_SETTING=3
EXIT_INVALID_ACTION=4

# server-running related failures
EXIT_SERVER_NOT_RUNNING=5
EXIT_SERVER_ALREADY_RUNNING=6
EXIT_SERVER_DISAPPEARED=7
EXIT_SERVER_CANNOT_START=8

# support file related codes:
EXIT_MINECRAFT_SERVER_NOT_FOUND=10
EXIT_NO_SERVER_PROPERTIES=11
EXIT_SERVER_LOG_NOT_FOUND=12

EXIT_MAKE_FIFO_FAILED=20
EXIT_SEND_COMMAND_FAILED=21

EXIT_NO_JAVA=30

# backup related codes:
EXIT_CANNOT_CREATE_BACKUP_DIR=50
EXIT_CANNOT_BACKUP_WORLD_DATA=51
EXIT_CANNOT_BACKUP_CONFIGS=52
EXIT_FAILED_TO_DELETE_SYMLINK=53
EXIT_ERORR_CREATING_SYMLINK=54
EXIT_BACKUPS_DISABLED=55
EXIT_LATEST_BACKUP_NOT_FOUND=56
EXIT_CANNOT_RESTORE_WORLD=57

EXIT_BAD_COMPRESSION_TYPE=60

# installer related codes:
EXIT_CANNOT_BACKUP_OLD_MINECRAFT_SERVER=70
EXIT_DOWNLOAD_MINECRAFT_SERVER_FAILED=71
EXIT_CREATE_MINECRAFT_SERVER_DIR_FAILED=72
EXIT_CANNOT_MOVE_MINECRAFT_SERVER=73
EXIT_EXISTING_MINECRAFT_SERVER_NOT_FOUND=74

# misc other codes:
EXIT_NOT_IMPLEMENTED=98
EXIT_RUNNING_AS_ROOT=99

#### End Exit Codes

# absolutely, under no circumstances, let mcwrapper be run as root!!!!
if [[ `id -u` = 0 ]]; then
  echo "You have started mcwrapper as root." >&2
  echo "This is not recommended. Please run as an un-privilaged user." >&2
  echo "" >&2
  exit 99 # $EXIT_RUNNING_AS_ROOT
fi

# default filename of the minecraft server
MINECRAFT_SERVER_NAME="minecraft_server.jar"

# filename of the minecraft server.properties file
MINECRAFT_SERVER_PROPERTIES_NAME="server.properties"

function print_usage {
  local MCWRAPPER_NAME=$( basename $0 )

  echo "USAGE:"
  echo "    $MCWRAPPER_NAME <action> [ <action_options> ]"
  echo ""
  echo "Action can be one of:"
  echo "    help    -- this usage screen"
  echo "    version -- outputs mcwrapper's version number"
  echo "    about   -- output information about mcwrapper"
  echo "    start   -- start the server if it's not already running"
  echo "    stop    -- stop a running server"
  echo "    restart -- restart a running server (issues stop, waits for it to stop, then starts)"
  echo "    status  -- whether the server is running or not"
  echo "    check   -- runs basic sanity checks"
  echo "    install -- runs an installation wizard to walk you through setup"
  echo "    update  -- update your Minecraft Server binary"
  echo "    log     -- follows the server log as it's written to"
  echo "    backup  -- safe backup of your Minecraft world data"
  echo "    restore -- restore a specified backup. Takes the path to the backup as an argument"
  echo "               restoring from a backup will cause a hard restart of the server and"
  echo "               all users will be disconnected. A non-destructive backup of current world"
  echo "               data will be created."
  echo "               example: $MCWRAPPER_NAME restore /usr/local/minecraft/backups/20121118235500"
  echo "    config  -- used to read configuration information about mcwrapper"
  echo "               example: $MCWRAPPER_NAME config serverpath"
  echo "               valid configuration parameters are:"
  echo "                *  serverpath       -- absolute path to minecraft_server.jar"
  echo "                *  serverdir        -- absolute path to server directory (containing minecraft_server.jar)"
  echo "                *  pidfile          -- absolute path to mcwrapper pidfile"
  echo "                *  pid              -- the pid of the currently running minecraft server process"
  echo "                *  pipe             -- absolute path to the mcwrapper command pipe"
  echo "                *  command          -- the command that will be used to launch the minecraft server"
  echo "                *  backupdir        -- the path to the backup directory"
  echo "                *  latestbackup     -- the path to the latest backup if there is one"
  echo "                *  backup-retention -- the number of backups to keep before deleting old ones"
  echo "    prop    -- used to read server.properties configuration information"
  echo "               best when used with external scripts"
  echo "               example: $MCWRAPPER_NAME prop level-name"
  echo "               if no property name is supplied, mcwrapper will print out all property keys from the file."
  echo "    command -- execute a minecraft server command. As an alternative to writing to the FIFO. Also aliased as 'cmd'"
  echo "For README and other documentation, see: https://github.com/spikegrobstein/mcwrapper"
  echo ""
}

function print_version {
  echo "mcwrapper $MCWRAPPER_VERSION"
}

function print_about {
  print_version
  echo "https://github.com/spikegrobstein/mcwrapper"
  echo "Finally, simplified management of your Minecraft server."
  echo "Start, stop, monitor, backup."
  echo "Run with no arguments to see usage."
  echo ""
}

# figure out where the config file lives
# first check to see if it's set in the MCWRAPPER_CONFIG_PATH
# then check: ./mcwrapper.conf, ~/.mcwrapper.conf, /etc/mcwrapper.conf
function get_config_path {

  # if it's defined in an ENV var, then let's use that  
  if [[ ! -z "$MCWRAPPER_CONFIG_PATH" ]]; then
    echo $MCWRAPPER_CONFIG_PATH
    return
  fi

  # check ./mcwrapper.conf
  local CURRENT_PATH="${MCWRAPPER_DIR}/${MCWRAPPER_CONFIG_NAME}"
  if [[ -e "$CURRENT_PATH" ]]; then
    echo $CURRENT_PATH
    return
  fi

  # check ~/.mcwrapper.conf
  CURRENT_PATH=~/".${MCWRAPPER_CONFIG_NAME}"
  if [[ -e "$CURRENT_PATH" ]]; then
    echo $CURRENT_PATH
    return
  fi

  # check /etc/mcwrapper.conf
  CURRENT_PATH="/etc/${MCWRAPPER_CONFIG_NAME}"
  if [[ -e "$CURRENT_PATH" ]]; then
    echo $CURRENT_PATH
    return
  fi

  # if we can't find the config, it's no big deal. we'll just use defaults and not read it.
}

# configure self from config file
function read_config {
  # set the global config path:
  CONFIG_PATH=`get_config_path`

  # if it's not found, don't do shit. stick with default values.
  if [[ -z "$CONFIG_PATH" || ! -e "$CONFIG_PATH" ]]; then
    return
  fi

  # it was found, so we read it by sourcing it.
  . "$CONFIG_PATH"  
}

function default_config {
  # path to the minecraft_server.jar
  # if this is not defined in the existing environment, define here.
  if [[ -z "$MINECRAFT_SERVER_PATH" ]]; then

    # check in the current directory first, then check one level up for minecraft.
    # if it's not actually where it thinks it is, it'll break when it tries to do something.
    # the resulting value of MINECRAFT_SERVER_PATH will be the last place that it looked.

    MINECRAFT_SERVER_PATH="${MCWRAPPER_DIR}/${MINECRAFT_SERVER_NAME}"

    if [[ ! -e "$MINECRAFT_SERVER_PATH" ]]; then
      MINECRAFT_SERVER_PATH="${MCWRAPPER_DIR}/../${MINECRAFT_SERVER_NAME}"
    fi

  fi

  # Java binary (uses one in PATH by default)
  JAVA_BIN="java"

  # Java VM settings (increasing these never hurts)
  MX_SIZE="1024M"
  MS_SIZE="1024M"

  # these can be relative or absolute paths
  # if relative, they're relative to the mcwrapper executable
  PID_FILE="mcwrapper.pid"
  COMMAND_PIPE="command_input"

  # the directory of the minecraft_server.jar based off $MINECRAFT_SERVER_PATH
  MINECRAFT_SERVER_DIR_PATH=`dirname $MINECRAFT_SERVER_PATH`

  BACKUP_DIRECTORY_PATH="backups"

  # what the name of the symlink is.
  LATEST_BACKUP_NAME="latest"

  # how many backups to keep in the backups directory
  # (we automatically delete old backups)
  # set to -1 to retain ALL backups (never delete)
  # set to 0 to completely disable backups.
  BACKUPS_TO_KEEP=5

  # set backup name to
  #   +%Y%m%d       -- just the datestamp; no time.
  #   +%Y%m%d%H%M%S -- full timestamp including hour, minute, second
  CURRENT_BACKUP_NAME=`date +%Y%m%d%H%M%S`
}

# run this to process a loaded config
# some variables require some modification before they can be used
# for example $PID_FILE which can be relative or absolute.
# if relative, we want to prepend the MCWRAPPER_DIR to it.
function process_config {

  # MINECRAFT_SERVER_PATH can be relative or absolute
  if [[ ! "$MINECRAFT_SERVER_PATH" =~ ^/ && ! "$MINECRAFT_SERVER_PATH" =~ "$MCWRAPPER_DIR" ]]; then
    MINECRAFT_SERVER_PATH="${MCWRAPPER_DIR}/$MINECRAFT_SERVER_PATH"
  fi
  MINECRAFT_SERVER_DIR_PATH=`dirname $MINECRAFT_SERVER_PATH`

  pushd "$MINECRAFT_SERVER_DIR_PATH" &> /dev/null
  MINECRAFT_SERVER_DIR=$(pwd)
  popd &> /dev/null

  # PID_FILE can be relative or absolute
  if [[ ! "$PID_FILE" =~ ^/ ]]; then
    PID_FILE="${MCWRAPPER_DIR}/$PID_FILE"
  fi

  # COMMAND_PIPE can be relative or absolute
  if [[ ! "$COMMAND_PIPE" =~ ^/ ]]; then
    COMMAND_PIPE="${MCWRAPPER_DIR}/$COMMAND_PIPE"
  fi

  # set MINECRAFT_SERVER_CMD
  # this may be overridden in the config, so if it's set already, don't set it.
  if [[ -z "$MINECRAFT_SERVER_CMD" ]]; then
    # command for starting minecraft_server.jar
    MINECRAFT_SERVER_CMD="$JAVA_BIN -Xmx${MX_SIZE} -Xms${MS_SIZE} -jar "$MINECRAFT_SERVER_PATH" nogui"
  fi

  # the path to the server.properties file
  if [[ -z "$SERVER_PROPERTIES_PATH" ]]; then
    SERVER_PROPERTIES_PATH=`dirname "$MINECRAFT_SERVER_PATH"`"/${MINECRAFT_SERVER_PROPERTIES_NAME}"
  fi

  # BACKUP_DIRECTORY_PATH can be relative or absolute
  if [[ ! "$BACKUP_DIRECTORY_PATH" =~ ^/ ]]; then
    BACKUP_DIRECTORY_PATH="${MCWRAPPER_DIR}/${BACKUP_DIRECTORY_PATH}"
  fi
}

function read_server_property {
  # takes 1 arg... the property name
  local PROP_NAME=$1;shift

  if [[ ! -e "$SERVER_PROPERTIES_PATH" ]]; then
    echo "Cannot locate server.properties path. ($SERVER_PROPERTIES_PATH)" >&2
    exit $EXIT_NO_SERVER_PROPERTIES
  fi

  # if no property is supplied, just dump the entire properties file's keys
  if [[ -z "$PROP_NAME" ]]; then
    cat "$SERVER_PROPERTIES_PATH" | grep -v '^#' | awk -F '=' '{ print $1 }'
    return
  fi

  cat "$SERVER_PROPERTIES_PATH" | grep "$PROP_NAME\=" | awk -F '=' '{ print $2 }'
}

function read_command {
  sleep 1

  # read from the command pipe via FD7 (needed for read timeout)
  # no special reason to use 7, it's just sufficiently high that it probably won't collide with anything.
  exec 7<> "$COMMAND_PIPE"

  # initialize INPUT to be empty string
  local INPUT=""

  # number of seconds between reads
  # this is needed to make sure the server is still running
  local READ_TIMEOUT=2

  while [[ "$INPUT" != 'stop' ]]; do
    read -t "$READ_TIMEOUT" -u 7 INPUT

    # if it timed out or got no input, then exit if server isnt' running.
    if [[ "$?" != 0 || -z "$INPUT" ]]; then
      check_is_running || exit $EXIT_SERVER_DISAPPEARED

      continue
    fi

    echo $INPUT

    # if the user said "stop" then exit after the command completes.
    if [[ "$INPUT" = "stop" ]]; then
      clean_up
      exit $EXIT_SUCCESS
    fi
  done
}

function send_command {
  check_is_running \
    || { echo "Server is NOT running. Not sending command" >&2 ; exit $EXIT_SERVER_NOT_RUNNING; }

  # echo the command into the command pipe to be picked up by the reader process:
  local COMMAND=$1
  (echo "$COMMAND" > "$COMMAND_PIPE") &> /dev/null \
   || { echo "Error sending command: '${COMMAND}' (${?})" >&2 ; exit $EXIT_SEND_COMMAND_FAILED; }
}

function create_pid {
  local PID_VALUE=$1
  echo $PID_VALUE > $PID_FILE
}

function remove_pid {
  # clean up PID file when done.
  rm $PID_FILE
}

# reads the pidfile and echos it
# returns 1 if the pidfile does not exist or if there was an error reading it.
function read_pid {
  if [[ ! -e "$PID_FILE" ]]; then
    #echo "Server not running!" >&2
    return $EXIT_SERVER_NOT_RUNNING
  fi

  local PID=`cat "$PID_FILE" 2>&1`

  if [[ $? != $EXIT_SUCCESS ]]; then
   return $EXIT_SERVER_NOT_RUNNING
  fi

  echo $PID
}

function check_is_running {
  local PID=`read_pid`

  # if read_pid returned a non-zero status, then we're not running
  if [[ $? != $EXIT_SUCCESS ]]; then
    return $EXIT_SERVER_NOT_RUNNING
  fi

  # check to see if we have a wrapper currently running
  # send a 0 signal to process to see if it's running.
  if ! kill -0 "$PID" &> /dev/null; then
    return $EXIT_SERVER_NOT_RUNNING
  fi

  return $EXIT_SUCCESS
}

function set_up_pipe {
  if [[ ! -p "$COMMAND_PIPE" ]]; then
    # if the file exists, but it's not a pipe, then we can't start.
    if [[ -e "$COMMAND_PIPE" ]]; then
      echo "Cannot create the pipe ($COMMAND_PIPE)" >&2
      echo "A file or directory already exists." >&2
      echo ""
      exit "$EXIT_MAKE_FIFO_FAILED"
    fi

    mkfifo "$COMMAND_PIPE"

    local PIPE_STATUS=$?

    if [[ $PIPE_STATUS != 0 ]]; then
      # if mkfifo failed, print error message, exit non-zero.
      echo "Error creating the pipe: $COMMAND_PIPE ($PIPE_STATUS)." >&2
      exit $EXIT_MAKE_FIFO_FAILED
    fi
  fi
}

function remove_pipe {
  if [[ -p "$COMMAND_PIPE" ]]; then
    rm "$COMMAND_PIPE"
  fi
}

# write the PID file and start'er up!
# don't start if we're already running.
function start_minecraft {
  if check_is_running; then
    echo "Server is already running. Exiting..." >&2
    exit $EXIT_SERVER_ALREADY_RUNNING
  fi

  set_up_pipe

  # now we go to the minecraft_server directory and start the server in a background process
  # need to go to the directory to make sure that the Minecraft server puts the files in the right place (it puts them in the CWD)
  pushd $MINECRAFT_SERVER_DIR_PATH &> /dev/null
  read_command | $MINECRAFT_SERVER_CMD &> /dev/null &

  create_pid $!

  # sleep for one second to make sure that the process actually started properly.
  sleep 1

  # verify that minecraft server actually started.
  if ! check_is_running; then
    echo "Could not start Minecraft Server." >&2
    exit $EXIT_SERVER_CANNOT_START
  fi
}

# stops the minecraft server by sending it the 'stop' command via the FIFO
function stop_minecraft {
  # if $BACKUP_ON_EXIT is non-zero length, then backup the world before exiting.
  if [[ ! -z "$BACKUP_ON_EXIT" ]]; then
    echo ""
    echo -n "Backing up world data before exiting..." >&2
    ( backup_world )
    # TODO: check status of backup_world. Don't say "Done" if we didn't back anything up.
    echo "Done." >&2
  fi

  send_command "stop"
}

function restart_minecraft {
  stop_minecraft
  wait_for_minecraft_to_stop
  start_minecraft
}

# waits for minecraft to stop
# TODO: Make this timeout and make time configurable.
function wait_for_minecraft_to_stop {
  if check_is_running; then
    # if it's still running... sleep for 1 second and try again
    echo -n "."
    sleep 1
    wait_for_minecraft_to_stop
  fi
}

function server_log_path {
  echo "${MINECRAFT_SERVER_DIR_PATH}/server.log"
}

function check_server_log_exists {
  local SERVER_LOG_PATH=`server_log_path`

  # make sure that the log file exists before trying to tail it.
  if [[ ! -e "$SERVER_LOG_PATH" ]]; then
    echo "Server log not found! ($SERVER_LOG_PATH)" >&2
    echo ""
    exit $EXIT_SERVER_LOG_NOT_FOUND
  fi
}

# tail and follow the server.log
# ^C to stop
function tail_server_log {
  local SERVER_LOG_PATH=`server_log_path`
  check_server_log_exists

  tail -F "$SERVER_LOG_PATH"
}

function sanity_check {
  # TODO: add checks to make sure that PID_FILE and COMMAND_PIPE are writable

  # make sure that there is a java binary installed in the PATH
  which "$JAVA_BIN" &> /dev/null
  if [[ $? != 0 ]]; then
   echo "The java binary is not found." >&2
   echo "Please install the necessary package(s) or specify the JAVA_BIN configuration option." >&2
   echo "" >&2
   exit $EXIT_NO_JAVA
  fi

  # check to make sure that things that need to exist exist.
  if [[ ! -e "$MINECRAFT_SERVER_PATH" ]]; then
    # the minecraft server path does not exist.
    echo "Minecraft server not found! (MINECRAFT_SERVER_PATH=$MINECRAFT_SERVER_PATH)" >&2
    echo "" >&2
    exit $EXIT_MINECRAFT_SERVER_NOT_FOUND
  fi
}

# performs cleanup after stopping mcwrapper
# removes pid and pipe
function clean_up {
  remove_pid
  remove_pipe
}

##########################################################################################
## Installer portion: ============>>>>>>>>>>>>

# runs through interactive installer
# confirm configuration
# download minecraft_server.jar
# sanity check
function run_installer () {
  echo "Welcome to the mcwrapper installer."
  echo "Before the Minecraft Server is installed, we must first confirm a few settings..."
  echo ""

  # check for configuration
  local CURRENT_CONFIG_PATH=`get_config_path`

  if [[ -z "$CURRENT_CONFIG_PATH" ]]; then
    echo "Using default configuration."
    echo "An example configuration is included in the mcwrapper package."
    echo "See mcwrapper.conf-example for details."
  else
    echo "mcwrapper config path: $CURRENT_CONFIG_PATH"
  fi
  echo ""

  # show where minecraft_server.jar will be installed

  echo "Minecraft Server Path: $MINECRAFT_SERVER_PATH"

  if [[ -e "$MINECRAFT_SERVER_PATH" ]]; then
    echo -n "Minecraft server already exists! Do you wish to overwrite? [y/N]: "
    read OVERWRITE_SERVER
    if [[ "$OVERWRITE_SERVER" != 'y' ]]; then
      echo ""
      echo "Not overwriting server. Thanks, bye!"
      echo ""
      exit $EXIT_SUCCESS
    fi

    backup_old_server
  fi

  echo -n "Is this where you wish to install the Minecraft Server? [Y/n]: "
  read INSTALL_PATH_CORRECT
  if [[ "$INSTALL_PATH_CORRECT" != 'y' && ! -z "$INSTALL_PATH_CORRECT" ]]; then
    echo ""
    echo "Please update your mcwrapper.conf and re-run this installer."
    echo ""
    exit $EXIT_SUCCESS
  fi

  echo "Downloading and installing Minecraft Server..."
  download_minecraft_server

  # ok, so now the server is downloaded and copied to the right location.

  echo "Minecraft is downloaded and in place. You can now start it by running the following command:"
  echo "$MCWRAPPER start"

  exit 0
}

# download the minecraft_server.jar file
# parse the minecraft.net download page and look for the download link for the server
# then download that to the necessary place
# if anything hard-fails, it prints an error message and exits.
function download_minecraft_server () {
  local MINECRAFT_SERVER_BASE_URL="http://www.minecraft.net"
  local MINECRAFT_SERVER_DOWNLOAD_PAGE="${MINECRAFT_SERVER_BASE_URL}/download"

  which curl \
    || { echo "curl does not appear to be installed. This is required to download the Minecraft server" >&2; exit $EXIT_NO_CURL; }

  # parse the download page and read the minecraft_server.jar download URI
  local MINECRAFT_SERVER_DOWNLOAD_URI=`curl --progress-bar "$MINECRAFT_SERVER_DOWNLOAD_PAGE" | grep -E -o 'href="[^"]*?minecraft_server.jar.*"' | awk -F '"' '{ print $2; }'`

  # check if there was an error grabbing the download page (either curl returns a bad value or we didn't find the URI)
  if [[ "$?" != "0" || -z "$MINECRAFT_SERVER_DOWNLOAD_URI" ]]; then
    echo "There was an error locating the download link. www.minecraft.net down?"
    echo ""
    exit $EXIT_DOWNLOAD_MINECRAFT_SERVER_FAILED
  fi

  # build the minecraft_server.jar download URL
  local MINECRAFT_SERVER_DOWNLOAD_URL="${MINECRAFT_SERVER_DOWNLOAD_URI}"

  local MINECRAFT_SERVER_TEMP_FILE="/tmp/minecraft_server.jar"

  # if the tempfile exists, delete it
  if [[ -e "$MINECRAFT_SERVER_TEMP_FILE" ]]; then
    rm "$MINECRAFT_SERVER_TEMP_FILE"
  fi

  echo "Downloading Minecraft server from: $MINECRAFT_SERVER_DOWNLOAD_URL"

  # download the server to the temp directory  
  curl --progress-bar -L -o "$MINECRAFT_SERVER_TEMP_FILE" "$MINECRAFT_SERVER_DOWNLOAD_URL"

  # assuming that was successful, make sure the directories exist and move the binary to the right location
  local CURL_RETURN=$?
  if [[ "$CURL_RETURN" != "0" ]]; then
    echo "An error occurred ($CURL_RETURN) while downloading minecraft_server.jar from: $MINECRAFT_SERVER_DOWNLOAD_URL"
    echo ""
    exit $EXIT_DOWNLOAD_MINECRAFT_SERVER_FAILED
  elif [[ ! -s "$MINECRAFT_SERVER_TEMP_FILE" ]]; then
    echo "Failed downloading the minecraft server."
    echo "This is usually caused by a server error on minecraft.net."
    echo ""
    exit $EXIT_DOWNLOAD_MINECRAFT_SERVER_FAILED
  fi

  # make sure directories exit
  mkdir -p "$MINECRAFT_SERVER_DIR_PATH"
  if [[ $? != 0 ]]; then
    echo "Failed creating the minecraft server directory ($MINECRAFT_SERVER_DIR_PATH)"
    echo ""
    exit $EXIT_CREATE_MINECRAFT_SERVER_DIR_FAILED
  fi

  # move the minecraft server to the right place:
  mv "$MINECRAFT_SERVER_TEMP_FILE" "$MINECRAFT_SERVER_PATH"

  # check for errors when moving the minecraft_server.jar file
  if [[ "$?" != 0 ]]; then
    echo "An error occurred when moving minecraft_server.jar to the install directory."
    echo ""
    exit $EXIT_CANNOT_MOVE_MINECRAFT_SERVER
  fi
}

# backs up an old minecraft_server.jar file before downloading a new one
# if something fails, it prints an error message and exits
function backup_old_server () {
  # back up the old minecraft server (just in case)
  mv "$MINECRAFT_SERVER_PATH" "${MINECRAFT_SERVER_PATH}.old"

  if [[ "$?" != "0" ]]; then
    echo "Failed backing up the old minecraft server!"
    echo ""
    exit $EXIT_CANNOT_BACKUP_OLD_MINECRAFT_SERVER
  fi
}

# basically the same as install without all of the confirmation levels
# if an existing minecraft server is not found, then bail.
function update_minecraft_server () {
  if [[ ! -e "$MINECRAFT_SERVER_PATH" ]]; then
    echo "Existing Minecraft Server not found! ($MINECRAFT_SERVER_PATH)"
    echo "Either run \`$MCWRAPPER install\` or make sure you install minecraft_server.jar in the above location."
    echo ""
    exit $EXIT_EXISTING_MINECRAFT_SERVER_NOT_FOUND
  fi

  echo "Updating server..."

  backup_old_server
  download_minecraft_server

  if ! check_is_running; then
    # server is not running, so just return
    return
  fi

  read -p "Would you like to restart Minecraft Server? [Y/n]: " INPUT
  if [[ -z "$INPUT" || "$INPUT" == 'y' ]]; then
    echo -n "Restarting Minecraft Server..."
    restart_minecraft
    echo "Done."
  fi

}

## End Installer portion.
##########################################################################################
## MCBackup portion: ============>>>>>>>>>>>>


# create the backup directory
# if it exists, this effectively does nothing.
function create_backup_directory () {
  mkdir -p "$CURRENT_BACKUP_PATH"

  if [[ $? != 0 ]]; then
    #an error occurred
    echo "An error occurred when creating the backup directory." >&2
    exit $EXIT_CANNOT_CREATE_BACKUP_DIR
  fi
}

# stop writing to the world file(s) after flushing the buffer
function stop_writing_world () {
  send_command "save-all"
  send_command "save-off"
}

# begin writing the world data again
function start_writing_world () {
  send_command "save-on"
}

# get the path to the current world directory
function world_dir_path () {
  local LEVEL_NAME=`read_server_property level-name`
  local WORLD_DATA_DIR="${MINECRAFT_SERVER_DIR_PATH}/${LEVEL_NAME}"

  echo $WORLD_DATA_DIR
}

# copy the world data and configuration
function do_backup () {
  local WORLD_DATA_DIR=$(world_dir_path)

  cp -R "$WORLD_DATA_DIR" "$CURRENT_BACKUP_PATH/"

  if [[ $? != 0 ]]; then
    #an error occurred
    echo "An error occurred when copying the world data." >&2
    exit $EXIT_CANNOT_BACKUP_WORLD_DATA
  fi

  cp -R "${MINECRAFT_SERVER_DIR_PATH}/"*.{txt,properties} "$CURRENT_BACKUP_PATH/"

  if [[ $? != 0 ]]; then
    #an error occurred
    echo "An error occurred when copying the configuration information" >&2
    exit $EXIT_CANNOT_BACKUP_CONFIGS
  fi

  if [[ ! -z "$COMPRESS_BACKUP" ]]; then
    # TODO: add support for bz2
    # TODO: make this code a little more readable without the secret, back alley variable updating.
    case "$COMPRESS_BACKUP" in
      zip )
        zip_backup
        ;;
      tgz )
        tgz_backup
        ;;
      * )
        echo "UKNOWN COMPRESSION TYPE: $COMPRESS_BACKUP"
        exit $EXIT_BAD_COMPRESSION_TYPE
        ;;
    esac

    # after the backup is compressed, remove the uncompressed version
    rm -rf "$CURRENT_BACKUP_PATH"

    # ARCHIVE_FILENAME gets set in the compressor ({tgz,zip}_backup) functions
    # we set CURRENT_BACKUP_PATH so the symlink gets pointed to the archive rather than the directory we just deleted
    CURRENT_BACKUP_PATH="${BACKUP_DIRECTORY_PATH}/${ARCHIVE_FILENAME}"
  fi
}


#TODO: there's some duplicate code here... should probably fix it.
# concept:
# create a compress_backup( $type ) function
# check for `type ${type}_backup` function, if it exists
# call it; it should have a signature like: somekind_backup( $current_backup_path )
# and return the path to the compressed backup
function tgz_backup {
  # cd to the backup directory
  # create new tgz backup
  pushd "$BACKUP_DIRECTORY_PATH"

  local FILENAME=`basename "$CURRENT_BACKUP_PATH"`
  ARCHIVE_FILENAME="${FILENAME}.tgz"

  tar cfz "$ARCHIVE_FILENAME" "$FILENAME"  

  popd
}

function zip_backup {
  pushd "$BACKUP_DIRECTORY_PATH"

  local FILENAME=`basename "$CURRENT_BACKUP_PATH"`
  ARCHIVE_FILENAME="${FILENAME}.zip"

  zip -q -r "$ARCHIVE_FILENAME" "$FILENAME"

  popd
}

function create_symlink () {
  # then we symlink the current backup to "latest" in backups directory
  if [[ -L "$LATEST_BACKUP_PATH" ]]; then
    # if the symlink already exists, delete it before creating it.
    rm "$LATEST_BACKUP_PATH"

    if [[ $? != 0 ]]; then
      #an error occurred
      echo "An error occurred when deleting the old symlink." >&2
      exit $EXIT_FAILED_TO_DELETE_SYMLINK
    fi
  fi

  # just the directory/filename of the current backup
  # this way, the symlink isn't an absolute path, so you can move the 
  # backup directory without issue.
  local NEW_BACKUP=`basename "$CURRENT_BACKUP_PATH"`

  ln -s "$NEW_BACKUP" "$LATEST_BACKUP_PATH"

  if [[ $? != 0 ]]; then
    #an error occurred
    echo "An error occurred when creating the symlink." >&2
    exit $EXIT_ERORR_CREATING_SYMLINK
  fi
}

# delete old backups
function cleanup_old_backups () {
  if [[ "$BACKUPS_TO_KEEP" = "-1" ]]; then
    # if we want infinite retention, then set BACKUPS_TO_KEEP to -1
    return
  fi

  echo "Cleaning up old backups..." >&2

  OLD_BACKUPS=`ls -r "$BACKUP_DIRECTORY_PATH" | grep -v "$LATEST_BACKUP_NAME" | tail -n +"${BACKUPS_TO_KEEP}"`

  for old_backup in $OLD_BACKUPS; do
    echo "Removing $old_backup" >&2
    rm -rf "${BACKUP_DIRECTORY_PATH}/$old_backup"
    if [[ $? != 0 ]]; then
      #an error occurred but don't exit.
      echo "An error occurred when deleting a previous backup: ${old_backup}." >&2
    fi
  done
}

# call this to go through the whole backup procedure
# makes sure backup directory exists, makes sure we don't back up a worldfile that's actively being written to, backs it up, symlinks it. everything.
function backup_world {
  if [[ "$BACKUPS_TO_KEEP" = "0" ]]; then
    # set BACKUPS_TO_KEEP to "0" to disable backups entirely.
    echo ""
    echo "Backups are disabled. Not backing anything up."
    exit $EXIT_BACKUPS_DISABLED
  fi

  # the path to the to-be-backed-up directory
  CURRENT_BACKUP_PATH="${BACKUP_DIRECTORY_PATH}/$CURRENT_BACKUP_NAME"

  # the path to the symlink to the above.
  LATEST_BACKUP_PATH="${BACKUP_DIRECTORY_PATH}/${LATEST_BACKUP_NAME}"

  create_backup_directory

  # stop writing world if we're running
  if [[ $(check_is_running) ]]; then
    stop_writing_world
  fi

  do_backup

  # start writing world only if we're running
  if [[ $(check_is_running) ]]; then
    start_writing_world
  fi

  create_symlink

  cleanup_old_backups
}

function path_to_latest_backup {
  local LATEST_BACKUP_PATH="${BACKUP_DIRECTORY_PATH}/${LATEST_BACKUP_NAME}"

  # if the link doesn't exist, then warn the user and exit with proper exit code
  if [[ ! -L "$LATEST_BACKUP_PATH" ]]; then
    echo "Latest backup not found. Either never created or not a link or something. ($LATEST_BACKUP_PATH)" >&2
    exit $EXIT_LATEST_BACKUP_NOT_FOUND
  fi

  # read the link to the latest backup
  local LATEST_BACKUP_LINK=`readlink "$LATEST_BACKUP_PATH"`

  # if the link to the latest backup is absolute, output that, otherwise, build the path and output that.
  if [[ "$LATEST_BACKUP_LINK" =~ ^/ ]]; then
    echo $LATEST_BACKUP_LINK
    exit $EXIT_SUCCESS
  fi

  echo "${BACKUP_DIRECTORY_PATH}/${LATEST_BACKUP_LINK}"
}

# given a path to a world backup, restore the current world with the contents
# when doing this, back up the current world, if it exists
function restore_world {
  local RESTORE_FROM=$1

  # check to make sure a RESTORE_FROM parameter is supplied
  [[ -z "$RESTORE_FROM" ]] \
    && { echo "USAGE: $0 restore <backup_name>" >&2; exit $EXIT_CANNOT_RESTORE_WORLD; }

  # check to make sure world dir exists and is a dir
  [[ -e "$RESTORE_FROM" && -d "$RESTORE_FROM" ]] \
    || { echo "Path does not appear to be a Minecraft world directory or does not exist." >&2; exit $EXIT_CANNOT_RESTORE_WORLD; }

  # back-up current world data and temporarily enable infinite retention
  # we don't want to inadvertently clobber any existing backups
  BACKUPS_TO_KEEP=-1
  backup_world

  local SERVER_IS_RUNNING=$(check_is_running && echo "RUNNING")
  local SERVER_IS_RUNNING
  local WORLD_DIR_PATH=$(world_dir_path)

  if server_is_running; then
    SERVER_IS_RUNNING="1"
    stop_server
  else
    SERVER_IS_RUNNING="0"
  fi

  # delete old world
  rm -rf "$WORLD_DIR_PATH"

  # copy world
  cp -R "$RESTORE_FROM" "$WORLD_DIR_PATH"
  echo "$RESTORE_FROM" > "$WORLD_DIR_PATH/RESTORED_FROM"

  # start server if it was running when we started
  if [[ "$SERVER_IS_RUNNING" = '1' ]]; then
    start_minecraft
  fi
}

## End MCBackup portion.
##########################################################################################

## begin meat of program:

if [[ $# -eq 0 ]]; then
  print_usage
  exit $EXIT_SUCCESS
fi

ACTION=$1;shift

# selfconfigure
default_config
read_config
process_config

# before most actions are run, sanity_check is called
# this ensures that things are configured properly before
# performing any actions that require specific configuration

case $ACTION in
  help|--help|-?|-h )
    print_usage
    exit $EXIT_SUCCESS
    ;;
  version|--version )
    print_version
    exit $EXIT_SUCCESS
    ;;
  about )
    print_about
    exit $EXIT_SUCCESS
    ;;
  start )
    sanity_check
    echo -n "Starting minecraft... "  
    start_minecraft
    echo "Done."
    exit $EXIT_SUCCESS
    ;;
  stop )
    sanity_check
    echo -n "Stopping minecraft... "
    stop_minecraft
    echo "Done."
    exit $EXIT_SUCCESS
    ;;
  restart )
    sanity_check
    echo -n "Restarting minecraft..."
    restart_minecraft
    echo " Done."
    exit $EXIT_SUCCESS
    ;;
  status )
    sanity_check
    if check_is_running; then
      echo "Server is running." >&2
      exit $EXIT_SUCCESS
    fi

    echo "Server is NOT running." >&2
    exit $EXIT_SERVER_NOT_RUNNING

    ;;
  check )
    sanity_check

    # sanity_check will exit with an exit code if it fails
    # so, assuming it didn't exit, everything is ok.

    echo "Everything looks OK!"
    exit $EXIT_SUCCESS
    ;;

  install )
    run_installer
    exit $EXIT_SUCCESS
    ;;
  update )
    sanity_check
    update_minecraft_server
    exit $EXIT_SUCCESS
    ;;
  backup )
    sanity_check
    echo "Backing up minecraft world data..."
    backup_world
    echo "Done."
    exit $EXIT_SUCCESS
    ;;
  restore )
    sanity_check
    RESTORE_FROM=$1;shift
    restore_world $RESTORE_FROM
    echo "Done."
    exit $EXIT_SUCCESS
    ;;
  log )
    sanity_check
    check_server_log_exists
    echo "Tailing from: ${MINECRAFT_SERVER_DIR_PATH}/server.log" >&2
    echo "Press ^C to cancel." >&2
    echo "-------------------------------------------------------------------------------------------" >&2

    tail_server_log

    exit $EXIT_SUCCESS
    ;;
  config )
    # dump info about the config
    CONFIG_SETTING=$1
    case $CONFIG_SETTING in
      serverpath )
        echo $MINECRAFT_SERVER_PATH
        exit $EXIT_SUCCESS
        ;;
      serverdir )
        echo $MINECRAFT_SERVER_DIR_PATH
        exit $EXIT_SUCCESS
        ;;
      pidfile )
        echo $PID_FILE
        exit $EXIT_SUCCESS
        ;;
      pid )
        check_is_running
        if [[ $? != 0 ]]; then
          echo "Server is NOT running." >&2
          exit $EXIT_SERVER_NOT_RUNNING
        fi

        echo `read_pid`
        exit $EXIT_SUCCESS
        ;;
      pipe )
        echo $COMMAND_PIPE
        exit $EXIT_SUCCESS
        ;;
      configfile )
        echo $CONFIG_PATH
        exit $EXIT_SUCCESS
        ;;
      command )
        echo $MINECRAFT_SERVER_CMD
        exit $EXIT_SUCCESS
        ;;
      backupdir )
        echo $BACKUP_DIRECTORY_PATH
        exit $EXIT_SUCCESS
        ;;
      latestbackup )
        echo $(path_to_latest_backup)
        exit $EXIT_SUCCESS
        ;;
      backup-retention )
        echo $BACKUPS_TO_KEEP
        exit $EXIT_STATUS
        ;;
      *)
        echo "Unknown config setting: $CONFIG_SETTING"
        exit $EXIT_UNKNOWN_CONFIG_SETTING
        ;;
    esac
    ;;
  prop )
    sanity_check
    PROP=$1    
    read_server_property $PROP
    exit $EXIT_SUCCESS
    ;;
  command|cmd )
    sanity_check
    COMMAND="$@"
    echo -n "sending: $COMMAND ... "
    send_command "$COMMAND"
    echo "Done."
    exit $EXIT_SUCCESS
    ;;
  * )
    echo "Invalid action: $ACTION" >&2
    echo "" >&2
    print_usage
    exit $EXIT_INVALID_ACTION
esac

exit $EXIT_SUCCESS


