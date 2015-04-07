#!/bin/bash

# Script to check all md5's in a disk (passthrough as command parameter)

# CONFIG="/etc/checkmd5.conf"
FOLDER="$(cat "$CONFIG")"
# echo $1

# exit
FOLDER=$1
#FOLDER="user/TestShare"

DIR="/mnt/$FOLDER"

LOG="/var/log/check_md5.log"

# Make sure that the folder passed actually exists

if [ -d "$DIR" ]
then
	echo "" >> $LOG
	echo "" >> $LOG
	echo "New check started.  Please close then reopen this window to view the log" >> $LOG

	if [ "$DIR" = "/mnt/" ]
	then
		echo "Using /mnt/ as a source is not allowed because it will check all of the drives and /mnt/user and /mnt/user0." >> $LOG
		echo "In otherwords, it will check every file 3 times" >> $LOG
		echo "Please use /mnt/user instead to check every file." >> $LOG
		echo "" >> $LOG
		echo "Aborting..." >> $LOG
		exit 1
	fi

	
	# start the log over again

	if [ -e $LOG ]
	then
		rm $LOG
	fi

	echo "Check_MD5 Plugin Log" >> $LOG
	echo "" >> $LOG
	echo "Checking MD5 checksums for $DIR" >> $LOG
	echo "" >> $LOG
	echo "Start time: $(date)" >> $LOG
	echo "" >> $LOG

# Loop throough all the video files on the disk

	echo "Gathering files in $DIR" >> $LOG

	find $DIR -type f -iname "*.md5" | while read FILENAME
	do

# check if the user wants us to abort

		if [ -e /tmp/checkmd5_abort ]
		then
			exit
		fi

		echo "**** Testing $FILENAME" >> $LOG
		printf " ${FILENAME%/*}/" >> $LOG
		cd "${FILENAME%/*}"
        	md5sum -c "$FILENAME" &>> $LOG
	done

	echo "" >> $LOG
	echo "Finish Time: $(date)" >> $LOG

# Completed
# Now begin failure analysis

	GOOD=$(cat $LOG | egrep -c ": OK")
	BAD=$(cat $LOG | egrep -c ": FAILED")
	BADMD5=$(cat $LOG | egrep -c ": no properly formatted MD5 checksum lines found")
	ORPHANED=$(cat $LOG | egrep -c ": No such file or directory")

	if [ $BAD -gt 0 ] || [ $BADMD5 -gt 0 ] || [ $ORPHANED -gt 0 ]
	then
		if [ -e /tmp/check_md5.tmp ]
		then
			rm /tmp/check_md5.tmp
		fi

		cat $LOG | egrep ": FAILED" | while read FAILED
		do
			TESTFILE=$(echo "$FAILED" | sed 's/\: FAILED//g')
			MD5FILE="$TESTFILE.md5"

			if [ -e "$MD5FILE" ]
			then
				if [ $(date +%s -r "$TESTFILE") -gt $(date +%s -r "$MD5FILE") ];
				then
					echo "$TESTFILE: FILE UPDATED" >> /tmp/check_md5.tmp
				else
					echo "$TESTFILE: CORRUPTED" >> /tmp/check_md5.tmp
				fi
			else
				echo "$TESTFILE: UNKNOWN FAILURE" >> /tmp/check_md5.tmp
			fi
		done

		cat $LOG | egrep ": no properly formatted MD5 checksum lines found" | while read FAILED
		do
			TESTFILE=$(echo "$FAILED" | sed 's/\: no properly formatted MD5 checksum lines found//g')
			echo "$TESTFILE: BAD MD5" >> /tmp/check_md5.tmp
		done

		cat $LOG | egrep ": No such file or directory" | while read FAILED
		do
			TESTFILE=$(echo "$FAILED" | sed 's/\: no properly formatted MD5 checksum lines found//g')
			echo "$TESTFILE: ORPHANED" >> /tmp/check_md5.tmp
		done

		echo "" >> $LOG
		echo "**********************" >> $LOG
		echo "** Failure Analysis **" >> $LOG
		echo "**********************" >> $LOG
		echo "" >> $LOG

		UPDATEDFILES=$(cat /tmp/check_md5.tmp | egrep -c ": FILE UPDATED")
		CORRUPTFILES=$(cat /tmp/check_md5.tmp | egrep -c ": CORRUPTED")
		UNKNOWNFILES=$(cat /tmp/check_md5.tmp | egrep -c ": UNKNOWN FAILURE")
		BADMD5FILES=$(cat /tmp/check_md5.tmp | egrep -c ": BAD MD5")
		ORPHANEDFILES=$(cat /tmp/check_md5.tmp | egrep -c ": ORPHANED")

		if [ $UPDATEDFILES -gt 0 ]
		then
			echo "FILES WHICH HAVE BEEN UPDATED: $UPDATEDFILES" >> $LOG
			echo "" >> $LOG


			cat /tmp/check_md5.tmp | egrep ": FILE UPDATED" | while read FAILED
			do
				echo "$FAILED" | sed 's/\: FILE UPDATED//g' >> $LOG
 			done
			echo "" >> $LOG
		fi

		if [ $CORRUPTFILES -gt 0 ]
		then
			echo "FILES WHICH ARE CORRUPTED: $CORRUPTFILES" >> $LOG
			echo "" >> $LOG

			cat /tmp/check_md5.tmp | egrep ": CORRUPTED" | while read FAILED
			do
				echo "$FAILED" | sed 's/\: CORRUPTED//g'>> $LOG
			done
			echo "" >> $LOG
		fi

		if [ $UNKNOWNFILES -gt 0 ]
		then
			echo "FILES WHICH HAVE UNKNOWN FAILURES: (Review the logs): $UNKNOWNFILES" >> $LOG
			echo "" >> $LOG

			cat /tmp/check_md5.tmp | egrep ": UNKNOWN FAILURE" | while read FAILED
			do
				echo "$FAILED" | sed 's/\: UNKNOWN FAILURE//g'>> $LOG
			done
			echo "" >> $LOG
		fi

		if [ $BADMD5FILES -gt 0 ]
		then
			echo "FILES WHICH HAVE BAD / CORRUPTED MD5'S (Review the logs:): $BADMD5FILES" >> $LOG
			echo "" >> $LOG

			cat /tmp/check_md5.tmp | egrep ": BAD MD5" | while read FAILED
			do
				echo "$FAILED" | sed -n -e 's/^.*md5sum: //p'| sed 's/\: BAD MD5//g' >> $LOG
			done
			echo "" >> $LOG
		fi

		if [ $ORPHANEDFILES -gt 0 ]
		then
			echo "FILES WHICH HAVE BEEN DELETED (ORPHANED MD5) (Review the logs:): $ORPHANEDFILES" >> $LOG
			echo "" >> $LOG

			cat /tmp/check_md5.tmp | egrep ": ORPHANED" | while read FAILED
			do
				echo "$FAILED"| sed -n -e 's/^.*md5sum: //p'| sed 's/\: ORPHANED//g' >> $LOG
			done
			echo "" >> $LOG
		fi

		rm /tmp/check_md5.tmp

	else
		echo "ALL FILES PASSED MD5 VERIFICATION" >> $LOG
		echo "" >> $LOG
	fi

	echo "Total number of files passed MD5 Verification: $GOOD" >> $LOG

# Save the log files to the flash drive

	LOGFILE=$(date "+%Y%m%d-%H%M%S-Check_MD5_log.txt")

	if [ ! -d "/boot/config/plugins/Check_MD5/Logs/" ]
	then
		mkdir -p "/boot/config/plugins/Check_MD5/Logs"
	fi

# Convert to DOS format for easy viewing

	awk 'sub("$", "\r")' $LOG > "/boot/config/plugins/Check_MD5/Logs/$LOGFILE"

	exit 0
else
	echo "Aborting Verification Checks"
	echo "$DIR Does NOT exist.  Aborting" >> $LOG
	exit 1
fi



