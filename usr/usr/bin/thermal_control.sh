#!/bin/bash
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

# Paths to thermal sensors device present states and threshold parameters
thermal_path=/config/mellanox/thermal
pwm_min=$thermal_path/pwm_min
temp1_input_port=$thermal_path/temp1_input_port
temp1_crit_port=$thermal_path/temp1_crit_port
temp1_crit_alarm_port=$thermal_path/temp1_crit_alarm_port
temp1_fault_port=$thermal_path/temp1_fault_port
temp1_input_asic=$thermal_path/temp1_input_asic
temp1_input_ambient=$thermal_path/temp1_input_ambient
temp2_input_ambient=$thermal_path/temp2_input_ambient
temp1_input_cpu=$thermal_path/temp1_input_cpu
pwm1=$thermal_path/pwm1
pwm_max_state=$thermal_path/pwm_max_state
pwm_cur_state=$thermal_path/pwm_cur_state
psu1_present=$thermal_path/psu1
psu2_present=$thermal_path/psu2

# Input params for sensors polling time (sec) and minimum FAN speed (percent)
system_thermal_type_def=1
polling_time_def=15
pwm_min_speed_def=50
system_thermal_type=${1:-$system_thermal_type_def}
polling_time=${2:-$polling_time_def}
pwm_min_speed=${3:-$pwm_min_speed_def}

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

p2c_dir_trust_t1=(45000 20)
p2c_dir_untrust_t1=(15000 20 25000 30 30000 40 35000 50 40000 60)
c2p_dir_trust_t1=(40000 20 45000 30)
c2p_dir_untrust_t1=(40000 20 45000 30)
unk_dir_trust_t1=(40000 20 45000 30)
unk_dir_untrust_t1=(15000 20 25000 30 30000 40 35000 50 40000 60)

# Thermal zones thresholds setting for CPU and ASIC per system type (port
# thresholds if supported are read from ports EEPROM data). It contains the
# threshold for monitoring activation - when the temperature is above this
# threshold, thermal control should be active and when temperature is above
# this threshold, thermal control should be passive. And it contains the
# critical threshold. When the temperature is above this threshold, FANs should
# be at maximum speed or system shutdown should be performed.
cpu_zones_t1=(90000 110000)
asic_zones_t1=(75000 80000 85000 105000 110000)

# Local constants
pwm_noact=0
pwm_up=1
pwm_down=2
pwm_max=3
temp_trend_unchanged=0
temp_trend_up=1
temp_trend_down=2
temp_normal=0
temp_high=1
temp_hot=2
temp_warning=3
temp_critical=4

# Local variables
pwm_required_cpu=$pwm_noact
pwm_required_cpu_pending=$pwm_noact
temp_trend_cpu=$temp_trend_unchanged
temp_state_cpu=$temp_normal
temp_input_cpu=0
pwm_required_asic=$pwm_noact
pwm_required_asic_pending=$pwm_noact
temp_trend_asic=$temp_trend_unchanged
temp_state_asic=$temp_normal
temp_input_asic=0
pwm_required_port=$pwm_noact
pwm_required_port_pending=$pwm_noact
temp_trend_port=$temp_trend_unchanged
temp_state_port=$temp_normal
temp_input_port=0
pwm_required_psu=$pwm_noact
untrusted_sensor=0
p2c_dir=0
cp2_dir=0
unk_dir=0
ambient=0
pwm_max_state=0
pwm_cur_state=0
hysteresis_trip=5000

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

get_pwm_max_state()
{
	pwm_max_state=`cat $pwm_max_state`
	pwm_cur_state=`cat $pwm_max_state`
}

get_psu_presence()
{
	psu1_presence=`cat $psu1_present`
	psu2_presence=`cat $psu2_present`
	if [ $psu1_presence -eq 0 -o $psu2_presence -eq 0 ]; then
		pwm_required_psu=$pwm_max
	else
		pwm_required_psu=$pwm_noact
	fi
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
	temp1_ambient=`cat $temp1_input_ambient`
	temp2_ambient=`cat $temp2_input_ambient`
	if [ $temp1_ambient -gt  $temp2_ambient ]; then
		ambient=$temp2_ambient
		p2c_dir=1
	elif [ $temp1_ambient -lt  $temp2_ambient ]; then
		ambient=$temp1_ambient
		cp2_dir=1
	else
		ambient=$temp1_ambient
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
					echo $p2c_dir_trust[$(($i+1))] > $pwm_min
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_trust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${c2p_dir_trust[i]}
				if [ $ambient -lt $tresh ]; then
					echo $c2p_dir_trust[$(($i+1))] > $pwm_min
					break
				fi
			done
		else
			size=${#unk_dir_trust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${unk_dir_trust[i]}
				if [ $ambient -lt $tresh]; then
					echo $unk_dir_trust[$(($i+1))] > $pwm_min
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
					echo ${unk_dir_untrust[$(($i+1))]} > $pwm_min
					break
				fi
			done
		elif [ $c2p_dir -eq 1 ]; then
			size=${#c2p_dir_untrust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${c2p_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					echo $c2p_dir_untrust[$(($i+1))] > $pwm_min
					break
				fi
			done
		else
			size=${#unk_dir_untrust[@]}
			for ((i=0; i<$size; i+=2))
			do
				tresh=${unk_dir_untrust[i]}
				if [ $ambient -lt $tresh ]; then
					echo $unk_dir_untrust[$(($i+1))] > $pwm_min
					break
				fi
			done
		fi
	fi
}

get_cpu_temp()
{
	temp=`cat $temp1_input_cpu`
	prev_state=$temp_state_cpu

	# Find the temperature trend: up, down or unchanged
	if [ $temp -lt $temp_input_cpu ]; then
		temp_trend_cpu=$temp_trend_down
	elif [ $temp -gt $temp_input_cpu ]; then
		temp_trend_cpu=$temp_trend_up
	else
		temp_trend_cpu=$temp_trend_unchanged
	fi

	# If CPU temperature is in critical state FAN speed should be at
	# maximum or system thermal shutdown should be performed. If CPU is in
	# normal state it does not require any change in FAN speed setting. If
	# CPU temperature is in monitoring state and trend is unchanged - no
	# action is required, if trend is up or down - respectively speed
	# increasing or decreasing is required. Find to which zone the current
	# temperature belongs
	size=${#temp_thresholds_cpu[@]}
	for ((i=0; i<$size; i++))
	do
		tresh=${temp_thresholds_cpu[i]}
		if [ $temp -lt $tresh ]; then
			break
		fi
	done

	case $i in
		$temp_normal)
			temp_state_cpu=$temp_normal
			case $prev_state in
				$temp_normal)
					pwm_required_cpu=$pwm_noact
					;;
				*)
					pwm_required_cpu=$pwm_down
					;;
			esac
			;;
		$temp_high)
			temp_state_cpu=$temp_high
			case $temp_trend_cpu in
				$temp_trend_unchanged)
					pwm_required_cpu=$pwm_noact
					;;
				$temp_trend_down)
					pwm_required_cpu=$pwm_down
					;;
				$temp_trend_up)
					pwm_required_cpu=$pwm_up
					;;
			esac
			;;
		$temp_critical)
			temp_state_cpu=$temp_critical
			pwm_required_cpu=$pwm_max
			;;
	esac

	temp_input_cpu=$temp
}

get_asic_temp()
{
	temp=`cat $temp1_input_asic`
	prev_state=$temp_state_asic

	# Find the temperature trend: up, down or unchanged
	if [ $temp -lt $temp_input_asic ]; then
		temp_trend_asic=$temp_trend_down
	elif [ $temp -gt $temp_input_asic ]; then
		temp_trend_asic=$temp_trend_up
	else
		temp_trend_asic=$temp_trend_unchanged
	fi

	# If ASIC temperature is in critical state FAN speed should be at
	# maximum or system thermal shutdown should be performed. 
	# If ASIC temperature is in warning state FAN speed should be at
	# maximum.
	# If ASIC temperature is in hot state FAN speed should be at
	# maximum.
	# If ASIC temperature is in high or normal state FAN speed FAN
	# speed throttling is required according to the temperature trend.
	# If ASIC temperature is in monitoring state and trend is unchanged -
	# no action is required, if trend is up or down - respectively speed
	# increasing or decreasing is required.
	# Find to which zone the current temperature belongs.
	size=${#temp_thresholds_asic[@]}
	for ((i=0; i<$size; i++))
	do
		tresh=${temp_thresholds_asic[i]}
		if [ $temp -lt $tresh ]; then
			break
		fi
	done

	case $i in
		$temp_normal)
			temp_state_asic=$temp_normal
			case $prev_state in
				$temp_normal)
					pwm_required_asic=$pwm_noact
					;;
				*)
					pwm_required_asic=$pwm_down
					;;
			esac
			;;
		$temp_monitored)
			temp_state_asic=$temp_monitored
			case $temp_trend_asic in
				$temp_trend_unchanged)
					pwm_required_asic=$pwm_noact
					;;
				$temp_trend_down)
					pwm_required_asic=$pwm_down
					;;
				$temp_trend_up)
					pwm_required_asic=$pwm_up
					;;
			esac
			;;
		$temp_critical)
			temp_state_asic=$temp_critical
			pwm_required_asic=$pwm_max
			;;
	esac

	temp_input_asic=$temp
}

get_port_temp()
{
	temp=`cat $temp1_input_port`
	prev_state=$temp_state_port

	# Find the temperature trend: up, down or unchanged
	if [ $temp -lt $temp_input_port ]; then
		temp_trend_port=$temp_trend_down
	elif [ $temp -gt $temp_input_port ]; then
		temp_trend_port=$temp_trend_up
	else
		temp_trend_port=$temp_trend_unchanged
	fi

	# If port temperature is in critical state FAN speed should be at
	# maximum or system thermal shutdown should be performed. If port is in
	# normal state it does not require any change in FAN speed setting. If
	# port temperature is in monitoring state and trend is unchanged - no
	# action is required, if trend is up or down - respectively speed
	# increasing or decreasing is required. For FAN speed decreasing, the
	# value for trip point should be taken with  hysteresis adjustment.
	# Find to which zone the current temperature belongs.
	hot=`cat $temp1_crit_port`
	high=`cat $temp1_crit_alarm_port`
	if [ $temp -gt $hot ]; then
		# Hot temperature
		temp_state_port=$temp_hot
		pwm_required_port=$pwm_max
	elif [ $temp -gt $high ]; then
		# High temperature
		hysteresis=$(($hot-$hysteresis_trip))
		temp_state_port=$temp_high
		case $temp_trend_port in
			$temp_trend_unchanged)
				pwm_required_port=$pwm_noact
				;;
			$temp_trend_down)
				if [ temp -lt hysteresis ]; then
					pwm_required_port=$pwm_down
				else
					pwm_required_port=$pwm_noact
				fi
				;;
			$temp_trend_up)
				pwm_required_port=$pwm_up
				;;
			esac
	else
		# Normal temperature
		hysteresis=$(($high-$hysteresis_trip))
		temp_state_port=$temp_normal
		case $temp_trend_port in
			$temp_trend_unchanged)
				pwm_required_port=$pwm_noact
				;;
			$temp_trend_down)
				if [ temp -lt hysteresis ]; then
					pwm_required_port=$pwm_down
				else
					pwm_required_port=$pwm_noact
				fi
				;;
			$temp_trend_up)
				pwm_required_port=$pwm_up
				;;
			esac
	fi

	temp_input_port=$temp
}

set_pwm()
{
	pwm=`cat $pwm1`
	pwm_min=`cat $pwm_min`
	fault=`cat $temp1_fault_port`
	echo PWM $pwm minimum $pwm_min max state $pwm_max_state current state $pwm_cur_state
	echo CPU temp $temp_input_cpu trend $temp_trend_cpu state $temp_state_cpu pwm action $pwm_required_cpu
	echo ASIC temp $temp_input_asic trend $temp_trend_asic state $temp_state_asic pwm action $pwm_required_asic
	echo PORT temp $temp_input_port trend $temp_trend_port state $temp_state_port pwm action $pwm_required_port fault $fault
	echo PSU pwm action $pwm_required_psu
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

# Set initial values
echo $pwm_min_speed > $pwm_min
temp_input_cpu=`cat $temp1_input_cpu`
temp_input_asic=`cat $temp1_input_asic`
temp_input_port=`cat $temp1_input_port`
get_pwm_max_state

# Start thermal monitoring 
while true
do
    	/bin/sleep $polling_time
	get_psu_presence
	if [ $pwm_required_psu -eq $pwm_max ]; then
		echo > $pwm_max
		continue
	fi
	set_pwm_min_threshold
	get_cpu_temp
	get_asic_temp
	get_port_temp
	set_pwm
done

