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
The thermal algorithm considers the next rules for FAN speed setting:
This is because the absence of power supply has bad impact on air flow.
The minimal PWM setting is dynamic and depends on FAN direction and cable
type. For system with copper cables only or/and with trusted optic cable
minimum PWM setting could be decreased according to the system definition.
Thermal active monitoring is performed based on the values of the next three
sensors: CPU temperature, ASIC temperature and port cumulative temperature.
The decision for PWM setting is taken based on the worst measure of them.
All the sensors and statuses are exposed through the sysfs interface for the
user space application access.

Thermal tables for the minimum FAN setting per system time. It contains
entries with ambient temperature threshold values and relevant minimum
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

Thermal zones thresholds setting for CPU and ASIC per system type (port
thresholds if supported are read from ports EEPROM data). It contains the
thresholds for monitoring activation - when the temperature is above this
threshold, thermal control should be active and when temperature is above
this threshold, thermal control should be passive. And it contains the
critical threshold. When the temperature is above this threshold, FANs should
be at maximum speed or system shutdown should be performed.

Package contains the following files:
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
/usr/bin/mellanox-thermal.sh
	performs initialization and de-initialization, detects the system type,
	connects thermal drivers according to the system topology, activates
	and deactivates thermal algorithm.


Location:
https://github.com/MellanoxBSP/thermal-control

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
