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
#  t1: MSN27*|MSN24*		Panther, Spider
#  t2: MSN21*			Bulldog
#  t3: MSN274*			Panther SF
#  t4: MSN201*			Boxer
#  t5: MSN27*|MSB*|MSX*		Neptune, Tarantula, Scorpion, Scorpion2
#  t6: QMB7*|SN37*|SN34*	Jaguar, Anaconda

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
temp_port=$thermal_path/temp1_input_port
temp_port_fault=$thermal_path/temp1_fault_port
temp_fan_amb=$thermal_path/fan_amb
temp_port_amb=$thermal_path/port_amb
temp_asic=$thermal_path/temp1_input_asic
pwm=$thermal_path/pwm1
psu1_status=$thermal_path/psu1_status
psu2_status=$thermal_path/psu2_status
tz_mode=$thermal_path/thermal_zone_mode
temp_trip_min=$thermal_path/temp_trip_min
tz_temp=$thermal_path/thermal_zone_temp
cooling_cur_state=$thermal_path/cooling_cur_state

# Input parameters for the system thermal class, the number of tachometers, the
# number of replicable power supply units and for sensors polling time (seconds)
system_thermal_type_def=1
polling_time_def=15
max_tachos_def=12
max_psus_def=2
system_thermal_type=${1:-$system_thermal_type_def}
max_tachos=${2:-$max_tachos_def}
max_psus=${3:-$max_psus_def}
polling_time=${4:-$polling_time_def}

# Local constants
pwm_noact=0
pwm_max=1
pwm_max_rpm=255
max_amb=120000

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

# Class t1 for MSN27*|MSN24* (Panther, Spider)
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		30	30	30	30	30	30
#  0-5		30	30	30	30	30	30
#  5-10		30	30	30	30	30	30
# 10-15		30	30	30	30	30	30
# 15-20		30	30	30	30	30	30
# 20-25		30	30	40	40	40	40
# 25-30		30	40	50	50	50	50
# 30-35		30	50	60	60	60	60
# 35-40		30	60	60	60	60	60
# 40-45		50	60	60	60	60	60

p2c_dir_trust_t1=(45000 13 $max_amb 13)
p2c_dir_untrust_t1=(25000 13 30000 14 30000 14 35000 15 40000 16 $max_amb 16)
c2p_dir_trust_12=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
c2p_dir_untrust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_trust_t1=(20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_untrust_t1=(20000 13 25000 14 30000 15 35000 16  $max_amb 16)
trust1=16
untrust1=16

# Class t2 for MSN21* (Bulldog)
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

p2c_dir_trust_t2=(45000 12 $max_amb 12)
p2c_dir_untrust_t2=(15000 12 25000 13 30000 14 35000 15 40000 16 $max_amb 16)
c2p_dir_trust_t2=(40000 12 45000 13 $max_amb 13)
c2p_dir_untrust_t2=(40000 12 45000 13 $max_amb 13)
unk_dir_trust_t2=(40000 12 45000 13 $max_amb 13)
unk_dir_untrust_t2=(15000 12 25000 13 30000 14 35000 15 40000 16 $max_amb 16)
trust2=13
untrust2=16

# Class t3 for MSN274* (Panther SF)
# Direction	P2C		C2P		Unknown
#--------------------------------------------------------------
# Amb [C]	copper/	AOC W/O copper/	AOC W/O	copper/	AOC W/O
#		sensors	sensor	sensor	sensor	sensor	sensor
#--------------------------------------------------------------
#  <0		30	30	30	30	30	30
#  0-5		30	30	30	30	30	30
#  5-10		30	30	30	30	30	30
# 10-15		30	30	30	30	30	30
# 15-20		30	30	30	40	30	40
# 20-25		30	30	30	40	30	40
# 25-30		30	30	30	40	30	40
# 30-35		30	30	30	50	30	50
# 35-40		30	40	30	70	30	70
# 40-45		30	50	30	70	30	70

p2c_dir_trust_t3=(45000 13  $max_amb 13)
p2c_dir_untrust_t3=(35000 13 40000 14 45000 15 $max_amb 15)
c2p_dir_trust_t3=(45000 13  $max_amb 13)
c2p_dir_untrust_t3=(15000 13 30000 14 35000 15 40000 17 $max_amb 17)
unk_dir_trust_t3=(45000 13 $max_amb 13)
unk_dir_untrust_t3=(15000 13 30000 14 35000 15 40000 17 $max_amb 17)
trust3=13
untrust3=17

# Class t4 for MSN201* (Boxer)
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
# 20-25		20	40	20	30	20	40
# 25-30		20	40	20	40	20	40
# 30-35		20	50	20	50	20	50
# 35-40		20	60	20	60	20	60
# 40-45		20	60	20	60	20	60

p2c_dir_trust_t4=(45000 12 $max_amb 12)
p2c_dir_untrust_t4=(10000 12 15000 13 20000 14 30000 15 35000 16 $max_amb 16)
c2p_dir_trust_t4=(45000 12 $max_amb 12)
c2p_dir_untrust_t4=(15000 12 20000 13 25000 14 30000 15 35000 16 $max_amb 16)
unk_dir_trust_t4=(45000 12  $max_amb 12)
unk_dir_untrust_t4=(10000 12 15000 13 20000 14 30000 15 35000 16 $max_amb 16)
trust4=12
untrust4=16

# Local variables
report_counter=120
pwm_required=$pwm_noact
fan_max_state=10
fan_dynamic_min=12
fan_dynamic_min_last=12
untrusted_sensor=0
p2c_dir=0
c2p_dir=0
unk_dir=0
ambient=0

validate_thermal_configuration()
{
	# Validate FAN fault symbolic links.
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ ! -L $thermal_path/fan"$i"_fault ]; then
			log_failure_msg "FAN fault status attributes are not exist"
			exit 1
		fi
		if [ ! -L $thermal_path/fan"$i"_input ]; then
			log_failure_msg "FAN input attributes are not exist"
			exit 1
		fi
	done
	if [ ! -L $cooling_cur_state ] || [ ! -L $tz_mode  ] ||
	   [ ! -L $temp_trip_min ] || [ ! -L $tz_temp ]; then
		log_failure_msg "Thermal zone attributes are not exist"
		exit 1
	fi
	if [ ! -L $pwm ] || [ ! -L $temp_asic ]; then
		log_failure_msg "PWM control and ASIC attributes are not exist"
		exit 1
	fi
	if [ ! -L $temp_port ] || [ ! -L $temp_port_fault ]; then
		log_failure_msg "Port attributes are not exist"
		exit 1
	fi
	if [ ! -L $temp_fan_amb ] || [ ! -L $temp_port_amb ]; then
		log_failure_msg "Ambient temperate sensors attributes are not exist"
		exit 1
	fi
	if [ $max_psus -gt 0 ]; then
		if [ ! -L $psu1_status ] || [ ! -L $psu2_status ]; then
			log_failure_msg "PS units status attributes are not exist"
			exit 1
		fi
	fi
}

thermal_periodic_report()
{
	f1=`cat $temp_port`
	f2=`cat $temp_asic`
	f3=`cat $tz_temp`
	f4=`cat $temp_fan_amb`
	f5=`cat $temp_port_amb`
	f6=`cat $pwm`
	f7=`cat $temp_port_fault`
	f8=$(($fan_dynamic_min-$fan_max_state))
	f8=$(($f8*10))
	log_success_msg "Thermal periodic report"
	log_success_msg "======================="
	log_success_msg "Temperature: port $f1 asic $f2 tz $f3"
	log_success_msg "fan amb $f4 port amb $f5"
	log_success_msg "Cooling: pwm $f6 port fault $f7 dynaimc_min $f8"
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ -f $thermal_path/fan"$i"_input ]; then
			tacho=`cat $thermal_path/fan"$i"_input`
			fault=`cat $thermal_path/fan"$i"_fault`
			log_success_msg "tacho$i speed is $tacho fault is $fault"
		fi
	done
}

config_p2c_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		p2c_dir_trust[i]=${array[i]}
	done
}

config_p2c_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		p2c_dir_untrust[i]=${array[i]}
	done
}

config_c2p_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		c2p_dir_trust[i]=${array[i]}
	done
}

config_c2p_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		c2p_dir_untrust[i]=${array[i]}
	done
}

config_unk_dir_trust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		unk_dir_trust[i]=${array[i]}
	done
}

config_unk_dir_untrust()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		unk_dir_untrust[i]=${array[i]}
	done
}

config_thermal_zones_cpu()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		temp_thresholds_cpu[i]=${array[i]}
	done
}

config_thermal_zones_asic()
{
	array=("$@")
	size=${#array[@]}
	for ((i=0; i<$size; i++)); do
		temp_thresholds_asic[i]=${array[i]}
	done
}

get_psu_presence()
{
	for ((i=1; i<=$max_psus; i+=1)); do
		if [ -f $thermal_path/psu"$i"_status ]; then
			present=`cat $thermal_path/psu"$i"_status`
			if [ $present -eq 0 ]; then
				pwm_required_act=$pwm_max
				mode=`cat $tz_mode`
				# Disable thermal zone if was enabled.
				if [ $mode == "enabled" ]; then
					echo disabled > $tz_mode
					echo $pwm_max_rpm > $pwm
					log_action_msg "Thermal zone is disabled due to PS unit absence"
				fi
				return
			fi
		fi
	done

	pwm_required_act=$pwm_noact
}

get_fan_faults()
{
	for ((i=1; i<=$max_tachos; i+=1)); do
		if [ -f $thermal_path/fan"$i"_fault ]; then
			fault=`cat $thermal_path/fan"$i"_fault`
			if [ $fault -eq 1 ]; then
				pwm_required_act=$pwm_max
				mode=`cat $tz_mode`
				# Disable thermal zone if was enabled.
				if [ $mode == "enabled" ]; then
					echo disabled > $tz_mode
					echo $pwm_max_rpm > $pwm
					log_action_msg "Thermal zone is disabled due to FAN fault"
				fi
				return
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
	c2p_dir=0
	unk_dir=0

	# Check for untrusted modules
	temp1_fault=`cat $temp_port_fault`
	if [ $temp1_fault -eq 1 ]; then
		untrusted_sensor=1
	fi

	# Define FAN direction
	temp_fan_ambient=`cat $temp_fan_amb`
	temp_port_ambient=`cat $temp_port_amb`
	if [ $temp_fan_ambient -gt  $temp_port_ambient ]; then
		ambient=$temp_port_ambient
		p2c_dir=1
	elif [ $temp_fan_ambient -lt  $temp_port_ambient ]; then
		ambient=$temp_fan_ambient
		c2p_dir=1
	else
		ambient=$temp_fan_ambient
		unk_dir=1
	fi

	# Set FAN minimum speed according to FAN direction, cable type and
	# presence of untrusted cabels.
	if [ $untrusted_sensor -eq 0 ]; then
		if [ $p2c_dir -eq 1 ]; then
			size=${#p2c_dir_trust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${p2c_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${p2c_dir_trust[$(($i+1))]}
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_trust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${c2p_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${c2p_dir_trust[$(($i+1))]}
					break
				fi
			done
		else
			size=${#unk_dir_trust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${unk_dir_trust[i]}
				if [ $ambient -lt $tresh]; then
					fan_dynamic_min==${unk_dir_trust[$(($i+1))]}
					break
				fi
			done
		fi
	else
		if [ $p2c_dir -eq 1 ]; then
			size=${#p2c_dir_untrust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${unk_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${unk_dir_untrust[$(($i+1))]}
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_untrust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${c2p_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${c2p_dir_untrust[$(($i+1))]}
					break
				fi
			done
		else
			size=${#unk_dir_untrust[@]}
			for ((i=0; i<$size; i+=2)); do
				tresh=${unk_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					fan_dynamic_min=${unk_dir_untrust[$(($i+1))]}
					break
				fi
			done
		fi
	fi
}

init_system_dynamic_minimum_db()
{
	case $system_thermal_type in
	1)
		# Config FAN minimal speed setting for class t1
		config_p2c_dir_trust "${p2c_dir_trust_t1[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t1[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t1[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t1[@]}"
		config_unk_dir_trust "${unk_dir_trust_t1[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t1[@]}"
		;;
	2)
		# Config FAN minimal speed setting for class t2
		config_p2c_dir_trust "${p2c_dir_trust_t2[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t2[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t2[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t2[@]}"
		config_unk_dir_trust "${unk_dir_trust_t2[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t2[@]}"
		;;
	3)
		# Config FAN minimal speed setting for class t3
		config_p2c_dir_trust "${p2c_dir_trust_t3[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t3[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t3[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t3[@]}"
		config_unk_dir_trust "${unk_dir_trust_t3[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t3[@]}"
		;;
	4)
		# Config FAN minimal speed setting for class t4
		config_p2c_dir_trust "${p2c_dir_trust_t4[@]}"
		config_p2c_dir_untrust "${p2c_dir_untrust_t4[@]}"
		config_c2p_dir_trust "${c2p_dir_trust_t4[@]}"
		config_c2p_dir_untrust "${c2p_dir_untrust_t4[@]}"
		config_unk_dir_trust "${unk_dir_trust_t4[@]}"
		config_unk_dir_untrust "${unk_dir_untrust_t4[@]}"
		;;
	*)
		echo thermal type $system_thermal_type is not supported
		exit 0
		;;
	esac
}

set_pwm_min_speed()
{
	untrusted_sensor=0

	# Check for untrusted modules
	temp1_fault=`cat $temp_port_fault`
	if [ $temp1_fault -eq 1 ]; then
		untrusted_sensor=1
	fi
	# Set FAN minimum speed according to  presence of untrusted cabels.
	if [ $untrusted_sensor -eq 0 ]; then
		fan_dynamic_min=$config_trust
	else
		fan_dynamic_min=$config_untrust
	fi
}

init_fan_dynamic_minimum_speed()
{
	case $system_thermal_type in
	1)
		# Config FAN minimal speed setting for class t1
		config_trust=$trust1
		config_untrust=$untrust1
		;;
	2)
		# Config FAN minimal speed setting for class t2
		config_trust=$trust2
		config_untrust=$untrust2
		;;
	3)
		# Config FAN minimal speed setting for class t3
		config_trust=$trust3
		config_untrust=$untrust3
		;;
	4)
		# Config FAN minimal speed setting for class t4
		config_trust=$trust4
		config_untrust=$untrust4
		;;
	*)
		echo thermal type $system_thermal_type is not supported
		exit 0
		;;
	esac
}

thermal_control_exit()
{
	if [ -f /var/run/mellanox-thermal.pid ]; then
		rm -rf /var/run/mellanox-thermal.pid
	fi

	log_end_msg "Mellanox thermal control is terminated (PID=$thermal_control_pid)."
	exit 1
}

check_trip_min_vs_current_temp()
{
	trip_min=`cat $temp_trip_min`
	temp_now=`cat $tz_temp`
	if [ $trip_min -gt  $temp_now ]; then
		set_cur_state=$(($fan_dynamic_min-$fan_max_state))
		echo $set_cur_state > $cooling_cur_state
		set_cur_state=$(($set_cur_state*10))
		case $1 in
		1)
			log_action_msg "FAN speed is set to $set_cur_state percent due to thermal zone event."
		;;
		2)
			log_action_msg "FAN speed is set to $set_cur_state percent due to system health recovery"
		;;
		*)
			return
		;;
		esac
		log_action_msg "FAN speed is set to $set_cur_state percent due to thermal zone event."
	fi
}

# Handle events sent by command kill -USR1 to /var/run/mellanox-thermal.pid.
thermal_control_event()
{
	# The received event notifies about fast temperature decreasing. It
	# could happen in case one or few very hot port cables have been
	# removed. In this situation temperature trend, handled by the kernel
	# thermal algorithm could go down once, and then could stay in stable
	# state, while PWM state will be decreased only once. As a side effect
	# PWM will be in not optimal. Set PWM speed to dynamic speed minimum
	# value and give to kernel thermal algorithm can stabilize PWM speed
	# if necessary.
	check_trip_min_vs_current_temp 1
}

# Handle the next POSIX signals by thermal_control_exit:
# SIGINT	2	Terminal interrupt signal.
# SIGKILL	9	Kill (cannot be caught or ignored).
# SIGTERM	15	Termination signal.
trap 'thermal_control_exit' INT KILL TERM

# Handle the next POSIX signal by thermal_control_event:
# SIGUSR1	10	User-defined signal 1.
trap 'thermal_control_event' USR1

# Initialization during start up.
thermal_control_pid=$$
if [ -f /var/run/mellanox-thermal.pid ]; then
	zone1=`cat /var/run/mellanox-thermal.pid`
	# Only one instance of thermal control could be activated
	if [ -d /proc/$zone1 ]; then
		log_warning_msg "Mellanox thermal control is already running."
		exit 0
	fi
fi

# Validate thermal configuration.
validate_thermal_configuration
# Initialize system dynamic minimum speed data base.
init_fan_dynamic_minimum_speed

echo $thermal_control_pid > /var/run/mellanox-thermal.pid
log_action_msg "Mellanox thermal control is started"

# Periodic report counter
periodic_report=$(($polling_time*$report_counter))
periodic_report=12	# For debug - remove after tsting
count=0
# Start thermal monitoring.
while true
do
    	/bin/sleep $polling_time
	# If one of PS units is out disable thermal zone and set PWM to the
	# maximum speed.
	get_psu_presence
	if [ $pwm_required_act -eq $pwm_max ]; then
		continue
	fi
	# If one of tachometers is faulty disable thermal zone and set PWM
	# to the maximum speed.
	get_fan_faults
	if [ $pwm_required_act -eq $pwm_max ]; then
		continue
	fi
	# Set dynamic FAN speed minimum, depending on ambient temperature,
	# presence of untrusted optical cables or presence of any cables
	# with untrusted temperature sensing.
	set_pwm_min_speed
	# Update cooling levels of FAN If dynamic minimum has been changed
	# since the last time.
	if [ $fan_dynamic_min -ne $fan_dynamic_min_last ]; then
		echo $fan_dynamic_min > $cooling_cur_state
		fan_from=$(($fan_dynamic_min_last-$fan_max_state))
		fan_from=$(($fan_from*10))
		fan_to=$(($fan_dynamic_min-$fan_max_state))
		fan_to=$(($fan_to*10))
		log_action_msg "FAN minimum speed is changed from $fan_from to $fan_to percent"
		fan_dynamic_min_last=$fan_dynamic_min
	fi
	# Enable thermal zone if it has been disabled before.
	mode=`cat $tz_mode`
	if [ $mode == "disabled" ]; then
		echo enabled > $tz_mode
		log_action_msg "Thermal zone is re-enabled"
		# System health (PS units or FANs) has been recovered. Set PWM
		# speed to dynamic speed minimum value and give to kernel
		# thermal algorithm can stabilize PWM speed if necessary.
		check_trip_min_vs_current_temp 2
	fi
	count=$(($count+1))
	if [ $count -eq $periodic_report ]; then
		count=0
		thermal_periodic_report
	fi
done
