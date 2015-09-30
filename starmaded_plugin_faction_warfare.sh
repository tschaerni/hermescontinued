#!/bin/bash
#Plugin main function (Every plugin has to have this function, named like the pluin itself)
WARFARE_ROUND_STARTED=false

faction_warfare() {
#If not started, start the warfare round
if [ $WARFARE_ROUND_STARTED = false ]
then
	WARFARE_ROUND_STARTED=true
	pl_fwf_warfare_round &
fi

#SEARCHWIRELESS="[SERVER][ACTIVATION] activated wireless logic on"
SEARCHWIRELESS="[SERVER][ACTIVATION] sent 'true'"
case "$1" in
	*"$SEARCHWIRELESS"*)
		pl_fwf_log_wireless_activated "$1" &
		;;
	*)
		;;
esac
}

faction_warfare_config() {
if [ "$(cat "$CONFIGPATH" | grep "Plugin Faction Warfare")" = "" ]
then
#Declare default values here
	FACTIONWARFAREFILES="$STARTERPATH/factionwarfarefiles"
	FACTIONWARFARECONFIG="$FACTIONWARFAREFILES/fwconfig.cfg"
#Write config
	CONFIGCREATE="cat >> $CONFIGPATH <<_EOF_
#------------------------Plugin Faction Warfare----------------------------------------------------------------------------
FACTIONWARFAREFILES=$STARTERPATH/factionwarfarefiles #The folder that contains files for faction warfare
FACTIONWARFARECONFIG=$FACTIONWARFAREFILES/fwconfig.cfg
_EOF_"
	as_user "$CONFIGCREATE"
fi
source "$CONFIGPATH"

if [ ! -e "$FACTIONWARFAREFILES" ]
then
	as_user "mkdir $FACTIONWARFAREFILES"
fi

if [ ! -e "$FACTIONWARFARECONFIG" ]
then
	pl_fwf_write_config_file
fi

source "$FACTIONWARFARECONFIG"
echo "In warfare attending factions: ${WARFACTIONIDS[@]}"
echo "Claimable mines: ${MINES[@]}"

for fid in ${WARFACTIONIDS[@]} ; do
	if [ ! -e "$FWFACTIONFILEPFX$fid.txt" ]
	then
		pl_fwf_write_faction_file "$FWFACTIONFILEPFX$fid.txt"
	fi
done

for mine_name in ${MINES[@]} ; do
	for faction_id in ${WARFACTIONIDS[@]} ; do
		CHECKPOINT_TRIGGER=(${CHECKPOINT_TRIGGER[@]} "${mine_name}_${faction_id}")
	done
done

if [ ! -e "$FWCHECKPOINTSFILE" ]
then
	echo "# List of claimable Faction Warfare Checkpoints" >"$FWCHECKPOINTSFILE"
fi

for mine_name in ${MINES[@]} ; do
	if [ "$(cat "$FWCHECKPOINTSFILE" | grep "$mine_name")" = "" ]
	then
		echo "$mine_name=0" >> "$FWCHECKPOINTSFILE"
	fi
done

}

pl_fwf_warfare_round() {
#run as long as the sm_log thread is running
while [ $SM_LOG_PID ] && [ -e /proc/$SM_LOG_PID ]
do
	sleep $FWCHECKPOINTROUND
#Count the occurrences of factionid or name in checkpoint.txt
	as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction Warfare Round ended!\"\n'"
	for fid in ${WARFACTIONIDS[@]}; do
		sumowned=$(grep -c "$fid" "$FWCHECKPOINTSFILE")
		wptoadd=$(($sumowned * $FWWARPOINTSPERCPROUND ))
		old_wpoints=$(grep "currentwp=" "$FWFACTIONFILEPFX$fid.txt" | cut -d= -f2 | tr -d ' ')
		new_wpoints=$(($old_wpoints + $wptoadd))
		as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$fid.txt"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction $fid got $wptoadd WP and has now $new_wpoints WP total.\"\n'"
	done

done
}

pl_fwf_write_config_file() {
CONFIGCREATE="cat > $FACTIONWARFARECONFIG <<_EOF_
#  Config file for Faction Warfare Plugin
#  FWCHECKPOINTSFILE: There the actual state of all checkpoints is saved.
#  FWFACTIONFILEPFX: The path and prefix of the warfare faction files
#  FWCHECKPOINTROUNDTIME: Roundtime in seconds. It's the intervall where the ownership of
#  FWWARPOINTSPERCPROUND: How many Warpoints the factions get per owned checkpoint per round
#  mines gets checked and warpoints get earned
#  WARFACTIONIDS: The IDs of the attending factions
#  MINES: IDs of the claimable mines. The entities with wirless blocks on them
#         have to have their name to beginn with sich an ID and end with a WARFACTIONID.
#         Example: Mine_6_6_6_part1_10001
FWCHECKPOINTSFILE=$FACTIONWARFAREFILES/checkpoints.txt
FWFACTIONFILEPFX=$FACTIONWARFAREFILES/faction
FWCHECKPOINTROUND=600
FWWARPOINTSPERCPROUND=1
WARFACTIONIDS=( 10001 10002 )
MINES=( Mine_6_6_6_part1 Mine_6_6_6_part2 Mine_6_6_6_part3 Mine_6_6_6_part4 )
_EOF_"
as_user "$CONFIGCREATE"
}

pl_fwf_write_faction_file() {
CONFIGCREATE="cat > $1 <<_EOF_
#  Faction Warfare Faction file
#  wp .. Warpoint
#  name: The name of the faction
#  currentwp: The current warpoints of the faction
name='Unnamed'
currentwp=0
_EOF_"
as_user "$CONFIGCREATE"
}

pl_fwf_log_wireless_activated() {
c=$1
#Get shipname where wireless logic was activated
mySep="Ship["
c="${c#*$mySep}"
c="${c%%]*}"
if [[ "${CHECKPOINT_TRIGGER[@]}" =~ "$c" ]]
then
	faction_id="${c##*_}"
	mine="${c%_*}"
	old_belonger=$(grep "$mine" "$FWCHECKPOINTSFILE" | cut -d= -f2 | tr -d ' ')
	if [ $old_belonger != $faction_id ]
	then
		as_user "sed -i 's/$mine=$old_belonger/$mine=$faction_id/g' $FWCHECKPOINTSFILE"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Checkpoint $mine from $old_belonger now belongs to Faction $faction_id\"\n'"
	fi
fi

}

#Chat commands:
function COMMAND_FW_MINES(){
#Allows you to see which mines are captured by which faction
#USAGE: !FW_MINES
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_MINES\n'"
	else
		#chechpoint_status=$(cat "$FWCHECKPOINTSFILE")
		checkpoint_status="The current checkpoint status is: "
		for checkpoint in $(cat "$FWCHECKPOINTSFILE"); do
			checkpoint_status="$checkpoint_status$checkpoint "
		done
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 \"$checkpoint_status[@]\"\n'"
	fi
}
