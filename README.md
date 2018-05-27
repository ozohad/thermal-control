# Mellanox thermal control reference design                 

This package supports thermal control for Mellanox switches.

Supported systems:

- MSN274* Panther SF
- MSN21* Bulldog    
- MSN24* Spider     
- MSN27*|MSB*|MSX* Neptune, Tarantula, Scorpion, Scorpion2
- MSN201* Boxer                                           
- QMB7*|SN37*|SN34* Jupiter, Jaguar, Anaconda

Description:
The thermal monitoring is performed in kernel space. The thermal zone binds PWM
control and the temperature measure, which is accumulated temperature from the
ports and from the ASIC. Kernel algorithm uses step wise policy. For details,
please refer to kernel documentation file Documentation/thermal/sysfs-api.txt.
Existing kernel thermal framework provides:
Concepts of thermal zones, trip points, cooling devices, thermal instances,
thermal governors:
 - Cooling device is an actual functional unit for cooling down the thermal
   zone: Fan.
 - Thermal instance describes how cooling devices work at certain trip point in
   the thermal zone.
 - Governor handles the thermal instance not thermal devices.
   Step wise governor sets cooling state based on thermal trend (STABLE, RAISING,
   DROPPING, RASING_FULL, DROPPING_FULL). It allows only one step change for
   increasing or decreasing at decision time.
Framework to register thermal zone and cooling devices:
  - Thermal zone devices and cooling devices will work after proper binding.
Performs a routing function of generic cooling devices to generic thermal zones
with the help of very simple thermal management logic.

This package provides additional functionally to the thermal control, which
contains the following polices:
- Setting PWM to full speed if one of PS units is not present (in such case
  thermal monitoring in kernel is set to disabled state until the problem is
  not recovered). Such events will be reported to systemd journaling system. 
- Setting PWM to full speed if one of FAN drawers is not present or one of
  tachometers is broken present (in such case thermal monitoring in kernel is
  set to disabled state until the problem is not recovered). Such events will
  be reported to systemd journaling system.
- Setting PWM dynamic speed minimum. The dynamic setting depends on FAN
  direction and cable type. For system with copper cables only or/and with
  trusted optic cable minimum PWM setting could be decreased according to the
  system definition. Such events will be reported to systemd journaling system.

The thermal zones are defined with the following trip points:
State		Temperature value	PWM speed	Action
Cold:		t < 75 Celsius		20% *		Do nothing
In range	75 <= t < 85 Celsius	20%-40% *	Keep minimal speed
Hot:		85 <= t < 105		40%-100% *	Perform hot algorithm
Hot alarm:	105 <= t < 110 Celsius	100%		Produce warning message
Critical: 	t >= 110 Celsius	100%		System shutdown

* Note:
The above table defines default minimum FAN speed per each thermal zone. This
setting can be reset in case the dynamical minimum speed is changed. The
cooling device bound to the thermal zone operates over the ten cooling logical
levels. The default vector for the cooling levels is defined with the next PWM
per level speeds:
20%	20%	30%	40%	50%	60%	70%	80%	90%	100%
In case system dynamical minimum is changed for example from 20% to 60%, the
cooling level vector will be dynamically updated as below:
60%	60%	60%	60%	60%	60%	70%	80%	90%	100%
In such way the allowed PWM minimum is limited according to the system thermal
requirements.

Thermal tables for the minimum FAN setting are defined per system type and
contains entries with ambient temperature threshold values and relevant minimum
speed setting. All Mellanox system are equipped with two ambient sensors:
port side ambient sensor and FAN side ambient sensor. FAN direction can
be read from FAN EEPROM data, in case FAN is equipped with EEPROM device,
it can be read from CPLD FAN direction register in other case. Or for the
common case it can be calculated according to the next rule:
if port side ambient sensor value is greater than FAN side ambient sensor
value - the direction is power to cable (forward); if it less - the direction
is cable to power (reversed), if these value are equal: the direction is
unknown. For each system the following six tables are defined:
p2c_dir_trust_tx	all cables with trusted or with no sensors, FAN
			direction is power to cable (forward)
p2c_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
			power to cable (forward)
c2p_dir_trust_tx	all cables with trusted or with no sensors, FAN
			direction is cable to power (reversed)
c2p_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
			cable to power (reversed)
unk_dir_trust_tx	all cables with trusted or with no sensors, FAN
			direction is unknown
unk_dir_untrust_tx	some cable sensor is untrusted, FAN direction is
			unknown

Package contains the following files, used within the workload:
/lib/systemd/system/mellanox-thermal.service
	system entries for thermal control activation and de-activation.
/lib/udev/rules.d/50-mellanox-thermal-events.rules
	udev rules defining the triggers on which events should be handled.  
	When trigger is matched, rule data is to be passed to the event handler
	(see below file /usr/bin/mellanox-thermal-events.sh).
/usr/bin/mellanox-thermal-control.sh
	contains thermal algorithm implementation.
/usr/bin/mellanox-thermal-events.sh
	handles udev triggers, according to the received data, it creates or
	destroys symbolic links to sysfs entries. It allows to create system
	independent entries and it allows thermal controls to work over this
	system independent model.
	Raises signal to mellanox-thermal-control in case of fast temperature
	decreasing. It could happen in case one or few very hot port cables
	have been removed.
	Sets PS units internal FAN speed to default value when unit is
	connected to power source.
/usr/bin/mellanox-thermal.sh
	performs initialization and de-initialization, detects the system type,
	connects thermal drivers according to the system topology, activates
	and deactivates thermal algorithm.

SYSFS attributes:
The thermal control operates over sysfs attributes. These attributes are
exposed as symbolic links to /config/mellanox/thermal folder. These folder
contains the next files (which are symbolic links):
cooling_cur_state	Current cooling state, exposed by cooling level (1..10)
fan<i>_fault		tachometer fault, <i> 1..max tachometers number
psu1_status		PS unit 1 presence status (1 - present, 0 - removed)
psu2_status		PS unit 2 presence status (1 - present, 0 - removed)
pwm			PWM speed exposed in RPM
temp_asic		ASIC ambient temperature value
temp_fan_amb		FAN side ambient temperature value
temp_port_amb		port side ambient temperature value
temp_port		port temperature value
temp_port_fault		port temperature fault
temp_trip_min		thermal zone minimum temperature trip
tz_mode			thermal zone mode (enabled or disabled)
tz_temp			thermal zone temperature

Kernel configuration required the next setting (kernel version should be v4.19
or later):
CONFIG_NET_VENDOR_MELLANOX
CONFIG_MELLANOX_PLATFORM
CONFIG_NET_DEVLINK
CONFIG_MAY_USE_DEVLINK
CONFIG_I2C
CONFIG_I2C_BOARDINFO
CONFIG_I2C_CHARDEV
CONFIG_I2C_MUX
CONFIG_I2C_MUX_REG
CONFIG_REGMAP
CONFIG_SYSFS
CONFIG_MLXSW_CORE
CONFIG_MLXSW_CORE_HWMON
CONFIG_MLXSW_CORE_THERMAL
CONFIG_MLXSW_PCI or/and CONFIG_MLXSW_I2C
CONFIG_MLXSW_SPECTRUM or/and CONFIG_MLXSW_MINIMAL
CONFIG_I2C_MLXCPLD
CONFIG_LEDS_MLXREG
CONFIG_MLX_PLATFORM
CONFIG_MLXREG_HOTPLUG
CONFIG_THERMAL
CONFIG_THERMAL_HWMON
CONFIG_THERMAL_WRITABLE_TRIPS
CONFIG_THERMAL_DEFAULT_GOV_STEP_WISE=y
CONFIG_THERMAL_GOV_STEP_WISE
CONFIG_PMBUS
CONFIG_SENSORS_PMBUS
CONFIG_HWMON
CONFIG_THERMAL_HWMON
CONFIG_SENSORS_LM75
CONFIG_SENSORS_TMP102
CONFIG_LEDS_MLXREG
CONFIG_LEDS_TRIGGERS
CONFIG_LEDS_TRIGGER_TIMER
CONFIG_NEW_LEDS
CONFIG_LEDS_CLASS

The package depends on the next packages:
init-system-helpers:	helper tools for all init systems
lsb-base:		Linux Standard Base init script functionality
udev:			/dev/ and hotplug management daemon
i2c-tools:		heterogeneous set of I2C tools for Linux

Package contains the folder debian, with the rules for Debian package build.

Location:
https://github.com/MellanoxBSP/thermal-control

To get package sources:
git clone https://github.com/MellanoxBSP/thermal-control.git

For Debian package build:
On a debian-based system, install the following programs:
sudo apt-get install devscripts build-essential lintian

a) Go into thermal-control base folder and build Debian package.
b) Run:
debuild -us -uc
c) Find in upper folder f.e. mellanox-thermal_1.mlnx.18.05.2018_amd64.deb

For converting deb package to rpm package:
On a debian-based system, install the following program:
sudo apt-get install alien

a) alien --to-rpm mellanox-thermal_1.mlnx.18.05.2018_amd64.deb
b) Find mellanox-thermal-1.mlnx.18.05.2018-2.x86_64.rpm

## Installation from local file and de-installation
Copy deb or rpm package to the system, for example to /tmp.

For deb package install with:
dpkg -i /tmp/ mellanox-thermal_1.mlnx.18.05.2018_amd64.deb
remove with:
dpkg --purge mellanox-thermal

For rpm install with:
yum localinstall /tmp/mellanox-thermal-1.mlnx.18.05.2018-2.x86_64.rpm
or
rpm -ivh -r /tmp mellanox-thermal-1.mlnx.18.05.2018-2.x86_64.rpm
remove with:
yum remove mellanox-thermal
or
rpm -e mellanox-thermal


## Activation, de-activation and reading status
mellanox-thermal can be initialized and de-initialized by systemd service.
The next command could be used in order to configure persistent initialization
and de-initialization of mellanox-thermal:
systemctl enable mellanox-thermal
systemctl disable mellanox-thermal
Running status of mellanox-thermal unit can be obtained by the following
command:
systemctl status mellanox-thermal
Logging records of the thermal control written by systemd-journald.service can
be queried by the following command:
journalctl --unit=mellanox-thermal
Once "systemctl enable mellanox-thermal" is invoked, the thermal control will
be automatically activated after the next and the following system reboots,
until "systemctl disable mellanox-thermal" is not invoked.
Application could be stopped by the following commands:
systemctl stop mellanox-thermal.service

## Authors

* **Michael Shych** <michaelsh@mellanox.com>
* **Mykola Kostenok** <c_mykolak@mellanox.com>
* **Ohad Oz** <ohado@mellanox.com>
* **Oleksandr Shamray** <oleksandrs@mellanox.com>
* **Vadim Pasternak** <vadimp@mellanox.com>

## License

This project is Licensed under the GNU General Public License Version 2.

## Acknowledgments

* Mellanox Low-Level Team.
