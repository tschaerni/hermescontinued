#!/bin/bash
#Plugin main function (Every plugin has to have this function, named like the pluin itself)
bounty() {
SEARCHKILL="Announcing kill:"
SEARCHFACTIONTURN="[FACTIONMANAGER] faction update took:"
case "$1" in
	*"$SEARCHKILL"*)
		pl_bounty_kill "$1" &
		;;
	*"$SEARCHFACTIONTURN"*)
		pl_bounty_turn "$1" &
		;;
	*)
		;;
esac
}

#Plugin config function (Every plugin has to have this function)
bounty_config() {
if [ "$(grep "Plugin Bounty" "$CONFIGPATH")" = "" ]
then
#Declare default values here
	BOUNTYFILES="$STARTERPATH/bountyfiles"
	BOUNTYFILESCONFIG="$BOUNTYFILES/bountyconfig.cfg"
#Write config
	CONFIGCREATE="cat >> $CONFIGPATH <<_EOF_
#------------------------Plugin Bounty----------------------------------------------------------------------------
BOUNTYFILES=$STARTERPATH/bountyfiles #The folder that contains files for the bounty system
BOUNTYFILESCONFIG=$BOUNTYFILES/bountyconfig.cfg
_EOF_"
	as_user "$CONFIGCREATE"
fi
source "$CONFIGPATH"

if [ ! -e "$BOUNTYFILES" ]
then
	as_user "mkdir $BOUNTYFILES"
fi

if [ ! -e "$BOUNTYFILESCONFIG" ]
then
	pl_bounty_write_config_file
fi

source "$BOUNTYFILESCONFIG"

}


pl_bounty_write_config_file() {
CONFIGCREATE="cat > $BOUNTYFILESCONFIG <<_EOF_
#  Config file for Bounty Plugin
#  BOUNTYFILEPLAYER:   Here all bounty-entries for players are listed
#  BOUNTYFILEFACTION:  Here all bounty-entries for factions are listed
#  BOUNTYADDEDPERKILL: How much bounty gets automatically set onto a player for each kill he performs
#  BOUNTYGARANTED:     How much a player gets for a kill, even if no bounty is set
#  BOUNTYFEE:          Percentage of Fee for setting bounty f.e.: 0 for none, 5 for 5%
BOUNTYFILEPLAYER=$BOUNTYFILES/player_bounty
BOUNTYFILEFACTION=$BOUNTYFILES/faction_bounty
BOUNTYADDEDPERKILL=1000
BOUNTYGARANTED=1000
BOUNTYFEE=0
_EOF_"
as_user "$CONFIGCREATE"
}

pl_bounty_kill() {
echo "Found kill!"
#remove * and ;
TMPSTR=${1//'*'}
TMPSTR=${TMPSTR//;}
#Get name of killed player
KILLEDFACTION=($TMPSTR)
KILLEDPLAYER=${KILLEDFACTION[1]}
KILLEDPLAYER=${KILLEDPLAYER/PlS[}
#Get faction of killed player
KILLEDFACTION=${KILLEDFACTION[3]}
KILLEDFACTION=${KILLEDFACTION/*f(}
KILLEDFACTION=${KILLEDFACTION/)]}

#remove full first term including the serachstring 
TMPSTR=${TMPSTR//*Announcing kill: }
#now the next term could begin with "Ship" "PlayerCharacter" "HeatMissile" "FafoMissile" "Planet" "Sector" "PLS" "AICharacter"
SOURCETYP=${TMPSTR//\[*}
KILLERNAME=${TMPSTR//]*}
KILLERNAME=${KILLERNAME//*\[}
KILLERFACTION=0
case "$SOURCETYP" in
	*"Ship"*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/ship_info_uid \"ENTITY_SHIP_$KILLERNAME\"\n'"
		sleep 0.5
#[SERVER-LOCAL-ADMIN] DatabaseEntry [uid=ENTITY_SHIP_Station_Piratestation Gamma_8_5_5_144596482932710, sectorPos=(8, 5, 5), type=5, seed=0, lastModifier=, spawner=<system>, realName=Station_Piratestation Gamma_8_5_5_144596482932710, touched=true, faction=-1, pos=(0.0, -28.5, 101.0), minPos=(-1, -1, -1), maxPos=(1, 1, 1), creatorID=0]
# --------------- If not found serach for something like this -------------
#[SERVER-LOCAL-ADMIN] UID Not Found in DB: ENTITY_SHIP_NullPointer_1446064354948; checking unsaved objects
#[SERVER-LOCAL-ADMIN] Attached: [PlS[AceFist [derblauefalke]*; id(321)(3)f(0)]]
		ENTITYINFO=$(tac /dev/shm/output.log | grep -m 1 "\[SERVER-LOCAL-ADMIN\] DatabaseEntry \[uid=ENTITY_SHIP_$KILLERNAME, ")
		if [ -n $ENTIYINFO ]
		then
			KILLERFACTION=${ENTITYINFO//*faction=}
			KILLERFACTION=${KILLERFACTION//,*}
			echo "Faction of Killer: $KILLERFACTION"
		else
			echo "Was an unsaved Entity, or we were too fast"
		fi
		;;
	*"PlayerCharacter"*)
		KILLERNAME=${KILLERNAME//*ENTITY_PLAYERCHARACTER_}
		KILLERNAME=${KILLERNAME//)*}
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		KILLERFACTION=$(grep "PlayerFaction=" "$PLAYERFILE/$KILLERNAME")
		KILLERFACTION=${KILLERFACTION/*=}
		KILLERFACTION=${KILLERFACTION// }
		;;
	*"PlS"*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		KILLERFACTION=$(grep "PlayerFaction=" "$PLAYERFILE/$KILLERNAME")
		KILLERFACTION=${KILLERFACTION/*=}
		KILLERFACTION=${KILLERFACTION// }
		;;
	*"HeatMissile"*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		;;
	*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		;;
esac

if [ $KILLERFACTION -gt 0 ] && [ $KILLEDFACTION -ne $KILLERFACTION ]
then
	echo "No friendly fire, give killreward"
fi

}

pl_bounty_turn() {
  echo "Found Factionturn, now doing bounty turn"
}

pl_bounty_calc_take_bounty() {
OLD_IFS=$IFS
IFS=$'\n'
BOUNTYSTRING=($(grep "PlayerWanted=$KILLEDPLAYER" "$BOUNTYFILEPLAYER"))
IFS=$OLD_IFS
i=0
BOUNTY=0
while [ $i -lt ${#BOUNTYSTRING[@]} ]; do
	LINE=(${BOUNTYSTRING[$i]})
	bounty=${LINE[2]/*=}
	balance=${LINE[3]/*=}
	if [ $bounty -le $balance ]
	then
		balance=$(($balance - $bounty))
		BOUNTY=$(($BOUNTY + $bounty))
		LINE[3]=${LINE[3]/=*}=$balance
		a="${BOUNTYSTRING[$i]}"
		b="${LINE[@]}"
		#as_user "sed -i 's/$a/$b' $BOUNTYFILEPLAYER"
		as_user "sed -i '0,/$a/s//$b/' $BOUNTYFILEPLAYER"
	fi
	((i++))
done
echo "Bounty for $KILLEDPLAYER is $BOUNTY"
}

#Chat commands:
function COMMAND_SETPLAYERBOUNTY() {
#Param 1 = Playername 2 = Victimname 3 = Reward 4 = Balance 5 = Timespan
#PlayerWanted=Knack PlayerPrincipal=NullPointer Reward=1000 Balance=10000 DeadlineTurnsLeft=4
if [ $# -ne 5 ]
then
	echo "To less arguments"
	return
fi
if [ ! "$3" -gt 0 ] || [ ! "$4" -gt 0 ] || [ ! "$5" -gt 0 ]
then
	echo "Reward, balance and timespan must be positive numbers!"
	return
fi
if [ ! -e "$PLAYERFILE/$2" ]
then
	echo "Wanted player does not exist!"
	return
fi
if [ ! "$4" -ge "$3" ]
then
	echo "Balance must at least cover one reward!"
	return
fi

BANKBALANCE=$(grep "CreditsInBank=" "$PLAYERFILE/$1")
BANKBALANCE=${BANKBALANCE/*=}
BANKBALANCE=${BANKBALANCE// }
if [ $BANKBALANCE -ge $4 ]
then
	BANKBALANCE=$(grep "CreditsInBank=" "$PLAYERFILE/$1")
	NEW=$(($BANKBALANCE - $4))
	as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEW/g' '$PLAYERFILE/$1'"
	echo "PlayerWanted=$2 PlayerPrincipal=$1 Reward=$3 Balance=$4 DeadlineTurnsLeft=$5" >> $BOUNTYFILEPLAYER
else
	echo "Insufficient funds!"
fi
}

function COMMAND_SETFACTIONBOUNTY() {
	echo "Not implemented"
}