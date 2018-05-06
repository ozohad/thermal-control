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

# Local variables
thermal_path=/config/mellanox/thermal

if [ "$1" == "add" ]; then
	if [ "$2" == "board_amb" ] || [ "$2" == "port_amb" ]; then
		ln -sf $3$4/temp1_input $thermal_path/$2
		ln -sf $3$4/temp1_max $thermal_path/$2_max
		ln -sf $3$4/temp1_max_hyst $thermal_path/$2_hyst
	fi
	if [ "$2" == "asic" ]; then
		ln -sf $3$4/temp1_input $thermal_path/$2
		ln -sf $3$4/temp1_highest $thermal_path/$2_highest
	fi
	if [ "$2" == "fan" ]; then
		# Take time for adding infrastructure
		sleep 3
		ln -sf $3$4/pwm1  $thermal_path/$pwm1
	fi
	if [ "$2" == "thermal_zone" ]; then
		busfolder=`basename $3$4`
		zonename=`echo $5`
		zonetype=`cat $3$4/type`
		if [ "$zonetype" == "mlxsw" ]; then
			# Set theraml zone governer to user space
			echo user_space > $3$4/policy
			# Enable thermal algorithm
			echo enabled > $3$4/mode
			zone=$zonetype
		else
			zone=$zonename-$zonetype
		fi
		mkdir -p /bsp/thermal_zone/$zone
		ln -sf $3$4/mode /bsp/thermal_zone/$zone/mode
		for i in {0..11}; do
			if [ -f $3$4/trip_point_"$i"_temp ]; then
				ln -sf $3$4/trip_point_"$i"_temp /bsp/thermal_zone/$zone/trip_point_$i
			fi
			if [ -d $3$4/cdev"$i" ]; then
				ln -sf $3$4/cdev"$i"/cur_state /bsp/thermal_zone/$zone/cooling"$i"_current_state
			fi
		done
	fi
	if [ "$2" == "cputemp" ]; then
		for i in {1..9}; do
			if [ -f $3$4/temp"$i"_input ]; then
				if [ $i -eq 1 ]; then
					name="pack"
				else
					id=$(($i-2))
					name="core$id"
				fi
				ln -sf $3$4/temp"$i"_input $thermal_path/cpu_$name
				ln -sf $3$4/temp"$i"_crit $thermal_path/cpu_"$name"_crit
				ln -sf $3$4/temp"$i"_crit_alarm $thermal_path/cpu_"$name"_crit_alarm
				ln -sf $3$4/temp"$i"_max $thermal_path/cpu_"$name"_max
			fi
		done
	fi
	if [ "$2" == "hotplug" ]; then
		for i in {1..12}; do
			if [ -f $3$4/fan$i ]; then
				ln -sf $3$4/fan$i $thermal_path/fan"$i"_status
			fi
		done
		for i in {1..2}; do
			if [ -f $3$4/psu$i ]; then
				ln -sf $3$4/psu$i $thermal_path/psu"$i"_status
			fi
		done
  	fi
elif [ "$1" == "change" ]; then
	echo "Do nothing on change"
elif [ "$1" == "offline" ]; then
	echo "Do nothing on offline"
else
	if [ "$2" == "board_amb" ] || [ "$2" == "port_amb" ]; then
		unlink $thermal_path/$2
		unlink $thermal_path/$2_max
		unlink $thermal_path/$2_hyst
	fi
	if [ "$2" == "asic" ]; then
		unlink $thermal_path/$2
		unlink $thermal_path/$2_highest
	fi
	if [ "$2" == "fan" ]; then
		unlink  $thermal_path/$pwm1
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonefolder=`basename /bsp/thermal_zone/$5*`
		if [ ! -d /bsp/thermal_zone/$zonefolder ]; then
			zonefolder=mlxsw
		fi
		if [ -d /bsp/thermal_zone/$zonefolder ]; then
			unlink /bsp/thermal_zone/$zonefolder/mode
			for i in {0..11}; do
				if [ -L /bsp/thermal_zone/$zonefolder/trip_point_$i ]; then
					unlink /bsp/thermal_zone/$zonfoldere/trip_point_$i
				fi
				if [ -L /bsp/thermal_zone/$zonefolder/cooling"$i"_current_state ]; then
					unlink /bsp/thermal_zone/$zonefolder/cooling"$i"_current_state
				fi
			done
			unlink /bsp/thermal_zone/$zonefolder/*
			rm -rf /bsp/thermal_zone/$zonefolder
		fi
  	fi
	if [ "$2" == "cputemp" ]; then
		unlink $thermal_path/cpu_pack
		unlink $thermal_path/cpu_pack_crit
		unlink $thermal_path/cpu_pack_crit_alarm
		unlink $thermal_path/cpu_pack_max
		for i in {1..8}; do
			if [ -L $thermal_path/cpu_core"$i" ]; then
				j=$((i+1))
				unlink $thermal_path/cpu_core"$j"
				unlink $thermal_path/cpu_core"$j"_crit
				unlink $thermal_path/cpu_core"$j"_crit_alarm
				unlink $thermal_path/cpu_core"$j"_max
			fi
		done
	fi
	if [ "$2" == "hotplug" ]; then
		for i in {1..12}; do
			if [ -L $thermal_path/fan"$i"_status ]; then
				unlink $thermal_path/fan"$i"_status
			fi
		done
		for i in {1..2}; do
			if [ -L $thermal_path/psu"$i"_status ]; then
				unlink $thermal_path/psu"$i"_status
			fi
		done
	fi
fi
