#!/system/bin/sh
# ##############################################################################
# Script Name   : afk-daily.sh
# Description   : Script automating daily
# Args          : [-c] [-e EVENT] [-f] [-g] [-i INI] [-l LOCATION]
#                 [-s TOTEST] [-t] [-v DEBUG] [-w]
# GitHub        : https://github.com/zebscripts/AFK-Daily
# License       : MIT
# ##############################################################################

# ##############################################################################
# Section       : Variables
# ##############################################################################
# Probably you don't need to modify this. Do it if you know what you're doing, I won't blame you (unless you blame me).

# Device settings
DEVICEWIDTH=1080

DEBUG=0
# DEBUG  = 0    Show no debug
# DEBUG >= 1    Show getColor calls > $HEX value
# DEBUG >= 2    Show test calls
# DEBUG >= 3    Show all core functions calls
# DEBUG >= 4    Show all functions calls
# DEBUG >= 9    Show tap calls

# Default settings
DEFAULT_DELTA=3 # Default delta for colors
DEFAULT_SLEEP=2 # equivalent to wait (default 2)

# Event flags
eventHoe=false          # Set to `true` if "Heroes of Esperia" event is live
eventTs=true            # Set to `true` if "Treasure Scramble" event is live
eventTv=false           # Set to `true` if "Treasure Vanguard" event is live
bountifulBounties=false # Set to `true` if "Bountiful Bounties" event is live

# Script state variables (Do not modify)
activeTab="Start"
activeEvents=""
currentPos="default"
dayofweek=$(TZ=UTC date +%u)
forceFightCampaign=false
forceWeekly=false
hasEnded=false
HEX=00000000
INILOCATION="/storage/emulated/0/scripts/afk-arena/"
INIFILE="config.ini"
oakRes=0
screenshotRequired=true
testServer=false
SCREENSHOTLOCATION="/storage/emulated/0/scripts/afk-arena/screen.dump"
withColors=true
hexdumpSu=false

# Colors
cNc="\033[0m"        # Text Reset
cRed="\033[0;91m"    # [ERROR]
cGreen="\033[0;92m"  # [OK]
cYellow="\033[0;93m" # [WARN]
cBlue="\033[0;94m"   # Values
cPurple="\033[0;95m" # [DEBUG]
cCyan="\033[0;96m"   # [INFO]

while getopts "ce:fgi:l:s:tv:w" opt; do
    case $opt in
    c)
        withColors=false
        ;;
    e)
        buIFS=$IFS
        # Explication: https://stackoverflow.com/a/7718539/7295428
        IFS=','
        for i in $OPTARG; do
            case "$i" in
            "hoe") eventHoe=true ;; # Heroes of Esperia
            "ts") eventTs=true ;;   # Treasure Scramble (same problem as HoE atm)
            "tv") eventTv=true ;;   # Treasure Vanguard (same problem as HoE atm)
            *)
                echo "Unknown event: $i" >&2
                ;;
            esac
        done
        IFS=$buIFS
        ;;
    f)
        forceFightCampaign=true
        ;;
    g)
        hexdumpSu=true
        ;;
    i)
        INIFILE="${OPTARG#config/}"
        ;;
    l)
        SCREENSHOTLOCATION="/$OPTARG/scripts/afk-arena/screen.dump"
        INILOCATION="/$OPTARG/scripts/afk-arena/"
        ;;
    s)
        totest=$OPTARG
        ;;
    t)
        testServer=true
        ;;
    v)
        DEBUG=$OPTARG
        ;;
    w)
        forceWeekly=true
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
done

. "$INILOCATION$INIFILE"
doLootAfkChest2="$doLootAfkChest"

# ##############################################################################
# Section       : Core Functions
# Description   : It's like a library of useful functions
# ##############################################################################

# ##############################################################################
# Function Name : checkToDo
# Description   : Check if argument is ToDo
# Args          : <TODO>: name of the variable containing the boolean
# Output        : return 0/1
# ##############################################################################
checkToDo() {
    if [ "$(eval echo \$"$1")" = false ]; then
        return 1
    fi
    if [ "$1" = "$currentPos" ]; then
        tries=$((tries + 1))
        printInColor "DEBUG" "checkToDo > $currentPos [$tries]"
    else
        eval "$currentPos=false"
        currentPos="$1"
        tries=0
    fi
    if [ $tries -lt 3 ]; then
        return 0
    else
        eval "$1=false"
        return 1
    fi
}

# ##############################################################################
# Function Name : closeApp
# Descripton    : Closes AFK Arena
# ##############################################################################
closeApp() {
    if [ "$testServer" = true ]; then
        am force-stop com.lilithgames.hgame.gp.id >/dev/null 2>/dev/null
    else
        am force-stop com.lilithgame.hgame.gp >/dev/null 2>/dev/null
    fi
}

# ##############################################################################
# Function Name : disableOrientation
# Descripton    : Disables automatic orientation
# ##############################################################################
disableOrientation() {
    content insert --uri content://settings/system --bind name:s:accelerometer_rotation --bind value:i:0
}

# ##############################################################################
# Function Name : getColor
# Descripton    : Sets $HEX, <-f> to force the screenshot
# Args          : [<-f>] <X> <Y>
# ##############################################################################
getColor() {
    logDebug "getColor ${cPurple}$*${cNc}" 3 "ENTER"

    for arg in "$@"; do
        shift
        case "$arg" in
        -f) screenshotRequired=true ;;
        *) set -- "$@" "$arg" ;;
        esac
    done
    takeScreenshot
    readHEX "$1" "$2"

    logDebug "getColor ${cPurple}$*${cNc} > HEX: ${cCyan}$HEX${cNc}" 1 "EXIT"
}

# ##############################################################################
# Function Name : getCounterInColor
# Descripton    : Print counter in color
# Args          : <TYPE> <COUNTER>
# ##############################################################################
getCounterInColor() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: getCounterInColor <TYPE> <COUNTER>" >&2
        echo " <TYPE>: L, W" >&2
        return
    fi
    if [ "$2" -eq 0 ]; then
        echo "${cYellow}$2 $1${cNc}"
    else
        if [ "$1" = "L" ]; then
            echo "${cRed}$2 $1${cNc}"
        elif [ "$1" = "W" ]; then
            echo "${cGreen}$2 $1${cNc}"
        fi
    fi
}

# ##############################################################################
# Function Name : getCountersInColor
# Descripton    : Print counters in color
# Args          : <COUNTER_WIN> [<COUNTER_LOOSE>]
# ##############################################################################
getCountersInColor() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: getCountersInColor <COUNTER_WIN> [<COUNTER_LOOSE>]" >&2
        return
    fi
    if [ "$#" -eq 1 ]; then
        echo "[$(getCounterInColor W "$1")]"
    elif [ "$#" -eq 2 ]; then
        echo "[$(getCounterInColor W "$1") / $(getCounterInColor L "$2")]"
    fi
}

# ##############################################################################
# Function Name : HEXColorDelta
# Args          : <COLOR1> <COLOR2>
# Output        : stdout [0 means similar colors, 100 means opposite colors]
# Source        : https://github.com/kevingrillet/ShellUtils/blob/main/utils/utils_colors.sh
# ##############################################################################
HEXColorDelta() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: HEXColorDelta <COLOR1> <COLOR2>" >&2
        echo " 0 means similar colors, 100 means opposite colors" >&2
        return
    fi
    logDebug "HEXColorDelta ${cPurple}$*${cNc}" 3
    r=$((0x${1:0:2} - 0x${2:0:2}))
    g=$((0x${1:2:2} - 0x${2:2:2}))
    b=$((0x${1:4:2} - 0x${2:4:2}))
    d=$((((765 - (${r#-} + ${g#-} + ${b#-})) * 100) / 765)) # 765 = 3 * 255
    d=$((100 - d))                                          # Delta is a distance... 0=same, 100=opposite need to reverse it
    echo $d
}

# ##############################################################################
# Function Name : inputSwipe
# Descripton    : Swipe
# Args          : <X> <Y> <XEND> <YEND> <TIME>
# ##############################################################################
inputSwipe() {
    logDebug "inputSwipe ${cPurple}$*${cNc}" 3 "ENTER"

    input touchscreen swipe "$1" "$2" "$3" "$4" "$5"
    sleep 2

    screenshotRequired=true

    logDebug "inputSwipe" 3 "EXIT"
}

# ##############################################################################
# Function Name : inputTapSleep
# Descripton    : input tap <X> <Y>, then SLEEP with default value DEFAULT_SLEEP
# Args          : <X> <Y> [<SLEEP>]
# ##############################################################################
inputTapSleep() {
    logDebug "inputTapSleep ${cPurple}$*${cNc}" 9 "ENTER"

    input tap "$1" "$2"          # tap
    sleep "${3:-$DEFAULT_SLEEP}" # sleep
    screenshotRequired=true

    logDebug "inputTapSleep" 9 "EXIT"
}

# ##############################################################################
# Function Name : loopUntilNotRGB
# Descripton    : Loops until HEX is not equal
# Args          : <SLEEP> <X> <Y> <COLOR> [<COLOR> ...]
# ##############################################################################
loopUntilNotRGB() {
    logDebug "loopUntilNotRGB ${cPurple}$*${cNc}" 3 "ENTER"

    sleep "$1"
    shift
    until testColorNAND -f "$@"; do
        sleep 1
    done

    logDebug "loopUntilRGB" 3 "EXIT"
}

# ##############################################################################
# Function Name : loopUntilRGB
# Descripton    : Loops until HEX is equal
# Args          : <SLEEP> <X> <Y> <COLOR> [<COLOR> ...]
# ##############################################################################
loopUntilRGB() {
    logDebug "loopUntilRGB ${cPurple}$*${cNc}" 3 "ENTER"

    sleep "$1"
    shift
    until testColorOR -f "$@"; do
        sleep 1
    done

    logDebug "loopUntilRGB" 3 "EXIT"
}

# ##############################################################################
# Function Name : printInColor
# Descripton    : Print message in color
# Args          : <TYPE> <MESSAGE>
# ##############################################################################
printInColor() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: printInColor <TYPE> <MESSAGE>" >&2
        echo " <TYPE>: DEBUG, DONE, ERROR, INFO, TEST, WARN" >&2
        return
    fi

    case "$1" in
    "DEBUG") msg="${cPurple}[DEBUG]${cNc} " ;;
    "DONE") msg="${cGreen}[DONE]${cNc}  " ;;
    "ERROR") msg="${cRed}[ERROR]${cNc} " ;;
    "INFO") msg="${cBlue}[INFO]${cNc}  " ;;
    "WARN") msg="${cYellow}[WARN]${cNc}  " ;;
    *) msg="        " ;;
    esac

    shift
    msg="$msg$1${cNc}" # The ${cNc} is a security if we forgot to reset color at the end of our message

    if [ "$withColors" = false ]; then
        msg=$(echo "$msg" | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g') # Source: https://stackoverflow.com/a/54648447
    fi

    echo "$msg"
}

# ##############################################################################
# Function Name : logDebug
# Description   : Logs debug messages based on the DEBUG level set.
# Args          : <MESSAGE> <LOG_LEVEL> [<MESSAGE_TYPE>]
#                   <MESSAGE>: The message to log.
#                   <LOG_LEVEL>: The log level required to log the message.
#                   <MESSAGE_TYPE>: Optional. "ENTER" or "EXIT".
# Remarks       : This function will only log messages if the DEBUG level
#                 is greater than or equal to the specified log level.
# ##############################################################################

logDebug() {
    message="$1"
    logLevel="${2:-1}" # Default log level for debug is 1
    msgType="${3:-}"   # Optional. Message type, should be "ENTER" or "EXIT"

    # Validate logLevel is an integer and greater than or equal to 1
    if ! expr "$logLevel" : '^[1-9][0-9]*$' >/dev/null; then
        logLevel=1
    fi

    # Determine log message based on msgType
    case "$msgType" in
    "ENTER")
        logMessage="Entering: $message."
        ;;
    "EXIT")
        logMessage="Exiting: $message"
        ;;
    *)
        msgType=""
        logMessage="$message"
        ;;
    esac

    # Check if the current DEBUG level is high enough to log the message
    if [ "$DEBUG" -ge "$logLevel" ]; then
        printInColor "DEBUG" "$logMessage" >&2
    fi
}

# ##############################################################################
# Function Name : readHEX
# Descripton    : Gets pixel color
# Args          : <X> <Y>
# Output        : $HEX
# ##############################################################################
readHEX() {
    offset=$((DEVICEWIDTH * $2 + $1 + 3))
    if [ "$hexdumpSu" = true ]; then
        HEX=$(dd if="$SCREENSHOTLOCATION" bs=4 skip="$offset" count=1 2>/dev/null | su -c hexdump -C)
    else
        HEX=$(dd if="$SCREENSHOTLOCATION" bs=4 skip="$offset" count=1 2>/dev/null | hexdump -C)
    fi
    HEX=${HEX:9:9}
    HEX="${HEX// /}"
}

# ##############################################################################
# Function Name : startApp
# Descripton    : Starts AFK Arena
# ##############################################################################
startApp() {
    if [ "$testServer" = true ]; then
        monkey -p com.lilithgames.hgame.gp.id 1 >/dev/null 2>/dev/null
    else
        monkey -p com.lilithgame.hgame.gp 1 >/dev/null 2>/dev/null
    fi
    sleep 1
    disableOrientation
}

# ##############################################################################
# Function Name : takeScreenshot
# Descripton    : Takes a screenshot and saves it if screenshotRequired=true
# Output        : $SCREENSHOTLOCATION
# ##############################################################################
takeScreenshot() {
    logDebug "takeScreenshot [screenshotRequired=${cCyan}$screenshotRequired${cNc}]" 3 "ENTER"

    if [ $screenshotRequired = false ]; then return; fi
    screencap "$SCREENSHOTLOCATION"
    screenshotRequired=false

    logDebug "takeScreenshot" 2 "EXIT"
}

# ##############################################################################
# Function Name : testColorNAND
# Descripton    : Equivalent to:
#                 if getColor <X> <Y> && [ "$HEX" != <COLOR> ] && [ "$HEX" != <COLOR> ]; then
# Args          : [-f] [-d <DELTA>] <X> <Y> <COLOR> [<COLOR> ...]
# Output        : if true, return 0, else 1
# ##############################################################################
testColorNAND() {
    logDebug "testColorNAND ${cPurple}$*${cNc}" 2 "ENTER"

    _testColorNAND_max_delta=0

    for arg in "$@"; do
        shift
        case "$arg" in
        -d)
            _testColorNAND_max_delta=$1
            shift
            ;;
        -f) screenshotRequired=true ;;
        *) set -- "$@" "$arg" ;;
        esac
    done
    getColor "$1" "$2" # looking for color
    shift
    shift                          # ignore arg
    for i in "$@"; do              # loop in colors
        if [ "$HEX" = "$i" ]; then # color found?
            logDebug "testColorNAND ${cCyan}$HEX${cNc} = ${cCyan}$i${cNc}" 2
            return 1 # At the first color found NAND is break, return 1
        else
            if [ "$DEBUG" -ge 2 ] || [ "$_testColorNAND_max_delta" -gt "0" ]; then
                _testColorNAND_delta=$(HEXColorDelta "$HEX" "$i")
                logDebug "testColorNAND ${cCyan}$HEX${cNc} != ${cCyan}$i${cNc} [Δ ${cCyan}$_testColorNAND_delta${cNc}%]" 2
                if [ "$_testColorNAND_delta" -le "$_testColorNAND_max_delta" ]; then
                    return 1
                fi
            fi
        fi
    done
    return 0 # If no result > return 0
}

# ##############################################################################
# Function Name : testColorOR
# Descripton    : Equivalent to:
#                 if getColor <X> <Y> && { [ "$HEX" = <COLOR> ] || [ "$HEX" = <COLOR> ]; }; then
# Args          : [-f] [-d <DELTA>] <X> <Y> <COLOR> [<COLOR> ...]
# Output        : if true, return 0, else 1
# ##############################################################################
testColorOR() {
    logDebug "testColorOR ${cPurple}$*${cNc}" 2 "ENTER"

    _testColorOR_max_delta=0
    for arg in "$@"; do
        shift
        case "$arg" in
        -d)
            _testColorOR_max_delta=$1
            shift
            ;;
        -f) screenshotRequired=true ;;
        *) set -- "$@" "$arg" ;;
        esac
    done
    getColor "$1" "$2" # looking for color
    shift
    shift                          # ignore arg
    for i in "$@"; do              # loop in colors
        if [ "$HEX" = "$i" ]; then # color found?
            logDebug "testColorOR ${cCyan}$HEX${cNc} = ${cCyan}$i${cNc}" 2
            return 0 # At the first color found OR is break, return 0
        else
            if [ "$DEBUG" -ge 2 ] || [ "$_testColorOR_max_delta" -gt "0" ]; then
                _testColorOR_delta=$(HEXColorDelta "$HEX" "$i")
                logDebug "testColorOR ${cCyan}$HEX${cNc} != ${cCyan}$i${cNc} [Δ ${cCyan}$_testColorOR_delta${cNc}%]" 2
                if [ "$_testColorOR_delta" -le "$_testColorOR_max_delta" ]; then
                    return 0
                fi
            fi
        fi
    done
    return 1 # if no result > return 1
}

# ##############################################################################
# Function Name : testColorORTapSleep
# Descripton    : Equivalent to:
#                   if testColorOR <X> <Y> <COLOR>; then
#                       inputTapSleep <X> <Y> <SLEEP>
#                   fi
# Args          : <X> <Y> <COLOR> <SLEEP>
# ##############################################################################
testColorORTapSleep() {
    logDebug "testColorORTapSleep" 2 "ENTER"

    if testColorOR "$1" "$2" "$3"; then                # if color found
        inputTapSleep "$1" "$2" "${4:-$DEFAULT_SLEEP}" # tap & sleep
    fi

    logDebug "testColorORTapSleep" 2 "EXIT"
}

# ##############################################################################
# Function Name : verifyHEX
# Descripton    : Verifies if <X> and <Y> have specific HEX then print <MESSAGE_*>
# Args          : <X> <Y> <HEX> <MESSAGE_SUCCESS> <MESSAGE_FAILURE>
# Output        : stdout MessageSuccess, stderr MessageFailure
# ##############################################################################
verifyHEX() {
    logDebug "verifyHEX" 3 "ENTER"

    getColor "$1" "$2"
    if [ "$HEX" != "$3" ]; then
        printInColor "ERROR" "verifyHEX: Failure! Expected ${cCyan}$3${cNc}, but got ${cCyan}$HEX${cNc} instead. [Δ ${cCyan}$(HEXColorDelta "$HEX" "$3")${cNc}%]" >&2
        printInColor "ERROR" "$5" >&2
        # WARN: The counter sometimes goes wrong. I did leave a print when tries > 0. Need to see if this bug comes back.
        printInColor "WARN" "Restarting for the ${cCyan}$((tries + 1))${cNc} time."
        init
        run
    else
        printInColor "DONE" "$4"
    fi
}

# ##############################################################################
# Function Name : wait
# Descripton    : Default wait time for actions
# ##############################################################################
wait() {
    sleep "$DEFAULT_SLEEP"
}

# ##############################################################################
# Section       : Game SubFunctions
# Description   : It's the extension of the Core for this specific game
# ##############################################################################

# ##############################################################################
# Function Name : doAuto
# Descripton    : Click on auto if not already enabled
# ##############################################################################
doAuto() {
    logDebug "doAuto" 3 "ENTER"

    testColorORTapSleep 760 1440 332b2b 0 # On:743b29 Off:332b2b

    logDebug "doAuto" 3 "EXIT"
}

# ##############################################################################
# Function Name : doSpeed
# Descripton    : Click on x4 if not already enabled
# ##############################################################################
doSpeed() {
    logDebug "doSpeed" 3 "ENTER"

    testColorORTapSleep 990 1440 332b2b 0 # On:[x2: 753b29, x4: 743b29] Off:332b2b

    logDebug "doSpeed" 3 "EXIT"
}

# ##############################################################################
# Function Name : doSkip
# Descripton    : Click on skip if avaible
# ##############################################################################
doSkip() {
    logDebug "doSkip" 3 "ENTER"

    testColorORTapSleep 760 1440 502e1d 0 # Exists: 502e1d

    logDebug "doSkip" 3 "EXIT"
}

# ##############################################################################
# Function Name : switchTab
# Descripton    : Switches to another tab if required by config.
# Args          : <TAB_NAME> [<FORCE>]
#                   <TAB_NAME>: Campaign / Dark Forest / Ranhorn / Chat
#                   <FORCE>: true / false, default false
# ##############################################################################
switchTab() {
    logDebug "switchTab" 3 "ENTER"

    if [ "$1" = "$activeTab" ]; then
        return
    fi
    case "$1" in
    "Campaign")
        if [ "${2:-false}" = true ] ||
            [ "$doLootAfkChest" = true ] ||
            [ "$doChallengeBoss" = true ] ||
            [ "$doFastRewards" = true ] ||
            [ "$doCollectFriendsAndMercenaries" = true ] ||
            [ "$doLootAfkChest" = true ]; then
            inputTapSleep 550 1850 2
            inputTapSleep 550 1850
            activeTab="$1"
            verifyHEX 450 1775 af7646 "Switched to the Campaign Tab." "Failed to switch to the Campaign Tab."
        fi
        ;;
    "Dark Forest")
        if [ "${2:-false}" = true ] ||
            [ "$doSoloBounties" = true ] ||
            [ "$doTeamBounties" = true ] ||
            [ "$doArenaOfHeroes" = true ] ||
            [ "$doLegendsTournament" = true ] ||
            [ "$doKingsTower" = true ] ||
            [ "$doFountainOfTime" = true ]; then
            inputTapSleep 300 1850 2
            inputTapSleep 300 1850
            activeTab="$1"
            verifyHEX 240 1775 b17848 "Switched to the Dark Forest Tab." "Failed to switch to the Dark Forest Tab."
        fi
        ;;
    "Ranhorn")
        if [ "${2:-false}" = true ] ||
            [ "$doGuildHunts" = true ] ||
            [ "$doTwistedRealmBoss" = true ] ||
            [ "$doBuyFromStore" = true ] ||
            [ "$doStrengthenCrystal" = true ] ||
            [ "$doTempleOfAscension" = true ] ||
            [ "$doCompanionPointsSummon" = true ] ||
            [ "$doCollectOakPresents" = true ] ||
            [ "$doCollectQuestChests" = true ] ||
            [ "$doCollectMail" = true ] ||
            [ "$doCollectMerchantFreebies" = true ]; then
            inputTapSleep 110 1850 2
            inputTapSleep 110 1850
            activeTab="$1"
            verifyHEX 20 1775 af7747 "Switched to the Ranhorn Tab." "Failed to switch to the Ranhorn Tab."
        fi
        ;;
    "Chat")
        inputTapSleep 970 1850
        activeTab="$1"
        verifyHEX 550 1690 ffffff "Switched to the Chat Tab." "Failed to switch to the Chat Tab."
        ;;
    esac

    logDebug "switchTab" 3 "EXIT"
}

# ##############################################################################
# Function Name : waitBattleFinish
# Descripton    : Waits until a battle has ended after <SECONDS>
# Args          : <SECONDS>
# ##############################################################################
waitBattleFinish() {
    logDebug "waitBattleFinish" 3 "ENTER"

    sleep "$1"
    finished=false
    until [ $finished = true ]; do
        # First HEX local device, second bluestacks
        if testColorOR -f 560 350 b8894d b7894c; then # Victory
            battleFailed=false
            finished=true
        elif [ "$HEX" = '171932' ] || [ "$HEX" = "171d3c" ]; then # Failed & Failed in Challenger Tournament
            battleFailed=true
            finished=true
        # First HEX local device, second bluestacks
        elif [ "$HEX" = "45331d" ] || [ "$HEX" = "44331c" ]; then # Victory with reward
            battleFailed=false
            finished=true
        # Win in Arena of Heroes with Reward
        elif testColorOR -f 550 696 fff085; then
            battleFailed=false
            finished=true
        fi
        sleep 1
    done

    logDebug "waitBattleFinish" 3 "EXIT"
}

# ##############################################################################
# Function Name : waitBattleStart
# Descripton    : Waits until battle starts
# ##############################################################################
waitBattleStart() {
    logDebug "waitBattleStart" 3 "ENTER"

    _waitBattleStart_count=0 # Max loops = 10 (10x.5s=5s max)
    # Check if pause button is present && less than 10 tries
    until testColorOR -f 110 1465 482f1f || [ $_waitBattleStart_count -ge 10 ]; do
        # Maybe pause button doesn't exist, so instead check for a skip button
        if testColorOR 760 1440 502e1d; then return; fi

        _waitBattleStart_count=$((_waitBattleStart_count + 1)) # Increment
        sleep .5
        # In case none were found, try again starting with the pause button
    done
    sleep 2

    logDebug "waitBattleStart" 3 "EXIT"
}

# ##############################################################################
# Function Name : pvpEvents
# Descripton    : Counts the number of PvP Events.
# ##############################################################################
pvpEvents() {
    logDebug "pvpEvents" 3 "ENTER"

    pvpEventsActive=0
    if [ "$eventHoe" = true ]; then
        pvpEventsActive=$((pvpEventsActive + 1)) # Increment
    fi
    if [ "$eventTs" = true ]; then
        pvpEventsActive=$((pvpEventsActive + 1)) # Increment
    fi
    if [ "$eventTv" = true ]; then
        pvpEventsActive=$((pvpEventsActive + 1)) # Increment
    fi

    logDebug "pvpEvents" 3 "EXIT"
}

# ##############################################################################
# Section       : Campaign
# ##############################################################################

# ##############################################################################
# Function Name : challengeBoss
# Descripton    : Challenges a boss in the campaign
# Remark        : Limited offers might screw this up.
# ##############################################################################
challengeBoss() {
    logDebug "challengeBoss" 4 "ENTER"

    inputTapSleep 550 1650 3            # Begin
    if testColorOR 550 740 f0daad; then # Check if boss
        inputTapSleep 550 1450 3        # Begin
    fi

    if [ "$forceFightCampaign" = "true" ]; then # Fight battle or not
        # Fight in the campaign because of Mythic Trick
        printInColor "INFO" "Fighting in the campaign until ${cCyan}$maxCampaignFights${cNc} defeat(s) because of Mythic Trick."
        _challengeBoss_LOOSE=0
        _challengeBoss_WIN=0

        # Check for battle screen
        until testColorNAND -d "$DEFAULT_DELTA" -f 495 95 fbdc87 || [ "$maxCampaignFights" -le 0 ]; do
            inputTapSleep 550 1850 .5 # Battle
            waitBattleStart
            doAuto
            doSpeed
            waitBattleFinish 10 # Wait until battle is over

            # Check battle result
            if [ "$battleFailed" = false ]; then     # Win
                if testColorOR 550 1670 e2dddc; then # Check for next stage
                    inputTapSleep 550 1670 6         # Next Stage
                    sleep 6

                    # WARN: Limited offers will fuck this part of the script up. I'm yet to find a way to close any possible offers.
                    # Tap top of the screen to close any possible Limited Offers
                    # inputTapSleep 550 75

                    if testColorOR 550 740 f0daad; then # Check if boss
                        inputTapSleep 550 1450 5
                    fi
                else
                    inputTapSleep 550 1670 3 # Continue to next battle

                    if testColorNAND -d "$DEFAULT_DELTA" -f 200 1850 2b1a12; then # For low levels, does not exists (before stage 4)
                        inputTapSleep 550 1650 3                                  # Begin
                        if testColorOR 550 740 f0daad; then                       # Check if boss
                            inputTapSleep 550 1450 3                              # Begin
                        fi
                    fi
                fi
                _challengeBoss_WIN=$((_challengeBoss_WIN + 1)) # Increment
            else                                               # Loose
                inputTapSleep 550 1720 5                       # Try again

                if testColorNAND -d "$DEFAULT_DELTA" -f 200 1850 2b1a12; then # For low levels, does not exists (before stage 4)
                    inputTapSleep 550 1650 3                                  # Begin
                    if testColorOR 550 740 f0daad; then                       # Check if boss
                        inputTapSleep 550 1450 3                              # Begin
                    fi
                fi

                _challengeBoss_LOOSE=$((_challengeBoss_LOOSE + 1)) # Increment
                maxCampaignFights=$((maxCampaignFights - 1))       # Dicrement
            fi
        done

        # Return to campaign
        if testColorNAND 450 1775 af7646; then # For low levels, you are automatically kicked out (before stage 4)
            inputTapSleep 60 1850              # Return
        fi

        testColorORTapSleep 715 1260 fefffe # Check for confirm to exit button
    else
        # Quick exit battle
        inputTapSleep 550 1850 4 # Battle
        inputTapSleep 80 1460    # Pause
        inputTapSleep 230 960 4  # Exit

        if testColorNAND 450 1775 af7646; then # Check for multi-battle
            inputTapSleep 70 1810
        fi
    fi

    wait
    if [ "$forceFightCampaign" = "true" ]; then
        verifyHEX 450 1775 af7646 \
            "Challenged boss in campaign. $(getCountersInColor "$_challengeBoss_WIN" "$_challengeBoss_LOOSE")" \
            "Failed to fight boss in Campaign. $(getCountersInColor "$_challengeBoss_WIN" "$_challengeBoss_LOOSE")"
    else
        verifyHEX 450 1775 af7646 "Challenged boss in campaign." "Failed to fight boss in Campaign."
    fi

    logDebug "challengeBoss" 4 "EXIT"
}

# ##############################################################################
# Function Name : collectFriendsAndMercenaries
# Descripton    : Collects and sends companion points, as well as auto lending mercenaries
# ##############################################################################
collectFriendsAndMercenaries() {
    logDebug "collectFriendsAndMercenaries" 4 "ENTER"

    inputTapSleep 970 750 1                                  # Friends
    inputTapSleep 930 1600                                   # Send & Recieve
    if testColorOR -d "$DEFAULT_DELTA" 825 1750 f54b3a; then # Check if its necessary to send mercenaries
        inputTapSleep 720 1760                               # Short-Term
        inputTapSleep 990 190                                # Manage
        inputTapSleep 630 1590                               # Apply
        inputTapSleep 750 1410 1                             # Auto Lend
        inputTapSleep 70 1810 0                              # Return
    else
        printInColor "INFO" "No mercenaries to lend..."
    fi
    inputTapSleep 70 1810 0 # Return

    wait
    verifyHEX 450 1775 af7646 "Sent and recieved companion points, as well as auto lending mercenaries." "Failed to collect/send companion points or failed to auto lend mercenaries."

    logDebug "collectFriendsAndMercenaries" 4 "ENTER"
}

# ##############################################################################
# Function Name : fastRewards
# Descripton    : Collects fast rewards
# ##############################################################################
fastRewards() {
    logDebug "fastRewards" 4 "ENTER"

    _fast_rewards_COUNT=0
    if testColorOR -d "$DEFAULT_DELTA" 980 1620 f05c3b; then # check red dot to see if free fast reward is avaible
        inputTapSleep 950 1660 1                             # Fast Rewards
        until [ "$_fast_rewards_COUNT" -ge "$totalFastRewards" ]; do
            inputTapSleep 710 1260 1                         # Collect
            inputTapSleep 560 1800 2                         # Clear Popup
            _fast_rewards_COUNT=$((_fast_rewards_COUNT + 1)) # Increment
        done
        inputTapSleep 400 1250 # Close
    else
        printInColor "INFO" "Fast Rewards collected already, not collecting..."
    fi
    verifyHEX 450 1775 af7646 "Fast rewards checked." "Failed to check fast rewards."

    logDebug "fastRewards" 4 "EXIT"
}

# ##############################################################################
# Function Name : lootAfkChest
# Descripton    : Loots afk chest
# ##############################################################################
lootAfkChest() {
    logDebug "lootAfkChest" 4 "ENTER"

    inputTapSleep 550 1500 1
    inputTapSleep 750 1350 3
    inputTapSleep 550 1850 1 # Tap campaign in case of level up
    wait
    verifyHEX 450 1775 af7646 "AFK Chest looted." "Failed to loot AFK Chest."

    logDebug "lootAfkChest" 4 "EXIT"
}

# ##############################################################################
# Section       : Dark Forest
# ##############################################################################

# ##############################################################################
# Function Name : arenaOfHeroes
# Descripton    : Does the daily arena of heroes battles
# ##############################################################################
arenaOfHeroes() {
    logDebug "arenaOfHeroes" 4 "ENTER"

    pvpEvents                # Counts number of Active pvp events
    inputTapSleep 800 1150 3 # Arena of Heroes
    inputTapSleep 550 80 2   # Collect Arena Tickets
    if [ "$pvpEventsActive" = "0" ]; then
        inputTapSleep 550 450 3 # Arena of Heroes
    elif [ "$pvpEventsActive" = "1" ]; then
        inputTapSleep 550 900 3 # Arena of Heroes
    else
        inputTapSleep 550 1400 3 # Arena of Heroes
    fi
    if testColorOR -d "$DEFAULT_DELTA" 1050 1770 eb523d; then # Red mark? old value: e52505 (d=5), fb1e0d (d=5)
        inputTapSleep 1000 1800 3                             # Record
        inputTapSleep 980 410                                 # Close
    fi
    inputTapSleep 540 1800 # Challenge

    if testColorNAND 200 1800 382314 382214; then # Check for new season
        _arenaOfHeroes_LOSS=0
        _arenaOfHeroes_WIN=0
        printInColor "INFO" "Fighting in the Arena Of Heroes ${cCyan}$totalAmountArenaTries${cNc} time(s)."
        until [ "$totalAmountArenaTries" -le 0 ]; do # Repeat a battle for as long as totalAmountArenaTries
            # Refresh
            # inputTapSleep 815 540

            # Fight specific opponent
            #                                Free         x1
            #  Opponent 1: 820 700      ->        acf0bd
            #  Opponent 2: 820 870      ->  2eaab4      aff3be
            #  Opponent 3: 820 1050     ->        acf0bd
            #  Opponent 4: 820 1220     ->  2daab4      aff1b8
            #  Opponent 5: 820 1400     ->        adf1be
            case $arenaHeroesOpponent in
            1)
                if testColorOR -d "$DEFAULT_DELTA" 820 700 a7f1b7; then # Check if opponent exists
                    inputTapSleep 820 700 0                             # Fight opponent
                else
                    # Refresh opponents and try to fight opponent $arenaHeroesOpponent
                    arenaOfHeroes_tapClosestOpponent 1
                fi
                ;;
            2)
                if testColorOR -d "$DEFAULT_DELTA" 820 870 2eaab4 aff3c0 aff1bf; then # Check if opponent exists
                    inputTapSleep 820 870 0                                           # Fight opponent
                else
                    arenaOfHeroes_tapClosestOpponent 2 # Try to fight the closest opponent to 2
                fi
                ;;
            3)
                if testColorOR -d "$DEFAULT_DELTA" 820 1050 adf1bf; then # Check if opponent exists
                    inputTapSleep 820 1050 0                             # Fight opponent
                else
                    arenaOfHeroes_tapClosestOpponent 3 # Try to fight the closest opponent to 3
                fi
                ;;
            4)
                if testColorOR -d "$DEFAULT_DELTA" 820 1220 2daab4 aff3c0 aff1bf; then # Check if opponent exists
                    inputTapSleep 820 1220 0                                           # Fight opponent
                else
                    arenaOfHeroes_tapClosestOpponent 4 # Try to fight the closest opponent to 4
                fi
                ;;
            5)
                if testColorOR -d "$DEFAULT_DELTA" 820 1400 aff1bf; then # Check if opponent exists
                    inputTapSleep 820 1400 0                             # Fight opponent
                else
                    arenaOfHeroes_tapClosestOpponent 5 # Try to fight the closest opponent to 5
                fi
                ;;
            *)
                # Invalid option
                echo "[WARN] Invalid arenaHeroesOpponent option in config, skipping..."
                break
                ;;
            esac

            # Check if return value of tapClosesopponent is 0. If it is 0, then it means a battle has been found.
            res=$?
            if [ $res = 0 ]; then
                wait
                if testColorOR -d "$DEFAULT_DELTA" 20 1200 e6c58f; then # In Battle Screen
                    inputTapSleep 550 1850 0                            # Battle
                    waitBattleStart
                    doSkip
                    waitBattleFinish 3
                    if [ "$battleFailed" = false ]; then
                        inputTapSleep 550 1550                         # Collect
                        _arenaOfHeroes_WIN=$((_arenaOfHeroes_WIN + 1)) # Increment
                    else
                        _arenaOfHeroes_LOSS=$((_arenaOfHeroes_LOSS + 1)) # Increment
                    fi
                    inputTapSleep 550 1550 3 # Finish battle
                else
                    printInColor "WARN" "Failed to enter battle in the Arena of Heroes."
                fi
            fi
            totalAmountArenaTries=$((totalAmountArenaTries - 1)) # Dicrement
        done

        inputTapSleep 1000 380
        sleep 4
    else
        printInColor "INFO" "Unable to fight in the Arena of Heroes because a new season is soon launching." >&2
    fi

    if [ "$doLegendsTournament" = false ]; then # Return to Tab if $doLegendsTournament = false
        inputTapSleep 70 1810
        inputTapSleep 70 1810
        verifyHEX 240 1775 b17848 \
            "Checked the Arena of Heroes out. $(getCountersInColor "$_arenaOfHeroes_WIN" "$_arenaOfHeroes_LOSS")" \
            "Failed to check the Arena of Heroes out. $(getCountersInColor "$_arenaOfHeroes_WIN" "$_arenaOfHeroes_LOSS")"
    else
        inputTapSleep 70 1810
        verifyHEX 760 70 1f2d3a \
            "Checked the Arena of Heroes out. $(getCountersInColor "$_arenaOfHeroes_WIN" "$_arenaOfHeroes_LOSS")" \
            "Failed to check the Arena of Heroes out. $(getCountersInColor "$_arenaOfHeroes_WIN" "$_arenaOfHeroes_LOSS")"
    fi

    logDebug "arenaOfHeroes" 4 "EXIT"
}

# ##############################################################################
# Function Name : arenaOfHeroes_tapClosestOpponent
# Descripton    : Attempts to tap the closest Arena of Heroes opponent
# Args          : <OPPONENT>: 1/2/3/4/5
# Output        : If failed, return 1
# ##############################################################################
arenaOfHeroes_tapClosestOpponent() {
    logDebug "arenaOfHeroes_tapClosestOpponent ${cPurple}$*${cNc}" 4 "ENTER"

    # Depending on the opponent number sent as a parameter ($1), this function
    # would attempt to check if there's an opponent above the one sent.
    # If there isn't, check the one above that one and so on until one is found.
    # When found, tap on the opponent and exit function.
    case $1 in
    1)
        # Refresh
        inputTapSleep 815 540

        # Attempt to fight $arenaHeroesOpponent opponent, and if not present, skip battle
        case $arenaHeroesOpponent in
        1)
            # Check if opponent 1 exists and fight if true
            if testColorOR -d "$DEFAULT_DELTA" 820 700 a7f1b7; then inputTapSleep 820 700 0; else return 1; fi
            ;;
        2)
            # Check if opponent 2 exists and fight if true
            if testColorOR -d "$DEFAULT_DELTA" 820 870 2eaab4 aff3c0 aff1bf; then inputTapSleep 820 870 0; else return 1; fi
            ;;
        3)
            # Check if opponent 3 exists and fight if true
            if testColorOR -d "$DEFAULT_DELTA" 820 1050 adf1bf; then inputTapSleep 820 1050 0; else return 1; fi
            ;;
        4)
            # Check if opponent 4 exists and fight if true
            if testColorOR -d "$DEFAULT_DELTA" 820 1220 2daab4 aff3c0 aff1bf; then inputTapSleep 820 1220 0; else return 1; fi
            ;;
        5)
            # Check if opponent 5 exists and fight if true
            if testColorOR -d "$DEFAULT_DELTA" 820 1400 aff1bf; then inputTapSleep 820 1400 0; else return 1; fi
            ;;
        esac
        ;;
    2)
        if testColorOR -d "$DEFAULT_DELTA" 820 700 a7f1b7; then # Check if opponent 1 exists
            inputTapSleep 820 700 0                             # Fight opponent
        else
            arenaOfHeroes_tapClosestOpponent 1 # Try to fight the closest opponent to 2
        fi
        ;;
    3)
        if testColorOR -d "$DEFAULT_DELTA" 820 870 2eaab4 aff3c0 aff1bf; then # Check if opponent 2 exists
            inputTapSleep 820 870 0                                           # Fight opponent
        else
            arenaOfHeroes_tapClosestOpponent 2 # Try to fight the closest opponent to 3
        fi
        ;;
    4)
        if testColorOR -d "$DEFAULT_DELTA" 820 1050 adf1bf; then # Check if opponent 3 exists
            inputTapSleep 820 1050 0                             # Fight opponent
        else
            arenaOfHeroes_tapClosestOpponent 3 # Try to fight the closest opponent to 4
        fi
        ;;
    5)
        if testColorOR -d "$DEFAULT_DELTA" 820 1220 2daab4 aff3c0 aff1bf; then # Check if opponent 4 exists
            inputTapSleep 820 1220 0                                           # Fight opponent
        else
            arenaOfHeroes_tapClosestOpponent 4 # Try to fight the closest opponent to 5
        fi
        ;;
    esac

    logDebug "arenaOfHeroes_tapClosestOpponent" 4 "EXIT"
}

# ##############################################################################
# Function Name : kingsTower
# Descripton    : Try to battle in every Kings Tower
# ##############################################################################
kingsTower() {
    logDebug "kingsTower" 4 "ENTER"

    inputTapSleep 550 850 5 # King's Tower
    printInColor "INFO" "Fighting King's Tower until ${cCyan}$maxKingsTowerFights${cNc} defeat(s)."

    if testColorOR 550 140 1a1212; then
        # King's Tower without Towers of Esperia unlocked (between stage 2-12 and 15-1)
        if [ "$doMainTower" = true ]; then
            printInColor "DONE" "Main Tower $(kingsTower_battle -1 -1)" # Main Tower
        fi
    else
        # King's Tower with Towers of Esperia unlocked (after stage 15-1)
        if [ "$doMainTower" = true ]; then
            printInColor "DONE" "Main Tower $(kingsTower_battle 550 800)" # Main Tower
        fi

        if [ "$doTowerOfLight" = true ] && { [ "$dayofweek" -eq 1 ] || [ "$dayofweek" -eq 5 ] || [ "$dayofweek" -eq 7 ]; }; then
            printInColor "DONE" "Tower of Light $(kingsTower_battle 300 950)" # Tower of Light
        fi

        if [ "$doTheBrutalCitadel" = true ] && { [ "$dayofweek" -eq 2 ] || [ "$dayofweek" -eq 5 ] || [ "$dayofweek" -eq 7 ]; }; then
            printInColor "DONE" "The Brutal Citadel $(kingsTower_battle 400 1250)" # The Brutal Citadel
        fi

        if [ "$doTheWorldTree" = true ] && { [ "$dayofweek" -eq 3 ] || [ "$dayofweek" -eq 6 ] || [ "$dayofweek" -eq 7 ]; }; then
            printInColor "DONE" "The World Tree $(kingsTower_battle 750 660)" # The World Tree
        fi

        if [ "$doCelestialSanctum" = true ] && { [ "$dayofweek" -eq 3 ] || [ "$dayofweek" -eq 5 ] || [ "$dayofweek" -eq 7 ]; }; then
            printInColor "DONE" "Celestial Sanctum $(kingsTower_battle 270 500)" # Celestial Sanctum
        fi

        if [ "$doTheForsakenNecropolis" = true ] && { [ "$dayofweek" -eq 4 ] || [ "$dayofweek" -eq 6 ] || [ "$dayofweek" -eq 7 ]; }; then
            printInColor "DONE" "The Forsaken Necropolis $(kingsTower_battle 780 1100)" # The Forsaken Necropolis
        fi

        if [ "$doInfernalFortress" = true ] && { [ "$dayofweek" -eq 4 ] || [ "$dayofweek" -eq 6 ] || [ "$dayofweek" -eq 7 ]; }; then
            printInColor "DONE" "Infernal Fortress $(kingsTower_battle 620 1550)" # Infernal Fortress
        fi
    fi

    # Exit
    inputTapSleep 70 1810
    verifyHEX 240 1775 b17848 "Battled at the Kings Tower." "Failed to battle at the Kings Tower."

    logDebug "kingsTower" 4 "EXIT"
}

# ##############################################################################
# Function Name : kingsTower_battle
# Descripton    : Battles in King's Towers
# Args          : <X> <Y>
# Remark        : Limited offers might screw this up.
# ##############################################################################
kingsTower_battle() {
    logDebug "kingsTower_battle ${cPurple}$*${cNc}" 4 "ENTER"

    _kingsTower_battle_COUNT=0 # Equivalent to loose
    _battle_WIN=0

    if [ "$1" -ge 0 ] && [ "$2" -ge 0 ]; then # Will be -1 if we already are in the tower
        inputTapSleep "$1" "$2" 2             # Tap chosen tower
    fi

    # Check if inside tower
    if testColorOR 550 140 1a1212; then
        inputTapSleep 540 1350 # Challenge

        # Battle until equal to maxKingsTowerFights & we haven't reached daily limit of 10 floors
        until [ "$_kingsTower_battle_COUNT" -ge "$maxKingsTowerFights" ] || testColorOR -f 550 140 1a1212; do
            inputTapSleep 550 1850 0 # Battle
            waitBattleStart
            doAuto
            doSpeed
            waitBattleFinish 2

            # Check if win or lose battle
            if [ "$battleFailed" = false ]; then
                _battle_WIN=$((_battle_WIN + 1)) # Increment
                inputTapSleep 550 1850 4         # Collect
                inputTapSleep 550 170            # Tap on the top to close possible limited offer

                # WARN: Limited offers might screw this up. Tapping 550 170 might close an offer.
                # Tap top of the screen to close any possible Limited Offers
                # if testColorOR 550 140 1a1212; then # not on screen with Challenge button
                #     inputTapSleep 550 75        # Tap top of the screen to close Limited Offer
                #     if testColorOR 550 140 1a1212; then # think i remember it needs two taps to close offer
                #         inputTapSleep 550 75    # Tap top of the screen to close Limited Offer
                # fi

                inputTapSleep 540 1350 # Challenge
            elif [ "$battleFailed" = true ]; then
                inputTapSleep 550 1720                                     # Try again
                _kingsTower_battle_COUNT=$((_kingsTower_battle_COUNT + 1)) # Increment
            fi

            # Check if reached daily limit / kicked us out of battle screen
        done

        # Return from chosen tower / battle
        inputTapSleep 70 1810 3
        if [ "$1" -ge 0 ] && [ "$2" -ge 0 ]; then # Will be -1 if we already are in the tower (low level)
            if testColorOR 550 140 1a1212; then   # In case still in tower, exit once more
                inputTapSleep 70 1810 0
            fi
        fi
        sleep 2
    fi
    getCountersInColor $_battle_WIN $_kingsTower_battle_COUNT

    logDebug "kingsTower_battle" 4 "EXIT"
}

# ##############################################################################
# Function Name : legendsTournament
# Descripton    : Does the daily Legends tournament battles
# Args          : <START_FROM_TAB>: true / false
# ##############################################################################
legendsTournament() {
    logDebug "legendsTournament ${cPurple}$*${cNc}" 4 "ENTER"

    if [ "$1" = true ]; then # Check if starting from tab or already inside activity
        inputTapSleep 740 1050
    fi
    ## For testing only! Keep as comment ##
    # inputTapSleep 740 1050 1
    ## End of testing ##

    if [ "$pvpEventsActive" = "0" ]; then
        inputTapSleep 550 900 # Legend's Challenger Tournament
    elif [ "$pvpEventsActive" = "1" ]; then
        inputTapSleep 550 1450 # Legend's Challenger Tournament
    else
        inputTapSleep 550 1800 3 # Legend's Challenger Tournament
    fi
    inputTapSleep 550 280 3  # Chest
    inputTapSleep 550 1550 3 # Collect

    if testColorOR -d "$DEFAULT_DELTA" 1040 1800 e61f06; then # Red mark?
        inputTapSleep 1000 1800                               # Record
        inputTapSleep 990 380                                 # Close
    fi

    _legendsTournament_LOOSE=0
    _legendsTournament_WIN=0
    printInColor "INFO" "Fighting in the Legends' Challenger Tournament ${cCyan}$totalAmountTournamentTries${cNc} time(s)."
    until [ "$totalAmountTournamentTries" -le 0 ]; do # Repeat a battle for as long as totalAmountTournamentTries
        inputTapSleep 550 1840 4                      # Challenge
        inputTapSleep 800 1140 4                      # Third opponent

        if testColorOR -d "$DEFAULT_DELTA" 20 1200 e6c58f; then
            inputTapSleep 550 1850 4 # Begin Battle
            # inputTapSleep 770 1470 4
            waitBattleStart
            doSkip
            waitBattleFinish 4
            if [ "$battleFailed" = false ]; then
                _legendsTournament_WIN=$((_legendsTournament_WIN + 1)) # Increment
            else
                _legendsTournament_LOOSE=$((_legendsTournament_LOOSE + 1)) # Increment
            fi
            inputTapSleep 550 800 4 # Tap anywhere to close
        else
            printInColor "WARN" "Failed to enter battle at the Legends Tournament."
            inputTapSleep 70 1810
        fi
        totalAmountTournamentTries=$((totalAmountTournamentTries - 1)) # Dicrement
    done

    inputTapSleep 70 1810
    inputTapSleep 70 1810
    verifyHEX 240 1775 b17848 \
        "Battled at the Legends Tournament. $(getCountersInColor $_legendsTournament_WIN $_legendsTournament_LOOSE)" \
        "Failed to battle at the Legends Tournament. $(getCountersInColor $_legendsTournament_WIN $_legendsTournament_LOOSE)"

    logDebug "legendsTournament" 4 "EXIT"
}

# ##############################################################################
# Function Name : soloBounties
# Descripton    : Starts Solo bounties
# ##############################################################################
soloBounties() {
    logDebug "soloBounties" 4 "ENTER"

    finished=false

    inputTapSleep 600 1320 2
    inputTapSleep 650 1700 1 # Solo Bounty
    inputTapSleep 780 1550 1 # Collect all

    # Check if there are bounties waiting to be dispatched
    if testColorOR -d "$DEFAULT_DELTA" -f 337 1550 ffffff; then
        # Check once before scrolling down
        dispatchBounties 1
        inputSwipe 300 1700 550 400 300 # Scroll Down
        until $finished; do
            dispatchBounties 2
            if [ "$_gold" -gt "$maxGold" ]; then
                inputTapSleep 140 300 1         # Refresh
                inputTapSleep 700 1260 1        # Confirm
                inputSwipe 300 1700 550 400 300 # Scroll Down
            else
                finished=true
            fi
            _gold=0
        done

        # Check again if there are bounties waiting to be dispatched
        if testColorOR -d "$DEFAULT_DELTA" -f 337 1550 ffffff; then
            inputTapSleep 350 1550   # Dispatch all
            inputTapSleep 550 1500 0 # Confirm
        fi
    fi

    # Return to the appropriate tab based on doTeamBounties flag
    if [ "$doTeamBounties" = false ]; then
        wait
        inputTapSleep 70 1810
        verifyHEX 240 1775 b17848 "Collected/dispatched solo bounties." "Failed to collect/dispatch solo bounties."
    else
        wait
        verifyHEX 650 1740 a15820 "Collected/dispatched solo bounties." "Failed to collect/dispatch solo bounties."
    fi

    logDebug "soloBounties" 4 "EXIT"
}

# ##############################################################################
# Function Name : dispatchBounties
# Descripton    : Dispatches non-gold bounties.
# Args          : <NUMBER>: 1 for pre scroll down, 2 for after.
# ######################d########################################################
dispatchBounties() {
    logDebug "dispatchBounties ${cPurple}$*${cNc}" 4 "ENTER"

    # Check if an argument is provided
    if [ -z "$1" ]; then
        printInColor "ERROR" "No argument provided. Expected 1 or 2."
        logDebug "dispatchBounties" 4 "EXIT"
        return 1
    fi

    if [ "$1" -eq 1 ] || [ "$1" -eq 2 ]; then
        if [ "$bountifulBounties" = "true" ]; then
            if [ "$1" -eq 1 ]; then
                # Dispatch bountiful bounties pre-scroll view
                dispatchBounties_nonGold 110 465 fbdc93  # Check 1st Item
                dispatchBounties_nonGold 110 675 fbda8f  # Check 2nd Item
                dispatchBounties_nonGold 110 885 f7d58d  # Check 3rd Item
                dispatchBounties_nonGold 110 1095 f3ce89 # Check 4th Item
                dispatchBounties_nonGold 110 1305 ebc180 # Check 5th Item
            else
                # Dispatch bountiful bounties post-scroll view
                dispatchBounties_nonGold 110 455 f6da98  # Check 1st Item
                dispatchBounties_nonGold 110 665 f6d692  # Check 2nd Item
                dispatchBounties_nonGold 110 875 f6d690  # Check 3rd Item
                dispatchBounties_nonGold 110 1085 f7d68f # Check 4th Item
                dispatchBounties_nonGold 110 1295 f8d78d # Check 5th Item
            fi
        else
            if [ "$1" -eq 1 ]; then
                # Dispatch bounties pre-scroll view
                dispatchBounties_nonGold 110 465 faeb9a  # Check 1st Item
                dispatchBounties_nonGold 110 675 fcf3a3  # Check 2nd Item
                dispatchBounties_nonGold 110 885 fcf8a8  # Check 3rd Item
                dispatchBounties_nonGold 110 1095 fbfaab # Check 4th Item
                dispatchBounties_nonGold 110 1305 fafaac # Check 5th Item
            else
                # Dispatch bounties post-scroll view
                dispatchBounties_nonGold 110 535 fcf09f  # Check 1st Item
                dispatchBounties_nonGold 110 745 fcf5a4  # Check 2nd Item
                dispatchBounties_nonGold 110 955 fcfaaa  # Check 3rd Item
                dispatchBounties_nonGold 110 1165 fbfaac # Check 4th Item
                dispatchBounties_nonGold 110 1375 fafaad # Check 5th Item
            fi
        fi
    else
        # If the argument is not 1 or 2, print an error message and exit
        printInColor "ERROR" "Invalid argument: $1. Expected 1 or 2."
        logDebug "dispatchBounties" 4 "EXIT"
        return 1
    fi

    logDebug "dispatchBounties" 4 "EXIT"
}

# ##############################################################################
# Function Name : dispatchBounty
# Descripton    : Dispatches a single bounty.
# Args          : <X> <Y>
# ##############################################################################
dispatchBounties_nonGold() {
    logDebug "dispatchBounties_nonGold ${cPurple}$*${cNc}" 4 "ENTER"

    x="$1"
    x=$((x + 800)) # Move Right to Dispatch Button
    y="$2"

    if [ "$bountifulBounties" = "true" ]; then
        y=$((y + 50))
    fi

    if testColorNAND -d "$DEFAULT_DELTA" -f "$1" "$2" "$3"; then       # Not Gold
        if testColorNAND -d "$DEFAULT_DELTA" -f "$x" "$y" ba9b6f; then # Not Dispatched yet
            dispatchBounties_nonGold_Autofill "$1" "$2"
        fi
    else
        _gold=$((_gold + 1)) # Increment
    fi

    logDebug "dispatchBounties_nonGold" 4 "EXIT"
}

# ##############################################################################
# Function Name : dispatchBounties_nonGold_Autofill
# Descripton    : Autofills the bounty.
# Args          : <X> <Y>
# ##############################################################################
dispatchBounties_nonGold_Autofill() {
    logDebug "dispatchBounties_nonGold_Autofill ${cPurple}$*${cNc}" 4 "ENTER"

    x="$1"
    x=$((x + 800)) # Move Right to Dispatch Button
    y="$2"
    inputTapSleep "$x" "$y" 1 # Dispatch
    inputTapSleep 350 1170 1  # Autofill
    inputTapSleep 740 1170 1  # Dispatch

    logDebug "dispatchBounties_nonGold_Autofill" 4 "EXIT"
}

# ##############################################################################
# Function Name : teamBounties
# Descripton    : Starts Team bounties
# Args          : <START_FROM_TAB>: true / false
# ##############################################################################
teamBounties() {
    logDebug "teamBounties ${cPurple}$*${cNc}" 4 "ENTER"

    if [ "$1" = true ]; then # Check if starting from tab or already inside activity
        inputTapSleep 600 1320 1
    fi
    ## For testing only! Keep as comment ##
    # inputTapSleep 600 1320 1
    ## End of testing ##
    inputTapSleep 910 1700 1 # Team Bounty
    inputTapSleep 780 1550 1 # Collect all
    inputTapSleep 350 1550   # Dispatch all
    inputTapSleep 550 1500   # Confirm
    inputTapSleep 70 1810    # Return
    verifyHEX 240 1775 b17848 "Collected/dispatched team bounties." "Failed to collect/dispatch team bounties."

    logDebug "teamBounties" 4 "EXIT"
}

# ##############################################################################
# Function Name : fountainOfTime
# Descripton    : Collects the Fountain of Time rewards.
# ##############################################################################
fountainOfTime() {
    logDebug "fountainOfTime" 4 "ENTER"

    inputTapSleep 870 800 4             # Temporal Rift
    inputTapSleep 250 1350 2            # Fountain of Time
    inputTapSleep 730 1360 2            # Collect
    inputTapSleep 550 75                # Tap Away Rewards
    if testColorOR 550 300 debd62; then # Level Up
        inputTapSleep 550 75            # Tap top of the screen to close pop-up
        printInColor INFO "Fountain of Time Level Up!"
        if testColorNAND 550 200 1f2438; then # "Newly Unlocked Beacons"
            inputTapSleep 550 75              # Tap top of the screen to close pop-up
        fi
    fi
    inputTapSleep 70 1810 # Return
    verifyHEX 240 1775 b17848 "Collected Fountain of Time." "Failed to collect Fountain of Time."

    logDebug "fountainOfTime" 4 "EXIT"
}

# ##############################################################################
# Section       : Ranhorn
# ##############################################################################

# ##############################################################################
# Function Name : buyFromStore
# Descripton    : Buy items from store
# ##############################################################################
buyFromStore() {
    logDebug "buyFromStore" 4 "ENTER"

    _store_purchase_COUNT=0

    inputSwipe 300 1700 550 100 300 # Scroll Down
    inputTapSleep 440 900 3         # Store

    # if [ "$buyStoreDust" = true ]; then # Dust
    #     buyFromStore_buyItem 175 1100
    # fi
    # if [ "$buyStorePoeCoins" = true ]; then # Poe Coins
    #     buyFromStore_buyItem 675 1690
    # fi
    # # Primordial Emblem
    # if [ "$buyStorePrimordialEmblem" = true ] && testColorOR -d "$DEFAULT_DELTA" 175 1690 c6ced5; then
    #     buyFromStore_buyItem 175 1690
    # fi
    # # Amplifying Emblem
    # if [ "$buyStoreAmplifyingEmblem" = true ] && testColorOR -d "$DEFAULT_DELTA" 175 1690 c59e71 cca67a; then
    #     buyFromStore_buyItem 175 1690
    # fi
    # # Soulstone (widh 90 diamonds)
    # if [ "$buyStoreSoulstone" = true ]; then
    #     if testColorOR -d "$DEFAULT_DELTA" 910 1100 cf9ced; then # row 1, item 4
    #         buyFromStore_buyItem 910 1100
    #     fi
    #     if testColorOR -d "$DEFAULT_DELTA" 650 1100 b165c0; then # row 1, item 3
    #         buyFromStore_buyItem 650 1100
    #     fi
    # fi
    # # Limited Elemental Shard
    # if [ "$buyStoreLimitedElementalShard" = true ]; then
    #     buyFromStore_buyItem 300 820
    # fi
    # # Limited Elemental Core
    # if [ "$buyStoreLimitedElementalCore" = true ]; then
    #     buyFromStore_buyItem 540 820
    # fi
    # # Limited Time Emblem
    # if [ "$buyStoreLimitedTimeEmblem" = true ]; then
    #     buyFromStore_buyItem 780 820
    # fi

    # Fuck all that just do Quick Buy
    if testColorOR -d "5" 860 720 fad8a5; then
        # Ensure at least one iteration if storeRefreshes is zero
        storeRefreshLimit=${storeRefreshes:-1}

        while [ "$_store_purchase_COUNT" -lt "$storeRefreshLimit" ]; do
            inputTapSleep 940 720                                # Quick Buy
            inputTapSleep 720 1220                               # Purchase
            inputTapSleep 550 1700 2                             # Close popup
            _store_purchase_COUNT=$((_store_purchase_COUNT + 1)) # Increment

            # Refresh only if storeRefreshes is greater than zero
            if [ "$storeRefreshes" -gt 0 ] && [ "$_store_purchase_COUNT" -lt "$storeRefreshLimit" ]; then
                inputTapSleep 1000 290 # Refresh
                inputTapSleep 700 1270 # Confirm
            fi
        done
    else
        printInColor INFO "Quick Buy not found."
    fi

    # if [ "$forceWeekly" = true ]; then
    #     # Weekly - Purchase an item from the Guild Store once (check red dot first row for most useful item)
    #     if [ "$buyWeeklyGuild" = true ]; then
    #         inputTapSleep 770 1810 # Guild Store
    #         if testColorOR -d "5" 620 750 ef1f06; then
    #             buyFromStore_buyItem 550 820 # Limited
    #         elif testColorOR -d "5" 250 1040 b02004; then
    #             buyFromStore_buyItem 180 1100 # row 1, item 1
    #         elif testColorOR -d "5" 500 1040 ed1f06; then
    #             buyFromStore_buyItem 420 1100 # row 1, item 2
    #         elif testColorOR -d "5" 744 1040 ed1f06; then
    #             buyFromStore_buyItem 660 1100 # row 1, item 3
    #         elif testColorOR -d "5" 985 1040 ef1e06; then
    #             buyFromStore_buyItem 900 1100 # row 1, item 4
    #         fi
    #     fi
    #     if [ "$buyWeeklyLabyrinth" = true ]; then
    #         inputTapSleep 1020 1810          # Labyrinth Store
    #         inputSwipe 1050 1600 1050 750 50 # Swipe all the way down
    #         if testColorOR -d "$DEFAULT_DELTA" 180 1350 0c8bbd; then # row 5, item 1 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
    #             buyFromStore_buyItem 180 1350
    #         elif testColorOR -d "$DEFAULT_DELTA" 420 1350 2a99cc; then # row 5, item 2 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
    #             buyFromStore_buyItem 420 1350
    #         elif testColorOR -d "$DEFAULT_DELTA" 660 1350 81938e; then # row 5, item 3 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
    #             buyFromStore_buyItem 660 1350
    #         elif testColorOR -d "$DEFAULT_DELTA" 900 1350 f9f9fb; then # row 5, item 4 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
    #             buyFromStore_buyItem 900 1350
    #         elif testColorOR -d "$DEFAULT_DELTA" 180 1600 2b2c4a; then # row 6, item 1 >  60 Soulstones (Ira) / 2400 Labyrinth Tokens
    #             buyFromStore_buyItem 180 1600
    #         elif testColorOR -d "$DEFAULT_DELTA" 420 1600 3d2f30; then # row 6, item 2 >  60 Soulstones (Golus) / 2400 Labyrinth Tokens
    #             buyFromStore_buyItem 420 1600
    #         elif testColorOR -d "$DEFAULT_DELTA" 660 1600 1b151a; then # row 6, item 3 >  60 Soulstones (Mirael) / 2400 Labyrinth Tokens
    #             buyFromStore_buyItem 660 1600
    #         elif testColorOR -d "$DEFAULT_DELTA" 900 1600 999f9f; then # row 6, item 4 >  60 Soulstones (Silvina) / 2400 Labyrinth Tokens
    #             buyFromStore_buyItem 900 1600
    #         else
    #             printInColor "INFO" "Can't buy item from Labyrinth store"
    #         fi
    #     fi
    # fi
    inputTapSleep 70 1810 # Return
    verifyHEX 20 1775 af7747 "Visited the Store." "Failed to visit the Store."

    logDebug "buyFromStore" 4 "EXIT"
}

# ##############################################################################
# Function Name : buyFromStore_buyItem
# Descripton    : Buys an item from the Store
# Args          : <X> <Y>
# ##############################################################################
buyFromStore_buyItem() {
    logDebug "buyFromStore_buyItem ${cPurple}$*${cNc}" 4 "ENTER"

    inputTapSleep "$1" "$2" 1 # Item
    inputTapSleep 550 1540 1  # Purchase
    inputTapSleep 550 1700    # Close popup

    logDebug "buyFromStore_buyItem" 4 "EXIT"
}

# ##############################################################################
# Function Name : buyFromStore_test
# Descripton    : Buy items from store ON TEST SERVER (old shop)
# Remark        : Should be removed if one day the test server has the new shop
# ##############################################################################
buyFromStore_test() {
    logDebug "buyFromStore_test" 4 "ENTER"

    inputTapSleep 330 1650 3

    if [ "$buyStoreDust" = true ]; then # Dust
        buyFromStore_buyItem 180 840
    fi
    if [ "$buyStorePoeCoins" = true ]; then # Poe Coins
        buyFromStore_buyItem 670 1430
    fi
    # Primordial Emblem
    if [ "$buyStorePrimordialEmblem" = true ] && testColorOR -d "$DEFAULT_DELTA" 180 1430 9eabbd; then
        buyFromStore_buyItem 180 1430
    fi
    # Amplifying Emblem
    if [ "$buyStoreAmplifyingEmblem" = true ] && testColorOR -d "$DEFAULT_DELTA" 180 1430 d8995d; then
        buyFromStore_buyItem 180 1430
    fi
    if [ "$buyStoreSoulstone" = true ]; then                    # Soulstone (widh 90 diamonds)
        if testColorOR -d "$DEFAULT_DELTA" 910 850 a569d7; then # row 1, item 4
            buyFromStore_buyItem 910 850
        fi
        if testColorOR -d "$DEFAULT_DELTA" 650 850 57447b; then # row 1, item 3
            buyFromStore_buyItem 650 850
        fi
        if testColorOR -d "$DEFAULT_DELTA" 410 850 9787c9; then # row 1, item 2
            buyFromStore_buyItem 410 850
        fi
    fi
    if [ "$forceWeekly" = true ]; then
        # Weekly - Purchase an item from the Guild Store once (check red dot first row for most useful item)
        if [ "$buyWeeklyGuild" = true ]; then
            inputTapSleep 530 1810                                  # Guild Store
            if testColorOR -d "$DEFAULT_DELTA" 100 910 87b8e4; then # row 1, item 1
                if testColorOR -d "5" 250 740 ea1c09; then buyFromStore_buyItem 180 810; fi
            elif testColorOR -d "$DEFAULT_DELTA" 345 910 93c1ed; then # row 1, item 2
                if testColorOR -d "5" 500 740 ed240f; then buyFromStore_buyItem 420 810; fi
            elif testColorOR -d "$DEFAULT_DELTA" 590 910 3b2312; then # row 1, item 3
                if testColorOR -d "5" 740 740 f51f06; then buyFromStore_buyItem 660 810; fi
            elif testColorOR -d "$DEFAULT_DELTA" 835 910 81bde2; then # row 1, item 4
                if testColorOR -d "5" 980 740 f12f1e; then buyFromStore_buyItem 900 810; fi
            fi
        fi
        if [ "$buyWeeklyLabyrinth" = true ]; then
            inputTapSleep 1020 1810                                  # Labyrinth Store
            inputSwipe 1050 1600 1050 750 50                         # Swipe all the way down
            if testColorOR -d "$DEFAULT_DELTA" 180 1350 0c8bbd; then # row 5, item 1 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
                buyFromStore_buyItem 180 1350
            elif testColorOR -d "$DEFAULT_DELTA" 420 1350 2a99cc; then # row 5, item 2 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
                buyFromStore_buyItem 420 1350
            elif testColorOR -d "$DEFAULT_DELTA" 660 1350 8ca5a3; then # row 5, item 3 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
                buyFromStore_buyItem 660 1350
            elif testColorOR -d "$DEFAULT_DELTA" 900 1350 f9f9fb; then # row 5, item 4 > 120 Rare Hero Soulstone / 4800 Labyrinth Tokens
                buyFromStore_buyItem 900 1350
            elif testColorOR -d "$DEFAULT_DELTA" 180 1600 2b2c4a; then # row 6, item 1 >  60 Soulstones (Ira) / 2400 Labyrinth Tokens
                buyFromStore_buyItem 180 1600
            elif testColorOR -d "$DEFAULT_DELTA" 420 1600 3d2f30; then # row 6, item 2 >  60 Soulstones (Golus) / 2400 Labyrinth Tokens
                buyFromStore_buyItem 420 1600
            elif testColorOR -d "$DEFAULT_DELTA" 660 1600 1b151a; then # row 6, item 3 >  60 Soulstones (Mirael) / 2400 Labyrinth Tokens
                buyFromStore_buyItem 660 1600
            elif testColorOR -d "$DEFAULT_DELTA" 900 1600 999f9f; then # row 6, item 4 >  60 Soulstones (Silvina) / 2400 Labyrinth Tokens
                buyFromStore_buyItem 900 1600
            else
                printInColor "INFO" "Can't buy item from Labyrinth store"
            fi
        fi
    fi
    inputTapSleep 70 1810 # Return
    verifyHEX 20 1775 af7747 "Visited the Store." "Failed to visit the Store."

    logDebug "buyFromStore_test" 4 "EXIT"
}

# ##############################################################################
# Function Name : guildHunts
# Descripton    : Battles against Guild boss Wrizz
# ##############################################################################
guildHunts() {
    logDebug "guildHunts" 4 "ENTER"

    inputSwipe 300 100 550 1700 300 # Scroll Up
    # Open Guild
    inputTapSleep 480 1050 6

    # Check for fortune chest
    if testColorOR 380 500 8e4633; then
        inputTapSleep 560 1300
        inputTapSleep 540 1830
    fi
    wait

    # Open Guild Hunting
    inputTapSleep 290 860 3
    printInColor "INFO" "Fighting Wrizz."
    guildHunts_quickBattle

    # Check and handle Soren battle
    inputTapSleep 970 890 1              # Soren
    if testColorOR 715 1815 8ae5c4; then # If Soren is open
        printInColor "INFO" "Fighting Soren."
        guildHunts_quickBattle
    elif [ "$canOpenSoren" = true ]; then
        printInColor "INFO" "Soren is closed."
        if testColorOR 580 1753 fae0ac; then
            printInColor "INFO" "Oppening Soren."
            inputTapSleep 550 1850
            inputTapSleep 700 1250 1
            printInColor "INFO" "Fighting Soren."
            guildHunts_quickBattle
        fi
    fi

    # Return to Ranhorn if doTwistedRealmBoss is false
    if [ "$doTwistedRealmBoss" = false ]; then
        inputTapSleep 70 1810 3
        inputTapSleep 70 1810 3
        verifyHEX 20 1775 af7747 "Battled Wrizz and possibly Soren." "Failed to battle Wrizz and possibly Soren."
    else
        inputTapSleep 70 1810
        verifyHEX 70 1000 a9a95f "Battled Wrizz and possibly Soren." "Failed to battle Wrizz and possibly Soren."
    fi

    logDebug "guildHunts" 4 "EXIT"
}

# ##############################################################################
# Function Name : guildHunts_quickBattle
# Descripton    : Sweeps Quick Battles
# Remark        : May break because "some resources have exceeded their maximum limit"
# ##############################################################################
guildHunts_quickBattle() {
    logDebug "guildHunts_quickBattle" 4 "ENTER"

    # Check if possible to fight Wrizz -> Grey: a1a1a1 / Blue: 9de8be
    if [ "$guildBattleType" = "challenge" ]; then
        inputTapSleep 350 1840   # Challenge
        inputTapSleep 550 1850 0 # Battle
        waitBattleStart
        doAuto
        doSpeed
        waitBattleFinish 10     # Wait until battle is over
        inputTapSleep 550 800 0 # Reward
        inputTapSleep 550 800 1 # Reward x2
    else
        inputTapSleep 710 1840 # Quick Battle
        # WARN: May break because "some resources have exceeded their maximum limit"
        inputTapSleep 720 1300 1 # Begin
        inputTapSleep 550 800 0  # Reward
        inputTapSleep 550 800 1  # Reward x2
    fi

    logDebug "guildHunts_quickBattle" 4 "EXIT"
}

# ##############################################################################
# Function Name : nobleTavern
# Descripton    : Let's do a "free" summon with Companion Points
# ##############################################################################
nobleTavern() {
    logDebug "nobleTavern" 4 "ENTER"

    inputTapSleep 280 1370 3 # The Noble Tavern
    inputTapSleep 400 1820 1 # The noble tavern again

    #until testColorOR 890 850 f4e38e; do       # Looking for heart
    until testColorOR -d "$DEFAULT_DELTA" 875 835 f88c6b; do # Looking for heart, old value: f39067 (d=4)
        inputTapSleep 870 1630 1                             # Next pannel
    done

    inputTapSleep 320 1450 3 # Summon
    inputTapSleep 540 900 3  # Click on the card
    inputTapSleep 70 1810    # close
    inputTapSleep 550 1820 1 # Collect rewards

    inputTapSleep 70 1810
    verifyHEX 20 1775 af7747 "Summoned one hero with Companion Points." "Failed to summon one hero with Companion Points."

    logDebug "nobleTavern" 4 "EXIT"
}

# ##############################################################################
# Function Name : oakInn
# Descripton    : Collect Oak Inn
# Concept       : https://github.com/Fortigate/AFK-Daily/blob/master/deploy.sh > collectInnGifts()
# ##############################################################################
oakInn() {
    logDebug "oakInn" 4 "ENTER"

    _oakInn_TRIES=0
    _oakInn_TRIES_MAX=10
    oakInn_collectedPresents=false

    inputSwipe 300 100 550 1700 300 # Scroll Up
    inputTapSleep 550 500 5         # Oak Inn
    printInColor "INFO" "Searching for presents to collect..."

    inputSwipe 950 1700 950 100 300 # Swipe to the Bottom
    inputSwipe 950 1700 950 100 300 # Swipe to the Bottom

    until [ "$_oakInn_TRIES" -ge "$_oakInn_TRIES_MAX" ]; do
        inputTapSleep 240 1185 # Click Present
        if testColorOR 955 1235 eadcb6; then # Check if tapped on present
            inputTapSleep 550 1650           # Collect Reward
            inputTapSleep 540 1650           # Tap Reward Screen
            printInColor "INFO" "Collected presents at the Oak Inn."
            oakInn_collectedPresents=true
            break
        fi
        _oakInn_TRIES=$((_oakInn_TRIES + 1)) # Increment
    done

    # If no present collected, warn user
    if [ "$oakInn_collectedPresents" = 'false' ]; then
        printInColor "WARN" "No presents collected at the Oak Inn."
    fi

    inputTapSleep 70 1810 3 # Return

    verifyHEX 20 1775 af7747 \
        "Attempted to collect Oak Inn presents." \
        "Failed to collect Oak Inn presents."

    logDebug "oakInn" 4 "EXIT"
}

# ##############################################################################
# Function Name : strengthenCrystal
# Descripton    : Strengthen Crystal
# ##############################################################################
strengthenCrystal() {
    logDebug "strengthenCrystal" 4 "ENTER"

    inputSwipe 300 100 550 1700 300                          # Scroll Up
    if testColorOR -d "$DEFAULT_DELTA" 835 1730 fa6645; then # If red circle
        inputTapSleep 700 1700 3                             # Resonating Crystal

        # Detect if free slot, and take it.
        testColorORTapSleep 620 1250 82ead0 # Detected: 82ead0 / Not: e4c38e

        inputTapSleep 550 1850                                                    # Strenghen Crystal
        if testColorOR 700 1250 9aedc4 && [ "$allowCrystalLevelUp" = true ]; then # If Level up
            printInColor "INFO" "Resonating Crystal Level up."
            inputTapSleep 700 1250 3 # Confirm level up window
            inputTapSleep 200 1850 1 # Close level up window
            inputTapSleep 200 1850   # Close gift window
        else
            inputTapSleep 200 1850 # Close level up window
        fi
        inputTapSleep 200 1850 .5 # Better safe than sorry
        inputTapSleep 70 1810     # Exit
    else
        printInColor "INFO" "Not necessary to strengthen the resonating Crystal."
    fi
    verifyHEX 20 1775 af7747 "Strengthened resonating Crystal." "Failed to Strenghen Resonating Crystal."

    logDebug "strengthenCrystal" 4 "EXIT"
}

# ##############################################################################
# Function Name : templeOfAscension
# Descripton    : Auto ascend heroes
# ##############################################################################
templeOfAscension() {
    logDebug "templeOfAscension" 4 "ENTER"

    inputSwipe 300 100 550 1700 300                                 # Scroll Up
    if testColorOR -d "$DEFAULT_DELTA" 605 1124 ef5b3a; then        # If red circle
        inputTapSleep 300 1450 3                                    # Temple Of Ascension
        until testColorNAND -d "$DEFAULT_DELTA" 925 1840 bd9665; do # Auto Ascend button
            inputTapSleep 900 1800                                  # Auto Ascend
            inputTapSleep 550 1460                                  # Confirm
            inputTapSleep 550 1810                                  # Close
            sleep 2
        done
        inputTapSleep 70 1810 # Exit
        inputTapSleep 70 1810 # Exit
        wait
        verifyHEX 20 1775 af7747 "Attempted to ascend heroes." "Failed to ascend heroes."
    else
        printInColor "INFO" "No heroes to ascend."
    fi

    logDebug "templeOfAscension" 4 "EXIT"
}

# ##############################################################################
# Function Name : twistedRealmBoss
# Descripton    : Battles against the Twisted Realm Boss
# Args          : <START_FROM_TAB>: true / false
# ##############################################################################
twistedRealmBoss() {
    logDebug "twistedRealmBoss ${cPurple}$*${cNc}" 4 "ENTER"

    if [ "$1" = true ]; then            # Check if starting from tab or already inside activity
        inputSwipe 300 100 550 1700 300 # Scroll Up
        inputTapSleep 480 1050 6        # Guild
    fi
    ## For testing only! Keep as comment ##
    # inputTapSleep 380 360 10
    ## End of testing ##

    inputTapSleep 820 820 2 # Hellscape

    if testColorOR 540 1220 9aedc1; then # Check if TR is being calculated
        printInColor "INFO" "Unable to fight in the Twisted Realm because it's being calculated." >&2
    else
        # Check for Hellscape screen
        if testColorOR 750 100 1c2d3e; then
            inputTapSleep 550 700 2 # Twisted Realm
        fi

        printInColor "INFO" "Fighting Twisted Realm Boss ${cCyan}$totalAmountTwistedRealmBossTries${cNc} time(s)."
        until [ "$totalAmountTwistedRealmBossTries" -le 0 ]; do
            inputTapSleep 550 1850 # Challenge

            # When no challenges left, a pop-up appears that asks if you want to reset them for 50 diamonds
            if testColorOR 620 1260 a1eebf; then
                inputTapSleep 70 1810 # Skip pop-up
                break
            fi
            inputTapSleep 550 1850 0 # Battle
            waitBattleStart
            doAuto
            doSpeed
            waitBattleFinish 40
            wait
            inputTapSleep 550 800 3                                                    # tap score screen
            inputTapSleep 550 800                                                      # tap score screen to close it
            totalAmountTwistedRealmBossTries=$((totalAmountTwistedRealmBossTries - 1)) # Dicrement
        done
    fi

    inputTapSleep 70 1810
    inputTapSleep 70 1810 1
    verifyHEX 20 1775 af7747 "Checked Twisted Realm Boss out." "Failed to check the Twisted Realm out."

    logDebug "twistedRealmBoss" 4 "EXIT"
}

# ##############################################################################
# Section       : End
# ##############################################################################

# ##############################################################################
# Function Name : checkWhereToEnd
# Descripton    : Checks where to end the script
# ##############################################################################
checkWhereToEnd() {
    logDebug "checkWhereToEnd" 4 "ENTER"

    case "$endAt" in
    "oak")
        switchTab "Ranhorn" true
        inputSwipe 300 100 550 1700 300 # Scroll Up
        inputTapSleep 550 500 5         # Oak Inn
        ;;
    "soren")
        switchTab "Ranhorn" true
        inputSwipe 300 100 550 1700 300 # Scroll Up
        inputTapSleep 480 1050 6        # Guild
        inputTapSleep 290 860 3         # Guild Hunting
        inputTapSleep 970 890 0         # Soren
        ;;
    "mail")
        inputTapSleep 960 570 0
        ;;
    "chat")
        switchTab "Chat" true
        ;;
    "tavern")
        switchTab "Ranhorn" true
        inputSwipe 300 1700 550 400 300 # Scroll Down
        inputTapSleep 200 600 0
        ;;
    "merchants")
        inputTapSleep 100 250 0
        ;;
    "campaign")
        inputTapSleep 550 1850 0
        ;;
    "championship")
        switchTab "Dark Forest" true
        inputTapSleep 740 1050
        if [ "$pvpEventsActive" = "0" ]; then
            inputTapSleep 550 1370 0 # Championship
        elif [ "$pvpEventsActive" = "1" ]; then
            inputTapSleep 550 1680 0 # Championship
        else
            inputSwipe 550 1600 550 500 2 # Swipe up to see Championship
            inputTapSleep 550 1700 0      # Legend's Challenger Tournament
        fi
        ;;
    "closeApp")
        closeApp
        ;;
    *)
        printInColor "WARN" "Unknown location to end script on. Ignoring..." >&2
        ;;
    esac

    logDebug "checkWhereToEnd" 4 "EXIT"
}

# ##############################################################################
# Function Name : collectQuestChests
# Descripton    : Collects quest chests (well, switch tab then call collectQuestChests_quick)
# Remark        : May break because "some resources have exceeded their maximum limit"
# ##############################################################################
collectQuestChests() {
    logDebug "collectQuestChests" 4 "ENTER"

    # WARN: May break because "some resources have exceeded their maximum limit"
    # WARN: This actually happened to me today, and the script handled it well, as it thought it had one more chest to collect
    # WARN: and closed the warning message. Might not be a problem anymore.
    inputTapSleep 960 250 # Quests
    inputTapSleep 420 1650 1
    collectQuestChests_quick
    sleep 4

    inputTapSleep 650 1650 1 # Weeklies
    inputTapSleep 650 1650   # Weeklies
    collectQuestChests_quick
    sleep 4

    #WARN: May break if the reward is a new champ...
    inputTapSleep 930 1650 1                                   # Campaign
    inputTapSleep 930 1650                                     # Campaign
    until testColorNAND -d "$DEFAULT_DELTA" 950 610 acf0bd; do # Old value: 82fdf5
        inputTapSleep 860 610
    done

    inputTapSleep 70 1650 2 # Return
    verifyHEX 20 1775 af7747 "Collected daily and weekly quest chests." "Failed to collect daily and weekly quest chests."

    logDebug "collectQuestChests" 4 "EXIT"
}

# ##############################################################################
# Function Name : collectQuestChests_quick
# Descripton    : Collects quest chests
# ##############################################################################
collectQuestChests_quick() {
    logDebug "collectQuestChests_quick" 4 "ENTER"

    # Collect Quests
    until testColorNAND -d "$DEFAULT_DELTA" 700 770 79ede5; do # Old value: 82fdf5
        inputTapSleep 900 770
    done

    if testColorNAND -d "$DEFAULT_DELTA" 300 500 94722c && testColorNAND 300 500 a77d44; then   # OFF: 4b2711 COLLECTED: a77d44
        inputTapSleep 300 500                                                                   # Chest 20
        inputTapSleep 580 1850 0                                                                # Collect
    elif testColorNAND -d "$DEFAULT_DELTA" 470 500 e4b981 && testColorNAND 470 500 af7d3b; then # OFF: 552813 COLLECTED: af7d3b
        inputTapSleep 470 500                                                                   # Chest 40
        inputTapSleep 580 600 0                                                                 # Collect
    elif testColorNAND -d "$DEFAULT_DELTA" 630 500 4e2713 && testColorNAND 630 500 ae7c3a; then # OFF: 4e2713 COLLECTED: ae7c3a
        inputTapSleep 630 500                                                                   # Chest 60
        inputTapSleep 580 600 0                                                                 # Collect
    elif testColorNAND -d "$DEFAULT_DELTA" 800 500 f6d76c && testColorNAND 800 500 a77c44; then # OFF: 502611 COLLECTED: a77c44
        inputTapSleep 800 500                                                                   # Chest 80
        inputTapSleep 580 600 0                                                                 # Collect
    elif testColorNAND -d "$DEFAULT_DELTA" 970 500 e4c181 && testColorNAND 970 500 af7d3b; then # OFF: 662611 COLLECTED: af7d3b
        inputTapSleep 970 500                                                                   # Chest 100
        inputTapSleep 580 600                                                                   # Collect
    fi

    logDebug "collectQuestChests_quick" 4 "EXIT"
}

# ##############################################################################
# Function Name : collectMail
# Descripton    : Collects mail
# Remark        : May break because "some resources have exceeded their maximum limit"
# ##############################################################################
collectMail() {
    logDebug "collectMail" 4 "ENTER"

    # WARN: May break because "some resources have exceeded their maximum limit"
    if testColorOR -d "$DEFAULT_DELTA" 1035 535 ff5843; then # Red mark
        inputTapSleep 960 570                                # Mail
        inputTapSleep 790 1600                               # Collect all
        inputTapSleep 50 1850                                # Return
        inputTapSleep 50 1850                                # Return
        verifyHEX 20 1775 af7747 "Collected Mail." "Failed to collect Mail."
    else
        printInColor "INFO" "No mail to collect."
    fi

    logDebug "collectMail" 4 "EXIT"
}

# ##############################################################################
# Function Name : collectMerchants
# Descripton    : Collects Daily/Weekly/Monthly from the merchants page
# Remark        : Breaks if a pop-up message shows up or the merchant ship moves location "drastically"
# ##############################################################################
collectMerchants() {
    logDebug "collectMerchants" 4 "ENTER"

    inputTapSleep 120 300 7 # Merchants
    # WARN: Breaks if a pop-up message shows up

    # Check for Monthly Card
    if testColorOR -d "$DEFAULT_DELTA" 342 849 ea452c; then # Red exclamation mark
        inputTapSleep 270 950                               # Monthly Card Chest
        inputTapSleep 550 300                               # Collect rewards
        sleep 2
    fi

    # Check for Deluxe Monthly Card
    if testColorOR -d "$DEFAULT_DELTA" 895 849 f14c33; then # Red exclamation mark
        inputTapSleep 820 950                               # Deluxe Monthly Card Chest
        inputTapSleep 550 300                               # Collect rewards
        sleep 2
    fi
    inputTapSleep 780 1820 2 # Merchant Ship

    # Check for "Specials" freebie
    if testColorOR -d "$DEFAULT_DELTA" 365 740 f04b32; then
        inputTapSleep 210 945 # Free
        inputTapSleep 550 300 # Collect rewards
    else
        printInColor "INFO" "No 'Specials' reward to collect. [Tile]"
    fi

    # Check for "Daily Deals" freebie
    if testColorOR -d "$DEFAULT_DELTA" 345 1521 fd5037; then
        inputTapSleep 280 1625 2
        if testColorOR -d "$DEFAULT_DELTA" 365 515 d20101; then
            inputTapSleep 210 720 # Free
            inputTapSleep 550 300 # Collect rewards
        elif testColorOR -d "$DEFAULT_DELTA" 365 1000 e54830; then
            inputTapSleep 210 1200 # Free
            inputTapSleep 550 300  # Collect rewards
        else
            printInColor "INFO" "No 'Daily Deals' reward to collect. [Tile]"
        fi
    else
        printInColor "INFO" "No 'Daily Deals' reward to collect. [Menu]"
    fi

    # Check for "Biweeklies" freebie
    if testColorOR -d "$DEFAULT_DELTA" 520 1521 fd5037; then
        inputTapSleep 455 1625
        if testColorOR -d "$DEFAULT_DELTA" 365 515 d20101; then
            inputTapSleep 210 720 # Free
            inputTapSleep 550 300 # Collect rewards
        elif testColorOR -d "$DEFAULT_DELTA" 365 1475 f14f36; then
            inputTapSleep 210 1480 # Free
            inputTapSleep 550 300  # Collect rewards
        else
            printInColor "INFO" "No 'Biweeklies' reward to collect. [Tile]"
        fi
    else
        printInColor "INFO" "No 'Biweeklies' reward to collect. [Menu]"
    fi

    inputTapSleep 70 1810 4
    verifyHEX 20 1775 af7747 "Attempted to collect merchant freebies." "Failed to collect merchant freebies."

    logDebug "collectMerchants" 4 "EXIT"
}

# ##############################################################################
# Section       : Test
# ##############################################################################

# ##############################################################################
# Function Name : doTest
# Description   : Print HEX then exit
# Args          : <X> <Y> [<COLOR_TO_COMPARE>] [<REPEAT>] [<SLEEP>]
# Output        : stdout color
# ##############################################################################
doTest() {
    _doTest_COUNT=0
    until [ "$_doTest_COUNT" -ge "${4:-3}" ]; do
        sleep "${5:-.5}"
        getColor -f "$1" "$2"
        if [ "$#" -ge 3 ] && [ "${3:-""}" != "" ]; then
            printInColor "DEBUG" "doTest [${cPurple}$1${cNc}, ${cPurple}$2${cNc}] > HEX: ${cCyan}$HEX${cNc} [Δ ${cCyan}$(HEXColorDelta "$HEX" "$3")${cNc}%]"
        else
            printInColor "DEBUG" "doTest [${cPurple}$1${cNc}, ${cPurple}$2${cNc}] > HEX: ${cCyan}$HEX${cNc}"
        fi
        _doTest_COUNT=$((_doTest_COUNT + 1)) # Increment
    done
    # exit
}

# ##############################################################################
# Function Name : tests
# Descripton    : Uncomment tests to run it. Will exit after tests done.
# Remark        : If you want to run multiple tests you need to comment exit in test()
# ##############################################################################
tests() {
    printInColor "INFO" "Starting tests... ($(date))"

    # doTest 450 1050 ef2118 # Random coords
    # doTest 550 740         # Check for Boss in Campaign
    # doTest 660 520         # Check for Solo Bounties HEX
    # doTest 650 570         # Check for Team Bounties HEX
    # doTest 700 670         # Check for chest collection HEX
    # doTest 715 1815        # Check if Soren is open
    # doTest 740 205         # Check if game is updating
    # doTest 270 1800        # Oak Inn Present Tab 1
    # doTest 410 1800        # Oak Inn Present Tab 2
    # doTest 550 1800        # Oak Inn Present Tab 3
    # doTest 690 1800        # Oak Inn Present Tab 4

    printInColor "INFO" "End of tests! ($(date))"
    exit
}

# Run test functions
# tests

if [ -n "$totest" ]; then
    test_x=$(echo "$totest" | cut -d ',' -f 1)
    test_y=$(echo "$totest" | cut -d ',' -f 2)
    test_color=$(echo "$totest" | cut -d ',' -f 3)
    test_repeat=$(echo "$totest" | cut -d ',' -f 4)
    test_time=$(echo "$totest" | cut -d ',' -f 5)

    doTest "$test_x" "$test_y" "$test_color" "$test_repeat" "$test_time"
    exit
fi

# ##############################################################################
# Section       : Script Start
# ##############################################################################

# ##############################################################################
# Function Name : init
# Descripton    : Init the script (close/start app, preload, wait for update)
# Remark        : Can be skipped if you are already in the game
# ##############################################################################
init() {
    closeApp
    sleep 0.5
    startApp
    sleep 10

    # Loop until the game has launched
    until testColorOR -f 450 1775 af7646; do
        sleep 2
        # Close popup
        inputTapSleep 550 1850 .1
        #Check special popup that need to be closed with the cross
        testColorORTapSleep 1100 300 131517
    done

    # Preload graphics
    switchTab "Campaign" true
    sleep 3
    switchTab "Dark Forest"
    sleep 1

    # Check for HoE event
    if testColorOR -d "$DEFAULT_DELTA" 770 1165 c19e3a; then
        printInColor "INFO" "Heroes of Esperia event detected."
        eventHoe=true
    fi

    switchTab "Ranhorn"
    sleep 1
    switchTab "Campaign" true
    sleep 1

    # Open menu for friends, etc
    inputTapSleep 970 430 0

    # Check if game is being updated
    if testColorOR -f 740 205 ffc359; then
        printInColor "INFO" "Game is being updated!" >&2
        if [ "$waitForUpdate" = true ]; then
            printInColor "INFO" "Waiting for game to finish update..." >&2
            loopUntilNotRGB 5 740 205 ffc359
            printInColor "DONE" "Game finished updating."
        else
            printInColor "WARN" "Not waiting for update to finish." >&2
        fi
    fi
}

# ##############################################################################
# Function Name : run
# Descripton    : Run the script based on config
# ##############################################################################
run() {
    if [ "$hasEnded" = true ]; then return 0; fi # If the script has restarted we need a way to stop looping at the end.

    # CAMPAIGN TAB
    switchTab "Campaign"
    if checkToDo doLootAfkChest; then lootAfkChest; fi
    if checkToDo doChallengeBoss; then challengeBoss; fi
    if checkToDo doFastRewards; then fastRewards; fi
    if checkToDo doCollectFriendsAndMercenaries; then collectFriendsAndMercenaries; fi
    if checkToDo doLootAfkChest2; then lootAfkChest; fi

    # DARK FOREST TAB
    switchTab "Dark Forest"
    if checkToDo doSoloBounties; then
        soloBounties
        if checkToDo doTeamBounties; then teamBounties; fi
    elif checkToDo doTeamBounties; then teamBounties true; fi
    if checkToDo doArenaOfHeroes; then
        arenaOfHeroes
        if checkToDo doLegendsTournament; then legendsTournament; fi
    elif checkToDo doLegendsTournament; then legendsTournament true; fi
    if checkToDo doKingsTower; then kingsTower; fi
    if checkToDo doFountainOfTime; then fountainOfTime; fi

    # RANHORN TAB
    switchTab "Ranhorn"
    if checkToDo doGuildHunts; then
        guildHunts
        if checkToDo doTwistedRealmBoss; then twistedRealmBoss; fi
    elif checkToDo doTwistedRealmBoss; then twistedRealmBoss true; fi
    if checkToDo doBuyFromStore; then
        if [ "$testServer" = true ]; then
            buyFromStore_test
        else buyFromStore; fi
    fi
    if checkToDo doStrengthenCrystal; then strengthenCrystal; fi
    if checkToDo doTempleOfAscension; then templeOfAscension; fi
    if checkToDo doCompanionPointsSummon; then nobleTavern; fi
    if checkToDo doCollectOakPresents; then oakInn; fi

    # END
    if checkToDo doCollectQuestChests; then collectQuestChests; fi
    if checkToDo doCollectMail; then collectMail; fi
    if checkToDo doCollectMerchantFreebies; then collectMerchants; fi
    # Ends at given location
    sleep 1
    checkWhereToEnd

    eval "$currentPos=false" # Prevent loop on error
    hasEnded=true
}

printInColor "INFO" "Starting script... ($(date))"
if [ "$DEBUG" -gt 0 ]; then printInColor "INFO" "Debug: ${cBlue}ON${cNc} [${cCyan}$DEBUG${cNc}]"; fi
if [ "$forceFightCampaign" = true ]; then printInColor "INFO" "Fight Campaign: ${cBlue}ON${cNc}"; else printInColor "INFO" "Fight Campaign: ${cBlue}OFF${cNc}"; fi
if [ "$forceWeekly" = true ]; then printInColor "INFO" "Weekly: ${cBlue}ON${cNc}"; else printInColor "INFO" "Weekly: ${cBlue}OFF${cNc}"; fi
if [ "$testServer" = true ]; then printInColor "INFO" "Test server: ${cBlue}ON${cNc}"; fi

# Events
if [ "$eventHoe" = true ]; then activeEvents="${activeEvents} Heroes of Esperia |"; fi
if [ "$eventTs" = true ]; then activeEvents="${activeEvents} Treasure Scramble |"; fi
if [ "$eventTv" = true ]; then activeEvents="${activeEvents} Treasure Vanguard |"; fi
if [ "$bountifulBounties" = true ]; then activeEvents="${activeEvents} Bountiful Bounties |"; fi
if [ -n "$activeEvents" ]; then printInColor "INFO" "Active event(s): ${cBlue}|${activeEvents}${cNc}"; fi

echo
init
run

echo
printInColor "INFO" "End of script! ($(date))"
exit 0
