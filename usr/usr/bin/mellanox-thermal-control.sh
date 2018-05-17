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

# Thermal configuration per system type. The next types are supported:
#  t1: MSN21*			Bulldog
#  t2: MSN274*			Panther SF
#  t3: MSN24*			Spider
#  t4: MSN27*|MSB*|MSX*		Neptune, Tarantula, Scorpion, Scorpion2
#  t5: MSN201*			Boxer
#  t6: QMB7*|SN37*|SN34*	Jupiter, Jaguar, Anaconda

# The thermal algorithm considers the next rules for FAN speed setting:
# This is because the absence of power supply has bad impact on air flow.
# The minimal PWM setting is dynamic and depends on FAN direction and cable
# type. For system with copper cables only or/and with trusted optic cable
# minimum PWM setting could be decreased according to the system definition.
# Thermal active monitoring is performed based on the values of the next three
# sensors: CPU temperature, ASIC temperature and port cumulative temperature.
# The decision for PWM setting is taken based on the worst measure of them.
# All the sensors and statuses are exposed through the sysfs interface for the
# user space application access.

. /lib/lsb/init-functions

# Paths to thermal sensors, device present states, thermal zone and cooling device
thermal_path=/config/mellanox/thermal
temp1_input_port=$thermal_path/temp1_input_port
temp1_fault_port=$thermal_path/temp1_fault_port
temp1_input_fan_amb=$thermal_path/temp1_input_fan_amb
temp1_input_port_amb=$thermal_path/temp1_input_port_amb
temp1_input_cpu=$thermal_path/temp1_input_cpu
pwm1=$thermal_path/pwm1
psu1_present=$thermal_path/psu1
psu2_present=$thermal_path/psu2
tz_mode=$thermal_path/mode
cooling_cur_state=$thermal_path/cooling_cur_state

# Input params for sensors polling time (sec) and system thermal class
system_thermal_type_def=1
polling_time_def=15
system_thermal_type=${1:-$system_thermal_type_def}
polling_time=${2:-$polling_time_def}

# Thermal tables for the minimum FAN setting per system time. It contains
# entries with ambient temperature threshold values and relevant minimum
# speed setting. All Mellanox system are equipped with two ambient sensors:
# port side ambient sensor and FAN side ambient sensor. FAN direction can
# be read from FAN EEPROM data, in case FAN is equipped with EEPROM device,
# it can be read from CPLD FAN direction register in other case. Or for the
# common case it can be calculated according to the next rule:
# if port side ambient sensor value is greater than FAN side ambient sensor
# value - the direction is power to cable (forward); if it less - the direction
# is cable to power (reversed), if these value are equal: the direction is
# unknown. For each system the following six tables are defined:
# p2c_dir_trust_tx	all cables with trusted or with no sensors, FAN
#			direction is power to cable (forward)
# p2c_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
#			power to cable (forward)
# c2p_dir_trust_tx	all cables with trusted or with no sensors, FAN
#			direction is cable to power (reversed)
# c2p_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
#			cable to power (reversed)
# unk_dir_trust_tx	all cables with trusted or with no sensors, FAN
#			direction is unknown
# unk_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
#			unknown
# The below tables are defined per system thermal class and defines the
# relationship between the ambient temperature and minimal FAN speed. Th
# minimal FAN speed is coded as following: 12 for 20%, 13 for 30%, ..., 19 for
# 90%, 20 for 100%.

# Class t1 for MSN21* (Bulldog)
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------	
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		20	20	20	20	20	20
#  0-5		20	20	20	20	20	20
#  5-10		20	20	20	20	20	20
# 10-15		20	20	20	20	20	20
# 15-20		20	30	20	20	20	30
# 20-25		20	30	20	20	20	30
# 25-30		20	40	20	20	20	40
# 30-35		20	50	20	20	20	50
# 35-40		20	60	20	20	20	60
# 40-45		20	60	30	30	30	60

p2c_dir_trust_t1=(45000 12)
p2c_dir_untrust_t1=(15000 12 25000 13 30000 14 35000 15 40000 16)
c2p_dir_trust_t1=(40000 12 45000 13)
c2p_dir_untrust_t1=(40000 12 45000 13)
unk_dir_trust_t1=(40000 12 45000 13)
unk_dir_untrust_t1=(15000 12 25000 13 30000 14 35000 15 40000 16)

# Local constants
pwm_noact=0
pwm_max=1
max_tachos=12

# Local variables
pwm_required=$pwm_noact
untrusted_sensor=0
p2c_dir=0
cp2_dir=0
unk_dir=0
ambient=0

config_p2c_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		p2c_dir_trust[i]=${array[i]}
	done
}

config_p2c_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		p2c_dir_untrust[i]=${array[i]}
	done
}

config_c2p_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		c2p_dir_trust[i]=${array[i]}
	done
}

config_c2p_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		c2p_dir_untrust[i]=${array[i]}
	done
}

config_unk_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		unk_dir_trust[i]=${array[i]}
	done
}

config_unk_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		unk_dir_untrust[i]=${array[i]}
	done
}

config_thermal_zones_cpu()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		temp_thresholds_cpu[i]=${array[i]}
	done
}

config_thermal_zones_asic()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++))
	do
		temp_thresholds_asic[i]=${array[i]}
	done
}

get_psu_presence()
{
	psu1_presence=`cat $psu1_present`
	psu2_presence=`cat $psu2_present`
	if [ $psu1_presence -eq 0 -o $psu2_presence -eq 0 ]; then
		pwm_required_act=$pwm_max
		echo disabled > $tz_mode
		echo $pwm_max_rpm > $pwm1
	else
		pwm_required_act=$pwm_noact
	fi
}

get_fan_faults()
{
	for i in {1..$max_tachos}; do
		if [ -f $thermal_path/fan"$i"_fault ]; then
			fault=`cat $thermal_path/fan"$i"_fault``
			if [ $fault -eq 1 ]; then
				pwm_required_act=$pwm_max
				echo disabled > $tz_mode
				echo $pwm_max_rpm > $pwm1
			fi
		fi
	done

	pwm_required_act=$pwm_noact
}

set_pwm_min_threshold()
{
	untrusted_sensor=0
	ambient=0
	p2c_dir=0
	cp2_dir=0
	unk_dir=0

	# Check for untrusted modules
	temp1_fault=`cat $temp1_fault_port`
	if [ $temp1_fault -eq 1 ]; then
		untrusted_sensor=1
	fi

	# Define FAN direction
	temp1_fan_ambient=`cat $temp1_input_fan_amb`
	temp1_port_ambient=`cat $temp1_input_port_amb`
	if [ $temp1_fan_ambient -gt  $temp1_port_ambient ]; then
		ambient=$temp1_port_ambient
		p2c_dir=1
	elif [ $temp1_fan_ambient -lt  $temp1_port_ambient ]; then
		ambient=$temp1_fan_ambient
		cp2_dir=1
	else
		ambient=$temp1_fan_ambient
		unk_dir=1
	fi

	# Set FAN minimum speed according to direction and cable type and trust
	if [ $untrusted_sensor -eq 0 ]; then
		if [ $p2c_dir -eq 1 ]; then
			size=${#p2c_dir_trust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${p2c_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					echo $p2c_dir_trust[$(($i+1))] > $cooling_cur_state
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_trust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${c2p_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					echo $c2p_dir_trust[$(($i+1))] > $cooling_cur_state
					break
				fi
			done
		else
			size=${#unk_dir_trust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${unk_dir_trust[i]}
				if [ $ambient -lt $tresh]; then
					echo $unk_dir_trust[$(($i+1))] > $cooling_cur_state
					break
				fi
			done
		fi
	else
		if [ $p2c_dir -eq 1 ]; then
			size=${#p2c_dir_untrust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${unk_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					echo ${unk_dir_untrust[$(($i+1))]} > $cooling_cur_state
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_untrust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${c2p_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					echo $c2p_dir_untrust[$(($i+1))] > $cooling_cur_state
					break
				fi
			done
		else
			size=${#unk_dir_untrust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${unk_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					echo $unk_dir_untrust[$(($i+1))] > $cooling_cur_state
					break
				fi
			done
		fi
	fi
}

case $system_thermal_type in
	1)
		# Config FAN minimal speed setting
		config_p2c_dir_trust "${p2c_dir_trust_t1[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t1[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t1[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t1[@]}"
		config_unk_dir_trust "${unk_dir_trust_t1[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t1[@]}"
		# Config thermal zones for monitoring
		config_thermal_zones_cpu "${cpu_zones_t1[@]}"
		config_thermal_zones_asic "${asic_zones_t1[@]}"
		;;
	*)
		echo thermal type $system_thermal_type is not supported
		exit 0
		;;
esac

thermal_control_exit()
{
	if [ -f /var/run/mlxsw_thermal/zone1 ]; then
		rm -rf /var/run/mlxsw_thermal/zone1
	fi

	echo "Thermal control is terminated (PID=$thermal_control_pid)"
	exit 1
}

# Handle the next POSIX signals by thermal_control_exit:
# SIGINT	2	Terminal interrupt signal.
# SIGKILL	9	Kill (cannot be caught or ignored).
# SIGTERM	15	Termination signal.
trap 'thermal_control_exit' 2 9 15

# Initialization during start up
thermal_control_pid=$$
if [ -f /var/run/mlxsw_thermal/zone1 ]; then
	zone1=`cat /var/run/mlxsw_thermal/zone1`
	# Only one instance of thermal control could be activated
	if [ -d /proc/$zone1 ]; then
		echo Thermal control is already running
		exit 0
	fi
fi

if [ ! -d /var/run/mlxsw_thermal ]; then
	mkdir -p /var/run/mlxsw_thermal
fi

echo $thermal_control_pid > /var/run/mlxsw_thermal/zone1
echo "Thermal control is started (PID=$thermal_control_pid)"

# Start thermal monitoring 
while true
do
    	/bin/sleep $polling_time
	# If one of PS units is out disable thermal zone and set PWM to the
	# maximum speed.
	get_psu_presence
	if [ $pwm_required_act -eq $pwm_max ]; then
		continue
	fi
	# If one of tachometers  is faulty  disable thermal zone and set PWM
	# to the maximum speed.
	get_fan_faults
	if [ $pwm_required_act -eq $pwm_max ]; then
		continue
	fi
	# Enable thermal zone if it has been disabled before.
	if [ "$tz_mode" == "disabled" ]; then
		echo enabled > $tz_mode
	fi
	# Set dynamic FAN speed minimum, depending on ambient temperature,
	# presence of untrusted optical cables or presence of any cables
	# with untrusted temperature sensing. 
	set_pwm_min_threshold
done

