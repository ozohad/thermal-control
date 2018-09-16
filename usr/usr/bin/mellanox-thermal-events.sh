#!/bin/bash
########################################################################
# Copyright (c) 2018 Mellanox Technologies. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the names of the copyright holders nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# Alternatively, this software may be distributed under the terms of the
# GNU General Public License ("GPL") version 2 as published by the Free
# Software Foundation.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

. /lib/lsb/init-functions

# Local variables
thermal_path=/config/mellanox/thermal
max_psus=2
max_tachos=12
max_modules_ind=65
fan_command=0x3b
fan_psu_default=0x3c
i2c_bus_max=10
i2c_bus_offset=0
i2c_asic_bus_default=2

find_i2c_bus()
{
	# Find physical bus number of Mellanox I2C controller. The default
	# number is 1, but it could be assigned to others id numbers on
	# systems with different CPU types.
	for ((i=1; i<$i2c_bus_max; i++)); do
		folder=/sys/bus/i2c/devices/i2c-$i
		if [ -d $folder ]; then
			name=`cat $folder/name | cut -d' ' -f 1`
			if [ "$name" == "i2c-mlxcpld" ]; then
				i2c_bus_offset=$(($i-1))
				return
			fi
		fi
	done

	log_failure_msg "i2c-mlxcpld driver is not loaded"
	exit 0
}

if [ "$1" == "add" ]; then
	if [ "$2" == "fan_amb" ] || [ "$2" == "port_amb" ]; then
		ln -sf $3$4/temp1_input $thermal_path/$2
	fi
	if [ "$2" == "switch" ]; then
		name=`cat $3$4/name`
		if [ "$name" == "mlxsw" ]; then
			ln -sf $3$4/temp1_input $thermal_path/temp1_input_asic
			ln -sf $3$4/pwm1 $thermal_path/pwm1
			for ((i=1; i<=$max_tachos; i+=1)); do
				if [ -f $3$4/fan"$i"_fault ]; then
					ln -sf $3$4/fan"$i"_fault $thermal_path/fan"$i"_fault
				fi
				if [ -f $3$4/fan"$i"_input ]; then
					ln -sf $3$4/fan"$i"_input $thermal_path/fan"$i"_input
				fi
			done
			for ((i=2; i<=$max_modules_ind; i+=1)); do
				if [ -f $3$4/temp"$i"_input ]; then
					j=$(($i-1))
					ln -sf $3$4/temp"$i"_input $thermal_path/temp_input_port"$j"
					ln -sf $3$4/temp"$i"_fault $thermal_path/temp_fault_port"$j"
					ln -sf $3$4/temp"$i"_crit $thermal_path/temp_crit_port"$j"
					ln -sf $3$4/temp"$i"_emergency $thermal_path/temp_emergency_port"$j"
				fi
			done
		fi
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		zonep0type="${zonetype:0:${#zonetype}-1}"
		zonep1type="${zonetype:0:${#zonetype}-2}"
		zonep2type="${zonetype:0:${#zonetype}-3}"
		if [ "$zonetype" == "mlxsw" ] || [ "$zonep0type" == "mlxsw-port" ] ||
		   [ "$zonep1type" == "mlxsw-port" ] || [ "$zonep2type" == "mlxsw-port" ]; then
			ln -sf $3$4/mode $thermal_path/"$zonetype"_thermal_zone_mode
			ln -sf $3$4/policy $thermal_path/"$zonetype"_thermal_zone_policy
			ln -sf $3$4/trip_point_0_temp $thermal_path/"$zonetype"_temp_trip_norm
			ln -sf $3$4/trip_point_1_temp $thermal_path/"$zonetype"_temp_trip_high
			ln -sf $3$4/trip_point_2_temp $thermal_path/"$zonetype"_temp_trip_hot
			ln -sf $3$4/trip_point_3_temp $thermal_path/"$zonetype"_temp_trip_crit
			ln -sf $3$4/temp $thermal_path/"$zonetype"_thermal_zone_temp
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ]; then
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
	if [ "$2" == "psu1" ] || [ "$2" == "psu2" ]; then
		# PSU unit FAN speed set
		busdir=`echo $5$3 |xargs dirname |xargs dirname`
		busfolder=`basename $busdir`
		bus="${busfolder:0:${#busfolder}-5}"
		if [ "$2" == "psu1" ]; then
			i2cset -f -y $bus 0x59 $fan_command $fan_psu_default wp
		else
			i2cset -f -y $bus 0x58 $fan_command $fan_psu_default wp
		fi
	fi
elif [ "$1" == "change" ]; then
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		zonep0type="${zonetype:0:${#zonetype}-1}"
		zonep1type="${zonetype:0:${#zonetype}-2}"
		zonep2type="${zonetype:0:${#zonetype}-3}"
		if [ "$zonetype" == "mlxsw" ] || [ "$zonep0type" == "mlxsw-port" ] ||
		   [ "$zonep1type" == "mlxsw-port" ] || [ "$zonep2type" == "mlxsw-port" ]; then
			# Notify thermal control about thermal zone change.
			if [ -f /var/run/mellanox-thermal.pid ]; then
				pid=`cat /var/run/mellanox-thermal.pid`
				kill -USR1 $pid
			fi
		fi
	fi
	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ]; then
			echo $thermal_path/cooling_cur_state >> /etc/trace
		fi
	fi
	if [ "$2" == "hotplug_asic" ]; then
		if [ -d /sys/module/mlxsw_pci ]; then
			return
		fi
		find_i2c_bus
		bus=$(($i2c_asic_bus_default+$i2c_bus_offset))
		path=/sys/bus/i2c/devices/i2c-$bus
		if [ "$3" == "up" ]; then
			if [ ! -d /sys/module/mlxsw_minimal ]; then
				modprobe mlxsw_minimal
			fi
			if [ ! -d /sys/bus/i2c/devices/$bus-0048 ] &&
			   [ ! -d /sys/bus/i2c/devices/$bus-00048 ]; then
				echo mlxsw_minimal 0x48 > $path/new_device
			fi
		elif [ "$3" == "down" ]; then
			if [ -d /sys/bus/i2c/devices/$bus-0048 ] ||
			   [ -d /sys/bus/i2c/devices/$bus-00048 ]; then
				echo 0x48 > $path/delete_device
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
			unlink $thermal_path/temp1_input_asic
			unlink $thermal_path/pwm1
			for ((i=1; i<=$max_tachos; i+=1)); do
				if [ -L $thermal_path/fan"$i"_fault ]; then
					unlink $thermal_path/fan"$i"_fault
				fi
				if [ -L $thermal_path/fan"$i"_input ]; then
					unlink $thermal_path/fan"$i"_input
				fi
			done
			unlink $thermal_path/$pwm1
			for ((i=2; i<=$max_modules_ind; i+=1)); do
				if [ -L $thermal_path/temp_input_port"$j" ]; then
					j=$(($i-1))
					unlink $thermal_path/temp_input_port"$j"
					unlink $thermal_path/temp_fault_port"$j"
					unlink $thermal_path/temp_crit_port"$j"
					unlink $thermal_path/temp_emergency_port"$j"
				fi
			done
		fi
	fi
	if [ "$2" == "thermal_zone" ]; then
		zonetype=`cat $3$4/type`
		zonep0type="${zonetype:0:${#zonetype}-1}"
		zonep1type="${zonetype:0:${#zonetype}-2}"
		zonep2type="${zonetype:0:${#zonetype}-3}"
		if [ "$zonetype" == "mlxsw" ] || [ "$zonep0type" == "mlxsw-port" ] ||
		   [ "$zonep1type" == "mlxsw-port" ] || [ "$zonep2type" == "mlxsw-port" ]; then
			unlink $thermal_path/"$zonetype"_thermal_zone_mode
			unlink $thermal_path/"$zonetype"_thermal_policy
			unlink $thermal_path/"$zonetype"_temp_trip_norm
			unlink $thermal_path/"$zonetype"_temp_trip_high
			unlink $thermal_path/"$zonetype"_temp_trip_hot
			unlink $thermal_path/"$zonetype"_temp_trip_crit
			unlink $thermal_path/"$zonetype"_thermal_zone_temp
		fi
	fi

	if [ "$2" == "cooling_device" ]; then
		coolingtype=`cat $3$4/type`
		if [ "$coolingtype" == "mlxsw_fan" ] ||
		   [ "$coolingtype" == "mlxreg_fan" ]; then
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
