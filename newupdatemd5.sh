#!/bin/sh
# Script to create MD5 hashes for only video files

#  Create / Update MD5 files.  Usage: UpdateMD5.sh
#
# Switches:
#	-i *.ext	only create / update *.ext files. if multiple file types, use multiple -i Default all files
#	-s sharename	traverse only certain share (default = all shares) MAY TAKE A LONG TIME WITH APPDATA FILES
#	-u 		Update changed md5's for files whose date stamps are newer than the date stamp of the md5 file
#	-U		Don't update md5's for  files whose date stamps are newer than the date stamp of the md5 file (default)
#	-m		If the MD5 doesn't exist on the same drive as the media file, move it to the same drive (default)
#	-M		do not move the MD5
#	-P		pause during a parity check / rebuild  (default = don't pause)
#	-h		Usage help
#

# Get command arguments

INCL_EXCL=""
INCL_PARA=0
UPDATE=0
MOVE=1
SHARES=""
SHAREFLAG=0
PARITY=0
INCLUDES=""
EXCLUDES=""
TITLE="MD5_Updater"

while getopts i:e:s:uUmMhP OPT;
do
	case "$OPT" in
		i)
			if [ $INCL_PARA -gt "0" ]
			then
				INCL_EXCL="$INCL_EXCL -o"
			fi

			INCL_EXCL="$INCL_EXCL -iname $OPTARG"
			INCL_PARA=1
			INCLUDES="$INCLUDES $OPTARG"
			;;
		e)
			INCL_EXCL="$INCL_EXCL ! -name $OPTARG"
			INCL_PARA=1
			EXCLUDES="$EXCLUDES $OPTARG"
			;;
		u)
			UPDATE=1
			;;
		U)
			UPDATE=0
			;;
		m)
			MOVE=1
			;;
		M)
			MOVE=0
			;;
		s)
			SHARES="$(echo "$SHARES $OPTARG")"
			SHAREFLAG=1
			;;
		P)	PARITY=1
			;;
		h)
			echo "Usage:"
			echo "-i *.ext   only create / update *.ext files.  If using multiple file types, use multiple -i  At least one entry is required"
			echo "-e *.ext   excludes *.ext files.  If using multiple file types, use multiple -e switches"
			echo "-s  share name - required.  Use multiple if required"
			echo "-u  Update changed md5 for modified files (datestamp > datestamp of md5)"
			echo "-U  Don't update changed md5 for modified files (default)"
			echo "-m  Move the .md5 from user shares to disk shares (ensure on same drive as media file)(default)"
			echo "-M  Don't move the .md5 from user share to disk share"

			exit 0
			;;
		\?)
			echo "you are an idiot"
			exit 0
			;;
	esac
done

if [ $SHAREFLAG -eq 0 ]
then
	SHARES="."
fi

INCL_EXCL="$INCL_EXCL ! -name *.md5"

# Quick and dirty error checking

for SHARE in $SHARES
do
	if [ ! -d "/mnt/user/$SHARE" ];
	then
		echo "$SHARE does not exist"
		exit 1
	fi
done

# PASS #1 -> create MD5's on the user shares

logger -t $TITLE "Scanning $SHARES for new files without .MD5"
logger -t $TITLE "Included Files: $INCLUDES"
logger -t $TITLE "Excluded Files: $EXCLUDES"

if [ $UPDATE -eq "1" ]
then
	logger -t $TITLE "Update Changed Files: True"
else
	logger -t $TITLE "Update Changed Files: False"
fi

if [ $MOVE -eq "1" ]
then
	logger -t $TITLE "Move MD5 onto disk shares: True"
else
	logger -t $TITLE "Move MD5 onto disk shares: False"
fi

if [ $PARITY -eq "1" ]
then
	logger -t $TITLE "Pause during parity check / rebuild: True"
else
	logger -t $TITLE "Pause during parity check / rebuild: False"
fi

for CURRENTSHARE in $SHARES
do

echo $TOTALFILES

	cd "/mnt/user/$CURRENTSHARE"

	find $DIR -type f $INCL_EXCL | while read FILENAME
	do
	        cd "/mnt/user/$CURRENTSHARE"

# check if Parity is running and pause if need be

		if [ $PARITY -eq 1 ]
		then
			if [ $(grep mdResync= /var/local/emhttp/var.ini | awk '{print $3}' FS='[="]') -gt 0 ]
			then
				logger -t $TITLE "Parity Check / Rebuild in Progress.  Pausing MD5 Creation"

				while  [ $(grep mdResync= /var/local/emhttp/var.ini | awk '{print $3}' FS='[="]') -gt 0 ]
				do
					sleep 30
				done

				logger -t $TITLE "Resuming MD5 Creation"
			fi
		fi

		MD5FILE="$FILENAME.md5"

		if [ -e "$MD5FILE" ]
		then
			if [ $UPDATE -eq "1" ]
			then
        	                if [ $(date +%s -r "$FILENAME") -gt $(date +%s -r "$MD5FILE") ];
                	        then
					LOGFILE="/mnt/user/$CURRENTSHARE/$(echo "$FILENAME" | sed 's/^.\{2\}//')"

                                	logger -t $TITLE "$LOGFILE changed... Updating MD5"
			                cd "/mnt/user/$CURRENTSHARE/${FILENAME%/*}"
	                                md5sum -b "$(basename "$FILENAME")" > /tmp/md5file.md5

			                cd "/mnt/user/$CURRENTSHARE"

        	                        mv /tmp/md5file.md5 "$MD5FILE"
                	        fi
			fi


                else
			LOGFILE="/mnt/user/$CURRENTSHARE/$(echo "$FILENAME" | sed 's/^.\{2\}//')"

			logger -t $TITLE "Creating MD5 for $LOGFILE"

			cd "/mnt/user/$CURRENTSHARE/${FILENAME%/*}"

			md5sum -b "$(basename "$FILENAME")" > /tmp/md5file.md5
			cd "/mnt/user/$CURRENTSHARE"

			mv /tmp/md5file.md5 "$MD5FILE"
                fi
	done

done

logger -t $TITLE "Update of MD5 files complete"

# PASS 2 - > ensure the MD5 files are on the same disk as the file itself
# because of cache drive and split settings, it may not be

if [ $MOVE -eq "1" ]
then
	logger -t $TITLE "Scanning disks for missing .MD5 Files"

	ALLDISK=$(ls /mnt --color="never" | egrep "disk")

	for DISK in $ALLDISK
	do
		DIR="/mnt/$DISK"
		for SHARE in $SHARES
		do
			TESTDIR="$DIR/$SHARE"
			SHAREDIR="/mnt/user/$SHARE"

			find $TESTDIR $INCL_EXCL | while read FILENAME
			do
				MD5FILE="$FILENAME.md5"

				if [ ! -e "$MD5FILE" ]
				then
					MD5="$(basename "$FILENAME").md5"

					SHAREFILE=$(find /mnt/user/$SHARE -name "$MD5")

					if [ -e "$SHAREFILE" ]
					then
						logger -t $TITLE "$MD5FILE does not exist"
						logger -t $TITLE "Moving from $SHAREFILE to $MD5FILE"
						mv "$SHAREFILE" /tmp/md5file.md5
						mv /tmp/md5file.md5 "$MD5FILE"
					fi
				fi
			done
		done
	done

	logger -t $TITLE "Scan of Missing MD5 Files Complete"

fi
