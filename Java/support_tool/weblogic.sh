#!/bin/bash

DIR=$1
CP='cp -p'

source /etc/sysconfig/outsystems

APPSERVER_NAME="Application Server"
WEBLOGIC_NAME="WebLogic"
JBOSS_NAME="JBoss"
WILDFLY_NAME="Wildfly"
WL_ADMIN_SERVER_NAME="AdminServer"

LOGDAYS=30


JAVA_BIN=$JAVA_HOME/bin


source utils.sh

LOGS_FOLDER=""

if [ "$WL_DOMAIN" != "" ]; then
	APPSERVER_NAME="$WEBLOGIC_NAME"
	if [ "$PROCESS_USER" == "" ]; then
		PROCESS_USER=$(stat -c %U $WL_DOMAIN)
	fi
	
	if [ "$WL_MANAGED_SERVER_NAME" == "" ]; then
		PROCESS_PID=$(ps -u $PROCESS_USER --format "pid cmd" 2>>/dev/null | grep java | grep weblogic.Server | grep -v weblogic.Name=$WL_ADMIN_SERVER_NAME | gawk '{print $1}')
		ADMINSERVER_PID=$(ps -u $PROCESS_USER --format "pid cmd" 2>>/dev/null | grep java | grep weblogic.Server | grep weblogic.Name=$WL_ADMIN_SERVER_NAME | gawk '{print $1}')
		WL_MANAGED_SERVER_NAME=$(ps --pid $PROCESS_PID --format cmd | grep java | sed 's/.*weblogic.Name=[ ]*\([^ ]*\).*/\1/g')
	else
		PROCESS_PID=$(ps -u $PROCESS_USER --format "pid cmd" 2>>/dev/null | grep java | grep weblogic.Server | grep weblogic.Name=$WL_MANAGED_SERVER_NAME | gawk '{print $1}')
	fi
	LOGS_FOLDER="$WL_DOMAIN/servers/$WL_MANAGED_SERVER_NAME/logs"
fi

if [ "$PROCESS_PID" == "" ]; then
	echo "Could not find the $APPSERVER_NAME process."
else
		echo "Gathering $APPSERVER_NAME (Process $PROCESS_PID) info..."
		echo "    * CPU statistics"
		# cpu status
		top -b -n 5 -p $PROCESS_PID > $DIR/cpu_"$APPSERVER_NAME".log 2>> $DIR/errors.log
		pmap -d $PROCESS_PID > $DIR/pmap_$APPSERVER_NAME 2>> $DIR/errors.log
		if [ -f $JAVA_BIN/jrcmd ]; then
			echo "    * Thread Stacks"
			su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jrcmd $PROCESS_PID print_threads > $DIR/threads_"$APPSERVER_NAME".log 2>> $DIR/errors.log"
			su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jrcmd $ADMINSERVER_PID print_threads > $DIR/threads_"$WL_ADMIN_SERVER_NAME".log 2>> $DIR/errors.log"
			echo "    * Java Counters"
			su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jrcmd $PROCESS_PID -l > $DIR/counters_"$APPSERVER_NAME".log 2>> $DIR/errors.log"
			echo "    * Object Summary"
			su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jrcmd $PROCESS_PID print_object_summary > $DIR/object_summary_"$APPSERVER_NAME".log 2>> $DIR/errors.log"
			echo "    * Heap Diagnostics"
			su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jrcmd $PROCESS_PID heap_diagnostics > $DIR/heap_diagnostics_"$APPSERVER_NAME".log 2>> $DIR/errors.log"
		else
			echo "    * Thread Stacks"
			su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jstack $PROCESS_PID > $DIR/threads_"$APPSERVER_NAME".log 2>> $DIR/errors.log"
			if [ -d $JBOSS_HOME/standalone/ ]; then
				su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jstack $PID_MQ > $DIR/threads_"$APPSERVER_NAME"_mq.log 2>> $DIR/errors.log"
			fi
		fi
fi


# Weblogic Specific
if [ "$APPSERVER_NAME" == "$WEBLOGIC_NAME" ]; then
	echo "    * Patch information"
	su $PROCESS_USER - -s /bin/bash -c "cd $MW_HOME/utils/bsu ; ./bsu.sh -prod_dir=$WL_HOME -status=applied -verbose -view > $DIR/weblogic_patches 2>> $DIR/errors.log"
fi

if [ "$PROCESS_PID" == "" ]; then
	echo "not collecting memory dump because couldn't find process pid"
else
	if askYesNo "n" "Include $APPSERVER_NAME Memory Dump?"; then
		echo "Gathering $APPSERVER_NAME (Process $PROCESS_PID) memory dump..."
		# heap dump
		if [ -f $JAVA_BIN/jrcmd ]; then
			su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jrcmd $PROCESS_PID hprofdump filename=$DIR/heap.hprof > /dev/null 2>> $DIR/errors.log"
		else
			su $PROCESS_USER - -c "$JAVA_BIN/jmap -J-d64 -dump:format=b,file=$DIR/heap.hprof $PROCESS_PID > /dev/null 2>> $DIR/errors.log"
			if [ -d $JBOSS_HOME/standalone ]; then
				su $PROCESS_USER - -s /bin/bash -c "$JAVA_BIN/jmap -J-d64 -dump:format=b,file=$DIR/heap_mq.hprof $PID_MQ > /dev/null 2>> $DIR/errors.log"
			fi
		fi
	fi
fi


if [ "$LOGS_FOLDER" == "" ]; then
	echo "Invalid logs folder: '$LOGS_FOLDER'"
else
	echo "Gathering $APPSERVER_NAME Logs..."
	# Application Server Logs
	find $LOGS_FOLDER/ -name '*.log*' -ctime -$LOGDAYS -exec $CP \{\} $DIR \;
	find $LOGS_FOLDER/ -name '*.out*' -ctime -$LOGDAYS -exec $CP \{\} $DIR \;

	if [ -d $JBOSS_HOME/standalone/log-mq ] ; then
		mkdir $DIR/log-mq/
		find $JBOSS_HOME/standalone/log-mq/ -name '*.log*' -ctime -$LOGDAYS -exec $CP \{\} $DIR/log-mq/ \;
	fi
fi



