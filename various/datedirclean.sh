#!/bin/bash

# Script to clean up date-based directories based off predefined settings.
# The script will always count from the last date in the directories, so
#   you never lose all the directories, even if no new ones get created.
# 
# Usage: $0 sourceDir [keepHours [keepDays [keepWeeks [keepMonths [keepYears]]]]]
# 
#   Sourcedir is the directory that has the date-named directories (default ./).
#   The keep* parameters are 0 or positive integers that indicate how much back
#     in time *from the most recent directory* will be kept. 
#     For any given timeframe, the kept backup will be the most recent one that
#     fits that timeframe.
#     0 means none of that level will be kept, so if you were to specify 0 hours 
#     and 3 days, then no hourly backups will be kept, but the most recent one 
#     will be kept, as well as the most recent ones of each day, counting
#     backwards until three days have been reached.
#     If you specify all zeroes, then nothing at all will be kept.
#     Defaults for the keep* parameters are:
#     24 hours, 7 days, 4 weeks, 12 months and 10 years


# These three parameters specify the conversion of your directory names from and
#   to things that the date utility understands.
# First of all, please make sure that your directories sort in the proper order,
#   as I can't smell how to sort them.
# Make sure to set the below very accurately, or stuff can go horribly wrong.
# Remember that this tool is going to delete stuff :-)
#
# dateFormat specifies the formatstring for date (without the plus) that will 
#   output timestamps in the exact format as your directories. You can probably
#   find the setting for this in the utility that creates the directories.
# See 'man date' for the details of this.
dateFormat='%Y%m%d-%H%M%S'
# dateMatch is a grep expression that will match ONLY the directories you want
#   cleaned. Properly set it prevents other stuff in there from being deleted.
dateMatch='^[0-9]\{8\}-[0-9]\{6\}$'
# dateInterpret() is an inline function that will reformat a directory name to
#   something that "date -d" will understand. This is necessary to be able to 
#   perform proper date arithmetic.
dateInterpret () { echo $1 | /bin/sed 's/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4\:\5\:\6/'; }

# These are simply the paths to the proper utilities. You shouldn't change them
#   unless the script complains it can't find them.
date='/bin/date'
grep='/bin/grep'
ls='/bin/ls'
sort='/usr/bin/sort'

# These pick up the parameters and set the defaults. You *can* change the defaults,
#   but I feel they're sensible, and it's better to override them with parameters.
sourceDir=$1
keepHours=${2:-24}
keepDays=${3:-7}
keepWeeks=${4:-4}
keepMonths=${5:-12}
keepYears=${6:-10}

################################################################################
## BELOW HERE THERE BE DRAGONS                                                ##
################################################################################
# This code does some weird stuff with dates. Test changes thoroughly before
#   you delete your entire disk :-)

if [[ "$sourceDir" == "" ]]; then
  echo "Usage:"
  echo "  $(basename $0) sourceDir [keepHours [keepDays [keepWeeks [keepMonths [keepYears]]]]]"
  echo ""
  echo "Source directory is non-optional to make it your own fault if you delete your data."
  echo "The rest of the parameters default to 24 hours, 7 days, 4 weeks, 12 months and 10 years."
  echo "Have a look at the top of the script for further information."
  exit 10
fi
if [[ ! -d "$sourceDir" ]]; then
  echo "ERROR: $sourceDir is not a directory"
  exit 10
fi
if [[ ! -x "$date" ]]; then
  echo "ERROR: The date utility is not at $date"
  exit 10
fi
if [[ ! -x "$grep" ]]; then
  echo "ERROR: The grep utility is not at $grep"
  exit 10
fi
if [[ ! -x "$ls" ]]; then
  echo "ERROR: The ls utility is not at $ls"
  exit 10
fi
if [[ ! -x "$sort" ]]; then
  echo "ERROR: The sort utility is not at $sort"
  exit 10
fi
if [[ ! -x /bin/sed ]]; then
  echo "ERROR: The sed utility is not at /bin/sed"
  exit 10
fi

oldIFS="$IFS"
# The newline below MUST REMAIN and \n doesn't work.
IFS='
'
aList=(`$ls "$sourceDir" | $grep "$dateMatch" | $sort -rn`)
IFS="$oldIFS"

lastDate=${aList[0]}
count=${#aList[@]}
index=0

echo "Sorting through $count entries."

echo "Keeping last $keepHours hours..."
minHoursDate=`$date -d "$(dateInterpret $lastDate) $keepHours hours ago" +$dateFormat`
echo "lastDate: $lastDate -- minHoursDate: $minHoursDate"
lastKept=''
lastKeptDate=''
while [[ ${aList[$index]} > $minHoursDate && $index -le $count ]]; do
  if [[ `$date -d "$(dateInterpret ${aList[$index]})" +%Y%m%d-%H` != $lastKept ]]; then
    echo "  keeping ${aList[$index]}"
    lastKeptDate=${aList[$index]}
    lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%Y%m%d-%H`
    unset aList[$index]
  else
    echo "  removing ${aList[$index]}"
  fi
  let index++
done


echo "Keeping last $keepDays days..."
minDaysDate=`$date -d "$(dateInterpret $lastDate) $keepDays days ago" +$dateFormat`
echo "lastDate: $lastDate -- minDaysDate: $minDaysDate"
if [[ "$lastKeptDate" != '' ]]; then
  lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%Y%m%d`
fi
while [[ ${aList[$index]} > $minDaysDate && $index -le $count ]]; do
  if [[ `$date -d "$(dateInterpret ${aList[$index]})" +%Y%m%d` != $lastKept ]]; then
    echo "  keeping ${aList[$index]}"
    lastKeptDate=${aList[$index]}
    lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%Y%m%d`
    unset aList[$index]
  else
    echo "  removing ${aList[$index]}"
  fi
  let index++
done


echo "Keeping last $keepWeeks weeks..."
minWeeksDate=`$date -d "$(dateInterpret $lastDate) $keepWeeks weeks ago" +$dateFormat`
echo "lastDate: $lastDate -- minWeeksDate: $minWeeksDate"
if [[ "$lastKeptDate" != '' ]]; then
  lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%G-%V`
fi
while [[ ${aList[$index]} > $minWeeksDate && $index -le $count ]]; do
  if [[ `$date -d "$(dateInterpret ${aList[$index]})" +%G-%V` != $lastKept ]]; then
    echo "  keeping ${aList[$index]}"
   lastKeptDate=${aList[$index]}
    lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%G-%V`
    unset aList[$index]
  else
    echo "  removing ${aList[$index]}"
  fi
  let index++
done


echo "Keeping last $keepMonths months..."
minMonthsDate=`$date -d "$(dateInterpret $lastDate) $keepMonths months ago" +$dateFormat`
echo "lastDate: $lastDate -- minMonthsDate: $minMonthsDate"
if [[ "$lastKeptDate" != '' ]]; then
  lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%Y%m`
fi
while [[ ${aList[$index]} > $minMonthsDate && $index -le $count ]]; do
  if [[ `$date -d "$(dateInterpret ${aList[$index]})" +%Y%m` != $lastKept ]]; then
    echo "  keeping ${aList[$index]}"
    lastKeptDate=${aList[$index]}
    lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%Y%m`
    unset aList[$index]
  else
    echo "  removing ${aList[$index]}"
  fi
  let index++
done


echo "Keeping last $keepYears years..."
minYearsDate=`$date -d "$(dateInterpret $lastDate) $keepYears years ago" +$dateFormat`
echo "lastDate: $lastDate -- minYearsDate: $minYearsDate"
if [[ "$lastKeptDate" != '' ]]; then
  lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%Y`
fi
while [[ ${aList[$index]} > $minYearsDate && $index -le $count ]]; do
  if [[ `$date -d "$(dateInterpret ${aList[$index]})" +%Y` != $lastKept ]]; then
    echo "  keeping ${aList[$index]}"
    lastKeptDate=${aList[$index]}
    lastKept=`$date -d "$(dateInterpret $lastKeptDate)" +%Y`
    unset aList[$index]
  else
    echo "  removing ${aList[$index]}"
  fi
  let index++
done


for toBeDeleted in "${aList[@]}"; do
  echo "Deleting $sourceDir/$toBeDeleted"
  rm -rf "$sourceDir/$toBeDeleted"
done

