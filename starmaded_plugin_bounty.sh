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
case "$SOURCETYP" in
	*"Ship"*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		;;
	*"PlayerCharacter"*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		;;
	*"HeatMissile"*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		;;
	*)
		echo "$KILLEDPLAYER got killed by a $SOURCETYP named $KILLERNAME"
		;;
esac

}

pl_bounty_turn() {
  echo "Found Factionturn, now doing bounty turn"
}

#Chat commands:
function COMMAND_SETPLAYERBOUNTY() {
	echo "Not implemented"
#Param 1 = Playername 2 = Victimname 3 = Reward 4 = Balance 5 = Timespan
#PlayerWanted=Knack PlayerPrincipal=NullPointer Reward=1000 Balance=10000 DeadlineTurnsLeft=4
BANKBALANCE=$(grep "CreditsInBank=" "$PLAYERFILE\$1")
BANKBALANCE=${BANKBALANCE/*=}
BANKBALANCE=${BANKBALANCE// }
if [ $BANKBALANCE -ge $4 ]
then
echo aaal
fi
	echo "PlayerWanted=Knack PlayerPrincipal=$1 Reward=1000 Balance=10000 DeadlineTurnsLeft=4" >> BOUNTYFILEPLAYER
}

function COMMAND_SETFACTIONBOUNTY() {
	echo "Not implemented"
}