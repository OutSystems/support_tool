#!/bin/bash

function askYesNo() {
	local answerYN="$1"

	echo -e -n "${*:2} [\e[49;32;3m$1\e[m] "

	read answerYN
	while [ "$answerYN" != "y" -a "$answerYN" != "n" -a "$answerYN" != "" ] ; do
		echo "Invalid value. Please write 'y' or 'n'"
		echo -e -n "${*:2} [\e[49;32;3m$1\e[m] "
		read answerYN
	done
	if [ "$answerYN" = "" ] ; then
			answerYN="$1"
	fi

	[ "$answerYN" = "y" ]
}
