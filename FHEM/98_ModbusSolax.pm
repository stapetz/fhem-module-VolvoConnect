#############################################
# $Id: 98_ModbusSolax.pm 
#
package main;

use strict;
use warnings;
use Time::HiRes qw( time );

sub ModbusSolax_Initialize($);

# deviceInfo defines properties of the device.
# some values can be overwritten in parseInfo, some defaults can even be overwritten by the user with attributes if a corresponding attribute is added to AttrList in _Initialize.
#
my %ModbusSolaxdeviceInfo = (
	"timing"	=>	{
			timeout		=>	2,		# 2 seconds timeout when waiting for a response
			commDelay	=>	0.1,	# 0.7 seconds minimal delay between two communications e.g. a read a the next write,
									# can be overwritten with attribute commDelay if added to AttrList in _Initialize below
			sendDelay	=>	0.1,	# 0.7 seconds minimal delay between two sends, can be overwritten with the attribute
									# sendDelay if added to AttrList in _Initialize function below
			}, 
	"i"			=>	{				# details for "input registers" if the device offers them
			read		=>	4,		# use function code 4 to read discrete inputs. They can not be read by definition.
			defLen		=>	1,		# default length (number of registers) per value ((e.g. 2 for a float of 4 bytes that spans 2 registers)
									# can be overwritten in parseInfo per reading by specifying the key "len"
			combine		=>	10,		# allow combined read of up to 10 adjacent registers during getUpdate
#			combine		=>	1,		# no combined read (read more than one registers with one read command) during getUpdate
			defFormat	=>	"%.0f",	# default format string to use after reading a value in sprintf
									# can be overwritten in parseInfo per reading by specifying the key "format"
			defUnpack	=>	"n",	# default pack / unpack code to convert raw values, e.g. "n" for a 16 bit integer oder
									# "f>" for a big endian float IEEE 754 floating-point numbers
									# can be overwritten in parseInfo per reading by specifying the key "unpack"
			defPoll		=>	1,		# All defined Input Registers should be polled by default unless specified otherwise in parseInfo or by attributes
			defShowGet	=>	1,		# default für showget Key in parseInfo
			},
	"h"			=>	{				# details for "holding registers" if the device offers them
			read		=>	3,		# use function code 3 to read holding registers.
			write		=>	16,		# use function code 6 to write holding registers (alternative could be 16)
			defLen		=>	1,		# default length (number of registers) per value (e.g. 2 for a float of 4 bytes that spans 2 registers)
									# can be overwritten in parseInfo per reading by specifying the key "len"
			combine		=>	10,		# allow combined read of up to 10 adjacent registers during getUpdate
			defUnpack	=>	"n",	# default pack / unpack code to convert raw values, e.g. "n" for a 16 bit integer oder
									# "f>" for a big endian float IEEE 754 floating-point numbers
									# can be overwritten in parseInfo per reading by specifying the key "unpack"
			defShowGet	=>	1,		# default für showget Key in parseInfo
			defPoll		=>	1,
},
);

# %parseInfo:
# r/c/i+adress => objHashRef (h = holding register, c = coil, i = input register, d = discrete input)
# the address is a decimal number without leading 0
#
# Explanation of the parseInfo hash sub-keys:
# name			internal name of the value in the modbus documentation of the physical device
# reading		name of the reading to be used in Fhem
# set			can be set to 1 to allow writing this value with a Fhem set-command
# setmin		min value for input validation in a set command
# setmax		max value for input validation in a set command
# hint			string for fhemweb to create a selection or slider
# expr			perl expression to convert a string after it has bee read
# map			a map string to convert an value from the device to a more readable output string 
# 				or to convert a user input to the machine representation
#				e.g. "0:mittig, 1:oberhalb, 2:unterhalb"				
# setexpr		per expression to convert an input string to the machine format before writing
#				this is typically the reverse of the above expr
# format		a format string for sprintf to format a value read
# len			number of Registers this value spans
# poll			defines if this value is included in the read that the module does every defined interval
#				this can be changed by a user with an attribute
# unpack		defines the translation between data in the module and in the communication frame
#				see the documentation of the perl pack function for details.
#				example: "n" for an unsigned 16 bit value or "f>" for a float that is stored in two registers
# showget		can be set to 1 to allow a Fhem get command to read this value from the device
# polldelay		if a value should not be read in each iteration after interval has passed, 
#				this value can be set to a multiple of interval
#
#     
#        vals['Grid Voltage'] = unsigned16(result, 0x00) / 10
#        vals['Grid Current'] = signed16(result, 0x01) / 10
#        vals['Grid Power'] = signed16(result, 0x02) / 10
#        vals['PV1 Voltage'] = unsigned16(result, 0x03) / 10
#        vals['PV2 Voltage'] = unsigned16(result, 0x04) / 10
#        vals['PV1 Current'] = unsigned16(result, 0x05) / 10
#        vals['PV2 Current'] = unsigned16(result, 0x06) / 10
#        vals['Grid Frequency'] = unsigned16(result, 0x07) / 100
#        vals['Inner Temp'] = signed16(result, 0x08)
#       vals['Run Mode'] = unsigned16(result, 0x09)
#       vals['PV1 Power'] = unsigned16(result, 0x0a)
#       vals['PV2 Power'] = unsigned16(result, 0x0b)
#      vals['Battery Voltage'] = signed16(result, 0x14) / 100
#      vals['Battery Current'] = signed16(result, 0x15) / 100
#      vals['Battery Power'] = signed16(result, 0x16)
#      vals['Charger Board Temperature'] = signed16(result, 0x17)
#      vals['Charger Battery Temperature'] = signed16(result, 0x18)
#      vals['Charger Boost Temperature'] = signed16(result, 0x19)
#     vals['Battery Capacity'] = unsigned16(result, 0x1C)
#     vals['Battery Energy Charged'] = unsigned32(result, 0x1D) / 10 
#     vals['BMS Warning'] = unsigned16(result, 0x1F)
#     vals['Battery Energy Discharged'] = unsigned32(result, 0x20) / 10
#     vals['Battery State of Health'] = unsigned16(result, 0x23)
#     vals['Inverter Fault'] = unsigned32(result, 0x40) 
#     vals['Charger Fault'] = unsigned16(result, 0x42) 
#      vals['Manager Fault'] = unsigned16(result, 0x43) 
#        vals['Feed In Power'] = signed32(result, 0x46) # Power to the grid
#        vals['Feed In Energy'] = unsigned32(result, 0x48) / 100 # Energy delivered to the grid, kWh
#        vals['Consumed Energy'] = unsigned32(result, 0x4A) / 100 # Energy consumed from the grid, kWh
#        vals['EPS Voltage'] = unsigned16(result, 0x4C) / 10
#        vals['EPS Current'] = unsigned16(result, 0x4D) / 10
#        vals['EPS VA'] = unsigned16(result, 0x4E)
#        vals['EPS Frequency'] = unsigned16(result, 0x4F) / 100
#        vals['Energy Today'] = unsigned16(result, 0x50) / 10
#        vals['Energy Total'] = unsigned32(result, 0x52) / 1000
#        vals['Battery Temperature'] = unsigned16(result, 0x55) / 10
#        vals['Solar Energy Total'] = unsigned32(result, 0x70) / 10 # kWh
#        self.powerBudgets.append(vals['Power Budget'])
#        if len(self.powerBudgets) > self.config['power_budget_avg_samples']:
#            del self.powerBudgets[0]
#        vals['Power Budget Average'] =  sum(self.powerBudgets) / len(self.powerBudgets)
        
#        vals['Usage'] = vals['Grid Power'] + vals['PV1 Power'] + vals['PV2 Power'] - vals['Battery Power'] - vals['Feed In Power']

my %ModbusSolaxparseInfo = (
	"i0"	=>	{	# holding register 0x0000
					name		=> "Spannung Netz",		# internal name of this register in the hardware doc
					reading		=> "Grid_Voltage",		# name of the reading for this value
					format		=> '%.1f V',		# format string for sprintf
					polldelay	=> "x11",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 10',
				
},
	"i1"	=>	{	# holding register 0x0000
					name		=> "Stromstärke Netz",		# internal name of this register in the hardware doc
					reading		=> "Grid_Current",		# name of the reading for this value
					format		=> '%.1f A',		# format string for sprintf
					polldelay	=> "x11",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 10',	
					#unpack 		=> "s>"	
},
	"i2"	=>	{	# holding register 0x0000
					name		=> "Leistung Netz",		# internal name of this register in the hardware doc
					reading		=> "Grid_Power",		# name of the reading for this value
					format		=> '%.1f W',		# format string for sprintf
					polldelay	=> "x11",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 10',	
					#unpack 		=> "s>"	
},

	"i3"	=>	{	# holding register 0x0000
					name		=> "Spannung PV 1",		# internal name of this register in the hardware doc
					reading		=> "PV1_Voltage",		# name of the reading for this value
					format		=> '%.1f V',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 10',	
},

	"i4"	=>	{	# holding register 0x0000
					name		=> "Spannung PV 2",		# internal name of this register in the hardware doc
					reading		=> "PV2_Voltage",		# name of the reading for this value
					format		=> '%.1f V',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 10',	
},

	"i5"	=>	{	# holding register 0x0000
					name		=> "Stromstärke PV 1",		# internal name of this register in the hardware doc
					reading		=> "PV1_Current",		# name of the reading for this value
					format		=> '%.1f A',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 10',	
},

	"i6"	=>	{	# holding register 0x0000
					name		=> "Stromstärke PV 2",		# internal name of this register in the hardware doc
					reading		=> "PV2_Current",		# name of the reading for this value
					format		=> '%.1f A',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 10',	
},

	"i7"	=>	{	# holding register 0x0000
				name		=> "Frequenz Netz",		# internal name of this register in the hardware doc
					reading		=> "Grid_Frequency",		# name of the reading for this value
					format		=> '%.1f Hz',		# format string for sprintf
					polldelay	=> "x11",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 100',
},	

	"i8"	=>	{	# holding register 0x0000
					name		=> "Temperatur Wechselrichter",		# internal name of this register in the hardware doc
					reading		=> "Temp_WR",		# name of the reading for this value
					format		=> '%.0f °C',		# format string for sprintf
					polldelay	=> "x11",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					#unpack 		=> "s>"		
},

	"i9"	=>	{	# holding register 0x0000
					name		=> "Betriebsmodus",		# internal name of this register in the hardware doc
					reading		=> "Run_Mode",		# name of the reading for this value
					polldelay	=> "x11",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val',
        				map 		=> '0:AUS, 2:Normalbetrieb, 8:Standby',
          				setexpr		=> '$val',
},

	"i10"	=>	{	# holding register 0x0000
					name		=> "Leistung PV 1",		# internal name of this register in the hardware doc
					reading		=> "PV1_Power",		# name of the reading for this value
					format		=> '%.0f',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
},

	"i11"	=>	{	# holding register 0x0000
					name		=> "Leistung PV 2",		# internal name of this register in the hardware doc
					reading		=> "PV2_Power",		# name of the reading for this value
					format		=> '%.0f',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
},
		
	"i20"	=>	{	# holding register 0x0000
					name		=> "Spannung Batterie",		# internal name of this register in the hardware doc
					reading		=> "Battery_Voltage",		# name of the reading for this value
					format		=> '%.1f V',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 100',	
					#unpack		=> "s",
},
	"i21"	=>	{	# holding register 0x0000
					name		=> "Stromstärke Batterie",		# internal name of this register in the hardware doc
					reading		=> "Battery_Current",		# name of the reading for this value
					format		=> '%.1f A',		# format string for sprintf
					#polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val / 100',
					unpack		=> "s>",
},
	"i22"	=>	{	# holding register 0x0000
					name		=> "Leistung Batterie",		# internal name of this register in the hardware doc
					reading		=> "Battery_Power",		# name of the reading for this value
					format		=> '%.1f',		# format string for sprintf
					polldelay	=> "x1",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					#expr		=> '$val / 100',
					unpack		=> "s>",
},
	"i23"	=>	{	# holding register 0x0000
					name		=> "Temperatur Charger Board",		# internal name of this register in the hardware doc
					reading		=> "Charger_Board_Temp",		# name of the reading for this value
					format		=> '%.0f °C',		# format string for sprintf
					polldelay	=> "x10",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					#unpack 		=> "s"	
},					
	"i24"	=>	{	# holding register 0x0000
					name		=> "Temperatur Charger Batterie",		# internal name of this register in the hardware doc
					reading		=> "Battery_Board_Temp",		# name of the reading for this value
					format		=> '%.0f',		# format string for sprintf
					polldelay	=> "x10",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					#unpack 		=> "s"	
},				
	"i25"	=>	{	# holding register 0x0000
					name		=> "Temperatur Charger Boost",		# internal name of this register in the hardware doc
					reading		=> "Charger_Boost_Temp",		# name of the reading for this value
					format		=> '%.0f °C',		# format string for sprintf
					polldelay	=> "x10",	
					#unpack 		=> "s"	
},
	"i28"	=>	{	# holding register 0x0000
					name		=> "Batterie Kapazität",		# internal name of this register in the hardware doc
					reading		=> "Battery_Capacity",		# name of the reading for this value
					format		=> '%.0f',		# format string for sprintf
					polldelay	=> "x10",	
},
	"i29"	=>	{	# holding register 0x0000
					name		=> "Leistung Batterie Laden",		# internal name of this register in the hardware doc
					reading		=> "Battery_Energy_Charged",		# name of the reading for this value
					format		=> '%.1f kWh',		# format string for sprintf
					#polldelay	=> "x1",
					len  		=> "2",	
					expr		=> '$val / 10',
					unpack 		=> "s>"	
},
	"i32"	=>	{	# holding register 0x0000
					name		=> "Energie Batterie Endladen",		# internal name of this register in the hardware doc
					reading		=> "Battery_Energy_Discharged",		# name of the reading for this value
					format		=> '%.1f kWh',		# format string for sprintf
					#polldelay	=> "x1",
					len  		=> "2",	
					expr		=> '$val / 10',
					unpack 		=> "s>"	
},
	"i31"	=>	{	# holding register 0x0000
					name		=> "BMS Warnung",		# internal name of this register in the hardware doc
					reading		=> "BMS_Warning",		# name of the reading for this value
					polldelay	=> "x10",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val',
        				map 		=> '0:OK',
          				setexpr		=> '$val',
},
	"i35"	=>	{	# holding register 0x0000
					name		=> "Batterie Status health",		# internal name of this register in the hardware doc
					reading		=> "Battery_State_Health",		# name of the reading for this value
					polldelay	=> "x10",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val',
        				map 		=> '100:OK',
          				setexpr		=> '$val',
},
	"i64"	=>	{	# holding register 0x0000
					name		=> "Fehler Inverter",		# internal name of this register in the hardware doc
					reading		=> "Inverter_Fault",		# name of the reading for this value
					polldelay	=> "x10",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val',
        				map 		=> '0:OK',
					len		=>  "2",
          				setexpr		=> '$val',
},
	"i66"	=>	{	# holding register 0x0000
					name		=> "Fehler Charger",		# internal name of this register in the hardware doc
					reading		=> "Charger_Fault",		# name of the reading for this value
					polldelay	=> "x10",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val',
        				map 		=> '0:OK',
          				setexpr		=> '$val',
},
	"i67"	=>	{	# holding register 0x0000
					name		=> "Manager Charger",		# internal name of this register in the hardware doc
					reading		=> "Manager_Fault",		# name of the reading for this value
					polldelay	=> "x10",		# only poll this Value if last read is older than x*Iteration, otherwiese getUpdate will skip it
					expr		=> '$val',
        				map 		=> '0:OK',
          				setexpr		=> '$val',
},


#        vals['Feed In Power'] = signed32(result, 0x46) # Power to the grid
#        vals['Feed In Energy'] = unsigned32(result, 0x48) / 100 # Energy delivered to the grid, kWh
#        vals['Consumed Energy'] = unsigned32(result, 0x4A) / 100 # Energy consumed from the grid, kWh


	"i70"	=>	{	# holding register 0x0000
					name		=> "Leistung ins Netz",		# internal name of this register in the hardware doc
					reading		=> "Power_feed_in",		# name of the reading for this value
					format		=> '%.0f',		# format string for sprintf
					polldelay	=> "x1",
					len  		=> "2",	
					unpack		=> "s>",
},
	"i72"	=>	{	# holding register 0x0000
					name		=> "Energie ins Netz geliefert",		# internal name of this register in the hardware doc
					reading		=> "Energy_feed_in",		# name of the reading for this value
					format		=> '%.0f kWh',		# format string for sprintf
					polldelay	=> "x10",
					len  		=> "2",	
					unpack		=> "s",
					expr		=> '$val / 100',
},
	"i74"	=>	{	# holding register 0x0000
					name		=> "Energie verbraucht",		# internal name of this register in the hardware doc
					reading		=> "Energy_consumed",		# name of the reading for this value
					format		=> '%.0f kWh',		# format string for sprintf
					polldelay	=> "x10",
					len  		=> "2",	
					expr		=> '$val / 100',
					unpack		=> "s",
},
	"i112"	=>	{	# holding register 0x0000
					name		=> "Solarenergie gesamt",		# internal name of this register in the hardware doc
					reading		=> "Solar_Energy_total",		# name of the reading for this value
					format		=> '%.3f kWh',		# format string for sprintf
					polldelay	=> "x10",
					len  		=> "2",	
					expr		=> '$val / 10',
					unpack		=> "s>",

#        vals['Energy Today'] = unsigned16(result, 0x50) / 10
#        vals['Energy Total'] = unsigned32(result, 0x52) / 1000



},
	"i82"	=>	{	# holding register 0x0000
					name		=> "Energie gesamt",		# internal name of this register in the hardware doc
					reading		=> "Energy_total",		# name of the reading for this value
					format		=> '%.1f kWh',		# format string for sprintf
					polldelay	=> "x10",
					len  		=> "2",	
					expr		=> '$val / 1000',
					unpack 		=> "s"	
},
	"i80"	=>	{	# holding register 0x0000
					name		=> "Energie heute",		# internal name of this register in the hardware doc
					reading		=> "Energy_today",		# name of the reading for this value
					format		=> '%.1f kWh',		# format string for sprintf
					polldelay	=> "x10",
					expr		=> '$val / 10',
					#unpack 		=> "s"	
},
	"i85"	=>	{	# holding register 0x0000
					name		=> "Batterie Temperatur",		# internal name of this register in the hardware doc
					reading		=> "Battery_temp",		# name of the reading for this value
					format		=> '%.0f',		# format string for sprintf
					#polldelay	=> "x1",
					expr		=> '$val / 10',
},
	"i76"	=>	{	# holding register 0x0000
					name		=> "EPS Spannung",		# internal name of this register in the hardware doc
					reading		=> "EPS_Voltage",		# name of the reading for this value
					format		=> '%.0f V',		# format string for sprintf
					polldelay	=> "x10",
					expr		=> '$val / 10',

},
	"i77"	=>	{	# holding register 0x0000
					name		=> "EPS Stromstärke",		# internal name of this register in the hardware doc
					reading		=> "EPS_Current",		# name of the reading for this value
					format		=> '%.0f A',		# format string for sprintf
					polldelay	=> "x1",
					expr		=> '$val / 10',

},
	"i78"	=>	{	# holding register 0x0000
					name		=> "EPS VA",		# internal name of this register in the hardware doc
					reading		=> "EPS_VA",		# name of the reading for this value
					format		=> '%.0f V',		# format string for sprintf
					polldelay	=> "x10",
},
	"i79"	=>	{	# holding register 0x0000
					name		=> "EPS Frequenz",		# internal name of this register in the hardware doc
					reading		=> "EPS_Frequency",		# name of the reading for this value
					format		=> '%.0f Hz',		# format string for sprintf
					polldelay	=> "x10",
					expr		=> '$val / 100',

},

	# Ende parseInfo
);


#####################################
sub
ModbusSolax_Initialize($)
{
    my ($modHash) = @_;

	require "$attr{global}{modpath}/FHEM/98_Modbus.pm";

	$modHash->{parseInfo}  = \%ModbusSolaxparseInfo;			# defines registers, inputs, coils etc. for this Modbus Defive

	$modHash->{deviceInfo} = \%ModbusSolaxdeviceInfo;			# defines properties of the device like 
															# defaults and supported function codes

	ModbusLD_Initialize($modHash);							# Generic function of the Modbus module does the rest

	$modHash->{AttrList} = $modHash->{AttrList} . " " .		# Standard Attributes like IODEv etc 
		$modHash->{ObjAttrList} . " " .						# Attributes to add or overwrite parseInfo definitions
		$modHash->{DevAttrList} . " " .						# Attributes to add or overwrite devInfo definitions
		"poll-.* " .										# overwrite poll with poll-ReadingName
		"polldelay-.* ";									# overwrite polldelay with polldelay-ReadingName
}


1;

=pod
=begin html

<a name="ModbusSolax"></a>
<h3>ModbusSolax</h3>
<ul>
    ModbusSolax uses the low level Modbus module to provide a way to communicate with SOLAXM smart electrical meter from B+G E-Tech & EASTON.
	It defines the modbus input and holding registers and reads them in a defined interval.
	
	<br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef requires Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="ModbusSolaxDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; ModbusSolax &lt;Id&gt; &lt;Interval&gt;</code>
        <br><br>
        The module connects to the smart electrical meter with Modbus Id &lt;Id&gt; through an already defined modbus device and actively requests data from the 
        smart electrical meter every &lt;Interval&gt; seconds <br>
        <br>
        Example:<br>
        <br>
        <ul><code>define Solax ModbusSolax 1 60</code></ul>
    </ul>
    <br>

    <a name="ModbusSolaxConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
        apart from the modbus id and the interval which both are specified in the define command there is nothing that needs to be defined.
		However there are some attributes that can optionally be used to modify the behavior of the module. <br><br>
        
        The attributes that control which messages are sent / which data is requested every &lt;Interval&gt; seconds are:

        <pre>
		poll-Energy_total__kWh
		poll-Energy_import__kWh
		poll-Energy_L1_total__kWh
		poll-Energy_L2_total__kWh
		poll-Energy_L3_total__kWh
		</pre>
        
        if the attribute is set to 1, the corresponding data is requested every &lt;Interval&gt; seconds. If it is set to 0, then the data is not requested.
        by default the temperatures are requested if no attributes are set.
        <br><br>
        Example:
        <pre>
        define SOLAX ModbusSolax 1 60
        attr SOLAX poll-Energy_total__kWh 0
        </pre>
    </ul>

    <a name="ModbusSolax"></a>
    <b>Set-Commands</b><br>
    <ul>
        The following set options are available:
        <pre>
        </pre>
    </ul>
	<br>
    <a name="ModbusSolaxGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings are also available as Get commands. Internally a Get command triggers the corresponding 
        request to the device and then interprets the data and returns the right field value. To avoid huge option lists in FHEMWEB, only the most important Get options
        are visible in FHEMWEB. However this can easily be changed since all the readings and protocol messages are internally defined in the modue in a data structure 
        and to make a Reading visible as Get option only a little option (e.g. <code>showget => 1</code> has to be added to this data structure
    </ul>
	<br>
    <a name="ModbusSolaxattr"></a>
    <b>Attributes</b><br><br>
    <ul>
	<li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
		<li><b>poll-Energy_total__kWh</b></li> 
		<li><b>poll-Energy_import__kWh</b></li> 
		<li><b>poll-Energy_L1_total__kWh</b></li> 
		<li><b>poll-Energy_L2_total__kWh</b></li> 
		<li><b>poll-Energy_L3_total__kWh</b></li> 
            include a read request for the corresponding registers when sending requests every interval seconds <br>
        <li><b>timeout</b></li> 
            set the timeout for reads, defaults to 2 seconds <br>
		<li><b>minSendDelay</b></li> 
			minimal delay between two requests sent to this device
		<li><b>minCommDelay</b></li>  
			minimal delay between requests or receptions to/from this device
    </ul>
    <br>
</ul>

=end html
=cut
