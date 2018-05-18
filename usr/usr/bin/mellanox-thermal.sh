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

### BEGIN INIT INFO
# Provides:        bsp for Mellanox systems
# Required-Start:  $syslog 
# Required-Stop:   $syslog
# Default-Start:   2 3 4 5       
# Default-Stop:    0 1 6
# Short-Description: Mellanox x86 MSN systems bsp
# Description:       Mellanox system support
# Supported systems:
#  MSN274*		Panther SF
#  MSN21*		Bulldog
#  MSN24*		Spider
#  MSN27*|MSB*|MSX*	Neptune, Tarantula, Scorpion, Scorpion2, Spider
#  MSN201*		Boxer
#  QMB7*|SN37*|SN34*	Jupiter, Jaguar, Anaconda
# Available options:
# start        - install all BSP kernel drivers, connect drivers to devices, create BSP dictionary as symbolic
#                links to sysfs entries
# stop         - destroy BSP dictionary, disconnect drivers from devices, uninstall BSP kernel drivers
# restart      - combined stop and start sequence
#                driver reloading
### END INIT INFO

. /lib/lsb/init-functions

# Local constants and variables
thermal_type=0
thermal_type_t1=1
thermal_type_t2=2
thermal_type_t3=3
thermal_type_t4=4
thermal_type_t4=4
thermal_type_t5=5
max_psus=2
max_tachos=12

module_load_path=(	i2c/i2c-dev.ko \
			hwmon/lm75.ko \
			hwmon/tmp102.ko \
			net/ethernet/mellanox/mlxsw/mlxsw_minimal.ko)

module_unload_list=(	tmp102 lm75 mlxsw_minimal i2c_dev)

msn2700_connect_table=(	mlxsw_minimal 0x48 2 \
			lm75 0x4a 7 \
			lm75 0x49 17)

msn2700_dis_table=(	0x4a 7 \
			0x49 17 \
			0x48 2)

msn2100_connect_table=(	mlxsw_minimal 0x48 2 \
			lm75 0x4a 7 \
			lm75 0x4b 7)

msn2100_dis_table=(	0x4a 7 \
			0x4b 7 \
			0x48 2)

msn2740_connect_table=(	mlxsw_minimal 0x48 2 \
			tmp102 0x49 6 \
			tmp102 0x48 7)

msn2740_dis_table=(	0x49 6 \
			0x48 7 \
			0x48 2)

msn2010_connect_table=(	mlxsw_minimal 0x48 2 \
			lm75 0x4a 7 \
			lm75 0x4b 7)

msn2010_dis_table=(	0x4b 7 \
			0x4a 7 \
			0x48 2)

qmb700_connect_table=(	mlxsw_minimal 0x48 2 \
			tmp102 0x49 7 \
			tmp102 0x4a 7)

qmb700_dis_table=(	0x49 7 \
			0x4a 7 \	
			0x48 2)

ACTION=$1

is_module()
{
        /sbin/lsmod | grep -w "$1" > /dev/null
        RC=$?
        return $RC
}

msn274x_specific()
{
	connect_size=${#msn2740_connect_table[@]}
	for ((i=0; i<$connect_size; i++))
	do
		connect_table[i]=${msn2740_connect_table[i]}
	done
	disconnect_size=${#msn2740_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++))
	do
		dis_table[i]=${msn2740_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=4
}

msn21xx_specific()
{
	connect_size=${#msn2100_connect_table[@]}
	for ((i=0; i<$connect_size; i++))
	do
		connect_table[i]=${msn2100_connect_table[i]}
	done
	disconnect_size=${#msn2100_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++))
	do
		dis_table[i]=${msn2100_dis_table[i]}
	done

	thermal_type=$thermal_type_t3
	thermal_type=$thermal_type_t1
	max_tachos=8
	max_psus=0
}

msn24xx_specific()
{
	connect_size=${#msn2700_connect_table[@]}
	for ((i=0; i<$connect_size; i++))
	do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++))
	do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
}

msn27xx_msb_msx_specific()
{
	connect_size=${#msn2700_connect_table[@]}
	for ((i=0; i<$connect_size; i++))
	do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++))
	do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
}

msn201x_specific()
{
	connect_size=${#msn2010_connect_table[@]}
	for ((i=0; i<$connect_size; i++))
	do
		connect_table[i]=${msn2010_connect_table[i]}
	done
	disconnect_size=${#msn2010_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++))
	do
		dis_table[i]=${msn2010_dis_table[i]}
	done

	thermal_type=$thermal_type_t4
	max_tachos=8
	max_psus=0
}

qmb7xxx_sn37x_sn34x_specific()
{
	connect_size=${#qmb700_connect_table[@]}
	for ((i=0; i<$connect_size; i++))
	do
		connect_table[i]=${qmb700_connect_table[i]}
	done
	disconnect_size=${#qmb700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++))
	do
		dis_table[i]=${qmb700_dis_table[i]}
	done

	thermal_type=$thermal_type_t5
}

check_system()
{
	manufacturer=`cat /sys/devices/virtual/dmi/id/sys_vendor | awk '{print $1}'`
	if [ "$manufacturer" = "Mellanox" ]; then
		product=`cat /sys/devices/virtual/dmi/id/product_name`
		case $product in
			MSN274*)
				msn274x_specific
				;;
			MSN21*)
				msn21xx_specific
				;;
			MSN24*)
				msn24xx_specific
				;;
			MSN27*|MSB*|MSX*)
				msn27xx_msb_msx_specific
				;;
			MSN201*)
				msn201x_specific
				;;
			QMB7*|SN37*|SN34*)
				qmb7xxx_sn37x_sn34x_specific
				;;
			*)
				echo $product is not supported
				exit 0
				;;
		esac
	else
		# Check ODM
		board=`cat /sys/devices/virtual/dmi/id/board_name`
		case $board in
			VMOD0001)
				msn27xx_msb_msx_specific
				;;
			VMOD0002)
				msn21xx_specific
				;;
			VMOD0003)
				msn274x_specific
				;;
			VMOD0004)
				msn201x_specific
				;;
			VMOD0005)
				qmb7xxx_sn37x_sn34x_specific
				;;
			*)
				echo $manufacturer is not Mellanox
				exit 0
		esac
	fi

	kernel_release=`uname -r`
}

load_module()
{
	filename=`basename /lib/modules/${kernel_release}/kernel/drivers/$1`
	name="${filename%.*}"
	alternative=`echo "$name" | tr '-' '_'`
	if [ -f /lib/modules/${kernel_release}/kernel/drivers/$1 ]; then
		if is_module $name || is_module $alternative; then
			log_warning_msg "$name module has already been loaded"
		else
			param=
			if [ $name = "at24" ]; then
				param="io_limit=32"
			fi
			if modprobe $name $param 2>/dev/null; then
				log_success_msg "$name module load passed"
			else
				log_failure_msg "$name module load failed"
			fi
		fi
	fi

	return 0
}

unload_module()
{
	if [ -d /sys/module/$1 ]; then
		if [ ! -f /sys/module/$1/refcnt ]; then
			return 0
		fi
		refcnt=`cat /sys/module/$1/refcnt`
		if [ "$refcnt" -gt 0 ]; then
			return 0
		fi

		if is_module $1; then
			if rmmod $1 2>/dev/null ; then
				log_success_msg "$1 module is unloaded"
			else
				log_failure_msg "$1 module unload failed"
			fi
		else
			log_warning_msg "No $1 module loaded"
		fi
	fi

	return 0
}

connect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-$3/new_device ]; then
		addr=`echo $2 | tail -c +3`
		if [ ! -d /sys/bus/i2c/devices/$3-00$addr ] &&
		   [ ! -d /sys/bus/i2c/devices/$3-000$addr ]; then
			echo $1 $2 > /sys/bus/i2c/devices/i2c-$3/new_device
		fi
	fi

	return 0
}

disconnect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-$2/delete_device ]; then
		addr=`echo $1 | tail -c +3`
		if [ -d /sys/bus/i2c/devices/$2-00$addr ] ||
		   [ -d /sys/bus/i2c/devices/$2-000$addr ]; then
			echo $1 > /sys/bus/i2c/devices/i2c-$2/delete_device
		fi
	fi

	return 0
}

load_modules()
{
	log_daemon_msg "Starting Mellanox x86 system bsp modules"
	log_end_msg 0

	COUNT=${#module_load_path[@]}
	for ((i=0; i<$COUNT; i++))
	do
		load_module ${module_load_path[i]}
	done

	return 0
}

unload_modules()
{
	log_daemon_msg "Stopping Mellanox x86 system bsp module"
	log_end_msg 0

	COUNT=${#module_unload_list[@]}
	for ((i=0; i<$COUNT; i++))
	do
		unload_module ${module_unload_list[i]}
	done

	return 0
}

connect_platform()
{
	for ((i=0; i<$connect_size; i+=3))
	do
		connect_device 	${connect_table[i]} ${connect_table[i+1]} \
				${connect_table[i+2]}
        done
}

disconnect_platform()
{
	for ((i=0; i<$disconnect_size; i+=2))
	do
		disconnect_device ${dis_table[i]} ${dis_table[i+1]}
	done
}

case $ACTION in
        start)
		check_system
		depmod -a 2>/dev/null
		load_modules
		sleep 1
		connect_platform
		mellanox-thermal-control.sh $thermal_type $mac_tachos $max_psus &
	;;
        stop)
		# Kill thermal control if running
		if [ -f /var/run/mellanox-thermal.pid ]; then
			thermal_control_pid=`cat /var/run/mellanox-thermal.pid`
			if [ -d /proc/$thermal_watch_pid ]; then
				kill $thermal_control_pid
			fi
		fi

		check_system
		disconnect_platform
		unload_modules
		# Clean thermal directory - remove folder if it's empty
		if [ -d /config/mellanox/thermal ]; then
			sleep 3
			for filename in /config/mellanox/thermal/*; do
				if [ -d $filename ]; then
					if [ -z "$(ls -A $filename)" ]; then
						rm -rf $filename
					fi
				elif [ -L $filename ]; then
					unlink $filename
				fi
			done
		fi
	;;
	*)
		echo
		echo "Usage: `basename $0` {start|stop|restart}"
		echo
		exit 1
	;;
esac
