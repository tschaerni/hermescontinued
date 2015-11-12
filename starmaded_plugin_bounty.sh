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
#source "$CONFIGPATH"

if [ ! -e "$BOUNTYFILES" ]
then
	as_user "mkdir $BOUNTYFILES"
fi

if [ ! -e "$BOUNTYFILESCONFIG" ]
then
	pl_bounty_write_config_file
fi

source "$BOUNTYFILESCONFIG"

if [ ! -e "$BOUNTYFILEPLAYER" ]
then
	as_user "echo \"#This file containes bounty on players\" > $BOUNTYFILEPLAYER"
fi

if [ ! -e "$BOUNTYFILEFACTION" ]
then
	as_user "echo \"#This file containes bounty on factions\" > $BOUNTYFILEFACTION"
fi
pl_bounty_list_all
}


pl_bounty_write_config_file() {
CONFIGCREATE="cat > $BOUNTYFILESCONFIG <<_EOF_
#  Config file for Bounty Plugin
#  BOUNTYFILEPLAYER:    Here all bounty-entries for players are listed
#  BOUNTYFILEFACTION:   Here all bounty-entries for factions are listed
#  BOUNTYADDEDPERKILL:  How much bounty gets automatically set onto a player for each kill he performs
#  BOUNTYGARANTED:      How much a player gets for a kill, even if no bounty is set
#  BOUNTYFEE:           Percentage of Fee for setting bounty f.e.: 0 for none, 5 for 5%
#  CREDITDROPPERCENTAGE:Percentage of Credits dropped on death. (Dropped means directly transfered to the killer)
BOUNTYFILEPLAYER=$BOUNTYFILES/player_bounty
BOUNTYFILEFACTION=$BOUNTYFILES/faction_bounty
BOUNTYADDEDPERKILL=1000
BOUNTYGARANTED=1000
BOUNTYFEE=0
CREDITDROPPERCENTAGE=10
_EOF_"
as_user "$CONFIGCREATE"
}

pl_bounty_kill() {
#remove * and ;
TMPSTR=${1//'*'}
TMPSTR=${TMPSTR//;}
#Get name of killed player
KILLEDFACTION=($TMPSTR)
KILLEDPLAYER=${KILLEDFACTION[1]}
KILLEDPLAYER=${KILLEDPLAYER/PlS[}
#Get faction of killed player
KILLEDFACTION=${KILLEDFACTION[3]}
#if the server doesn't use the StarMader Registry
if [ "$KILLEDFACTION" == "Announcing" ]
then
	KILLEDFACTION=${KILLEDFACTION[2]}
fi
KILLEDFACTION=${KILLEDFACTION/*f(}
KILLEDFACTION=${KILLEDFACTION/)]}
if [ $KILLEDFACTION -eq 0 ]
then
	KILLEDFACTION="None"
fi

#remove full first term including the serachstring 
TMPSTR=${TMPSTR//*Announcing kill: }
#now the next term could begin with "Ship" "PlayerCharacter" "HeatMissile" "FafoMissile" "Planet" "Sector" "PLS" "AICharacter"
SOURCETYP=${TMPSTR//\[*}
KILLERNAME=${TMPSTR//]*}
KILLERNAME=${KILLERNAME//*\[}
KILLERFACTION=0
case "$SOURCETYP" in
	*"Ship"*)
		echo "$KILLEDPLAYER of faction $KILLEDFACTION got killed by a $SOURCETYP named $KILLERNAME"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/ship_info_uid \"ENTITY_SHIP_$KILLERNAME\"\n'"
		sleep 1
#[SERVER-LOCAL-ADMIN] DatabaseEntry [uid=ENTITY_SHIP_Station_Piratestation Gamma_8_5_5_144596482932710, sectorPos=(8, 5, 5), type=5, seed=0, lastModifier=, spawner=<system>, realName=Station_Piratestation Gamma_8_5_5_144596482932710, touched=true, faction=-1, pos=(0.0, -28.5, 101.0), minPos=(-1, -1, -1), maxPos=(1, 1, 1), creatorID=0]
# --------------- If not found serach for something like this -------------
#[SERVER-LOCAL-ADMIN] UID Not Found in DB: ENTITY_SHIP_NullPointer_1446064354948; checking unsaved objects
#[SERVER-LOCAL-ADMIN] Attached: [PlS[AceFist [derblauefalke]*; id(321)(3)f(0)]]
		ENTITYINFO=$(tac /dev/shm/output.log | grep -m 1 "\[SERVER-LOCAL-ADMIN\] DatabaseEntry \[uid=ENTITY_SHIP_$KILLERNAME, ")
		if [ -n "$ENTITYINFO" ]
		then
			KILLERFACTION=${ENTITYINFO//*faction=}
			KILLERFACTION=${KILLERFACTION//,*}
			echo "Faction of Killer: $KILLERFACTION"
			pl_bounty_kill_indirect
		else
			echo "Was an unsaved Entity, or we were too fast"
		fi
		;;
	*"PlayerCharacter"*)
		KILLERNAME=${KILLERNAME//*ENTITY_PLAYERCHARACTER_}
		KILLERNAME=${KILLERNAME//)*}
		echo "$KILLEDPLAYER of faction $KILLEDFACTION got killed by a $SOURCETYP named $KILLERNAME"
		pl_bounty_kill_direct
		;;
	*"PlS"*)
		KILLERNAME=${TMPSTR//PlS[}
		KILLERNAME=${KILLERNAME// *}
		echo "$KILLEDPLAYER of faction $KILLEDFACTION got killed by a $SOURCETYP named $KILLERNAME"
		if [ "$KILLEDPLAYER" != "$KILLERNAME" ]
		then
			echo "Got non sucide from a PlS"
			pl_bounty_kill_direct
		fi
		;;
	*"HeatMissile"*)
		echo "$KILLEDPLAYER of faction $KILLEDFACTION got killed by a $SOURCETYP named $KILLERNAME"
		;;
	*)
		echo "$KILLEDPLAYER of faction $KILLEDFACTION got killed by a $SOURCETYP named $KILLERNAME"
		;;
esac
KILLS=$(grep "PlayerDeaths=" "$PLAYERFILE/$KILLEDPLAYER")
KILLS=${KILLS/*=}
((KILLS++))
as_user "sed -i 's/PlayerDeaths=.*/PlayerDeaths=$KILLS/g' '$PLAYERFILE/$KILLEDPLAYER'"
if [ $KILLEDFACTION != "None" ]
then
	KILLS=$(grep "FactionDeaths=" "$FACTIONFILE/$KILLEDFACTION")
	KILLS=${KILLS/*=}
	((KILLS++))
	as_user "sed -i 's/FactionDeaths=.*/FactionDeaths=$KILLS/g' '$FACTIONFILE/$KILLEDFACTION'"
fi
as_user "screen -p 0 -S $SCREENID -X stuff $'/give_laser_weapon $KILLEDPLAYER\n'"
}

pl_bounty_kill_direct() {
if [ -e "$PLAYERFILE/$KILLERNAME" ]
then
	KILLERFACTION=$(grep "PlayerFaction=" "$PLAYERFILE/$KILLERNAME")
	KILLERFACTION=${KILLERFACTION/*=}
	KILLERFACTION=${KILLERFACTION// }
	if [ "$KILLERFACTION" == "None" ] || [ "$KILLERFACTION" != "$KILLEDFACTION" ]
	then
		pl_bounty_calc_take_bounty
		pl_bounty_credit_drops
		BOUNTY=$(($PLAYERBOUNTY + $FACTIONBOUNTY))
		if [ $BOUNTY -le 0 ] && [ $DROPEDCREDITS -le 0 ]
		then
			as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $KILLERNAME No bounty was set on ${KILLEDPLAYER}\s head!\n'"
			return
		fi
		BANKBALANCE=$(grep "CreditsInBank=" "$PLAYERFILE/$KILLERNAME")
		BANKBALANCE=${BANKBALANCE/*=}
		NEW=$(($BANKBALANCE + $BOUNTY + $DROPEDCREDITS))
		as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEW/g' '$PLAYERFILE/$KILLERNAME'"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $KILLERNAME You got $BOUNTY Credits from bounty and $DROPEDCREDITS Credits from creditdrop transfered onto your bankaccount for killing ${KILLEDPLAYER}!\n'"
		pl_bounty_list_all

		KILLS=$(grep "PlayerKills=" "$PLAYERFILE/$KILLERNAME")
		KILLS=${KILLS/*=}
		((KILLS++))
		as_user "sed -i 's/PlayerKills=.*/PlayerKills=$KILLS/g' '$PLAYERFILE/$KILLERNAME'"
	fi
fi
}

pl_bounty_kill_indirect() {
if [ -n "$KILLERFACTION"  ] && [ $KILLERFACTION -gt 0 ] && [ "$KILLEDFACTION" -ne "$KILLERFACTION" ]
then
	if [ -e "$FACTIONFILE/$KILLERFACTION" ]
	then
		pl_bounty_calc_take_bounty
		pl_bounty_credit_drops
		BOUNTY=$(($PLAYERBOUNTY + $FACTIONBOUNTY))
		if [ $BOUNTY -le 0 ]
		then
			return
		fi
		BANKBALANCE=$(grep "CreditsInBank=" "$FACTIONFILE/$KILLERFACTION")
		BANKBALANCE=${BANKBALANCE/*=}
		NEW=$(($BANKBALANCE + $BOUNTY + $DROPEDCREDITS))
		as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEW/g' '$FACTIONFILE/$KILLERFACTION'"
		as_user "screen -p 0 -S $SCREENID -X stuff $'/chatchannel \"Faction$KILLERFACTION\" \"Your Faction got $BOUNTY Credits from bounty and $DROPEDCREDITS Credits from creditdrop transfered onto your bankaccount for killing ${KILLEDPLAYER}!\"\n'"
		pl_bounty_list_all

		KILLS=$(grep "FactionKills=" "$FACTIONFILE/$KILLERFACTION")
		KILLS=${KILLS/*=}
		((KILLS++))
		as_user "sed -i 's/FactionKills=.*/FactionKills=$KILLS/g' '$FACTIONFILE/$KILLERFACTION'"
	fi
fi
}

pl_bounty_credit_drops() {
DROPEDCREDITS=0
if [ $CREDITDROPPERCENTAGE -gt 0 ]
then
	log_playerinfo $KILLEDPLAYER
	CURCREDITS=$(grep "CurrentCredits=" "$PLAYERFILE/$KILLEDPLAYER")
	CURCREDITS=${CURCREDITS//*=}
	CURCREDITS=${CURCREDITS// }
	DROPEDCREDITS=$(($CURCREDITS * $CREDITDROPPERCENTAGE / 100))
	CURCREDITS=$(($CURCREDITS - $DROPEDCREDITS))
	as_user "screen -p 0 -S $SCREENID -X stuff $'/give_credits $KILLEDPLAYER -$DROPEDCREDITS\n'"
	as_user "sed -i 's/CurrentCredits=.*/CurrentCredits=$CURCREDITS/g' '$PLAYERFILE/$KILLEDPLAYER'"
	#TODO add it to reward
fi
}

pl_bounty_turn() {
as_user "mv '$BOUNTYFILEPLAYER' '${BOUNTYFILEPLAYER}_tmp'"
as_user "echo \"#This file containes bounty on players\" > $BOUNTYFILEPLAYER"
OLD_IFS=$IFS
IFS=$'\n'
BOUNTYSTRING=($(grep "PlayerWanted=" "${BOUNTYFILEPLAYER}_tmp"))
IFS=$OLD_IFS
i=0
while [ $i -lt ${#BOUNTYSTRING[@]} ]; do
	LINE=(${BOUNTYSTRING[$i]})
	TURNSLEFT=${LINE[4]/*=}
	((TURNSLEFT--))
	LINE[4]="DeadlineTurnsLeft=$TURNSLEFT"
	balance=${LINE[3]/*=}
	bounty=${LINE[2]/*=}
	if [ $TURNSLEFT -gt 0 ] && [ $balance -ge $bounty ]
	then
		TMP="${LINE[@]}"
		as_user "echo \"$TMP\" >> $BOUNTYFILEPLAYER"
	else
#Give money back
		PLAYER=${LINE[1]/*=}
		BANKBALANCE=$(grep "CreditsInBank=" "$PLAYERFILE/$PLAYER")
		BANKBALANCE=${BANKBALANCE/*=}
		NEW=$(($BANKBALANCE + $balance))
		as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEW/g' '$PLAYERFILE/$PLAYER'"
	fi
	((i++))
done
as_user "rm '${BOUNTYFILEPLAYER}_tmp' 2>/dev/null"

as_user "mv '$BOUNTYFILEFACTION' '${BOUNTYFILEFACTION}_tmp'"
as_user "echo \"#This file containes bounty on factions\" > $BOUNTYFILEFACTION"
OLD_IFS=$IFS
IFS=$'\n'
BOUNTYSTRING=($(grep "FactionWanted=" "${BOUNTYFILEFACTION}_tmp"))
IFS=$OLD_IFS
i=0
while [ $i -lt ${#BOUNTYSTRING[@]} ]; do
	LINE=(${BOUNTYSTRING[$i]})
	TURNSLEFT=${LINE[4]/*=}
	((TURNSLEFT--))
	LINE[4]="DeadlineTurnsLeft=$TURNSLEFT"
	balance=${LINE[3]/*=}
	bounty=${LINE[2]/*=}
	if [ $TURNSLEFT -gt 0 ] && [ $balance -ge $bounty ]
	then
		TMP="${LINE[@]}"
		as_user "echo \"$TMP\" >> $BOUNTYFILEFACTION"
	else
#Give money back
		FACTIONID=${LINE[1]/*=}
		BANKBALANCE=$(grep "CreditsInBank=" "$FACTIONFILE/$FACTIONID")
		BANKBALANCE=${BANKBALANCE/*=}
		NEW=$(($BANKBALANCE + $balance))
		as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEW/g' '$FACTIONFILE/$FACTIONID'"
	fi
	((i++))
done
rm "${BOUNTYFILEFACTION}_tmp" 2>/dev/null
pl_bounty_list_all
}

pl_bounty_calc_take_bounty() {
OLD_IFS=$IFS
IFS=$'\n'
BOUNTYSTRING=($(grep "PlayerWanted=$KILLEDPLAYER" "$BOUNTYFILEPLAYER"))
IFS=$OLD_IFS
i=0
PLAYERBOUNTY=0
while [ $i -lt ${#BOUNTYSTRING[@]} ]; do
	LINE=(${BOUNTYSTRING[$i]})
	bounty=${LINE[2]/*=}
	balance=${LINE[3]/*=}
	if [ $bounty -le $balance ]
	then
		balance=$(($balance - $bounty))
		PLAYERBOUNTY=$(($PLAYERBOUNTY + $bounty))
		LINE[3]=${LINE[3]/=*}=$balance
		a="${BOUNTYSTRING[$i]}"
		b="${LINE[@]}"
		#as_user "sed -i 's/$a/$b' $BOUNTYFILEPLAYER"
		as_user "sed -i '0,/$a/s//$b/' $BOUNTYFILEPLAYER"
	fi
	((i++))
done

FACTIONBOUNTY=0
if [ "$KILLEDFACTION" != "None" ]
then
	OLD_IFS=$IFS
	IFS=$'\n'
	BOUNTYSTRING=($(grep "FactionWanted=$KILLEDFACTION" "$BOUNTYFILEFACTION"))
	IFS=$OLD_IFS
	i=0
	while [ $i -lt ${#BOUNTYSTRING[@]} ]; do
		LINE=(${BOUNTYSTRING[$i]})
		bounty=${LINE[2]/*=}
		balance=${LINE[3]/*=}
		if [ $bounty -le $balance ]
		then
			balance=$(($balance - $bounty))
			FACTIONBOUNTY=$(($FACTIONBOUNTY + $bounty))
			LINE[3]=${LINE[3]/=*}=$balance
			a="${BOUNTYSTRING[$i]}"
			b="${LINE[@]}"
			#as_user "sed -i 's/$a/$b' $BOUNTYFILEPLAYER"
			as_user "sed -i '0,/$a/s//$b/' '$BOUNTYFILEFACTION'"
		fi
		((i++))
	done
fi
echo "Bounty for $KILLEDPLAYER is $PLAYERBOUNTY + Factionbounty of $FACTIONBOUNTY"
}

pl_bounty_calc_bounty() {
FACTION=$(grep "PlayerFaction=" "$PLAYERFILE/$PLAYER" 2> /dev/null)
FACTION=${FACTION/*=}
FACTION=${FACTION// }
OLD_IFS=$IFS
IFS=$'\n'
BOUNTYSTRING=($(grep "PlayerWanted=$PLAYER" "$BOUNTYFILEPLAYER" 2> /dev/null))
IFS=$OLD_IFS
i=0
PLAYERBOUNTY=0
while [ $i -lt ${#BOUNTYSTRING[@]} ]; do
	LINE=(${BOUNTYSTRING[$i]})
	bounty=${LINE[2]/*=}
	balance=${LINE[3]/*=}
	if [ $bounty -le $balance ]
	then
		balance=$(($balance - $bounty))
		PLAYERBOUNTY=$(($PLAYERBOUNTY + $bounty))
	fi
	((i++))
done

FACTIONBOUNTY=0
if [ "$FACTION" != "None" ]
then
	OLD_IFS=$IFS
	IFS=$'\n'
	BOUNTYSTRING=($(grep "FactionWanted=$FACTION" "$BOUNTYFILEFACTION" 2> /dev/null))
	IFS=$OLD_IFS
	i=0
	while [ $i -lt ${#BOUNTYSTRING[@]} ]; do
		LINE=(${BOUNTYSTRING[$i]})
		bounty=${LINE[2]/*=}
		balance=${LINE[3]/*=}
		if [ $bounty -le $balance ]
		then
			balance=$(($balance - $bounty))
			FACTIONBOUNTY=$(($FACTIONBOUNTY + $bounty))
		fi
		((i++))
	done
fi
}

pl_bounty_list_all() {
OLD_IFS=$IFS
IFS=$'\n'
LINES=($(grep "PlayerWanted=" "$BOUNTYFILEPLAYER"))
PLAYERS=""
for line in ${LINES[@]}; do
	PLAYER=${line//*PlayerWanted=}
	PLAYER=${PLAYER// *}
	if [[ ! " $PLAYERS " =~ " $PLAYER " ]]
	then
		PLAYERS="$PLAYERS $PLAYER"
	fi
done
IFS=$OLD_IFS

as_user "echo '<root>' > /dev/shm/totalbounty.xml"
for PLAYER in ${PLAYERS[@]}; do
	pl_bounty_calc_bounty
	as_user "echo '	<entry Player=\"$PLAYER\" Totalbounty=\"$(($PLAYERBOUNTY + $FACTIONBOUNTY))\" Playerbounty=\"$PLAYERBOUNTY\" Factionbounty=\"$FACTIONBOUNTY\" />' >> /dev/shm/totalbounty.xml"
done
as_user "echo '</root>' >> /dev/shm/totalbounty.xml"
}

#Chat commands:
function COMMAND_SETPLAYERBOUNTY() {
#Param 1 = Playername 2 = Victimname 3 = Reward 4 = Balance 5 = Timespan
#PlayerWanted=Knack PlayerPrincipal=NullPointer Reward=1000 Balance=10000 DeadlineTurnsLeft=4
if [ $# -ne 5 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !SETPLAYERBOUNTY <playername> <bounty per kill> <balance> <duration in turns>\n'"
	return
fi
if [ ! "$3" -gt 0 ] || [ ! "$4" -gt 0 ] || [ ! "$5" -gt 0 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Reward, balance and timespan must be positive numbers!\n'"
	return
fi
if [ ! -e "$PLAYERFILE/$2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Wanted player does not exist!\n'"
	return
fi
if [ ! "$4" -ge "$3" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Balance must at least cover one reward!\n'"
	return
fi

BANKBALANCE=$(grep "CreditsInBank=" "$PLAYERFILE/$1")
BANKBALANCE=${BANKBALANCE/*=}
BANKBALANCE=${BANKBALANCE// }
if [ $BANKBALANCE -ge $4 ]
then
	NEW=$(($BANKBALANCE - $4))
	as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEW/g' '$PLAYERFILE/$1'"
	as_user "echo \"PlayerWanted=$2 PlayerPrincipal=$1 Reward=$3 Balance=$4 DeadlineTurnsLeft=$5\" >> $BOUNTYFILEPLAYER"
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Successfully set $3 bounty on $2\'s head for $5 turns. $4 credits were transfered to the bountyaccount.\n'"
	pl_bounty_list_all
else
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Insufficient funds on bankaccount!\n'"
fi
}

function COMMAND_SETFACTIONBOUNTY() {
#Param 1 = Playername 2 = VictimFaction 3 = Reward 4 = Balance 5 = Timespan
#FactionWanted=10001 FactionPrincipal=10002 Reward=1000 Balance=10000 DeadlineTurnsLeft=4
if [ $# -ne 5 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !SETFACTIONBOUNTY <factionid> <bounty per kill> <balance> <duration in turns>\n'"
	return
fi
if [ ! "$2" -gt 0 ] || [ ! "$3" -gt 0 ] || [ ! "$4" -gt 0 ] || [ ! "$5" -gt 0 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 FactionID, reward, balance and timespan must be positive numbers!\n'"
	return
fi
if [ ! -e "$FACTIONFILE/$2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Wanted faction does not exist!\n'"
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
if [ ! "$4" -ge "$3" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Balance must at least cover one reward!\n'"
	return
fi

BANKBALANCE=$(grep "CreditsInBank=" "$FACTIONFILE/$FACTIONID")
BANKBALANCE=${BANKBALANCE/*=}
BANKBALANCE=${BANKBALANCE// }
if [ $BANKBALANCE -ge $4 ]
then
	NEW=$(($BANKBALANCE - $4))
	as_user "sed -i 's/CreditsInBank=.*/CreditsInBank=$NEW/g' '$FACTIONFILE/$FACTIONID'"
	as_user "echo \"FactionWanted=$2 FactionPrincipal=$FACTIONID Reward=$3 Balance=$4 DeadlineTurnsLeft=$5\" >> $BOUNTYFILEFACTION"
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Successfully set $3 bounty on faction $2\'s head for $5 turns. $4 credits were transfered from faction bankaccount to the bountyaccount.\n'"
	pl_bounty_list_all
else
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Insufficient funds on faction bankaccount!\n'"
fi
}

function COMMAND_GETFACTIONID() {
if [ $# -ne 2 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !GETFACTIONID <playername>\n'"
	return
fi
if [ ! -e "$PLAYERFILE/$2" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Player $2 does not exist!\n'"
	return
fi
FACTIONID=$(grep "PlayerFaction=" "$PLAYERFILE/$2")
FACTIONID=${FACTIONID/*=}
FACTIONID=${FACTIONID// }
if [ "$FACTIONID" == "None" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Player $2 is not in a faction!\n'"
	return
fi
FNAME=$(grep "FactionName=" "$FACTIONFILE/$FACTIONID")
FNAME=${FNAME/FactionName=}
as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Player $2 is in the faction $FNAME (ID:$FACTIONID) !\n'"
}

function COMMAND_GETPLAYERBOUNTY() {
if [ $# -ne 2 ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Invalid parameters. Please use !GETPLAYERBOUNTY <playername>\n'"
	return
fi
PLAYER=$2
if [ ! -e "$PLAYERFILE/$PLAYER" ]
then
	as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Wanted player does not exist!\n'"
	return
fi
pl_bounty_calc_bounty
echo "Bounty for $PLAYER is $PLAYERBOUNTY + Factionbounty of $FACTIONBOUNTY"
as_user "screen -p 0 -S $SCREENID -X stuff $'/pm $1 Player $PLAYER has $PLAYERBOUNTY Credits on his head and his faction $FACTIONBOUNTY Credits!\n'"
}