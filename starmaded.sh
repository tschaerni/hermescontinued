#!/bin/bash
# Doomsider's and Titanmasher's Daemon Script for Starmade.  init.d script 7/10/13 based off of http://paste.boredomsoft.org/main.php/view/62107887
# All credits to Andrew for his initial work
# Version .17 6/8/2014
# Jstack for a dump has been added into the ebrake command to be used with the detect command to see if server is responsive.
# These dumps will be in starterpath/logs/threaddump.log and can be submitted to Schema to troubleshoot server crashes
# !!!You must update starmade.cfg for the Daemon to work on your setup!!!
# The daemon should be ran from the intended user as it detects and writes the current username to the configuration file

# Set the basics paths for the Daemon automatically.  This can be changed if needed for alternate configurations
# This sets the path of the script to the actual script directory.  This is some magic I found on stackoverflow http://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
DAEMONPATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/`basename "${BASH_SOURCE[0]}"`
#DAEMONPATH='/etc/init.d/starmaded'
CONFIGPATH="$(echo $DAEMONPATH | cut -d"." -f1).cfg"
# Set the starter path to the correct directory.  rev here is used to make the string backwards so that it can be cut at the last forward slash
STARTERPATH=$(echo $DAEMONPATH | rev | cut -d"/" -f2- | rev)
# Since this is a Daemon it can be called on from anywhere from just about anything.  This function below ensures the Daemon is using the proper user for the correct privileges
ME=$(whoami)

PLUGINSLOADED="false"

as_user() {
if [ "$ME" == "root" ] ; then
	echo "Not running as root. Aborting..."
else
	bash -c "$1"
fi
}

#------------------------------Daemon functions-----------------------------------------

sm_config() {
# Check to see if the config file is in place, if it is then see if an update is needed.  If it does not exist create it and other needed files and directories.
if [ -e $CONFIGPATH ]
then
	source $CONFIGPATH
else
# If no config file present set the username temporarily to the current user
	USERNAME=$(whoami)
	echo "Creating configuration file please edit configuration file (ie: starmade.cfg) or script may not function as intended"
# The following creates the directories and configuration files
	create_configpath
	source $CONFIGPATH
	sm_checkdir
	create_tipfile
	exit
fi
}
sm_checkdir() {
if [ ! -d "$STARTERPATH/logs" ]
then
	echo "No logs directory detected creating for logging"
	as_user "mkdir $STARTERPATH/logs"
fi
if [ ! -d "$PLAYERFILE" ]
then
	echo "No playerfile directory detected creating for logging"
	as_user "mkdir $PLAYERFILE"
fi
if [ ! -d "$FACTIONFILE" ]
then
	echo "No factionfile directory detected creating for logging"
	as_user "mkdir $FACTIONFILE"
fi
if [ ! -d "$STARTERPATH/oldlogs" ]
then
	echo "No oldlogs directory detected creating for logging"
	as_user "mkdir $STARTERPATH/oldlogs"
fi
}
sm_load_plugins() {
if [ "$PLUGINSLOADED" == "false" ]
then
	PLUGINSLOADED=true
	#Init plugin system. Search for plugins, take them over in plugin_list, include them via "source" and reduce the entries to the function name
	plugin_list=($(ls "${STARTERPATH}"/starmaded_plugin_*))
	echo "Found ${#plugin_list[@]} Plugins: ${plugin_list[@]}"
	i=0
	mySep="starmaded_plugin_"
	while [ $i -lt ${#plugin_list[@]} ]
	do
		source ${plugin_list[$i]}
		tmp="${plugin_list[$i]#*$mySep}"
		plugin_list[$i]="${tmp%%.sh*}"
		(( i++ ))
	done

	#call config from all plugins; Plugins have to check by themself if their configuration is already in the file
	for fn in ${plugin_list[@]}; do
		${fn}_config
	done
fi
}
sm_start() {
# Wipe and dead screens to prevent a false positive for a running Screenid
screen -wipe
# Check to see if StarMade is installed
if [ ! -d "$STARTERPATH/StarMade" ]
then
	echo "No StarMade directory found.  Either unzip a backup or run install"
	exit
fi
# Check if server is running already by checking for Screenid in the screen list
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
then
	echo "Tried to start but $SERVICE was already running!"
else
	echo "$SERVICE was not running... starting."
# Check to see if logs and other directories exists and create them if they do not
	sm_checkdir
# Make sure screen log is shut down just in case it is still running
    if ps aux | grep -v grep | grep $SCREENLOG >/dev/null
    then
		echo "Screenlog detected terminating"
		PID=$(ps aux | grep -v grep | grep $SCREENLOG | awk '{print $2}')
		kill $PID
    fi
# Check for the output.log and if it is there move it and save it with a time stamp
    if [ -e /dev/shm/output.log ]
    then
		MOVELOG=$STARTERPATH/oldlogs/output_$(date '+%b_%d_%Y_%H.%M.%S').log
		as_user "mv /dev/shm/output.log $MOVELOG"
    fi
# Execute the server in a screen while using tee to move the Standard and Error Output to output.log
	cd $STARTERPATH/StarMade
	#as_user "screen -dmS $SCREENID -m sh -c 'ionice -c2 -n0 nice -n -10 rlwrap java -Xmx$MAXMEMORY -Xms$MINMEMORY -XX:ParallelGCThreads=4 -d64 -jar $SERVICE -server -port:$PORT 2>&1 | tee /dev/shm/output.log'"
	as_user "screen -dmS $SCREENID -m sh -c 'nice -n 10 rlwrap java -Xmx$MAXMEMORY -Xms$MINMEMORY -XX:ParallelGCThreads=8 -Xincgc -d64 -Dcom.sun.management.jmxremote.host=78.46.81.50 -Dcom.sun.management.jmxremote.port=3333 -Dcom.sun.management.jmxremote.rmi.port=3333 -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -jar $SERVICE -server -port:$PORT 2>&1 | tee /dev/shm/output.log'"
# Created a limited loop to see when the server starts
    for LOOPNO in {0..7}
	do
		if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
		then
			break
		else
			echo "Service not running yet... Waiting...."
			sleep 1
		fi
	done
    if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
    then
		echo "$SERVICE is now running."
		as_user "rm $ONLINELOG 2> /dev/null"
# Start sm_screemlog if logging is set to yes
		if [ "$LOGGING" = "YES" ]
		then
			sm_screenlog
		fi
    else
		echo "Could not start $SERVICE."
    fi
fi
}
sm_stop() {
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
then
	echo "$SERVICE is running... stopping."
# Issue Chat and a command to the server to shutdown
	as_user "screen -p 0 -S $SCREENID -X eval 'stuff \"/chat Server restart will be back in some seconds.\"\015'"
	as_user "screen -p 0 -S $SCREENID -X eval 'stuff \"/shutdown 60\"\015'"
# Give the server a chance to gracefully shutdown if not kill it and then seg fault it if necessary
	sleep 60
	for LOOPNO in {0..60}
	do
		if ps aux | grep $SERVICE | grep -v grep | grep -v rlwrap | grep -v tee | grep port:$PORT >/dev/null
		then
			sleep 1
		else
			echo $SERVICE took $LOOPNO seconds to close
			break
		fi
	done
	if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
	then
		echo $SERVICE is taking too long to close and may be frozen. Forcing shut down
		PID=$(ps aux | grep -v grep | grep $SERVICE | grep -v tee | grep -v rlwrap | grep port:$PORT | awk '{print $2}')
		kill $PID
		for LOOPNO in {0..30}
		do
			if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
			then
				sleep 1
			else
				echo $SERVICE took $(($LOOPNO + 30)) seconds to close, and had to be force shut down
				break
			fi
		done
		if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
		then
			PID=$(ps aux | grep -v grep | grep $SERVICE | grep -v tee | grep port:$PORT | awk '{print $2}')
			kill -9 $PID
# This was added in to troubleshoot freezes at the request of Schema
			screen -wipe
			$SERVICE took too long to close. $SERVICE had to be killed
		fi
	fi
	else
		echo "$SERVICE not running"
  fi
}
sm_backup() {
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
then
	echo "$SERVICE is running! Will not start backup."
else
	echo "Backing up starmade data"
# Check to see if zip is installed, it isn't on most minimal server builds.
if command -v zip >/dev/null
then
	if [ -d "$BACKUP" ]
	then
		cd $STARTERPATH
		as_user "zip -r $BACKUPNAME$(date '+%b_%d_%Y_%H.%M.%S').zip StarMade"
		as_user "mv $BACKUPNAME*.zip $BACKUP"
		echo "Backup complete"
	else
		echo "Directory not found attempting to create"
		cd $STARTERPATH
		as_user "mkdir $BACKUP"
# Create a zip of starmade with time stamp and put it in backup
		as_user "zip -r $BACKUPNAME$(date '+%b_%d_%Y_%H.%M.%S').zip StarMade"
		as_user "mv $BACKUPNAME*.zip $BACKUP"
		echo "Backup complete"
	fi
else
	echo "Please install Zip"
	fi
fi
}
sm_upgrade() {
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep -v rlwrap | grep port:$PORT >/dev/null
then
	echo "$SERVICE is running! Will not start Install"
else
	echo "Upgrading Starmade"
	cd $STARTERPATH
# Execute the starters update routine for a headless server
	as_user "java -jar StarMade-Starter.jar -nogui"
fi
echo "Upgrade Complete"
}
sm_cronstop() {
# Stop Cronjobs to prevent things from running during maintenance
as_user "crontab -r"
echo "Cronjobs stopped"
}
sm_cronrestore() {
# Restore Cronjobs to original state
cd $STARTERPATH
as_user "crontab < cronbackup.dat"
echo "Cronjobs restored"
}
sm_cronbackup() {
# Backup Cronjobs
cd $STARTERPATH
as_user "crontab -l > cronbackup.dat"
echo "Cronjobs backed up"
}
sm_ebrake() {
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
then
	PID=$(ps aux | grep -v grep | grep $SERVICE | grep -v tee | grep port:$PORT | awk '{print $2}')
	jstack $PID >> $STARTERPATH/logs/threaddump.log
	kill $PID
# Give server a chance to gracefully shut down
	for LOOPNO in {0..30}
	do
		if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
		then
			sleep 1
		else
			echo $SERVICE closed after $LOOPNO seconds
			break
		fi
	done
# Check to make sure server is shut down if not kill it with a seg fault.
	if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
	then
		PID=$(ps aux | grep -v grep | grep $SERVICE | grep -v tee | grep port:$PORT | awk '{print $2}')
# This was added in to troubleshoot freezes at the request of Schema
		jstack $PID >> $STARTERPATH/logs/threaddump.log
		kill -9 $PID
		echo $SERVICE has to be forcibly closed. A thread dump has been taken and is saved at $STARTERPATH/logs/threaddump.log and should be sent to schema.
		screen -wipe
	fi
else
	echo "$SERVICE not running"
fi
}
sm_detect() {
# Special thanks to Fire219 for providing the means to test this script.  Appreciation to Titansmasher for collaboration.
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
then
# Add in a routine to check for STDERR: [SQL] Fetching connection
# Send the curent time as a serverwide message
	if (tail -5 /dev/shm/output.log | grep "Fetching connection" >/dev/null)
	then
		echo "Database Repairing itself"
	else
# Set the current to Unix time which is number of seconds since Unix was created.  Next send this as a PM to Unix time which will cause the console to error back Unix time.
		CURRENTTIME=$(date +%s)
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $CURRENTTIME testing\n'"
		echo "Unix time is $CURRENTTIME"
		sleep 10
# Check output.log to see if message was recieved by server.  The tail variable may need to be adjusted so that the
# log does not generate more lines that it looks back into the log
		if tac /dev/shm/output.log | grep -m 1 "$CURRENTTIME" >/dev/null
		then
			echo "Server is responding"
			echo "Server time variable is $CURRENTTIME"
        else
			echo "Server is not responding, shutting down and restarting"
			sm_ebrake
			sm_start
		fi
	fi
else
	echo "Starmade is not running!"
	sm_start
fi
}
sm_screenlog () {
# Start logging in a screen
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
then
	echo "Starmade is running checking for logging."
# Make sure smlog is not already running
	if ps aux | grep $SCREENLOG | grep -v grep >/dev/null
	then
		echo "Logging is already running"
	else
		echo "Starting Logging"
# Check to see if existing screen log exists and if so move and rename it
		if [ -e $STARTERPATH/logs/screen.log ]
		then
			MOVELOG=$STARTERPATH/oldlogs/screen_$(date '+%b_%d_%Y_%H.%M.%S').log
			as_user "mv $STARTERPATH/logs/screen.log $MOVELOG"
		fi
		STARTLOG="$DAEMONPATH log"
		as_user "screen -dmS $SCREENLOG -m sh -c '$STARTLOG 2>&1 | tee $STARTERPATH/logs/screen.log'"
	fi
fi
}
sm_status () {
# Check to see is Starmade is running or not
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
then
	echo "Starmade Server is running."
else
	echo "Starmade Server is NOT running."
fi
}
sm_restore() {
# Checks for server running and then restores the given backup zip file.  It pulls from the backup directory so no path is needed.
if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
then
	echo "Starmade Server is running."
	else
	cd $BACKUP
	as_user "unzip -o $2 -d $STARTERPATH"
	echo "Server $2 is restored"
fi
}
sm_dump() {
# Check to see if server is running and if so pass the second argument as a chat command to server.  Use quotes if you use spaces.
if command -v jstack >/dev/null
then
	if ps aux | grep $SERVICE | grep -v grep | grep -v tee | grep port:$PORT >/dev/null
	then
		if [ "$#" -ne "2" ]
		then
			echo "Usage - smdump <amount of thread dumps> <amount of delay between dumps> smdump 2 10"
			exit
		fi
		PID=$(ps aux | grep -v grep | grep $SERVICE | grep -v tee | grep port:$PORT | awk '{print $2}')
		count=$2
		delay=$3
		while [ $count -gt 0 ]
		do
			jstack $PID >> $STARTERPATH/logs/threaddump$(date +%H%M%S.%N).log
			sleep $delay
			let count--
		done
		else
		echo "$SERVICE not running"
	fi
else
echo "Please install Java JDK (ie: openjdk-7-jdk) to make dumps"
fi
}
sm_help() {
echo "updatefiles - Updates all stored files to the latest format, if a change is needed"
echo "start - Starts the server"
echo "stop - Stops the server with a server message and countdown approx 2 mins"
echo "ebrake - Stop the server without a server message approx 30 seconds"
echo "restore filename - Selected file unzips into the parent folder of starmade"
echo "backup - backs up current Starmade directory as zip"
echo "backupstar - Stops cron and server, makes backup, restarts cron and server"
echo "status - See if server is running"
echo "cronstop - Removes all cronjobs"
echo "cronrestore - Restores all cronjobs"
echo "cronbackup - Backs up your cron file"
echo "upgrade - Runs the starters upgrade routine"
echo "upgradestar - Stops cron and server, runs upgrade, restarts cron and server"
echo "restart - Stops and starts server"
echo "bankfee - Bill the taxes for using the Banksystem"
echo "detect - See if the server is frozen and restart if it is."
echo "log - Logs admin, chat, player, and kills."
echo "screenlog - Starts the logging function in a screen"
echo "dump - Do a thread dump with number of times and delay between them"
echo "box - Send a colored message box.  Usage: box <red|blue|green> <playername (optional)> <message>"
}
sm_log() {
#Saves the PID of this function being run
SM_LOG_PID=$$
# Chat commands are controlled by /playerfile/playername which contains the their rank and
# rankcommands.log which has ranks followed by the commands that they are allowed to call
echo "Logging started at $(date '+%b_%d_%Y_%H.%M.%S')"
autovoteretrieval &
randomhelptips &
create_rankscommands
create_creditstatusfile
# Create the playerfile folder if it doesnt exist
	mkdir -p $PLAYERFILE
	OLDBYTECOUNT=0
# This while loop runs as long as starmade stays running
	while (ps aux | grep $SERVICE | grep -v -e grep -e tee | grep port:$PORT >/dev/null)
	do
		sleep 0.1
#First check if the byte-count changed, because wc -c ist over 50 times faster than wc -l
		BYTECOUNT=$(wc -c /dev/shm/output.log)
		BYTECOUNT=${BYTECOUNT// *}
		if [ "$BYTECOUNT" -eq "$OLDBYTECOUNT" ]
		then
			continue
		fi
		OLDBYTECOUNT=$BYTECOUNT
# Uses Cat to calculate the number of lines in the log file
		NUMOFLINES=$(wc -l /dev/shm/output.log)
		NUMOFLINES=${NUMOFLINES// *}
# In case Linestart does not have a value give it an interger value of 1.  The prevents a startup error on the script.
		if [ -z "$LINESTART" ]
		then
			LINESTART=$NUMOFLINES
#			echo "Start at line $LINESTART"
		fi
# If the number of lines read from the log file is greater than last line read + 1 from the log then feed more lines.
		if [ "$NUMOFLINES" -gt "$LINESTART" ]
		then
#     		echo "$NUMOFLINES is the total lines of the log"
#     		echo "$LINESTART is linestart"
			((LINESTART++))
			OLD_IFS=$IFS
# This sets the field seperator to use \n next line instead of next space.  This makes it so the array is a whole sentence not a word
			IFS=$'\n'
# Linestring is stored as an array of every line in the log
			LINESTRING=( $(awk "NR==$LINESTART, NR==$NUMOFLINES" /dev/shm/output.log) )
			IFS=$OLD_IFS
			LINESTART=$NUMOFLINES
#			echo "$LINESTART is adjusted linestart"
		else
			LINESTRING=()
		fi
# Search strings that the logging function is looking to trigger events
		SEARCHWARNING="WARNING"
		SEARCHRAIL="[RAIL]"
		SEARCHLOGIN="[SERVER][LOGIN] login received. returning login info for RegisteredClient: "
		SEARCHREMOVE="[SERVER][DISCONNECT] Client 'RegisteredClient:"
		SEARCHCHAT="[CHANNELROUTER] RECEIVED MESSAGE ON Server(0): [CHAT]"
#		SEARCHCHAT="[CHAT]"
		SEARCHADMIN="[ADMIN COMMAND]"
		SEARCHINIT="SPAWNING NEW CHARACTER FOR PlS"
		SEARCHFACTIONCHANGE="is changing faction ("
		SEARCHFACTIONTURN="[FACTIONMANAGER] faction update took:"
		SEARCHCHANGE="has players attached. Doing Sector Change for PlS"
# Linenumber is set to zero and the a while loop runs through every present array in Linestring
		LINENUMBER=0
		while [ -n "${LINESTRING[$LINENUMBER]+set}" ]
		do
#		echo "Current Line in Array $LINENUMBER"
		CURRENTSTRING=${LINESTRING[$LINENUMBER]}
		((LINENUMBER++))
# Case statement here is used to match search strings from the current array or line in linestring
		case "$CURRENTSTRING" in
			*"$SEARCHWARNING"*)
				continue
				;;
			*"$SEARCHRAIL"*)
				continue
				;;
			*"$SEARCHLOGIN"*)
#				echo "Login detected"
#				echo $CURRENTSTRING
				log_on_login $CURRENTSTRING &
				;;
			*"$SEARCHREMOVE"*)
#				echo "Remove detected"
#				echo $CURRENTSTRING
				log_playerlogout $CURRENTSTRING &
				;;
 			*"$SEARCHCHAT"*)
#				echo "Chat detected"
#				echo $CURRENTSTRING
				log_chatcommands $CURRENTSTRING &
				log_chatlogging $CURRENTSTRING &
				;;
			*"$SEARCHADMIN"*)
#				echo "Admin detected"
#				echo $CURRENTSTRING
				log_admincommand $CURRENTSTRING &
				;;
			*"$SEARCHINIT"*)
#				echo "Init detected"
				log_initstring $CURRENTSTRING &
				;;
			*"$SEARCHFACTIONCHANGE"*)
				log_factionchange "$CURRENTSTRING" &
				;;
			*"$SEARCHCHANGE"*)
				log_sectorchange $CURRENTSTRING &
				;;
			*"$SEARCHFACTIONTURN"*)
				check_factions &
				check_credits &
				#use ;& to do also the next case statement
				;&
			*)
# Default: pass the CURRENTSTRING to all plugins in list
				for fn in ${plugin_list[@]}; do
					$fn "$CURRENTSTRING"
				done
				;;
			esac
#			echo "all done"
		done
	done
}
parselog(){
		SEARCHLOGIN="[SERVER][LOGIN] login received. returning login info for RegisteredClient: "
		SEARCHREMOVE="[SERVER][DISCONNECT] Client 'RegisteredClient:"
		SEARCHCHAT="[CHAT]"
		SEARCHCHANGE="has players attached. Doing Sector Change for PlS"
		SEARCHBUY="[BLUEPRINT][BUY]"
		SEARCHBOARD="[CONTROLLER][ADD-UNIT]"
		SEARCHDOCK="NOW REQUESTING DOCK FROM"
		SEARCHUNDOCK="NOW UNDOCKING:"
		SEARCHADMIN="[ADMIN COMMAND]"
		SEARCHKILL="Announcing kill:"
		SEARCHDESTROY="PERMANENTLY DELETING ENTITY:"
		SEARCHINIT="SPAWNING NEW CHARACTER FOR PlS"
		case "$@" in
			*"$SEARCHLOGIN"*)
#				echo "Login detected"
#				echo $@
				log_on_login $@ &
				;;
			*"$SEARCHREMOVE"*)
#				echo "Remove detected"
#				echo $@
				log_playerlogout $@ &
				;;
 			*"$SEARCHCHAT"*)
#				echo "Chat detected"
#				echo $@
				log_chatcommands $@ &
				log_chatlogging $@ &
				;;
			*"$SEARCHADMIN"*)
#				echo "Admin detected"
#				echo $@
				log_admincommand $@ &
				;;
			*"$SEARCHINIT"*)
#				echo "Init detected"
				log_initstring $@ &
				;;
			*)
				;;
			esac
}
sm_box() {
PRECEIVE=$(ls $PLAYERFILE)
#echo "Players $PRECEIVE"
ISPLAYER=$3
#echo "Possible playername $ISPLAYER"
if [[ $PRECEIVE =~ $ISPLAYER ]]
then
	echo "player found"
	MESSAGE=${@:4}
	case "$2" in
		*"green"*)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_to info $3 \'$MESSAGE\'\n'"
		;;
		*"blue"*)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_to warning $3 \'$MESSAGE\'\n'"
		;;
		*"red"*)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_to error $3 \'$MESSAGE\'\n'"
		;;
		*)
		;;
	esac
else
	echo "No player found"
	MESSAGE=${@:3}
	case "$2" in
		*"green"*)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \'$MESSAGE\'\n'"
		;;
		*"blue"*)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast warning \'$MESSAGE\'\n'"
		;;
		*"red"*)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast error \'$MESSAGE\'\n'"
		;;
		*)
		;;
	esac
fi
}
#------------------------------Core logging functions-----------------------------------------
copy_logs_to_workingdirectory() {
#If there are still files of us in /dev/shm move them back
move_logs_to_storagedirectory
#Factionfiles
as_user "mkdir /dev/shm/sm_factionfiles"
as_user "cp '$FACTIONFILE/'* /dev/shm/sm_factionfiles/"
#Playerfiles
as_user "mkdir /dev/shm/sm_playerfiles"
as_user "cp '$PLAYERFILE/'* /dev/shm/sm_playerfiles/"

#Plugin have to copy their files to /dev/shm/sm_* by themself.
#The move back function moves all sm_* folders back to starterpath/ and removes the sm_ prefix
}

move_logs_to_storagedirectory() {
if [ -e "/dev/shm/sm_factionfiles" ]
then
	as_user "mv /dev/shm/sm_factionfiles/* '$FACTIONFILE/'"
	as_user "rmdir /dev/shm/sm_factionfiles"
fi
if [ -e "/dev/shm/sm_playerfiles" ]
then
	as_user "mv /dev/shm/sm_playerfiles/* '$PLAYERFILE/'"
	as_user "rmdir /dev/shm/sm_playerfiles"
fi
for directory in /dev/shm/sm_*; do
	if [ -e "$directory" ]
	then
		directory=${directory/*\/sm_}
		as_user "mv /dev/shm/sm_$directory/* '$STARTERPATH/$directory'"
		as_user "rmdir /dev/shm/sm_$directory"
	fi
done
}

log_playerinfo() {
#Checks if the player has a mailbox file
#echo "$1 is the player name"
create_playerfile $1
as_user "screen -p 0 -S $SCREENID -X stuff $'/player_info $1\n'"
sleep 2
if tac /dev/shm/output.log | grep -m 1 -A 10 "Name: $1" >/dev/null
then
	extra_newlines=0
	OLD_IFS=$IFS
	IFS=$'\n'
#echo "Player info $1 found"
	PLAYERINFO=( $(tac /dev/shm/output.log | grep -m 1 -A 15 "Name: $1") )
	IFS=$OLD_IFS
	PNAME=${PLAYERINFO[0]/*Name: }
	PNAME=${PNAME// }
#echo "Player name is $PNAME"
	SMNAME=${PLAYERINFO[2]/*SM-NAME: }
#echo "StarMade-Registry name is $SMNAME"
	PIP=$(echo ${PLAYERINFO[1]} | cut -d\/ -f2)
#echo "Player IP is $PIP"
	PCREDITS=${PLAYERINFO[4]/*CREDITS: }
	PCREDITS=${PCREDITS// }
#echo "Credits are $PCREDITS"
#Faction descriptions may have newlines, so we have to check for them here
	while [[ ${PLAYERINFO[5+$extra_newlines]} != *"[SERVER-LOCAL-ADMIN] [PL]"* ]] && [ $extra_newlines -lt 10 ]
	do
		((extra_newlines++))
	done

	if [ $extra_newlines -lt 9 ]
	then
		PFACTION=${PLAYERINFO[5+$extra_newlines]//*FACTION: }
		PFACTION=${PFACTION/*id=}
		PFACTION=${PFACTION//,*}
		if [ "$PFACTION" == "null" ] || [ "$PFACTION" == "0" ]
		then
			PFACTION="None"
		fi
#echo "Faction id is $PFACTION"
		PSECTOR=$(echo ${PLAYERINFO[6+$extra_newlines]} | cut -d\( -f2 | cut -d\) -f1 | tr -d ' ')
#echo "Player sector is $PSECTOR"
		if echo ${PLAYERINFO[7+$extra_newlines]} | grep SHIP >/dev/null
		then
			PCONTROLOBJECT=$(echo ${PLAYERINFO[7+$extra_newlines]} | cut -d: -f2 | cut -d" " -f2 | cut -d\[ -f1)
#		echo "Player controlled object is $PCONTROLOBJECT"
			PCONTROLTYPE=$(echo ${PLAYERINFO[7+$extra_newlines]} | cut -d: -f2- | cut -d[ -f2 | cut -d] -f1)
#		echo "Player controlled entity type $PCONTROLTYPE"
		fi
		if echo ${PLAYERINFO[7+$extra_newlines]} | grep PLAYERCHARACTER >/dev/null
		then
			PCONTROLOBJECT=$(echo ${PLAYERINFO[7+$extra_newlines]} | cut -d: -f2 | cut -d" " -f2 | cut -d[ -f1)
#		echo "Player controlled object is $PCONTROLOBJECT"
			PCONTROLTYPE=Spacesuit
#		echo "Player controlled entity type $PCONTROLTYPE"
		fi
	else
#The Faction Description destroyed the PlayerInfo, use defaultvalues
		echo "Got malformated playerinfo for player $1"
		PFACTION="None"
		PSECTOR="0,0,0"
		PCONTROLTYPE="Spacesuit"
	fi
	PLASTUPDATE=$(date +%s)
#echo "Player file last update is $PLASTUPDATE"
	as_user "sed -i 's/SMName=.*/SMName=$SMNAME/g' $PLAYERFILE/$1"
	as_user "sed -i 's/CurrentIP=.*/CurrentIP=$PIP/g' $PLAYERFILE/$1"
	as_user "sed -i 's/CurrentCredits=.*/CurrentCredits=$PCREDITS/g' $PLAYERFILE/$1"
	as_user "sed -i 's/PlayerFaction=.*/PlayerFaction=$PFACTION/g' $PLAYERFILE/$1"
	as_user "sed -i 's/PlayerLocation=.*/PlayerLocation=$PSECTOR/g' $PLAYERFILE/$1"
	as_user "sed -i 's/PlayerControllingType=.*/PlayerControllingType=$PCONTROLTYPE/g' $PLAYERFILE/$1"
	as_user "sed -i 's/PlayerControllingObject=.*/PlayerControllingObject=$PCONTROLOBJECT/g' $PLAYERFILE/$1"
	as_user "sed -i 's/PlayerLastUpdate=.*/PlayerLastUpdate=$PLASTUPDATE/g' $PLAYERFILE/$1"
	as_user "sed -i 's/PlayerLoggedIn=.*/PlayerLoggedIn=Yes/g' $PLAYERFILE/$1"
	if [ "$PFACTION" != "None" ]
	then
		create_factionfile $PFACTION
		as_user "sed -i 's/FactionLastUpdate=.*/FactionLastUpdate=$PLASTUPDATE/g' $FACTIONFILE/$PFACTION"
	fi
fi
}
log_chatlogging() {
CHATGREP=$@
if [[ ! $CHATGREP == *WARNING* ]] && [[ ! $CHATGREP == *object* ]]
then
#	echo $CHATGREP
# If the chat contains : then - This filters out other non related chat output from console
	if echo $CHATGREP | grep ":" >/dev/null
	then
# If the chat is a whisper then
		if echo $CHATGREP | grep "\[WISPER\]" >/dev/null
		then
# Set variable for the person who is whispering
			PWHISPERED=$(echo $CHATGREP | cut -d\] -f4 | cut -d: -f1 | tr -d ' ')
# Set variable for the person who is recieving whisper
			PWHISPERER=$(echo $CHATGREP | cut -d\[ -f6 | cut -d\] -f1)
			PLAYERCHAT=$(echo $CHATGREP | cut -d\] -f6-)
# Format the whisper mesage for the log
			WHISPERMESSAGE="$(date '+%b_%d_%Y_%H.%M.%S') - \($PWHISPERER\) whispered to \($PWHISPERED\) '$PLAYERCHAT'"
			as_user "echo $WHISPERMESSAGE >> $CHATLOG"
# If not a whiper then
		fi
		if echo $CHATGREP | grep Server >/dev/null
		then
#			echo "CHAT DETECTED - $CHATGREP"
# Set variable for player name
			PLAYERCHATID=$(echo $CHATGREP | cut -d\) -f2 | cut -d: -f1 | tr -d ' ')
# Set variable for what the player said
			PLAYERCHAT=$(echo $CHATGREP | cut -d":" -f2- | tr -d \' | tr -d \")
# Format the chat message to be written for the chat log
			CHATMESSAGE="$(date '+%b_%d_%Y_%H.%M.%S') - \($PLAYERCHATID\)'$PLAYERCHAT'"
			as_user "echo $CHATMESSAGE >> $CHATLOG"
		fi
	fi
fi
}
log_chatcommands() {
# A big thanks to Titanmasher for his help with the Chat Commands.
#echo "This was passed to chat commands $1"
CHATGREP=$@
if [[ ! $CHATGREP == *WARNING* ]] && [[ ! $CHATGREP == *object* ]]
then
#	echo $CHATGREP
#	COMMAND=$(echo $CHATGREP | cut -d" " -f4)

	CUTSTRING=${CHATGREP#*=}
	PLAYERCHATID=${CUTSTRING%%]*}
#	echo $PLAYERCHATID
	CUTSTRING=${CUTSTRING#*=}
	CUTSTRING=${CUTSTRING#*=}
	CUTSTRING=${CUTSTRING#*=}
	COMMAND=${CUTSTRING%%]*}
#	echo $COMMAND

#	if [[ "$CHATGREP" =~ "[SERVER][CHAT][WISPER]" ]]
#	then
#		PLAYERCHATID=$(echo $CHATGREP | rev | cut -d"]" -f2 | rev | cut -d"[" -f2)
#	else
#		PLAYERCHATID=$(echo $CHATGREP | cut -d: -f1 | rev | cut -d" " -f1 | rev)
#	fi
	if [[ "${COMMAND:0:1}" == "!" ]]
	then
#	echo $CHATGREP
#	echo "this is the playerchatid $PLAYERCHATID"
# 				If the player does not have a log file, make one
		if [ -e $PLAYERFILE/$PLAYERCHATID ]
		then
			PLAYERFILEEXISTS=1
#		    echo "player has a playerfile"
		else
			log_playerinfo $PLAYERCHATID
		fi

#	Grab the chat command itself by looking for ! and then cutting after that
		CCOMMAND=( $(echo $COMMAND | cut -d! -f2-) )
#		CCOMMAND=( $(echo $CHATGREP | cut -d! -f2-) )
#	echo "first command is ${CCOMMAND[0]} parameter 1 ${CCOMMAND[1]} parameter 2 ${CCOMMAND[2]} parameter 3 ${CCOMMAND[3]} "
#				echo "Here is the command with variables ${CCOMMAND[@]}"
# 				Get the player rank from their log file
# 				echo "looking for player rank"
		PLAYERRANK=$(grep Rank= "$PLAYERFILE/$PLAYERCHATID" | cut -d= -f2)
# 	echo "$PLAYERRANK is the player rank"
#				Find the allowed commands for the current player rank
# 				echo "looking for allowed commands"
		ALLOWEDCOMMANDS=$(grep $PLAYERRANK $RANKCOMMANDS)
#	echo $ALLOWEDCOMMANDS
# 				Saves the command issued, player name and parameters to COMMANDANDPARAMETERS
#	Converts the command to uppercase, so lowercase commands can be used
		CCOMMAND[0]=$(echo ${CCOMMAND[0]} | tr [a-z] [A-Z])
		COMMANDANDPARAMETERS=(${CCOMMAND[0]} $PLAYERCHATID $(echo ${CCOMMAND[@]:1}))
#	echo "Here is the command and the parameters ${CCOMMAND[@]}"
#				echo "$PLAYERCHATID used the command ${COMMANDANDPARAMETERS[0]} with parameters ${COMMANDANDPARAMETERS[*]:2}"
#				Checks if the command exists. If not, sends a pm to the issuer
		function_exists "COMMAND_${COMMANDANDPARAMETERS[0]}"
		if [[ "$FUNCTIONEXISTS" == "0" ]]
		then	#		echo Exists
# Checks if the player has permission to use that command. -ALL- means they have access to all commands (Admin rank)
			if [[ "$ALLOWEDCOMMANDS" =~ "${COMMANDANDPARAMETERS[0]}" ]] || [[ "$ALLOWEDCOMMANDS" =~ "-ALL-" ]]
			then
# Echo's ALLOWED and then calls the function COMMAND_${COMMANDANDPARAMETERS[0]}
#						echo Allowed
				COMMAND_${COMMANDANDPARAMETERS[*]} &
#	 			$0 = Command name
#						$1 = playername
#						$2+ = parameter from command
			else
#			echo Disallowed
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm ${COMMANDANDPARAMETERS[1]} You do not have sufficient permission to use that command!\n'"
			fi
		else
#		echo Doesnt exist
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm ${COMMANDANDPARAMETERS[1]} Unrecognized command. Please try again or use !HELP\n'"
		fi
	fi
fi
}
log_admincommand() {
if [[ ! $@ == *org.schema.schine.network.server.AdminLocalClient* ]] && [[ ! $@ =~ "no slot free for" ]]
then
	# Format the admin command string to be written to the admin log
	ADMINSTR="$@ $(date '+%b_%d_%Y_%H.%M.%S')"
	as_user "echo '$ADMINSTR' >> $ADMINLOG"
fi
}
log_playerlogout() {
LOGOUTPLAYER=$(echo $@ | cut -d: -f2 | cut -d\( -f1 | tr -d ' ')
#echo "$LOGOUTPLAYER passed to playerlogout"

if [ -e $PLAYERFILE/$LOGOUTPLAYER ]
then
	PLAYERFILEEXISTS=1
#	echo "player has a playerfile"
else
	log_playerinfo $LOGOUTPLAYER
fi
# Use sed to change the playerfile PlayerLoggedIn to No
as_user "sed -i 's/PlayerLoggedIn=Yes/PlayerLoggedIn=No/g' $PLAYERFILE/$LOGOUTPLAYER"
# Echo current string and array to the guestboot as a log off
LOGOFF="$LOGOUTPLAYER logged off at $(date '+%b_%d_%Y_%H.%M.%S') server time"
as_user "echo $LOGOFF >> $GUESTBOOK"
as_user "sed -i '/$LOGOUTPLAYER/d' $ONLINELOG"
}
log_on_login() {
TMP="$@"
LOGINPLAYER=${TMP/*Client: }
LOGINPLAYER=${LOGINPLAYER// *}
#echo "$LOGINPLAYER logged in"
create_playerfile $LOGINPLAYER
DATE=$(date '+%b_%d_%Y_%H.%M.%S')
as_user "sed -i 's/JustLoggedIn=.*/JustLoggedIn=Yes/g' $PLAYERFILE/$LOGINPLAYER"
as_user "sed -i 's/PlayerLastLogin=.*/PlayerLastLogin=$DATE/g' $PLAYERFILE/$LOGINPLAYER"
LOGON="$LOGINPLAYER logged on at $(date '+%b_%d_%Y_%H.%M.%S') server time"
as_user "echo $LOGON >> $GUESTBOOK"
as_user "echo $LOGINPLAYER >> $ONLINELOG"
as_user "sort $ONLINELOG -o $ONLINELOG"
}
log_initstring() {
TMP="$@"
INITPLAYER=${TMP//*PlS[}
INITPLAYER=${INITPLAYER// *}
sleep 0.5
log_playerinfo $INITPLAYER
if grep -q "JustLoggedIn=Yes" $PLAYERFILE/$INITPLAYER
then
	LOGINMESSAGE="Welcome to the server $INITPLAYER! Type !HELP for chat commands"
	# A chat message that is displayed whenever a player logs in
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $INITPLAYER $LOGINMESSAGE\n'"
	as_user "sed -i 's/JustLoggedIn=.*/JustLoggedIn=No/g' $PLAYERFILE/$INITPLAYER"
fi
}

log_factionchange() {
PLAYER=${1/*PlS[}
PLAYER=${PLAYER// *}
NEWFACTION=${1//*is changing faction (}
NEWFACTION=${NEWFACTION//*to }
NEWFACTION=${NEWFACTION//; *}
if [ "$NEWFACTION" == "0" ]
then
	NEWFACTION="None"
fi

as_user "sed -i 's/PlayerFaction=.*/PlayerFaction=$NEWFACTION/g' $PLAYERFILE/$PLAYER"
create_factionfile $NEWFACTION
}

log_sectorchange(){
PLAYER="$@"
PLAYER=${PLAYER//*PlS[}
PLAYER=${PLAYER// *}
SECTOR="$@"
SECTOR=${SECTOR//*(}
SECTOR=${SECTOR/)}
SECTOR=${SECTOR// }
as_user "sed -i 's/PlayerLocation=.*/PlayerLocation=$SECTOR/g' $PLAYERFILE/$PLAYER"
}

#------------------------------Game mechanics-----------------------------------------

universeboarder() {
if [ "$UNIVERSEBOARDER" = "YES" ]
then
	XULIMIT=$(($(echo $UNIVERSECENTER | cut -d"," -f1) + $UNIVERSERADIUS))
	YULIMIT=$(($(echo $UNIVERSECENTER | cut -d"," -f2) + $UNIVERSERADIUS))
	ZULIMIT=$(($(echo $UNIVERSECENTER | cut -d"," -f3) + $UNIVERSERADIUS))
	XLLIMIT=$(($(echo $UNIVERSECENTER | cut -d"," -f1) - $UNIVERSERADIUS))
	YLLIMIT=$(($(echo $UNIVERSECENTER | cut -d"," -f2) - $UNIVERSERADIUS))
	ZLLIMIT=$(($(echo $UNIVERSECENTER | cut -d"," -f3) - $UNIVERSERADIUS))
	XCOORD=$(echo $1 | cut -d"," -f1)
	YCOORD=$(echo $1 | cut -d"," -f2)
	ZCOORD=$(echo $1 | cut -d"," -f3)
	if [ "$XCOORD" -ge "$XULIMIT" ] || [ "$YCOORD" -ge "$YULIMIT" ] || [ "$ZCOORD" -ge "$ZULIMIT" ] || [ "$XCOORD" -lt "$XLLIMIT" ] || [ "$YCOORD" -lt "$YLLIMIT" ] || [ "$ZCOORD" -lt "$ZLLIMIT" ]
	then
		if [ "$XCOORD" -ge "$XULIMIT" ]
		then
			NEWX=$(($XCOORD - $XULIMIT + $XLLIMIT))
		elif [ "$XCOORD" -lt "$XLLIMIT" ]
		then
			NEWX=$(($XCOORD - $XLLIMIT + $XULIMIT))
		else
			NEWX=$XCOORD
		fi
		if [ "$YCOORD" -ge "$YULIMIT" ]
		then
			NEWY=$(($YCOORD - $YULIMIT + $YLLIMIT))
		elif [ "$YCOORD" -lt "$YLLIMIT" ]
		then
			NEWY=$(($YCOORD - $YLLIMIT + $YULIMIT))
		else
			NEWY=$YCOORD
		fi
		if [ "$ZCOORD" -ge "$ZULIMIT" ]
		then
			NEWZ=$(($ZCOORD - $ZULIMIT + $ZLLIMIT))
		elif [ "$ZCOORD" -lt "$ZLLIMIT" ]
		then
			NEWZ=$(($ZCOORD - $ZLLIMIT + $ZULIMIT))
		else
			NEWZ=$ZCOORD
		fi
		sleep 4
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $2 You have warped to the opposite side of the universe! It appears you cant go further out...\n'"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/change_sector_for $2 $NEWX $NEWY $NEWZ\n'"
	fi
fi

}
randomhelptips(){
create_tipfile
while [ -e /proc/$SM_LOG_PID ]
do
	RANDLINE=$(($RANDOM % $(wc -l < "$TIPFILE") + 1))
	as_user "screen -p 0 -S $SCREENID -X stuff $'/chat $(sed -n ${RANDLINE}p $TIPFILE)\n'"
	sleep $TIPINTERVAL
done
}
autovoteretrieval(){
if [[ "$SERVERKEY" == "00000000000000000000" ]]
then
	NOKEY=YES
#	echo "No server key set for voting rewards"
else
	KEYURL="http://starmade-servers.com/api/?object=servers&element=voters&key=$SERVERKEY&month=current&format=xml"
	while [ -e /proc/$SM_LOG_PID ]
	do
		if [ "$(ls -A $PLAYERFILE)" ]
		then
			ALLVOTES=$(wget -q -O - $KEYURL)
			for PLAYER in $PLAYERFILE/*
			do
				PLAYER=$(echo $PLAYER | rev | cut -d"/" -f1 | rev )
				TOTALVOTES=$(echo $ALLVOTES | tr " " "\n" | grep -A1 "nickname>$PLAYER<" | tr "\n" " " | cut -d">" -f4 | cut -d"<" -f1)
				VOTINGPOINTS=$(grep "VotingPoints=" $PLAYERFILE/$PLAYER | cut -d= -f2 | tr -d " " )
				CURRENTVOTES=$(grep "CurrentVotes=" $PLAYERFILE/$PLAYER | cut -d= -f2 | tr -d " " )
				if [[ ! -z "$TOTALVOTES" ]]
				then
					if [ $TOTALVOTES -ge $CURRENTVOTES ]
					then
						ADDVOTES=$(($TOTALVOTES-$CURRENTVOTES))
					else
						ADDVOTES=$TOTALVOTES
					fi
					VOTESSAVED=$(($VOTINGPOINTS+$ADDVOTES))
					as_user "sed -i 's/VotingPoints=.*/VotingPoints=$VOTESSAVED/g' $PLAYERFILE/$PLAYER"
					as_user "sed -i 's/CurrentVotes=.*/CurrentVotes=$TOTALVOTES/g' $PLAYERFILE/$PLAYER"
					if [ $ADDVOTES -gt 0 ]
					then
						as_user "screen -p 0 -S $SCREENID -X stuff $'/chat $PLAYER just got $ADDVOTES point(s) for voting! You can get voting points too by going to starmade-servers.com!\n'"
					fi
				fi
			done
		fi
		sleep $VOTECHECKDELAY
	done
fi
}
function_exists(){
declare -f -F $1 > /dev/null 2>&1
FUNCTIONEXISTS=$?
}

#---------------------------Files Daemon Writes and Updates---------------------------------------------

write_factionfile() {
FLASTUPDATE=$(date +%s)
CREATEFACTION="cat > $FACTIONFILE/$1 <<_EOF_
FactionName=0
CreditsInBank=0
FactionLastUpdate=$FLASTUPDATE
FactionPoints=0
FactionKills=0
_EOF_"
as_user "$CREATEFACTION"
}
write_configpath() {
CONFIGCREATE="cat > $CONFIGPATH <<_EOF_
#  Settings below can all be custom tailored to any setup.
#  Username is your user on the server that runs starmade
#  Backupname is the name you want your backup file to have
#  Service is the name of your Starmade jar file
#  Backup is the path you want to move you backups to
#  Starterpath is where you starter file is located.  Starmade folder will be located in this directory
#  Maxmemory controls the total amount Java can use.  It is the -xmx variable in Java
#  Minmemory is the inital amounr of memory to use.  It is the -xms variable in Java
#  Port is the port that Starmade will use.  Set to 4242 by default.
#  Logging is for turning on or off with a YES or a NO
#  Daemon Path is only used if you are going to screen log
#  Server key is for the rewards and voting function and is setup for http://starmade-servers.com/
SERVICE='StarMade.jar' #The name of the .jar file to be run
USERNAME="$USERNAME" #Your login name
BACKUP='/home/$USERNAME/starbackup' #The location where all backups created are saved
BACKUPNAME='Star_Backup_' #Name of the backups
MAXMEMORY=512m #Java setting. Max memory assigned to the server
MINMEMORY=256m #Java setting. Min memory assigned to the server
PORT=4242 #The port the server will run on
SCREENID=smserver #Name of the screen the server will be run on
SCREENLOG=smlog #Name of the screen logging will be run on
LOGGING=YES #Determines if logging will be active (YES/NO))
SERVERKEY="00000000000000000000" #Server key found at starmade-servers.com (used for voting rewards)
#------------------------Logging files----------------------------------------------------------------------------
RANKCOMMANDS=$STARTERPATH/logs/rankcommands.log #The file that contains all the commands each rank is allowed to use
SHIPLOG=$STARTERPATH/logs/ship.log #The file that contains a record of all the ships with their sector location and the last person who entered it
CHATLOG=$STARTERPATH/logs/chat.log #The file that contains a record of all chat messages sent
PLAYERFILE=$STARTERPATH/playerfiles #The directory that contains all the individual player files which store player information
ADMINLOG=$STARTERPATH/logs/admin.log #The file with a record of all admin commands issued
GUESTBOOK=$STARTERPATH/logs/guestbook.log #The file with a record of all the logouts on the server
BANKLOG=$STARTERPATH/logs/bank.log #The file that contains all transactions made on the server
ONLINELOG=$STARTERPATH/logs/online.log #The file that contains the list of currently online players
TIPFILE=$STARTERPATH/logs/tips.txt #The file that contains random tips that will be told to players
FACTIONFILE=$STARTERPATH/factionfiles #The folder that contains individual faction files
CREDITSTATUSFILE=$STARTERPATH/logs/creditstatus.log #Contains all relevant infos about absolute creditflow
CREDITSTATISTICFILE=$STARTERPATH/logs/creditstatistic.log #Contains snapshots of total credits amount
#------------------------Game settings----------------------------------------------------------------------------
VOTECHECKDELAY=10 #The time in seconds between each check of starmade-servers.org
CREDITSPERVOTE=1000000 # The number of credits a player gets per voting point.
BANKALLOWANCE=1000000 # Tax allowance of the bank system
REGULARBANKFEE=5 # regular Bank fee in percent
DEPOSITBANKFEE=5 # Bank fee for deposits
UNIVERSEBOARDER=YES #Turn on and off the universe boarder (YES/NO)
UNIVERSECENTER=\"2,2,2\" #Set the center of the universe boarder
UNIVERSERADIUS=50 #Set the radius of the universe boarder around
TIPINTERVAL=600 #Number of seconds between each tip being shown
STARTINGRANK=Ensign #The initial rank players recieve when they log in for the first time. Can be edited.
_EOF_"
as_user "$CONFIGCREATE"
}
write_playerfile() {
PLAYERCREATE="cat > $PLAYERFILE/$1 <<_EOF_
Rank=$STARTINGRANK
CreditsInBank=0
VotingPoints=0
CurrentVotes=0
SMName=None
CurrentIP=0.0.0.0
CurrentCredits=0
PlayerFaction=None
PlayerLocation=2,2,2
PlayerControllingType=Spacesuit
PlayerControllingObject=PlayerCharacter
PlayerLastLogin=0
PlayerLastCore=0
PlayerLastUpdate=0
PlayerLoggedIn=No
PlayerKills=0
PlayerDeaths=0
JustLoggedIn=No
_EOF_"
as_user "$PLAYERCREATE"
}
write_rankcommands() {
CREATERANK="cat > $RANKCOMMANDS <<_EOF_
Ensign DEPOSIT WITHDRAW TRANSFER BALANCE RANKME RANKLIST RANKCOMMAND VOTEBALANCE PING HELP CORE CLEAR FDEPOSIT FWITHDRAW FBALANCE
Lieutenant DEPOSIT WITHDRAW TRANSFER BALANCE RANKME RANKLIST RANKCOMMAND VOTEBALANCE PING HELP CORE CLEAR FDEPOSIT FWITHDRAW FBALANCE
Commander DEPOSIT WITHDRAW TRANSFER BALANCE RANKME RANKLIST RANKCOMMAND VOTEBALANCE PING HELP CORE CLEAR FDEPOSIT FWITHDRAW FBALANCE
Captain DEPOSIT WITHDRAW TRANSFER BALANCE RANKME RANKLIST RANKCOMMAND VOTEBALANCE PING HELP CORE CLEAR FDEPOSIT FWITHDRAW FBALANCE
Admiral DEPOSIT WITHDRAW TRANSFER BALANCE RANKME RANKLIST RANKCOMMAND VOTEBALANCE PING HELP CORE CLEAR FDEPOSIT FWITHDRAW FBALANCE
Admin -ALL-
_EOF_"
as_user "$CREATERANK"
}
write_tipfile() {
CREATETIP="cat > $TIPFILE <<_EOF_
!HELP is your friend! If you are stuck on a command, use !HELP <Command>
Want to get from place to place quickly? Try !FOLD
Ever wanted to be rewarded for voting for the server? Vote now at starmade-servers.org to get voting points!
Been voting a lot lately? You can spend your voting points on a Jump Gate! Try !ADDJUMP
Want to reward people for killing your arch enemy? Try !POSTBOUNTY
Fancy becoming a bounty hunter? Use !LISTBOUNTY to see all bounties
Got too much money? Store some in your bank account with !DEPOSIT
Need to get some money? Take some out of your bank account with !WITHDRAW
Stuck in the middle of nowhere but dont want to suicide? Try !CORE
Want to tell your friend youve found something but theyre offline? Try !MAIL SEND
Logged in and you have an unread message? Try !MAIL LIST Unread
Want to secretly use a command? Try using a command inside a PM to yourself!
_EOF_"
as_user "$CREATETIP"
}

write_creditstatusfile() {
CREATEFILE="cat > $CREDITSTATUSFILE <<_EOF_
# ===Creditstatusfile===
# === Credits avlaibale to refill into the game ===
CreditsInBank=0
# === Actual Credit loss ===
ActualCreditLoss_Sum=0
ActualCreditLoss_Station=0
ActualCreditLoss_InactiveFaction=0
ActualCreditLoss_WeaponMeta=0
ActualCreditLoss_BankDepositFee=0
ActualCreditLoss_InactivePlayerBank=0
ActualCreditLoss_InactivePlayerCredits=0
ActualCreditLoss_TitanInterest=0
ActualCreditLoss_Other=0
# === Actual Credit gain ===
ActualCreditGain_Sum=0
ActualCreditGain_NewPlayers=0
ActualCreditGain_Beacons=0
ActualCreditGain_Checkpoints=0
ActualCreditGain_Other=0
# === Total Credit gain ===
TotalCreditLoss_Sum=0
TotalCreditLoss_Station=0
TotalCreditLoss_InactiveFaction=0
TotalCreditLoss_WeaponMeta=0
TotalCreditLoss_BankDepositFee=0
TotalCreditLoss_InactivePlayerBank=0
TotalCreditLoss_InactivePlayerCredits=0
TotalCreditLoss_TitanInterest=0
TotalCreditLoss_Other=0
# === Total Credit loss ===
TotalCreditGain_Sum=0
TotalCreditGain_NewPlayers=0
TotalCreditGain_Beacons=0
TotalCreditGain_Checkpoints=0
TotalCreditGain_Other=0
_EOF_"
as_user "$CREATEFILE"
}

create_creditstatusfile() {
if [ ! -e $CREDITSTATUSFILE ]
then
	write_creditstatusfile
fi
}

create_configpath() {
if [ ! -e $CONFIGPATH ]
then
	write_configpath
fi
}
create_tipfile(){
if [ ! -e $TIPFILE ]
then
	write_tipfile
fi
}
create_playerfile(){
if [[ ! -f $PLAYERFILE/$1 ]]
then
#	echo "File not found"
	write_playerfile $1
fi
}
create_factionfile(){
if [[ ! -f $FACTIONFILE/$1 ]] && [ "$1" != "None" ]
then
#	echo "File not found"
	write_factionfile $1
	update_faction_info $1
fi
}
create_rankscommands(){
if [ ! -e $RANKCOMMANDS ]
then
	write_rankcommands
fi
}
update_file() {
#echo "Starting Update"
#echo "$1 is the write function to update the old config filename"
#echo "$2 is the name of the specific file for functions like playerfile or factionfile"
# Grab first occurrence of value from the Daemon file itself to be used to determine correct path
DLINE=$(grep -n -m 1 $1 $DAEMONPATH | cut -d : -f 1)
#echo "This is the starting line for the write function $DLINE"
let DLINE++
EXTRACT=$(sed -n "${DLINE}p" $DAEMONPATH)
# echo "Here is the second line of write funtion $EXTRACT"
if [ "$#" -eq "2" ]
then
	PATHUPDATEFILE=$(echo $EXTRACT | cut -d$ -f2- | cut -d/  -f1)
#	echo "Extraction from Daemon $PATHUPDATEFILE"
	PATHUPDATEFILE=${!PATHUPDATEFILE}/$2
#	echo "modified directory $PATHUPDATEFILE"
else
	PATHUPDATEFILE=$(echo $EXTRACT | cut -d$ -f2- | cut -d" " -f1)
#	echo "This is what was extracted from the Daemon $PATHUPDATEFILE"
# Set the path to what the source of the config file value is
	PATHUPDATEFILE=${!PATHUPDATEFILE}
	cp $PATHUPDATEFILE $PATHUPDATEFILE.old
fi
# echo "This is the actual path to the file to be updated $PATHUPDATEFILE"
#This is how you would compare files for future work ARRAY=( $(grep -n -Fxvf test1 test2) )
OLD_IFS=$IFS
IFS=$'\n'
# Create an array of the old file
OLDFILESTRING=( $(cat $PATHUPDATEFILE) )
as_user "rm $PATHUPDATEFILE"
# $1 is the write file function for the file being updated and if $2 is set it will use specific file
$1 $2
# Put the newly written file into an array
NEWFILESTRING=( $(cat $PATHUPDATEFILE) )
IFS=$OLD_IFS
NEWARRAY=0
as_user "rm $PATHUPDATEFILE"
# The following rewrites the config file and preserves values from the old configuration file
while [ -n "${NEWFILESTRING[$NEWARRAY]+set}" ]
do
	NEWSTR=${NEWFILESTRING[$NEWARRAY]}
	OLDARRAY=0
	WRITESTRING=$NEWSTR
	while [ -n "${OLDFILESTRING[$OLDARRAY]+set}" ]
	do
	OLDSTR=${OLDFILESTRING[$OLDARRAY]}
# If a = is detected grab the value to the right of = and then overwrite the new value
	if [[ $OLDSTR == *=* ]]
	then
		NEWVAR=${NEWSTR%%=*}
#		echo "Here is the NEWVAR $NEWVAR"
		NEWVAL=${NEWSTR#*=}
#		echo "Here is the NEWVAL $NEWVAL"
		OLDVAR=${OLDSTR%%=*}
#		echo "Here is the OLDVAR $OLDVAR"
		OLDVAL=${OLDSTR#*=}
#		echo "Here is the OLDVAL $OLDVAL"
		if [[ "$OLDVAR" == "$NEWVAR" ]]
		then
#			echo "Matched oldvar $OLDVAR to newvar $NEWVAR"
			WRITESTRING=${NEWSTR/$NEWVAL/$OLDVAL}
		fi
	fi
	let OLDARRAY++
	done
#	echo "Here is the writestring $WRITESTRING"
	as_user "cat <<EOF >> $PATHUPDATEFILE
$WRITESTRING
EOF"
let NEWARRAY++
done
}
# Execute for a regular Bank fee (i.e one day a week)
bank_fee (){
	for i in $PLAYERFILE/*
	do
		BALANCECREDITS=$(grep CreditsInBank $i | cut -d= -f2- |  tr -d ' ')
		if [[ $BALANCECREDITS -gt $BANKALLOWANCE ]]
		then
			FEE=$(( BALANCECREDITS * $REGULARBANKFEE / 100 ))
			NEWBALANCE=$(( BALANCECREDITS - FEE ))
			as_user "sed -i 's/CreditsInBank=$BALANCECREDITS/CreditsInBank=$NEWBALANCE/g' $i"
		else
			continue
		fi
	done
}

# Execute for regular activity check of factions
check_factions() {
# One week are 604800 seconds
WEEK=604800
CURRENTTIME=$(date +%s)
for i in $FACTIONFILE/*
do
	FID=${i//*"/"}
	if [ $FID -gt 0 ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_get $FID\n'"
	fi
done
sleep 2
for i in $FACTIONFILE/*
do
	FID=${i//*"/"}
	if [ $FID -gt 0 ]
	then
		update_faction_info $FID "no"
		LASTACTIVITY=$(grep "FactionLastUpdate=" "$i")
		LASTACTIVITY=${LASTACTIVITY/FactionLastUpdate=}
		if [ -z "$FPOINTS" ] || [ -z "$FNAME" ]
		then
			echo "Faction $FID File is broken"
			if [ -z "$(grep "Faction $FID" "$STARTERPATH/logs/check_factions")" ]
			then
				as_user "echo 'Check Faction $FID' >> '$STARTERPATH/logs/check_factions'"
			fi
			continue
		fi
		if [ $(($CURRENTTIME - $LASTACTIVITY)) -gt $WEEK ]
		then
			FPOINTS=$(($FPOINTS * 95 / 100))
			echo "Faction $FID named $FNAME is inactive and looses 5% FP (New FP: $FPOINTS)"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_set $FID $FPOINTS\n'"
		else if [ $FPOINTS -lt -300 ]
		then
			echo "Faction $FID named $FNAME has less then -300 FPs, set them back to -300"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_set $FID -300\n'"
		else if [ $FPOINTS -gt 100000 ]
		then
			echo "Faction $FID named $FNAME has more then 100000 FPs, set them back to 100000"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_set $FID 100000\n'"
		fi
		fi
		fi
	fi
done
}

update_faction_info() {
if [ $# -eq 1 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_get $1\n'"
	sleep 1
fi
#[SERVER-LOCAL-ADMIN] [ADMIN COMMAND] [SUCCESS] faction points of Knack test now: -52660.0
#[ADMIN COMMAND] FACTION_POINT_GET from org.schema.schine.network.server.AdminLocalClient@7a886c25 params: [10002]
FNAME=""
FPOINTS=""
FACTIONINFO=$(tac /dev/shm/output.log | grep "\[ADMIN COMMAND\] FACTION_POINT".*"\[$1" -m 1 -B 1)
if [ -n "$FACTIONINFO" ] && [[ ! "$FACTIONINFO" =~ "\[ERROR\] Faction Not Found" ]]
then
	FNAME=${FACTIONINFO/*faction points of }
	FNAME=${FNAME/ now:*}
	FPOINTS=${FACTIONINFO/*now: }
	FPOINTS=${FPOINTS/.*}
	if [ -n "$FPOINTS" ] && [ -n "$FNAME" ]
	then
		as_user "sed -i 's/FactionName=.*/FactionName=$FNAME/g' '$FACTIONFILE/$1'"
		as_user "sed -i 's/FactionPoints=.*/FactionPoints=$FPOINTS/g' '$FACTIONFILE/$1'"
	fi
fi
}

check_credits() {
create_creditstatusfile
#$CREDITSTATUSFILE
update_credit_statistic
}

update_credit_statistic() {
CURRENTTIME=$(date +%s)
LASTACTIVITY=$(tac "$CREDITSTATISTICFILE" | grep "Timestamp=" -m 1 2> /dev/null)
LASTACTIVITY=${LASTACTIVITY/Timestamp=}
if [ ! -e "$CREDITSTATISTICFILE" ] || [ $(($CURRENTTIME - $LASTACTIVITY)) -gt 79200 ]
then
	echo "Updating Creditstatistic"
	#Set no player, so that pl_bounty_calc_bounty gives back total bounty
	PLAYER=""
	pl_bounty_calc_bounty
	collect_faction_credits
	collect_player_credits
	TRADINGCREDITS=$(grep "CreditsInBank=" "$CREDITSTATUSFILE")
	CREDTILOSS=$(grep "ActualCreditLoss_Sum=" "$CREDITSTATUSFILE")
	CREDITSGAIN=$(grep "ActualCreditGain_Sum=" "$CREDITSTATUSFILE")
	USEABLESUMMARY=$(($PLAYERBOUNTY + $FACTIONBOUNTY + $CREDITSINFACTIONBANKS + $CREDITSINPLAYERBANKS + $CREDITSOFPLAYERS))
	TOTALSUMMARY=$(($USEABLESUMMARY + $CREDITSGAIN + $TRADINGCREDITS - $CREDTILOSS))
	as_user "echo 'Timestamp=$CURRENTTIME' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'TotalSummary=$TOTALSUMMARY' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'UseableSummary=$USEABLESUMMARY' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'InTradingGuildBank=$TRADINGCREDITS' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'CreditLoss=$CREDTILOSS' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'CreditGain=$CREDITSGAIN' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'InPlayerBounty=$PLAYERBOUNTY' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'InFactionBounty=$FACTIONBOUNTY' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'InPlayerBank=$CREDITSINPLAYERBANKS' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'InFactionBank=$CREDITSINFACTIONBANKS' >> '$CREDITSTATISTICFILE'"
	as_user "echo 'InPlayerInventory=$CREDITSOFPLAYERS' >> '$CREDITSTATISTICFILE'"
fi
}

collect_faction_credits() {
CREDITSINFACTIONBANKS=0
#All Faction greater 0
FACTIONBANKBALANCE=($(cat $FACTIONFILE/1* | grep "CreditsInBank="))
for credits in ${FACTIONBANKBALANCE[@]}; do
	credits=${credits//*=}
	CREDITSINFACTIONBANKS=$(($CREDITSINFACTIONBANKS + $credits))
done
}

collect_player_credits() {
CREDITSINPLAYERBANKS=0
PLAYERBANKBALANCE=($(cat $PLAYERFILE/* | grep "CreditsInBank="))
for credits in ${PLAYERBANKBALANCE[@]}; do
	credits=${credits//*=}
	if [ $credits -gt 20000000 ]
	then
		echo "Someone has $credits in bank"
	fi
	CREDITSINPLAYERBANKS=$(($CREDITSINPLAYERBANKS + $credits))
done

CREDITSOFPLAYERS=0
PLAYERBANKBALANCE=($(cat $PLAYERFILE/* | grep "CurrentCredits="))
for credits in ${PLAYERBANKBALANCE[@]}; do
	credits=${credits//*=}
	if [ $credits -gt 5000000 ]
	then
		echo "Someone has $credits"
	fi
	CREDITSOFPLAYERS=$((CREDITSOFPLAYERS + $credits))
done
}

#---------------------------Chat Commands---------------------------------------------

#Example Command
#In the command system, $1 = Playername , $2 = parameter 1 , $3 = parameter 2 , ect
#e.g if Titansmasher types "!FOLD 9 8 7" then $1 = Titansmasher , $2 = 9 , $3 = 8 , $4 = 7
#function COMMAND_EXAMPLE(){
##Description told to user when !HELP EXAMPLE is used (This line must be a comment)
##USAGE: How to use the commands parameters (This line must be a comment)
#	if [ "$#" -ne "NumberOfParameters+1" ]
#	then
#		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 ParameterErrorMessage\n'"
#	else
#		Function workings
#	fi
#}

#Bank Commands
function COMMAND_DEPOSIT(){
#Deposits money into your server account from your player
#USAGE: !DEPOSIT <Amount>
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !DEPOSIT <Amount>\n'"
	else
# Check to make sure a posistive amount was entered
		if ! test "$2" -gt 0 2> /dev/null
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - You must put in a positive number\n'"
		else
# Run playerinfo command to update playerfile and get the current player credits
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTICE BANK - Connecting to servers\n'"
			log_playerinfo $1
#			as_user "screen -p 0 -S $SCREENID -X stuff $'/player_info $1\n'"
#			echo "sent message to counsel, now sleeping"
# Sleep is added here to give the console a little bit to respond

# Check the playerfile to see if it was updated recently by comparing it to the current time
			CURRENTTIME=$(date +%s)
#			echo "Current time $CURRENTTIME"
			OLDTIME=$(grep PlayerLastUpdate $PLAYERFILE/$1 | cut -d= -f2- |  tr -d ' ')
#			echo "Old time from playerfile $OLDTIME"
			ADJUSTEDTIME=$(( $CURRENTTIME - 10 ))
#			echo "Adjusted time to remove 10 seconds $ADJUSTEDTIME"
			if [ "$OLDTIME" -ge "$ADJUSTEDTIME" ]
			then
				BALANCECREDITS=$(grep CreditsInBank $PLAYERFILE/$1 | cut -d= -f2- |  tr -d ' ')
#				echo $BALANCECREDITS
				CREDITSTOTAL=$(grep CurrentCredits $PLAYERFILE/$1 | cut -d= -f2- |  tr -d ' ')
#				echo "Credits in log $CREDITTOTAL"
#				echo "Total credits are $CREDITSTOTAL on person and $BALANCECREDITS in bank"
#				echo "Credits to be deposited $2 "
				if [ "$CREDITSTOTAL" -ge "$2" ]
				then
#					echo "enough money detected"
					BANKTAX=$(( $2 * $DEPOSITBANKFEE / 100 ))
					NEWBALANCE=$(( $2 + $BALANCECREDITS - $BANKTAX ))
					NEWCREDITS=$(( $CREDITSTOTAL - $2 ))
#					echo "new bank balance is $NEWBALANCE"
					as_user "sed -i 's/CurrentCredits=$CREDITSTOTAL/CurrentCredits=$NEWCREDITS/g' $PLAYERFILE/$1"
					as_user "sed -i 's/CreditsInBank=$BALANCECREDITS/CreditsInBank=$NEWBALANCE/g' $PLAYERFILE/$1"
					#					as_user "sed -i '4s/.*/CreditsInBank=$NEWBALANCE/g' $PLAYERFILE/$1"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/give_credits $1 -$2\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK You successfully deposited $2 credits with a tax of $BANKTAX\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK Your balance is now $NEWBALANCE\n'"
					as_user "echo '$1 deposited $2' >> $BANKLOG"
				else
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK Insufficient money\n'"
#					echo "not enough money"
				fi
			else
#				echo "Time difference to great, playerfile not updated recently"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Connecting to GALACTICE BANK servers failed\n'"
			fi
		fi
	fi

#
}
function COMMAND_WITHDRAW(){
#Takes money out of your server account and gives it to your player
#USAGE: !WITHDRAW <Amount>
#	echo "Withdraw command"
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !WITHDRAW <Amount>\n'"
	else

		if ! test "$2" -gt 0 2> /dev/null
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - You must put in a positive number\n'"
		else
#			echo "Withdraw $2"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - Connecting to servers\n'"
			BALANCECREDITS=$(grep CreditsInBank $PLAYERFILE/$1 | cut -d= -f2 | tr -d ' ')
#			echo "bank balance is $BALANCECREDITS"
			if [ "$2" -le "$BALANCECREDITS" ]
			then
				NEWBALANCE=$(( $BALANCECREDITS - $2 ))
#				echo "new balance for bank account is $NEWBALANCE"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/give_credits $1 $2\n'"
				as_user "sed -i 's/CreditsInBank=$BALANCECREDITS/CreditsInBank=$NEWBALANCE/g' $PLAYERFILE/$1"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK You successfully withdrawn $2 credits\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK Your balance is $NEWBALANCE credits\n'"
				as_user "echo '$1 witdrew $2' >> $BANKLOG"
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - You have insufficient funds\n'"
			fi
		fi
	fi
}
function COMMAND_TRANSFER(){
#Sends money from your bank account to another players account
#USAGE: !TRANSFER <Player> <Amount>
	if [ "$#" -ne "3" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !TRANSFER <Player> <Amount>\n'"
	else
#	echo "Transfer $1 a total of $3 credits"
	if ! test "$3" -gt 0 2> /dev/null
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - You must put in a positive number\n'"
	else
		if [ -e $PLAYERFILE/$2 ] >/dev/null
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - Connecting to servers\n'"
			BALANCECREDITS=$(grep CreditsInBank $PLAYERFILE/$1 | cut -d= -f2 | tr -d ' ')
#			echo "Player transferring has $BALANCECREDITS in account"
			if [ "$3" -le "$BALANCECREDITS" ]
			then
				TRANSFERBALANCE=$(grep CreditsInBank $PLAYERFILE/$2 | cut -d= -f2 | tr -d ' ')
#				echo "Player receiving has $TRANSFERBALANCE in his account"
				NEWBALANCETO=$(( $3 + $TRANSFERBALANCE ))
				NEWBALANCEFROM=$(( $BALANCECREDITS - $3 ))
#				echo "Changing $1 account to $NEWBALANCEFROM and $2 account to $NEWBALANCETO"
				as_user "sed -i 's/CreditsInBank=$BALANCECREDITS/CreditsInBank=$NEWBALANCEFROM/g' $PLAYERFILE/$1"
				as_user "sed -i 's/CreditsInBank=$TRANSFERBALANCE/CreditsInBank=$NEWBALANCETO/g' $PLAYERFILE/$2"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK - You sent $3 credits to $2\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK - Your balance is now $NEWBALANCEFROM\n'"
				as_user "echo '$1 transferred to $2 in the amount of $3' >> $BANKLOG"
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - Not enough credits\n'"
			fi
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - No account found\n'"
		fi
	fi
fi
}
function COMMAND_BALANCE(){
#Tells the player how much money is stored in their server account
#USAGE: !BALANCE
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !BALANCE\n'"
	else
	BALANCECREDITS=$(grep CreditsInBank $PLAYERFILE/$1 | cut -d= -f2 | tr -d ' ')
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - You have $BALANCECREDITS credits\n'"
	fi
}
function COMMAND_FDEPOSIT(){
#Allows you to deposit credits into a shared faction bank account
#USAGE: !FDEPOSIT <Amount>
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FACTIONDEPOSIT <Amount>\n'"
	else
		if [ "$2" -gt 0 ] 2>/dev/null
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Connecting to GALACTICE BANK servers\n'"
			#log_playerinfo $1
			FACTION=$(grep "PlayerFaction=" $PLAYERFILE/$1 | cut -d= -f2)
			if [ ! $FACTION = "None" ]
			then
				create_factionfile $FACTION
				#CURRENTTIME=$(date +%s)
#				echo "Current time $CURRENTTIME"
				#OLDTIME=$(grep PlayerLastUpdate $PLAYERFILE/$1 | cut -d= -f2- |  tr -d ' ')
#				echo "Old time from playerfile $OLDTIME"
				#ADJUSTEDTIME=$(( $CURRENTTIME - 10 ))
#				echo "Adjusted time to remove 10 seconds $ADJUSTEDTIME"
				#if [ "$OLDTIME" -ge "$ADJUSTEDTIME" ]
				#then
					BALANCECREDITS=$(grep CreditsInBank= $FACTIONFILE/$FACTION | cut -d= -f2- |  tr -d ' ')
#					echo $BALANCECREDITS
					CREDITSTOTAL=$(grep CreditsInBank= $PLAYERFILE/$1 | cut -d= -f2- |  tr -d ' ')
#					echo "Credits in log $CREDITTOTAL"
#					echo "Total credits are $CREDITSTOTAL on person and $BALANCECREDITS in bank"
#					echo "Credits to be deposited $2 "
					if [ "$CREDITSTOTAL" -ge "$2" ]
					then
#						echo "enough money detected"
						NEWBALANCE=$(( $2 + $BALANCECREDITS ))
						NEWCREDITS=$(( $CREDITSTOTAL - $2 ))
#						echo "new bank balance is $NEWBALANCE"
						#as_user "sed -i 's/CurrentCredits=.*/CurrentCredits=$NEWCREDITS/g' $PLAYERFILE/$1"
						as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEWBALANCE/g' $FACTIONFILE/$FACTION"
						as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEWCREDITS/g' $PLAYERFILE/$1"
#						as_user "sed -i '4s/.*/CreditsInBank=$NEWBALANCE/g' $PLAYERFILE/$1"
						#as_user "screen -p 0 -S $SCREENID -X stuff $'/give_credits $1 -$2\n'"
						as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK You successfully deposited $2 credits\n'"
						as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK Your factions balance is now $NEWBALANCE\n'"
						as_user "echo '$1 deposited $2 into $FACTION bank account' >> $BANKLOG"
					else
						as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK Insufficient money\n'"
#						echo "not enough money"
					fi
				#else
#					echo "Time difference to great, playerfile not updated recently"
				#	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Connecting to GALACTICE BANK servers failed\n'"
				#fi
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTICE BANK - You are not in a faction\n'"
			fi
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Please enter a positive whole number\n'"
		fi
	fi
}
function COMMAND_FWITHDRAW(){
#Allows you to withdraw from a shared faction account
#USAGE: !FWITHDRAW <Amount>
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FWITHDRAW <Amount>\n'"
	else
		if [ "$2" -gt 0 ] 2>/dev/null
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTICE BANK - Connecting to servers\n'"
			#log_playerinfo $1
			FACTION=$(grep "PlayerFaction=" $PLAYERFILE/$1 | cut -d= -f2)
			if [ ! $FACTION = "None" ]
			then
				create_factionfile $FACTION
				BALANCECREDITS=$(grep CreditsInBank $FACTIONFILE/$FACTION | cut -d= -f2 | tr -d ' ')
#				echo "bank balance is $BALANCECREDITS"
				if [ "$2" -le "$BALANCECREDITS" ]
				then
					NEWBALANCE=$(( $BALANCECREDITS - $2 ))
#					echo "new balance for bank account is $NEWBALANCE"
					#as_user "screen -p 0 -S $SCREENID -X stuff $'/give_credits $1 $2\n'"
					as_user "sed -i 's/CreditsInBank=$BALANCECREDITS/CreditsInBank=$NEWBALANCE/g' $FACTIONFILE/$FACTION"
					PLAYERBALANCE=$(grep "CreditsInBank=" $PLAYERFILE/$1)
					PLAYERBALANCE=${PLAYERBALANCE//*=}
					PLAYERBALANCE=${PLAYERBALANCE// }
					PLAYERBALANCE=$(( $PLAYERBALANCE + $2 ))
					as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$PLAYERBALANCE/g' $PLAYERFILE/$1"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK You successfully withdrawn $2 credits\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALATIC BANK The factions balance is $NEWBALANCE credits\n'"
					as_user "echo '$1 witdrew $2 from $FACTION' >> $BANKLOG"
				else
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - Your faction has insufficent funds\n'"
				fi
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - You are not in a faction\n'"
			fi
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Please enter positive whole numbers only.\n'"
		fi
	fi

}
function COMMAND_FBALANCE(){
#Allows you to see how many credits are in a shared faction account
#USAGE: !FBALANCE
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !BALANCE\n'"
	else
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - Connecting to servers\n'"
#We don't need log_playerinfo anymore here. We get the factionchanges directly.
		create_playerfile $1
		FACTION=$(grep "PlayerFaction" $PLAYERFILE/$1 | cut -d= -f2)
		if [ ! $FACTION = "None" ]
		then
			BALANCECREDITS=$(grep CreditsInBank $FACTIONFILE/$FACTION | cut -d= -f2 | tr -d ' ')
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - Your faction has $BALANCECREDITS credits\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 GALACTIC BANK - You are not in a faction\n'"
		fi
	fi
}

function COMMAND_VOTEEXCHANGE(){
#Converts the specified number of voting points into credits at the rate of 2,000,000 credits per vote
#USAGE: !VOTEEXCHANGE <Amount>
if [ "$#" -ne "2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !VOTEEXCHANGE <Amount>\n'"
else
	if [ $2 -gt 0 ] 2>/dev/null
	then
		BALANCECREDITS=$(grep CreditsInBank $PLAYERFILE/$1 | cut -d= -f2 | tr -d ' ')
		VOTEBALANCE=$(grep "VotingPoints=" $PLAYERFILE/$1 | cut -d= -f2)
		if [ $VOTEBALANCE -ge $2 ]
		then
			NEWVOTE=$(($VOTEBALANCE - $2))
			NEWCREDITS=$(($BALANCECREDITS + $CREDITSPERVOTE * $2))
			as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEWCREDITS/g' $PLAYERFILE/$1"
			as_user "sed -i 's/VotingPoints=.*/VotingPoints=$NEWVOTE/g' $PLAYERFILE/$1"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You traded in $2 voting points for $(($BALANCECREDITS + $CREDITSPERVOTE * $2)) credits. The credits have been sent to your bank account.\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You dont have enough voting points to do that! You only have $VOTEBALANCE voting points\n'"
		fi
	else
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid amount entered. Please only use positive whole numbers.\n'"
	fi
fi
}

function COMMAND_VOTESILVER(){
#Converts the specified number of voting points into silverbars at the rate of two silverbars per vote
#USAGE: !VOTESILVER <Amount>
if [ "$#" -ne "2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !VOTESILVER <Amount>\n'"
else
	if [ $2 -gt 0 ] 2>/dev/null
	then
		VOTEBALANCE=$(grep "VotingPoints=" $PLAYERFILE/$1 | cut -d= -f2)
		if [ $VOTEBALANCE -ge $2 ]
		then
			NEWVOTE=$(($VOTEBALANCE - $2))
			BARS=$(($2 * 2))
			as_user "screen -p 0 -S $SCREENID -X stuff $'/giveid $1 342 $BARS\n'"
			as_user "sed -i 's/VotingPoints=.*/VotingPoints=$NEWVOTE/g' $PLAYERFILE/$1"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You traded in $2 voting points for $BARS silverbars. Please check your Inventory to confirm that.\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You dont have enough voting points to do that! You only have $VOTEBALANCE voting points\n'"
		fi
	else
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid amount entered. Please only use positive whole numbers.\n'"
	fi
fi
}

function COMMAND_VOTEGOLD(){
#Converts the specified number of voting points into goldbars at the rate of one goldbar per 4 votingpoints
#USAGE: !VOTEGOLD <Amount>
if [ "$#" -ne "2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !VOTEGOLD <Amount>\n'"
else
	if [ $2 -gt 0 ] 2>/dev/null
	then
		VOTEBALANCE=$(grep "VotingPoints=" $PLAYERFILE/$1 | cut -d= -f2)
		NUMVOTE=$(($2 * 4))
		if [ $VOTEBALANCE -ge $NUMVOTE ]
		then
			NEWVOTE=$(($VOTEBALANCE - $NUMVOTE))
			as_user "screen -p 0 -S $SCREENID -X stuff $'/giveid $1 343 $2\n'"
			as_user "sed -i 's/VotingPoints=.*/VotingPoints=$NEWVOTE/g' $PLAYERFILE/$1"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You traded in $NUMVOTE voting points for $2 goldbars. Please check your Inventory to confirm that.\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You dont have enough voting points to do that! You only have $VOTEBALANCE voting points\n'"
		fi
	else
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid amount entered. Please only use positive whole numbers.\n'"
	fi
fi
}

#Rank Commands
function COMMAND_RANKME(){
#Tells you what your rank is and what commands are available to you
#USAGE: !RANKME
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !RANKME\n'"
	else
			USERRANK=$(sed -n '3p' "$PLAYERFILE/$PLAYERCHATID" | cut -d" " -f2 | cut -d"[" -f2 | cut -d"]" -f1)
			USERCOMMANDS=$(grep $USERRANK $RANKCOMMANDS | cut -d" " -f2-)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $1 rank is $USERRANK\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Commands available are $USERCOMMANDS\n'"
	fi
}
function COMMAND_RANKLIST(){
#Lists all the available ranks
#USAGE: !RANKLIST
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !RANKLIST\n'"
	else
	    LISTRANKS=( $(cut -d " " -f 1 $RANKCOMMANDS) )
		CHATLIST=${LISTRANKS[@]}
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 The Ranks are: $CHATLIST \n'"
	fi
}
function COMMAND_RANKSET(){
#Sets the rank of the player
#USAGE: !RANKSET <Player> <Rank>
	if [ "$#" -ne "3" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !RANKSET <Name> <Rank>\n'"
	else
#		if ! grep -q $3 $RANKCOMMANDS
		if grep -q $3 $RANKCOMMANDS
		then
			if [ -e $PLAYERFILE/$2 ]
			then
				as_user "sed -i '3s/.*/Rank: \[$3\]/g' $PLAYERFILE/$2"
			else
				MakePlayerFile $2
				as_user "sed -i '3s/.*/Rank: \[$3\]/g' $PLAYERFILE/$2"
			fi
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $2 is now the rank $3\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 That rank does not exist\n'"
		fi
	fi
}
function COMMAND_RANKUSER(){
#Finds out the rank of the given player
#USAGE: !RANKUSER <Player>
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !RANKUSER <Name>\n'"
	else
		if [ -e $PLAYERFILE/$2 ]
		then
			RANKUSERSTING=$(sed -n '3p' $PLAYERFILE/$2 | cut -d" " -f2)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $RANKUSERSTING\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $2 has no current Rank or does not exist\n'"
		fi
	fi
}
function COMMAND_RANKCOMMAND(){
#Lists all commands available to you
#USAGE: !RANKCOMMAND
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !RANKCOMMAND\n'"
	else
		RANKUCOMMAND=$(grep $PLAYERRANK $RANKCOMMANDS | cut -d" " -f2-)
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Commands are $RANKUCOMMAND\n'"
	fi
}
function COMMAND_VOTEBALANCE(){
#Tells you how many voting points you have saved up
#USAGE: !VOTEBALANCE
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You have $(grep "VotingPoints=" $PLAYERFILE/$1 | cut -d= -f2 | tr -d " " ) votes to spend!\n'"
}

function COMMAND_LOAD(){
#A little info command to see how much of the system ressources are gathered from the starmade server process
#USAGE: !LOAD
	STAR_LOAD_CPU1=$(ps aux | grep java | grep StarMade.jar | grep $PORT | grep -v "rlwrap\|sh" | awk '{print $3}')
	CALC_CORES=$(ls /sys/devices/system/cpu/cpu? -dw1|wc -l)
#	STAR_LOAD_CPU=$(($STAR_LOAD_CPU1/$CALC_CORES))
	STAR_LOAD_CPU=$(echo "scale=1;$STAR_LOAD_CPU1/$CALC_CORES" | bc)
	STAR_LOAD_MEM=$(ps aux | grep java | grep StarMade.jar | grep $PORT | grep -v "rlwrap\|sh" | awk '{print $4}')
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Server load is currently:\n'"
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 CPU: $STAR_LOAD_CPU% MEM: $STAR_LOAD_MEM%.\n'"
}

function COMMAND_PING(){
#With this command, you can check if the server is responsive
#USAGE: !PING
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 !PONG\n'"
}

#Utility Commands
function COMMAND_HELP(){
#Provides help on any and all functions available to the player
#USAGE: !HELP <Command (optional)>
	if [ "$#" -gt "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !HELP <Command (Optional)>\n'"
	else
		PLAYERRANK[$1]=$(grep "Rank=" $PLAYERFILE/$1 | cut -d= -f2)
		ALLOWEDCOMMANDS[$1]=$(grep $PLAYERRANK $RANKCOMMANDS)
		HELPCOMMAND=$(echo $2 | tr [a-z] [A-Z])
		if [ "$#" -eq "1" ]
		then
			if [[ "${ALLOWEDCOMMANDS[$1]}" =~ "-ALL-" ]]
			then
				OLD_IFS=$IFS
				IFS=$'\n'
				for LINE in $(tac $DAEMONPATH)
				do
					if [[ $LINE =~ "function COMMAND_" ]] && [[ ! $LINE =~ "#" ]] && [[ ! $LINE =~ "\$" ]]
					then
						as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $(echo $LINE | cut -d"_" -f2 | cut -d"(" -f1) \n'"
					fi
				done
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Type !HELP <Command> to get more info about that command!\n'"
				IFS=$OLD_IFS
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $(echo ${ALLOWEDCOMMANDS[$1]} | cut -d" " -f2-)\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 All available commands are:\n'"
			fi
		else
			function_exists "COMMAND_$HELPCOMMAND"
			if [[ "$FUNCTIONEXISTS" == "0" ]]
			then
				if [[ "${ALLOWEDCOMMANDS[$1]}" =~ "$HELPCOMMAND" ]] || [[ "${ALLOWEDCOMMANDS[$1]}" =~ "-ALL-" ]]
				then
					OLDIFS=$IFS
					IFS=$'\n'
					HELPTEXT=( $(grep -A3 "function COMMAND_$HELPCOMMAND()" $DAEMONPATH) )
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $(echo ${HELPTEXT[2]} | cut -d\# -f2)\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $(echo ${HELPTEXT[1]} | cut -d\# -f2)\n'"
					IFS=$OLDIFS
				else
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You dont have permission to use $2\n'"
				fi
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 That command doesnt exist.\n'"
			fi
		fi
	fi
}
function COMMAND_CORE(){
#Provides you with a ship core. Only usable once every 10 minutes
#USAGE: !CORE
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !CORE\n'"
	else
		OLDPLAYERLASTCORE=$(grep PlayerLastCore $PLAYERFILE/$1 | cut -d= -f2- | tr -d ' ')
		CURRENTTIME=$(date +%s)
		ADJUSTEDTIME=$(( $CURRENTTIME - 600 ))
		if [ "$ADJUSTEDTIME" -gt "$OLDPLAYERLASTCORE" ]
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/giveid $1 1 1\n'"
			as_user "sed -i 's/PlayerLastCore=$OLDPLAYERLASTCORE/PlayerLastCore=$CURRENTTIME/g' $PLAYERFILE/$1"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You have received one core. There is a 10 minute cooldown before you can use it again\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Please allow Core command to cooldown. $((600-($(date +%s)-$(grep "PlayerLastCore=" $PLAYERFILE/$1 | cut -d= -f2)))) seconds left\n'"
		fi
	fi
}

#Vanilla Admin Commands
function COMMAND_GIVEMETA(){
#Gives you, or another player the specified meta item
#USAGE: !GIVEMETA <Player (optional)> <METAUTEN>
	if [ "$#" -ne "2" ] && [ "$#" -ne "3" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !GIVE <Playername (optional)> <Metaitem>\n'"
	else
		if [ "$#" -eq "2" ] 2>/dev/null
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/give_metaitem $1 $2\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You received $2\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/give_metaitem $2 $3\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $2 received $3\n'"
		fi
	fi
}
function COMMAND_CLEAR(){
#Removes all items from your inventory
#USAGE: !CLEAR
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !CLEAR\n'"
	else
		as_user "screen -p 0 -S $SCREENID -X stuff $'/give_all_items $1 -99999\n'"
as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Your inventory has been cleaned\n'"
	fi
}
function COMMAND_LISTWHITE(){
#Tells you all the names, IPs and accounts that are whitelisted on the server
#USAGE: !LISTWHITE <name/account/ip/all>
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !LISTWHITE <name/account/ip/all>\n'"
	else
		WHITELIST=( $( cat $STARTERPATH/StarMade/whitelist.txt ) )
		WHITENAME=()
		WHITEIP=()
		WHITEACCOUNT=()
		for ENTRY in ${WHITELIST[@]}
		do
			case $(echo $ENTRY | cut -d":" -f1) in
			nm)
				WHITENAME+=( $(echo $ENTRY | cut -d":" -f2) )
				;;
			ip)
				WHITEIP+=( $(echo $ENTRY | cut -d":" -f2) )
				;;
			ac)
				WHITEACCOUNT+=( $(echo $ENTRY | cut -d":" -f2) )
				;;
			esac
		done
		if [[ $(echo $2 | tr [a-z] [A-Z]) ==  "NAME" ]]
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 ${WHITENAME[@]}\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Whitelisted name\'s are:\n'"
		elif [[ $(echo $2 | tr [a-z] [A-Z]) ==  "IP" ]]
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 ${WHITEIP[@]}\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Whitelisted ip\'s are:\n'"
		elif [[ $(echo $2 | tr [a-z] [A-Z]) ==  "ACCOUNT" ]]
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 ${WHITEACCOUNT[@]}\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Whitelisted account\'s are:\n'"
		elif [[ $(echo $2 | tr [a-z] [A-Z]) ==  "ALL" ]]
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 ${WHITELIST[*]}\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 All whitelisted names, accounts and ip\'s:\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !LISTWHITE <name/account/ip/all>\n'"
		fi
	fi
}
function COMMAND_TELEPORT(){
#Teleports you and the entity you are controlling, or another player and the entity they are controling to the specified sector
#USAGE: !TELEPORT <Player (optional)> <X> <Y> <Z>
	if [ "$#" -ne "4" ] && [ "$#" -ne "5" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !TELEPORT <Player (optional)> <X> <Y> <Z>\n'"
	else
		if [ "$2" -eq "$2" ] 2>/dev/null
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/change_sector_for $1 $2 $3 $4\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You have been teleported to $2,$3,$4\n'"
		else
			as_user "screen -p 0 -S $SCREENID -X stuff $'/change_sector_for $2 $3 $4 $5\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $2 has been teleported to $2,$3,$4\n'"
		fi
	fi
}
#Debug Commands
function COMMAND_MYDETAILS(){
#Tells you all details that are saved inside your personal player file
#USAGE: !MYDETAILS
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !MYDETAILS\n'"
	else
		for ENTRY in $(tac $PLAYERFILE/$1)
		do
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $ENTRY\n'"
		done
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 All details inside your playerfile:\n'"
	fi
}
function COMMAND_THREADDUMP(){
#A debug tool that outputs what the server is doing to a file
#USAGE: !THREADDUMP
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !THREADDUMP\n'"
	else
		PID=$(ps aux | grep -v grep | grep $SERVICE | grep -v tee | grep port:$PORT | awk '{print $2}')
		as_user "jstack $PID >> $STARTERPATH/logs/threaddump$(date +%H%M%S.%N).log"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 The current java process has been exported to logs/threaddump$(date +%H%M%S.%N).log\n'"
	fi
}

#------------------------------Start of daemon script-----------------------------------------
sm_config

# End of regular Functions and the beginning of alias for commands, custom functions, and finally functions that use arguments.
case "$1" in
	start)
		sm_load_plugins
		sm_start
	;;
	status)
		sm_status
	;;
	detect)
		sm_detect
	;;
	log)
		sm_load_plugins
		sm_log
	;;
	screenlog)
		sm_load_plugins
		sm_screenlog
	;;
	stop)
		sm_stop
		screen -S $SCREENLOG -X quit
		echo "Stopping logging"
	;;
	ebrake)
		sm_ebrake
	;;
	upgrade)
		sm_upgrade
	;;
	cronstop)
		sm_cronstop
	;;
	cronrestore)
		sm_cronrestore
	;;
	cronbackup)
		sm_cronbackup
	;;
	backup)
		sm_backup
	;;
	restore)
		sm_restore $@
	;;
	dump)
		sm_dump $@
	;;
	box)
		sm_box $@
	;;
	help)
		sm_help
	;;
	restart)
		sm_stop
		screen -S $SCREENLOG -X quit
		echo "Stopping logging"
		sm_load_plugins
		sm_start
	;;
	backupstar)
		sm_cronstop
		sm_stop
		sm_backup
		sm_start
		sm_cronrestore
	;;
	upgradestar)
		sm_cronstop
		sm_stop
		sm_upgrade
		sm_start
		sm_cronrestore
	;;
	bankfee)
		bank_fee
	;;
	debug)
		echo ${@:2}
		parselog ${@:2}
	;;
	*)
		echo "Doomsider's and Titanmasher's Starmade Daemon (DSD) V.17"
		echo "Usage: starmaded.sh {help|start|stop|ebrake|restore|status|restart|upgrade|upgradestar|cronstop|cronbackup|cronrestore|bankfee|backup|backupstar|detect|log|screenlog|dump|box}"
		#******************************************************************************
		exit 1
	;;
esac
exit 0

### EOF ###
