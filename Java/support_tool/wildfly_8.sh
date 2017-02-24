#!/bin/bash

DIR=$1
CP='cp -p'

source /etc/sysconfig/outsystems

APPSERVER_NAME="Application Server"
WEBLOGIC_NAME="WebLogic"
JBOSS_NAME="JBoss"
WILDFLY_NAME="Wildfly"

LOGDAYS=30


JAVA_BIN=$JAVA_HOME/bin


source utils.sh

LOGS_FOLDER=""

if [ "$WILDFLY_HOME" != "" ]; then
       APPSERVER_NAME=$WILDFLY_NAME
       PROCESS_USER="wildfly"
       LOGS_FOLDER=$WILDFLY_HOME/standalone/log/
       PROCESS_PID=$(ps -ef | grep java.*standalone-outsystems.xml | grep -v grep | awk '{print $2}')
       PID_MQ=$(ps -ef | grep java.*standalone-outsystems-mq.xml | grep -v grep | awk '{print $2}')
       JBOSS_HOME=$WILDFLY_HOME
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


#JBoss Specific
if [ "$APPSERVER_NAME" == "$JBOSS_NAME" -o "$APPSERVER_NAME" == "$WILDFLY_NAME" ]; then
	echo "    * Configurations"
	# H2 directory
	if [ -d $JBOSS_HOME/server/outsystems/data/h2/ ] ; then 
		ls -lh $JBOSS_HOME/server/outsystems/data/h2/ > $DIR/h2_dir
	fi
	
	# Configuration
	if [ -d $JBOSS_HOME/server/outsystems/ ]; then
		$CP $JBOSS_HOME/bin/run.sh $DIR 2>> $DIR/errors.log
		$CP $JBOSS_HOME/bin/run.conf $DIR 2>> $DIR/errors.log
		# jboss service configuration
		$CP $JBOSS_HOME/server/outsystems/conf/jboss-service.xml  $DIR 2>> $DIR/errors.log
		# jboss connectors
		$CP $JBOSS_HOME/server/outsystems/deploy/jbossweb.sar/server.xml $DIR 2>> $DIR/errors.log
	else
		$CP -r $JBOSS_HOME/standalone/configuration/ $DIR 2>> $DIR/errors.log
		$CP -r $JBOSS_HOME/standalone/configuration-mq/ $DIR 2>> $DIR/errors.log
		$CP $JBOSS_HOME/bin/standalone-outsystems.conf $DIR 2>> $DIR/errors.log
		$CP $JBOSS_HOME/bin/standalone-outsystems-mq.conf $DIR 2>> $DIR/errors.log
		$CP $JBOSS_HOME/bin/standalone-outsystems-mq.properties $DIR 2>> $DIR/errors.log
		$CP $JBOSS_HOME/bin/standalone-outsystems.properties $DIR 2>> $DIR/errors.log
		if [ -f /var/log/jboss-as/console-outsystems.log ]; then
		  $CP /var/log/jboss-as/console-outsystems.log $DIR 2>> $DIR/errors.log
		fi
	fi
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

