#!/bin/bash
#Plugin main function (Every plugin has to have this function, named like the pluin itself)
SPAWNTHREADSTARTED="false"
faction_warfare() {
if [ "$SPAWNTHREADSTARTED" == "false" ]
then
	SPAWNTHREADSTARTED="true"
	sm_spawn_thread &
fi

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
#	*"$SEARCHFACTIONTURN"*)
#actualize the list
#		pl_fwf_warfare_round &
#		;;
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
#source "$CONFIGPATH"

if [ ! -e "$FACTIONWARFAREFILES" ]
then
	as_user "mkdir $FACTIONWARFAREFILES"
fi

if [ ! -e "$FACTIONWARFARECONFIG" ]
then
	pl_fwf_write_config_file
fi

source "$FACTIONWARFARECONFIG"
#echo "In warfare attending factions: ${WARFACTIONIDS[@]}"
#echo "Claimable checkpoints: ${CHECKPOINTS[@]}"

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
	as_user "echo \"# List of claimable Faction Warfare Checkpoints\" > \"$FWCHECKPOINTSFILE\""
fi

for checkpoint_name in ${CHECKPOINTS[@]} ; do
	if [ "$(grep "$checkpoint_name" "$FWCHECKPOINTSFILE")" == "" ]
	then
		echo "$checkpoint_name=0" >> "$FWCHECKPOINTSFILE"
	fi
done

if [ ! -e "$SPAWNBEACONLISTFILE" ]
then
	as_user "echo \"# List of respawning random beacons\" > \"$SPAWNBEACONLISTFILE\""
fi
}

pl_fwf_warfare_round() {
#run as long as the sm_log thread is running
#Count the occurrences of factionid or name in checkpoint.txt
as_user "screen -p 0 -S $SCREENID -X stuff $'/start_countdown 300 \"Warpointturn ends in:\" \n'"
sleep 300
as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction Warfare Round ended!\"\n'"
pl_fwf_reload_checkpoints
#If only special warfactions are attending
if [ ${#WARFACTIONIDS[@]} -gt 0 ]
then
	for fid in ${WARFACTIONIDS[@]}; do
		sumowned=$(grep -c "_WP_.*$fid" "$FWCHECKPOINTSFILE")
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
		FNAME=$(grep "FactionName=" "$FACTIONFILE/$fid")
		FNAME=${FNAME/FactionName=}

		sumowned=$(grep -c "_WP_.*$fid" "$FWCHECKPOINTSFILE")
		wptoadd=$(($sumowned * $FWWARPOINTSPERCPROUND ))
		if [ $wptoadd -gt 0 ]
		then
			old_wpoints=$(grep "currentwp=" "$FWFACTIONFILEPFX$fid.txt")
			old_wpoints=${old_wpoints//*=}
			old_wpoints=${old_wpoints// }
			new_wpoints=$(($old_wpoints + $wptoadd))
			as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$fid.txt"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction $FNAME (ID:$fid) got $wptoadd WP and has now $new_wpoints WP total.\"\n'"
		fi

		sumowned=$(grep -c "_Faction_.*$fid" "$FWCHECKPOINTSFILE")
		fptoadd=$(($sumowned * $CHECKPOINTFACTIONPOINTS ))
		if [ $fptoadd -gt 0 ]
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_add $fid $fptoadd\n'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction $FNAME (ID:$fid) got $fptoadd FP from checkpoints.\"\n'"
		fi

		sumowned=$(grep -c "_Credit_.*$fid" "$FWCHECKPOINTSFILE")
		crtoadd=$(($sumowned * $CHECKPOINTCREDITS ))
		if [ $crtoadd -gt 0 ]
		then
			credits=$(grep "CreditsInBank=" "$FACTIONFILE/$fid")
			credits=${credits/*=}
			credits=$(($credits + $crtoadd))
			as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$credits/g' $FACTIONFILE/$fid"
			CHECKPOINTGAIN=$(grep "ActualCreditGain_Checkpoints=" "$CREDITSTATUSFILE")
			CHECKPOINTGAIN=$(($CHECKPOINTGAIN + $crtoadd))
			as_user "sed -i 's/ActualCreditGain_Checkpoints=.*/ActualCreditGain_Checkpoints=$CHECKPOINTGAIN/g' '$CREDITSTATUSFILE'"
			as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Faction $FNAME (ID:$fid) got $crtoadd Credits from checkpoints.\"\n'"
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
#  SPAWNBEACONLISTFILE: The file where all respawning beacons are listed. Make sure to name them like GN_2_2_2_name <GN_ POS _ Name>
#  SPAWNPOSSIBLEFUNCTIONS: The psooible functions for the random spawn. The more often a function is present in the list, the higher is the possibility to spawn that kind
#  SPAWNTIMER: Respawntimer for Beacons
#  WPEXCHANGERATEFP: Exchangerate between WP and FP (0 to deactivate)
#  WPEXCHANGERATESILVER: Exchangerate between WP and Silver (0 to deactivate)
#  WPEXCHANGERATECREDITS: Exchangerate between WP and Credits (0 to deactivate)
FWCHECKPOINTSFILE=$FACTIONWARFAREFILES/checkpoints.txt
FWFACTIONFILEPFX=$FACTIONWARFAREFILES/faction
FWWARPOINTSPERCPROUND=1
WARFACTIONIDS=( )
CHECKPOINTS=( )
FUNCTIONALBEACONS=( )
DEFAULTBEACONBP=Beacon
DEFAULTPIRATEBP=Pirate
SPAWNBEACONLISTFILE=$FACTIONWARFAREFILES/beaconspawns.txt
SPAWNPOSSIBLEFUNCTIONS=( None )
SPAWNTIMER=1800
WPEXCHANGERATEFP=50
WPEXCHANGERATESILVER=2
WPEXCHANGERATECREDITS=0
BEACONCREDITS=50000
BEACONSILVER=3
BEACONFACTIONPOINTS=100
CHECKPOINTCREDITS=100000
CHECKPOINTFACTIONPOINTS=100
SCANCOSTGLOBAL=2
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
	if [ -z "$FACTIONID" ] || [ "$FACTIONID" == "None" ] || [ $FACTIONID -eq 0 ]
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
				*"Scanner"*)
					if [ $SCANCOSTGLOBAL -eq 0 ]
					then
						echo "Checkpoint says: \"I am a Scanner!\""
						ONLINEPLAYERS=($(cat $ONLINELOG))
						SCANRESULT=""
						for player in ${ONLINEPLAYERS[@]}; do
							POSITION=$(grep "PlayerLocation=" "$PLAYERFILE/$player")
							POSITION=${POSITION/*=}
							SCANRESULT="$SCANRESULT $player=($POSITION)"
						done
						as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER Receiving scan data: $SCANRESULT\n'"
					fi
				;&
				*"Faction"*)
				;&
				*"Credit"*)
				;&
				*"WP"*)
					echo "Checkpoint says: \"I am $SOURCE!\""
					old_belonger=$(grep "$SOURCE=" "$FWCHECKPOINTSFILE")
					old_belonger=${old_belonger//*=}
					old_belonger=${old_belonger// }
					if [ $old_belonger != $FACTIONID ]
					then
						FNAME=$(grep "FactionName=" "$FACTIONFILE/$FACTIONID")
						FNAME=${FNAME/FactionName=}
						OLDFNAME=$(grep "FactionName=" "$FACTIONFILE/$old_belonger" 2> /dev/null)
						OLDFNAME=${OLDFNAME/FactionName=}
						as_user "sed -i 's/$SOURCE=$old_belonger/$SOURCE=$FACTIONID/g' '$FWCHECKPOINTSFILE'"
						as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Checkpoint $SOURCE from $OLDFNAME (ID:$old_belonger) now belongs to Faction $FNAME (ID:$FACTIONID)\"\n'"
					fi
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
					for player in ${ONLINEPLAYERS[@]}; do
						POSITION=$(grep "PlayerLocation=" "$PLAYERFILE/$player")
						POSITION=${POSITION/*=}
						SCANRESULT="$SCANRESULT $player=($POSITION)"
					done
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER Receiving scan data: $SCANRESULT\n'"
					;;
				*"Schnitzel"*)
					FNAME=$(grep "FactionName=" "$FACTIONFILE/$FACTIONID")
					FNAME=${FNAME/FactionName=}
					as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"$PLAYER found the beacon $SOURCE for his faction $FNAME (ID:$FACTIONID)\"\n'"
					old=$(grep "beaconpoints=" "$FWFACTIONFILEPFX$FACTIONID.txt")
					old=${old//*=}
					old=${old// }
					as_user "sed -i 's/beaconpoints=$old/beaconpoints=$(($old + 1))/g' '$FWFACTIONFILEPFX$FACTIONID.txt'"
					;;
				*"Pirate"*)
					echo "Beacon says: \"Spawn a pirate: $DEFAULTPIRATEBP for me!\""
					POSITION=$(grep "PlayerLocation=" "$PLAYERFILE/$PLAYER")
					POSITION=${POSITION/*=}
					POSITION=${POSITION//,/ }
					as_user "screen -p 0 -S $SCREENID -X stuff $'/server_message_broadcast info \"Receiving emergency signal of a beacon at ($POSITION). Pirates will be there soon\"\n'"
					sleep 30
					as_user "screen -p 0 -S $SCREENID -X stuff $'/spawn_entity $DEFAULTPIRATEBP MOB_${DEFAULTPIRATEBP}_$RANDOM $POSITION -1 true\n'"
					;;
				*"Silver"*)
					echo "Beacon says: \"Give me silver!\""
					as_user "screen -p 0 -S $SCREENID -X stuff $'/give $PLAYER \"Silver Bar\" $BEACONSILVER\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER \"You just got $BEACONSILVER silver bars!\"\n'"
					TIMESTAMP=$(date +%s)
					as_user "echo 'time=$TIMESTAMP player=$1 amount=$BEACONSILVER type=BEACON' >> '$SILVEREXCHANGELOG'"
					;;
				*"Faction"*)
					echo "Beacon says: \"Give my faction FPs!\""
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER \"Your faction got ${BEACONFACTIONPOINTS}FP from a Factionbeacon!\"\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_add $FACTIONID $BEACONFACTIONPOINTS\n'"
					;;
				*"Vanta"*)
					echo "Beacon says: \"Give me vanta!\""
					as_user "screen -p 0 -S $SCREENID -X stuff $'/give $PLAYER \"Vanta\" 10\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER \"You just got 10 Vanta blocks!\"\n'"
					;;
				*"Credit"*)
					echo "Beacon says: \"Give me credits!\""
					as_user "screen -p 0 -S $SCREENID -X stuff $'/give_credits $PLAYER $BEACONCREDITS\n'"
					as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $PLAYER \"You just got $BEACONCREDITS Credits!\"\n'"
					CREDITS=$(grep "CurrentCredits=" "$PLAYERFILE/$PLAYER")
					CREDITS=${CREDITS/*=}
					CREDITS=$(($CREDITS + $BEACONCREDITS))
					as_user "sed -i 's/CurrentCredits=.*/CurrentCredits=$CREDITS/g' '$PLAYERFILE/$PLAYER'"
					BEACONGAIN=$(grep "ActualCreditGain_Beacons=" "$CREDITSTATUSFILE")
					BEACONGAIN=$(($BEACONGAIN + $BEACONCREDITS))
					as_user "sed -i 's/ActualCreditGain_Beacons=.*/ActualCreditGain_Beacons=$BEACONGAIN/g' '$CREDITSTATUSFILE'"
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

sm_get_rnd_beacon_fn(){
#POSSIBLEFUNCTIONS=( Faction Faction Pirate Silver Silver Scanner Random Schnitzel None )
if [ ${#SPAWNPOSSIBLEFUNCTIONS[@]} -ge 1 ]
then
	RNDFUNCTION=$(( $RANDOM % ${#SPAWNPOSSIBLEFUNCTIONS[@]} ))
	RNDFUNCTION=${SPAWNPOSSIBLEFUNCTIONS[$RNDFUNCTION]}
fi
}

sm_spawn_thread() {
#startup sleep
sleep 30
while [ -e /proc/$SM_LOG_PID ]; do
	sm_spawn_round
	sleep $SPAWNTIMER
done
}

sm_spawn_round() {
# CB_<function>_GN_2_2_2_<nr>_RND
# BEACONPREFIX = CB_
# FUNCTION = f.e. Scanner
# _
# NAME = GENERATEDPREFIX(GN_) POSITION(2_2_2) Nr/Name(_ABC or _1) RANDOMNUMMER(_12857) to prevent abuse
SPAWNLIST=$(grep "GN_" $SPAWNBEACONLISTFILE)
pl_fwf_reload_checkpoints
OLD="$(grep "FUNCTIONALBEACONS=" "$FACTIONWARFARECONFIG")"
NEW=$OLD
for spawn in $SPAWNLIST; do
	if [[ " $FUNCTIONALBEACONS " =~ "_${spawn}_" ]]
	then
		continue
	fi
	POS=${spawn/GN_}
	#POS=${POS%_*}
	POS=(${POS//_/ })
	POS="${POS[0]} ${POS[1]} ${POS[2]}"
	sm_get_rnd_beacon_fn
	if [ "$RNDFUNCTION" == "None" ]
	then
		continue
	fi
	ENTITY="CB_${RNDFUNCTION}_${spawn}_$RANDOM"

	NEW="${NEW:0: -1}"
	NEW="$NEW$ENTITY )"

	BP="${DEFAULTBEACONBP}_$RNDFUNCTION"
	echo "$BP $ENTITY $POS"
	as_user "screen -p 0 -S $SCREENID -X stuff $'/spawn_entity $BP $ENTITY $POS -2 false\n'"
done
#RNDX=$(( $RANDOM % 129 - 64 ))
#RNDY=$(( $RANDOM % 129 - 64 ))
#RNDZ=$(( $RANDOM % 129 - 64 ))
as_user "sed -i 's/$OLD/$NEW/g' '$FACTIONWARFARECONFIG'"
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
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 \"${checkpoint_status[@]}\"\n'"
	fi
}

function COMMAND_FW_POINTS(){
#Allows you to see the current Warpoints of ALL, OWN or a factionid
#USAGE: !FW_POINTS <ALL,OWN,factionid>
	if [ "$#" -ne "2" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_POINTS <ALL,OWN or factionid>\n'"
	else
		param=$(echo $2 | tr [a-z] [A-Z])
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
			if [ "$param" == "OWN" ]
			then
				FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$1")
				FACTIONID=${FACTIONID/*=}
				FACTIONID=${FACTIONID// }
				pl_fwf_check_factionfile $FACTIONID
				tmp=$(grep "currentwp=" "$FWFACTIONFILEPFX$FACTIONID.txt")
				tmp=${tmp//*=}
				tmp=${tmp// }
				wps="$wps Your Faction has $tmp WP"
			else if [ "$param" == "ALL" ]
			then
				FACTIONS=($(ls "$FWFACTIONFILEPFX"*.txt 2>/dev/null))
				for ffile in ${FACTIONS[@]}; do
					fid=${ffile/.txt}
					fid=${fid/*faction}
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
					FNAME=$(grep "FactionName=" "$FACTIONFILE/$FACTIONID")
					FNAME=${FNAME/FactionName=}
					tmp=$(grep "currentwp=" "$FWFACTIONFILEPFX$FACTIONID.txt")
					tmp=${tmp//*=}
					tmp=${tmp// }
					wps="$wps Faction $FNAME (ID:$FACTIONID) has $tmp WP"
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
#Exchanges WPs to factionpoints or silver
#USAGE: !FW_EXCHANGE <fp/silver> <amount>
	if [ "$#" -ne "3" ]
	then
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !FW_WPEXCHANGE fp/silver/credits nr. Exchange factor 1wp = ${WPEXCHANGERATEFP}FP or 1wp=${WPEXCHANGERATESILVER} silver or 1wp=${WPEXCHANGERATECREDITS} Credits\n'"
	else
		FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$1")
		FACTIONID=${FACTIONID/*=}
		FACTIONID=${FACTIONID// }
		wptosub=$3
		old_wpoints=$(grep "currentwp=" "$FWFACTIONFILEPFX$FACTIONID.txt")
		old_wpoints=${old_wpoints//*=}
		old_wpoints=${old_wpoints// }
		new_wpoints=$(($old_wpoints - $wptosub))
		if [ $new_wpoints -ge 0 ]
		then
			if [ $2 = "fp" ] && [ $WPEXCHANGERATEFP -gt 0 ]
			then
				as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$FACTIONID.txt"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/faction_point_add $FACTIONID $(($WPEXCHANGERATEFP * $3))\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Exchanged $wptosub WP into $(($WPEXCHANGERATEFP * $3)) FP\n'"
			else if [ $2 = "silver" ] && [ $WPEXCHANGERATESILVER -gt 0 ]
			then
				as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$FACTIONID.txt"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/give $1 silver $(($WPEXCHANGERATESILVER * $3))\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Exchanged $wptosub WP into $(($WPEXCHANGERATESILVER * $3)) silver\n'"
				TIMESTAMP=$(date +%s)
				as_user "echo 'time=$TIMESTAMP player=$1 amount=$(($WPEXCHANGERATESILVER * $3)) type=WP' >> '$SILVEREXCHANGELOG'"
			else if [ $2 = "credits" ] && [ $WPEXCHANGERATECREDITS -gt 0 ]
			then
				as_user "sed -i 's/currentwp=$old_wpoints/currentwp=$new_wpoints/g' $FWFACTIONFILEPFX$FACTIONID.txt"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/give_credits $1 $(($WPEXCHANGERATECREDITS * $3))\n'"
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Exchanged $wptosub WP into $(($WPEXCHANGERATECREDITS * $3)) ccredits\n'"
				CREDITS=$(grep "CurrentCredits=" "$PLAYERFILE/$1")
				CREDITS=${CREDITS/*=}
				CREDITS=$(($CREDITS + $WPEXCHANGERATECREDITS * $3))
				as_user "sed -i 's/CurrentCredits=.*/CurrentCredits=$CREDITS/g' '$PLAYERFILE/$1'"
			else
				as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 FW_WPEXCHANGE: second argument has to be either fp, silver or credits. Use without parameters to see exchangerates!\n'"
			fi
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
		#as_user "screen -p 0 -S $SCREENID -X stuff $'/destroy_uid ENTITY_SHIP_$beacon\n'"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/despawn_all $beacon all true\n'"
	done
	as_user "sed -i 's/FUNCTIONALBEACONS=.*/FUNCTIONALBEACONS=( )/g' '$FACTIONWARFARECONFIG'"
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Cleaned up the mess. The whole beaconlist got deleted and all matching entities got destroyed\n'"
fi
}

function COMMAND_SCANGLOBAL(){
FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$1")
FACTIONID=${FACTIONID/*=}
FACTIONID=${FACTIONID// }
if [ "$FACTIONID" == "None" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You are not in a faction!\n'"
	return
fi

sumowned=$(grep -c "_Scanner_.*$FACTIONID" "$FWCHECKPOINTSFILE")
if [ $sumowned -eq 0 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Your faction does not own a scanner-checkpoint!\n'"
	return
fi

pl_fwf_check_factionfile $FACTIONID
WPS=$(grep "currentwp=" "$FWFACTIONFILEPFX$FACTIONID.txt")
WPS=${WPS//*=}
WPS=${WPS// }
if [ $WPS -lt $SCANCOSTGLOBAL ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Your faction has not enough WP, a global scan costs $SCANCOSTGLOBAL WP!\n'"
	return
fi
WPS=$(($WPS - $SCANCOSTGLOBAL))
as_user "sed -i 's/currentwp=.*/currentwp=$WPS/g' '$FWFACTIONFILEPFX$FACTIONID.txt'"

ONLINEPLAYERS=($(cat $ONLINELOG))
SCANRESULT=""
for player in ${ONLINEPLAYERS[@]}; do
	POSITION=$(grep "PlayerLocation=" "$PLAYERFILE/$player")
	POSITION=${POSITION/*=}
	SCANRESULT="$SCANRESULT $player=($POSITION)"
done
#as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Receiving scan data: $SCANRESULT\n'"
as_user "screen -p 0 -S $SCREENID -X stuff $'/chatchannel \"Faction$FACTIONID\" \"Receiving scan data: $SCANRESULT\"\n'"

}

function COMMAND_SCANFACTION(){
if [ "$#" -ne "2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !SCANFACTION <faction id>\n'"
	return
fi

if [ ! -e "$FACTIONFILE/$2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Faction with ID $2 does not exist!\n'"
	return
fi

FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$1")
FACTIONID=${FACTIONID/*=}
FACTIONID=${FACTIONID// }
if [ "$FACTIONID" == "None" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You are not in a faction!\n'"
	return
fi

sumowned=$(grep -c "_Scanner_.*$FACTIONID" "$FWCHECKPOINTSFILE")
if [ $sumowned -eq 0 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Your faction does not own a scanner-checkpoint!\n'"
	return
fi

pl_fwf_check_factionfile $FACTIONID
WPS=$(grep "currentwp=" "$FWFACTIONFILEPFX$FACTIONID.txt")
WPS=${WPS//*=}
WPS=${WPS// }
if [ $WPS -lt $SCANCOSTGLOBAL ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Your faction has not enough WP, a global scan costs $SCANCOSTGLOBAL WP!\n'"
	return
fi
WPS=$(($WPS - $SCANCOSTGLOBAL))
as_user "sed -i 's/currentwp=.*/currentwp=$WPS/g' '$FWFACTIONFILEPFX$FACTIONID.txt'"

list_players_of_faction $2
SCANRESULT=""
for player in ${PLAYERS[@]}; do
	POSITION=$(grep "PlayerLocation=" "$PLAYERFILE/$player")
	POSITION=${POSITION/*=}
	SCANRESULT="$SCANRESULT $player=($POSITION)"
done
#as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Receiving scan data for faction $2: $SCANRESULT\n'"
as_user "screen -p 0 -S $SCREENID -X stuff $'/chatchannel \"Faction$FACTIONID\" \"Receiving scan data for faction $2: $SCANRESULT\"\n'"
}

function COMMAND_SCANPLAYER(){
if [ "$#" -ne "2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !SCANPLAYER <name>\n'"
	return
fi

if [ ! -e "$PLAYERFILE/$2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Player ID $2 does not exist!\n'"
	return
fi

FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$1")
FACTIONID=${FACTIONID/*=}
FACTIONID=${FACTIONID// }
if [ "$FACTIONID" == "None" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 You are not in a faction!\n'"
	return
fi

sumowned=$(grep -c "_Scanner_.*$FACTIONID" "$FWCHECKPOINTSFILE")
if [ $sumowned -eq 0 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Your faction does not own a scanner-checkpoint!\n'"
	return
fi


BALANCE=$(grep "CreditsInBank=" "$FACTIONFILE/$FACTIONID")
BALANCE=${BALANCE//*=}
BALANCE=${BALANCE// }
if [ $BALANCE -lt 400000 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Your faction has not enough Credits in bank, a playerscan costs 400000!\n'"
	return
fi
BALANCE=$(($BALANCE - 400000))
as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$BALANCE/g' '$FACTIONFILE/$FACTIONID'"

POSITION=$(grep "PlayerLocation=" "$PLAYERFILE/$2")
POSITION=${POSITION/*=}
#as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Receiving scan data for player $2: ($POSITION)\n'"
as_user "screen -p 0 -S $SCREENID -X stuff $'/chatchannel \"Faction$FACTIONID\" \"Receiving scan data for player $2: ($POSITION)\"\n'"

CREDITLOSS=$(grep "ActualCreditLoss_Other=" "$CREDITSTATUSFILE")
CREDITLOSS=$(($CREDITLOSS + 400000))
as_user "sed -i 's/ActualCreditLoss_Other=.*/ActualCreditLoss_Other=$CREDITLOSS/g' '$CREDITSTATUSFILE'"
}