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
# Provides:		Thermal control for Mellanox systems
# Supported systems:
#  MSN274*		Panther SF
#  MSN21*		Bulldog
#  MSN24*		Spider
#  MSN27*|MSB*|MSX*	Neptune, Tarantula, Scorpion, Scorpion2, Spider
#  MSN201*		Boxer
#  QMB7*|SN37*|SN34*	Jupiter, Jaguar, Anaconda
# Available options:
# start	- load the kernel drivers required for the thermal control support,
#	  connect drivers to devices, activate thermal control.
# stop	- disconnect drivers from devices, unload kernel drivers, which has
#	  been loaded, deactivate thermal control.
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
i2c_bus_max=10
i2c_bus_offset=0
thermal_path=/config/mellanox/thermal

# Topology description and driver specification for ambient sensors and for
# ASIC I2C driver per system class. Specific system class is obtained from DMI
# tables.
# ASIC I2C driver is supposed to be activated only in case PCI ASIC driver is
# not loaded. Both perform the same thermal algorithm and exposes the same
# sensors to sysfs. In case PCI path is available, access will be performed
# through PCI.
# Hardware monitoring related drivers for ambient temperature sensing will be
# loaded in case they were not loaded before or in case these drivers are not
# configured as modules.
module_load_path=(	hwmon/lm75.ko \
			hwmon/tmp102.ko \
			net/ethernet/mellanox/mlxsw/mlxsw_minimal.ko)

module_unload_list=(	tmp102 lm75 mlxsw_minimal)

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
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2740_connect_table[i]}
	done
	disconnect_size=${#msn2740_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2740_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=4
}

msn21xx_specific()
{
	connect_size=${#msn2100_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2100_connect_table[i]}
	done
	disconnect_size=${#msn2100_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
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
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
}

msn27xx_msb_msx_specific()
{
	connect_size=${#msn2700_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2700_connect_table[i]}
	done
	disconnect_size=${#msn2700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2700_dis_table[i]}
	done

	thermal_type=$thermal_type_t1
	max_tachos=8
}

msn201x_specific()
{
	connect_size=${#msn2010_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${msn2010_connect_table[i]}
	done
	disconnect_size=${#msn2010_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
		dis_table[i]=${msn2010_dis_table[i]}
	done

	thermal_type=$thermal_type_t4
	max_tachos=8
	max_psus=0
}

qmb7xxx_sn37x_sn34x_specific()
{
	connect_size=${#qmb700_connect_table[@]}
	for ((i=0; i<$connect_size; i++)); do
		connect_table[i]=${qmb700_connect_table[i]}
	done
	disconnect_size=${#qmb700_dis_table[@]}
	for ((i=0; i<$disconnect_size; i++)); do
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

	echo i2c-mlxcpld driver is not loaded
	exit 0
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
			if [ $name = "mlxsw_minimal" ]; then
				# Verify if mlxsw_pci module is loaded, if
				# it's - don't load mlxsw_minimal. thermal
				# algorithm will be performed by PCI based
				# mlxsw module.
				if [ -d /sys/module/mlxsw_pci ]; then
					return
				fi
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
		bus=$(($3+$i2c_bus_offset))
		if [ ! -d /sys/bus/i2c/devices/$bus-00$addr ] &&
		   [ ! -d /sys/bus/i2c/devices/$bus-000$addr ]; then
			echo $1 $2 > /sys/bus/i2c/devices/i2c-$bus/new_device
		fi
	fi

	return 0
}

disconnect_device()
{
	if [ -f /sys/bus/i2c/devices/i2c-$2/delete_device ]; then
		addr=`echo $1 | tail -c +3`
		bus=$(($2+$i2c_bus_offset))
		if [ -d /sys/bus/i2c/devices/$bus-00$addr ] ||
		   [ -d /sys/bus/i2c/devices/$bus-000$addr ]; then
			echo $1 > /sys/bus/i2c/devices/i2c-$bus/delete_device
		fi
	fi

	return 0
}

load_modules()
{
	log_daemon_msg "Loading modukes, used by Mellanox thermal control"
	log_end_msg 0

	count=${#module_load_path[@]}
	for ((i=0; i<$count; i++)); do
		load_module ${module_load_path[i]}
	done

	return 0
}

unload_modules()
{
	log_daemon_msg "Unloading modules, used by Mellanox thermal control"
	log_end_msg 0

	count=${#module_unload_list[@]}
	for ((i=0; i<$count; i++)); do
		unload_module ${module_unload_list[i]}
	done

	return 0
}

connect_platform()
{
	for ((i=0; i<$connect_size; i+=3)); do
		connect_device 	${connect_table[i]} ${connect_table[i+1]} \
				${connect_table[i+2]}
        done
}

disconnect_platform()
{
	for ((i=0; i<$disconnect_size; i+=2)); do
		disconnect_device ${dis_table[i]} ${dis_table[i+1]}
	done
}

case $ACTION in
        start)
		check_system
		find_i2c_bus
		depmod -a 2>/dev/null
		load_modules
		sleep 1
		connect_platform
		mellanox-thermal-control.sh $thermal_type $mac_tachos $max_psus &
	;;
        stop)
		# Kill thermal control if running.
		if [ -f /var/run/mellanox-thermal.pid ]; then
			thermal_control_pid=`cat /var/run/mellanox-thermal.pid`
			if [ -d /proc/$thermal_control_pid ]; then
				kill $thermal_control_pid
			fi
		fi

		check_system
		disconnect_platform
		unload_modules
		# Clean thermal directory.
		if [ -d $thermal_path ]; then
			sleep 3
			rm -rf $thermal_path/*
		fi
	;;
	*)
		echo "Usage: `basename $0` {start|stop}"
		exit 1
	;;
esac
