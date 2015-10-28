#!/bin/bash
#Plugin main function (Every plugin has to have this function, named like the pluin itself)

faction_warfare() {

SEARCHWIRELESS="[SERVER][ACTIVATION] sent 'true'"
SEARCHFACTIONTURN="[FACTIONMANAGER] faction update took:"
SEARCHGRAVITYCHANGE="starting gravity change DONE: source:"
case "$1" in
#	*"$SEARCHWIRELESS"*)
#at the moment deactivated, we use gravity now. If we ever want do introduce Alliances, we could use wireless detection again
#		pl_fwf_log_wireless_activated "$1" &
#		;;
	*"$SEARCHGRAVITYCHANGE"*)
		pl_fwf_log_gravity_changed "$1" &
		;;
	*"$SEARCHFACTIONTURN"*)
#actualize the list
		pl_fwf_warfare_round &
		;;
	*)
		;;
esac
}

faction_warfare_config() {
if [ "$(grep "Plugin Faction Warfare" "$CONFIGPATH")" = "" ]
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
echo "Claimable checkpoints: ${CHECKPOINTS[@]}"

for fid in ${WARFACTIONIDS[@]} ; do
	pl_fwf_check_factionfile $fid
done

for checkpoint_name in ${CHECKPOINTS[@]} ; do
	for faction_id in ${WARFACTIONIDS[@]} ; do
		CHECKPOINT_TRIGGER=(${CHECKPOINT_TRIGGER[@]} "${checkpoint_name}_${faction_id}")
	done
done

if [ ! -e "$FWCHECKPOINTSFILE" ]
then
	echo "# List of claimable Faction Warfare Checkpoints" >"$FWCHECKPOINTSFILE"
fi

for checkpoint_name in ${CHECKPOINTS[@]} ; do
	if [ "$(grep "$mine_name" "$FWCHECKPOINTSFILE")" = "" ]
	then
		echo "$checkpoint_name=0" >> "$FWCHECKPOINTSFILE"
	fi
done

}

pl_fwf_warfare_round() {
#run as long as the sm_log thread is running
#Count the occurrences of factionid or name in checkpoint.txt
as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction Warfare Round ended!\"\n'"
pl_fwf_reload_checkpoints
#If only special warfactions are attending
if [ ${#WARFACTIONIDS[@]} -gt 0 ]
then
	for fid in ${WARFACTIONIDS[@]}; do
		sumowned=$(grep -c "$fid" "$FWCHECKPOINTSFILE")
		wptoadd=$(($sumowned * $FWWARPOINTSPERCPROUND ))
		old_wpoints=$(grep "currentwp=" "$FWFACTIONFILEPFX$fid.txt")
		old_wpoints=${old_wpoints//*=}
		old_wpoints=${old_wpoints// }
		new_wpoints=$(($old_wpoints + $wptoadd))
		as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$fid.txt"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction $fid got $wptoadd WP and has now $new_wpoints WP total.\"\n'"
	done
else
#if every faction attends in warfare
	FACTIONS=($(ls "$FWFACTIONFILEPFX"*.txt 2>/dev/null))
	for ffile in ${FACTIONS[@]}; do
		fid=${ffile//*faction}
		fid=${fid/.txt}
		sumowned=$(grep -c "$fid" "$FWCHECKPOINTSFILE")
		wptoadd=$(($sumowned * $FWWARPOINTSPERCPROUND ))
		if [ $wptoadd -gt 0 ]
		then
			old_wpoints=$(grep "currentwp=" "$FWFACTIONFILEPFX$fid.txt")
			old_wpoints=${old_wpoints//*=}
			old_wpoints=${old_wpoints// }
			new_wpoints=$(($old_wpoints + $wptoadd))
			as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$fid.txt"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction $fid got $wptoadd WP and has now $new_wpoints WP total.\"\n'"
		fi
	done
fi
}

pl_fwf_write_config_file() {
CONFIGCREATE="cat > $FACTIONWARFARECONFIG <<_EOF_
#  Config file for Faction Warfare Plugin
#  FWCHECKPOINTSFILE: There the actual state of all checkpoints is saved.
#  FWFACTIONFILEPFX: The path and prefix of the warfare faction files
#  FWWARPOINTSPERCPROUND: How many Warpoints the factions get per owned checkpoint per round
#  mines gets checked and warpoints get earned
#  WARFACTIONIDS: The IDs of the attending factions
#  CHECKPOINTS: IDs of the claimable checkpoints. Example: ( CP_WP_Mine_6_6_6_part1 CP_WP_Mine_6_6_6_part2 CP_WP_Mine_6_6_6_part3 CP_WP_Mine_6_6_6_part4 )
#  FUNCTIONALBEACONS: IDs of all avaliable beacons. Its function is described by in the name after the prefix. Example: CB_Scanner_001
#         have to have their name to beginn with sich an ID and end with a WARFACTIONID.
#         Example: Mine_6_6_6_part1_10001
FWCHECKPOINTSFILE=$FACTIONWARFAREFILES/checkpoints.txt
FWFACTIONFILEPFX=$FACTIONWARFAREFILES/faction
FWWARPOINTSPERCPROUND=1
WARFACTIONIDS=( )
CHECKPOINTS=( CP_WP_Mine_6_6_6 CP_Scanner_3_3_3 )
FUNCTIONALBEACONS=( CB_Scanner_001 CB_Schnitzel_Dickbutt CB_Schnitzel_Blau CB_Schnitzel_Knack )
DEFAULTBEACONBP=Beacon
_EOF_"
as_user "$CONFIGCREATE"
}

pl_fwf_write_faction_file() {
CONFIGCREATE="cat > $1 <<_EOF_
#  Faction Warfare Faction file
#  wp .. Warpoint
#  name: The name of the faction
#  currentwp: The current warpoints of the faction
#  beaconpoints: The number of beacons found by this faction
name='Unnamed'
currentwp=0
beaconpoints=0
_EOF_"
as_user "$CONFIGCREATE"
}

pl_fwf_log_wireless_activated() {
c=$1
#Get shipname where wireless logic was activated
mySep="Ship["
c="${c#*$mySep}"
c="${c%%]*}"
if [[ " ${CHECKPOINT_TRIGGER[@]} " =~ " $c " ]]
then
	faction_id="${c##*_}"
	mine="${c%_*}"
	old_belonger=$(grep "$mine=" "$FWCHECKPOINTSFILE")
	old_belonger=${old_belonger//*=}
	old_belonger=${old_belonger// }
	if [ $old_belonger != $faction_id ]
	then
		as_user "sed -i 's/$mine=$old_belonger/$mine=$faction_id/g' '$FWCHECKPOINTSFILE'"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Checkpoint $mine from $old_belonger now belongs to Faction $faction_id\"\n'"
	fi
fi

}

pl_fwf_log_gravity_changed() {
SOURCE=${1/*source: }
SOURCE=${SOURCE//]*}
SOURCETYP=${SOURCE/\[*}
#Possible: "Ship" "Station" "Planet" 
if [ "$SOURCETYP" == "Ship" ] #|| [ "$SOURCETYP" == "Station" ]
then
	SOURCE=${SOURCE/*[}
	SOURCE=${SOURCE//*ENTITY_SHIP_}
#	SOURCE=${SOURCE//*ENTITY_SPACESTATION_}
	pl_fwf_reload_checkpoints
	if [[ " $CHECKPOINTS " =~ " $SOURCE " ]]
	then
		TYPE="cp"
	else if [[ " $FUNCTIONALBEACONS " =~ " $SOURCE " ]]
	then
		TYPE="bc"
	else
#Early bail out if not found in our list
		return
	fi
	fi

	PLAYER=${1/*[(ENTITY_PLAYERCHARACTER_}
	PLAYER=${PLAYER//)*}


# Look up faction of player
	FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$PLAYER")
	FACTIONID=${FACTIONID/*=}
	FACTIONID=${FACTIONID// }
	if [ -z "$FACTIONID" ] || [ $FACTIONID -eq 0 ] || [ "$FACTIONID" == "None" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER \"Your can\'t activate this beacon, because you are not in a faction!\"\n'"
		return
	fi
# if faction paticipates in warfare or no explizit warfaction is set
	if [[ " ${WARFACTIONIDS[@]} " =~ " $FACTIONID " ]] || [ ${#WARFACTIONIDS[@]} -eq 0 ]
	then
		pl_fwf_check_factionfile $FACTIONID
#if source is a registerd chekpoint or mine
		if [ "$TYPE" == "cp" ]
		then
			BCFUNCTION=${SOURCE//CP_}
			BCFUNCTION=${BCFUNCTION//_*}
			case "$BCFUNCTION" in
				*"WP"*)
					old_belonger=$(grep "$SOURCE=" "$FWCHECKPOINTSFILE")
					old_belonger=${old_belonger//*=}
					old_belonger=${old_belonger// }
					if [ $old_belonger != $FACTIONID ]
					then
						as_user "sed -i 's/$SOURCE=$old_belonger/$SOURCE=$FACTIONID/g' '$FWCHECKPOINTSFILE'"
						as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Checkpoint $SOURCE from $old_belonger now belongs to Faction $FACTIONID\"\n'"
					fi
					;;
				*"Scanner"*)
					echo "Checkpoint says: \"I am a Scanner!\""
					;;
				*)
					;;
			esac
		else if [ "$TYPE" == "bc" ]
		then
#It is a beacon with some spceial function
			BCFUNCTION=${SOURCE//CB_}
			BCFUNCTION=${BCFUNCTION//_*}
			
#delete beacon from list and delete entity. Do this before any other action to reduce the possibility of abuse. (F.e. use by two players simultaneously)
			as_user "screen -p 0 -S $SCREENID -X stuff $'/destroy_uid ENTITY_SHIP_$SOURCE\n'"
			OLD="$(grep "FUNCTIONALBEACONS=" "$FACTIONWARFARECONFIG")"
			NEW="${OLD/ $SOURCE / }"
			as_user "sed -i 's/$OLD/$NEW/g' '$FACTIONWARFARECONFIG'"
			case "$BCFUNCTION" in
				*"Scanner"*)
					echo "Beacon says: \"Do a scan for me!\""
					ONLINEPLAYERS=($(cat $ONLINELOG))
					SCANRESULT=""
					for player in $ONLINEPLAYERS; do
						POSITION=$(grep "PlayerLocation=" "$PLAYERFILE/$player")
						POSITION=${POSITION/*=}
						SCANRESULT="$SCANRESULT $player=($POSITION)"
					done
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER Receiving scan data: $SCANRESULT\n'"
					;;
				*"Schnitzel"*)
					as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"$PLAYER found the beacon $SOURCE for his faction $FACTIONID\"\n'"
					old=$(grep "beaconpoints=" "$FWFACTIONFILEPFX$FACTIONID.txt")
					old=${old//*=}
					old=${old// }
					as_user "sed -i 's/beaconpoints=$old/beaconpoints=$(($old + 1))/g' '$FWFACTIONFILEPFX$FACTIONID.txt'"
					;;
				*"Pirate"*)
					echo "Beacon says: \"Spawn a pirate for me!\""
					;;
				*"Gold"*)
					echo "Beacon says: \"Give me gold!\""
					as_user "screen -p 0 -S $SCREENID -X stuff $'/give $PLAYER \"Silver Bar\" 1\n'"
					;;
				*"Faction"*)
					echo "Beacon says: \"Give my faction FPs!\""
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER \"Your faction got 100FP from a Factionbeacon!\"\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_add $FACTIONID 100\n'"
					;;
				*"Random"*)
					echo "Beacon says: \"Do a random thing!\""
					;;
				*)
					echo "Unknown beacon function: $SOURCE"
					;;
			esac
		fi
		fi
	fi
fi
}

pl_fwf_check_factionfile() {
if [ ! -e "$FWFACTIONFILEPFX$1.txt" ]
then
	pl_fwf_write_faction_file "$FWFACTIONFILEPFX$1.txt"
fi
}

pl_fwf_reload_checkpoints() {
FUNCTIONALBEACONS=$(grep "FUNCTIONALBEACONS=" $FACTIONWARFARECONFIG)
FUNCTIONALBEACONS=${FUNCTIONALBEACONS/"FUNCTIONALBEACONS=("}
FUNCTIONALBEACONS=${FUNCTIONALBEACONS/ )}
CHECKPOINTS=$(grep "CHECKPOINTS=" $FACTIONWARFARECONFIG)
CHECKPOINTS=${CHECKPOINTS/"CHECKPOINTS=("}
CHECKPOINTS=${CHECKPOINTS/ )}
}

#Chat commands:
function COMMAND_FW_CHECKPOINTS(){
#Allows you to see which checkpoints are captured by which faction
#USAGE: !FW_CHECKPOINTS
	if [ "$#" -ne "1" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_CHECKPOINTS\n'"
	else
		checkpoint_status="The current checkpoint status is: "
		for checkpoint in $(cat "$FWCHECKPOINTSFILE"); do
			checkpoint_status="$checkpoint_status$checkpoint "
		done
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 \"$checkpoint_status[@]\"\n'"
	fi
}

function COMMAND_FW_POINTS(){
#Allows you to see the current Warpoints of ALL, OWN or a factionid
#USAGE: !FW_POINTS <ALL,OWN,factionid>
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_POINTS <ALL,OWN or factionid>\n'"
	else
		wps=""
		if [ ${#WARFACTIONIDS[@]} -gt 0 ]
			then
			for fid in ${WARFACTIONIDS[@]}; do
				tmp=$(grep "currentwp=" "$FWFACTIONFILEPFX$fid.txt")
				tmp=${tmp//*=}
				tmp=${tmp// }
				wps="$wps Faction $fid has $tmp WP"
			done
		else
			if [ "$2" == "OWN" ]
			then
				FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$1")
				FACTIONID=${FACTIONID/*=}
				FACTIONID=${FACTIONID// }
				pl_fwf_check_factionfile $FACTIONID
				tmp=$(grep "currentwp=" "$FWFACTIONFILEPFX$FACTIONID.txt")
				tmp=${tmp//*=}
				tmp=${tmp// }
				wps="$wps Your Faction has $tmp WP"
			else if [ "$2" == "ALL" ]
			then
				FACTIONS=($(ls "$FWFACTIONFILEPFX*.txt" 2>/dev/null))
				for ffile in ${FACTIONS[@]}; do
					fid=${ffile/.txt}
					fid=${fid/faction}
					tmp=$(grep "currentwp=" "$FWFACTIONFILEPFX$fid.txt")
					tmp=${tmp//*=}
					tmp=${tmp// }
#Only send factions that actually have WPs, otherwise this would mess up the players chat
					if [ $tmp -ne 0 ]
					then
						wps="$wps Faction $fid has $tmp WP"
					fi
				done
			else
				FACTIONID=$2
				if [ -e "$FWFACTIONFILEPFX$FACTIONID.txt" ]
				then
					tmp=$(grep "currentwp=" "$FWFACTIONFILEPFX$FACTIONID.txt")
					tmp=${tmp//*=}
					tmp=${tmp// }
					wps="$wps Faction $FACTIONID has $tmp WP"
				else
					wps="Faction $FACTIONID doesn\'t exist or hasn\'t attended the warfare yet!"
				fi
			fi
			fi
		fi
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 $wps\n'"
	fi
}

function COMMAND_FW_EXCHANGE(){
#Exchanges WPs to factionpoints or gold
#USAGE: !FW_EXCHANGE <fp/gold> <amount>
	if [ "$#" -ne "3" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_WPEXCHANGE fp/gold nr. Exchange factor 1wp = 100fp or 1wp=1gold\n'"
	else
		fid=${WARFACTIONIDS[0]}
		wptosub=$3
		old_wpoints=$(grep "currentwp=" "$FWFACTIONFILEPFX$fid.txt")
		old_wpoints=${old_wpoints//*=}
		old_wpoints=${old_wpoints// }
		new_wpoints=$(($old_wpoints - $wptosub))
		if [ $new_wpoints -ge 0 ]
		then
			if [ $2 = "fp" ]
			then
				as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$fid.txt"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_add $fid $((100 * $3))\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Exchanged $wptosub WP into $((100 * $3)) FP\n'"
			else if [ $2 = "gold" ]
			then
				as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$fid.txt"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/give $1 gold $3\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Exchanged $wptosub WP into $3 gold\n'"
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 FW_WPEXCHANGE: second argument has to be either fp or gold!\n'"
			fi
			fi
		fi
	fi
}

#ADMIN Commands:
function COMMAND_FW_ADMIN_CREATECB(){
#Allows admins to easily create beacons
#USAGE: !FW_ADMIN_CREATECB <function_name example: Faction_1> <optional blueprintname>
if [ "$#" -ne "2" ] && [ "$#" -ne "3" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_ADMIN_CREATECB beaconname <optional blueprintname>\n'"
else
# First remove the Prefix "CB_" if present to preventmultiple prefixed
	NAME=${2//CB_}
#Now set prefix
	NAME="CB_$NAME"
	pl_fwf_reload_checkpoints
	if [[ ! " $FUNCTIONALBEACONS " =~ " $NAME " ]]
	then
		OLD="$(grep "FUNCTIONALBEACONS=" "$FACTIONWARFARECONFIG")"
		NEW="${OLD:0: -1}"
		NEW="$NEW$NAME )"
		as_user "sed -i 's/$OLD/$NEW/g' '$FACTIONWARFARECONFIG'"
		LOCATION="$(grep "PlayerLocation=" "$PLAYERFILE/$1")"
		LOCATION=${LOCATION/*=}
		LOCATION="${LOCATION//,/ }"
		if [ "$#" == "3" ]
		then
			BP=$3
		else
			BCFUNCTION=${NAME//CB_}
			BCFUNCTION=${BCFUNCTION//_*}
			BP="${DEFAULTBEACONBP}_$BCFUNCTION"
		fi
		as_user "screen -p 0 -S $SCREENID -X stuff $'/spawn_entity $BP $NAME $LOCATION -2 false\n'"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Created Beacon. If the beacon is not near you, something went wrong and you have to delete the entry with FW_ADMIN_DELETECB $2\n'"
	else
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Beacon with ID: $2 already in list\n'"
	fi
fi
}

function COMMAND_FW_ADMIN_DELETECB(){
#Allows admins to easily delete beacons in the list, does not destroy entities
#USAGE: !FW_ADMIN_DELETECB <name>
if [ "$#" -ne "2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_ADMIN_DELETECB beaconname\n'"
else
# First remove the Prefix "CB_" if present to preventmultiple prefixed
	NAME=${2//CB_}
#Now set prefix
	NAME="CB_$NAME"
	OLD="$(grep "FUNCTIONALBEACONS=" "$FACTIONWARFARECONFIG")"
	NEW="${OLD/ $NAME / }"
	if [ "$OLD" != "$NEW" ]
	then
		as_user "sed -i 's/$OLD/$NEW/g' '$FACTIONWARFARECONFIG'"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Deleted beacon from list.\n'"
	else
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Beacon $2 not found in list.\n'"
	fi
fi
}

function COMMAND_FW_ADMIN_CLEANUPCBS(){
#Allows admins to easily delete beacons. Erases list and destroys all entities.
#USAGE: !FW_ADMIN_CLEANUPCBS
if [ "$#" -ne "1" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_ADMIN_CLEANUPCBS\n'"
else
	pl_fwf_reload_checkpoints
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Begining cleanup, this could take a while\n'"
	for beacon in $FUNCTIONALBEACONS; do
		as_user "screen -p 0 -S $SCREENID -X stuff $'/destroy_uid ENTITY_SHIP_$beacon\n'"
	done
	as_user "sed -i 's/FUNCTIONALBEACONS=.*/FUNCTIONALBEACONS=( )/g' '$FACTIONWARFARECONFIG'"
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Cleaned up the mess. The whole beaconlist got deleted and all matching entities got destroyed\n'"
fi
}