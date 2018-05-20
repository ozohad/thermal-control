#!/bin/bash
########################################################################
# Copyright (c) 2018 Mellanox Technologies.
# Copyright (c) 2018 Vadim Pasternak <vadimp@mellanox.com>
#
# Licensed under the GNU General Public License Version 2
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

# This is udev triggers handler. It creates or destroys symbolic links to sysfs
# entries according to the rules data and creates generic thermal model, which
# doesn't depend on specific system topology. It allows thermal algorithm to
# work in the same on different system over this system independent model.

# Local variables
thermal_path=/config/mellanox/thermal
max_psus=2
max_tachos=12

if [ "$1" == "add" ]; then
	if [ "$2" == "fan_amb" ] || [ "$2" == "port_amb" ]; then
		ln -sf $3$4/temp1_input $thermal_path/$2
	fi
	if [ "$2" == "switch" ]; then
		name=`cat $3$4/name`
		if [ "$name" == "mlxsw" ]; then
			ln -sf $3$4/pwm1 $thermal_path/pwm1
			for ((i=1; i<=$max_tachos; i+=1)); do
				if [ -f $3$4/fan"$i"_fault ]; then
					ln -sf $3$4/fan"$i"_fault $thermal_path/fan"$i"_fault
				fi
			done
		elif [ "$name" == "mlxsw_port" ]; then
			ln -sf $3$4/temp1_input $thermal_path/temp1_input_port
			ln -sf $3$4/temp1_fault $thermal_path/temp1_fault_port
		fi
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		if [ "$zonetype" == "mlxsw" ]; then
			ln -sf $3$4/mode $thermal_path/thermal_zone_mode
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "Fan" ]; then
			ln -sf $3$4/cur_state $thermal_path/cooling_cur_state
		fi
	fi
	if [ "$2" == "hotplug" ]; then
		for ((i=1; i<=$max_tachos; i+=1)); do
			if [ -f $3$4/fan$i ]; then
				ln -sf $3$4/fan$i $thermal_path/fan"$i"_status
			fi
		done
		for ((i=1; i<=$max_psus; i+=1)); do
			if [ -f $3$4/psu$i ]; then
				ln -sf $3$4/psu$i $thermal_path/psu"$i"_status
			fi
		done
  	fi
elif [ "$1" == "change" ]; then
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		if [ "$zonetype" == "mlxsw" ]; then
			# Notify thermal control about thermal zone change.
			if [ -f /var/run/mellanox-thermal.pid ]; then
				pid=`cat /var/run/mellanox-thermal.pid`
				kill -USR1 $pid
			fi
		fi
	fi
else
	if [ "$2" == "fan_amb" ] || [ "$2" == "port_amb" ]; then
		unlink $thermal_path/$2
	fi
	if [ "$2" == "switch" ]; then
		name=`cat $3$4/name`
		if [ "$name" == "mlxsw" ]; then
			unlink $thermal_path/pwm1
			for ((i=1; i<=$max_tachos; i+=1)); do
				if [ -L $thermal_path/fan"$i"_fault ]; then
					unlink $thermal_path/fan"$i"_fault
				fi
			done
			unlink  $thermal_path/$pwm1
		elif [ "$name" == "mlxsw_port" ]; then
			unlink $thermal_path/temp1_input_port
			unlink $thermal_path/temp1_fault_port
		fi
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		if [ "$zonetype" == "mlxsw" ]; then
			unlink $thermal_path/thermal_zone_mode
		fi
	fi

	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "Fan" ]; then
			unlink $thermal_path/cooling_cur_state
		fi
	fi
	if [ "$2" == "hotplug" ]; then
		for ((i=1; i<=$max_tachos; i+=1)); do
			if [ -L $thermal_path/fan"$i"_status ]; then
				unlink $thermal_path/fan"$i"_status
			fi
		done
		for ((i=1; i<=$max_psus; i+=1)); do
			if [ -L $thermal_path/psu"$i"_status ]; then
				unlink $thermal_path/psu"$i"_status
			fi
		done
	fi
fi
