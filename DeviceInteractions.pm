#!/usr/bin/perl

package DeviceInteractions;

=head2 device_actions

Returns a hash of serial actions, with a subroutine for each profile+action.

=cut
sub device_actions
{
  my $actions = {
    brocadeSwitch => [
      { action => "factoryReset", sub => \&factory_reset_brocade_switch, required_params => [] },
      { action => "setupVLAN", sub => \&setup_vlan_brocade_switch, required_params => [] },
      { action => "setupStack", sub => \&setup_stack_brocade_switch, required_params => [] },
      { action => "setPassword", sub => \&set_password_brocade_switch, required_params => ["root_password", "alteeve_password"] },
      { action => "enableSNMP", sub => \&enable_snmp_brocade_switch, required_params => [] },
      { action => "unformStackAll", sub => \&unform_stack_all_brocade_switch, required_params => [] },
      { action => "unformStackMember", sub => \&unform_stack_member_brocade_switch, required_params => ["member_id"] },
      { action => "setIP", sub => \&set_ip_brocade_switch, required_params => ["switch_ip_address"] },
      { action => "setJumboFrames", sub => \&set_jumbo_frames_brocade_switch, required_params => [] }
    ],

    apcPDU => [
      { action => "setIP", sub => \&configure_ip_apc_pdu, required_params => ["ip", "subnet", "gateway"] },
      { action => "checkSNMP", sub => \&check_snmp_apc_pdu, required_params => ["ip"] }
    ],

    apcUPS => [
      { action => "setIP", sub => \&set_ip_apc_ups, required_params => ["ip", "subnet", "gateway", "striker_dash1_ip"] },
      { action => "factoryReset", sub => \&factory_reset_apc_ups, required_params => [] },
      { action => "enableSNMP", sub => \&enable_snmp_apc_ups, required_params => [] },
      { action => "testing", sub => \&testing_apc_ups, required_params => [] }
    ]
  };
  return $actions;
}

=head2 serial_command_line_switches

Specifies a list of command line switches that will be used in serial actions.

=cut
sub command_line_switches
{
  my $switches = [
    'ip=s',
    'subnet=s',
    'gateway=s',
    'root_password=s',
    'alteeve_password=s',
    'member_id=s',
    'switch_ip_address=s',
    'switch_subnet_address=s',
    'striker_dash1_ip=s'
  ];
  return $switches;
}

=head2 configure_ip_apc_pdu

A device action that sets the ip, gateway, and subnet for an APC RackPDU.

=cut
sub configure_ip_apc_pdu
{
  my $parameter = shift;
  my $ip = defined $parameter->{ip} ? $parameter->{ip} : "";
  my $subnet = defined $parameter->{subnet} ? $parameter->{subnet} : "";
  my $gateway = defined $parameter->{gateway} ? $parameter->{gateway} : "";
  $parameter->{to_check} = [
    { input => "\e", output => "", message => "Bringing it back to the beginning..." },
    { input => "\e", output => "" },
    { input => "\e", output => "" },
    { input => "4\r", output => "" },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4, wait_time => 0 },
    { input => "apc\r", output => "Password  :", timeout => 4, wait_time => 0 },
    { input => "apc\r", output => "------- Control Console" },
    { input => "2\r", output => "------- Network" },
    { input => "1\r", output => "------- TCP/IP", skip => { goto => 11, output => "1- System IP" } },
    { input => "1\r", output => "------- Boot Mode" },
    { input => "4\r", output => "------- TCP/IP" },
    { input => "1\r", output => "System IP :" },
    { input => "$ip\r", output => "1- System IP      : $ip" },
    { input => "2\r", output => "Subnet Mask :" },
    { input => "$subnet\r", output => "2- Subnet Mask    : $subnet" },
    { input => "3\r", output => "Default Gateway :" },
    { input => "$gateway\r", output => "3- Default Gateway: $gateway" },
    { input => "\e", output => "------- Network" },
    { input => "\e", output => "------- Control Console" },
    { input => "4\r", output => "Logging out." },
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 check_snmp_apc_pdu

A serial action that checks for SNMP on an APC PDU.

=cut
sub check_snmp_apc_pdu
{
  my $parameter = shift;
  my $ip = defined $parameter->{ip} ? $parameter->{ip} : "";
  $parameter->{to_check} = [
    { input => "sysDescr.0", check_snmp => "$ip", output => "APC Web/SNMP Management Card", success_message => "SNMP is up on the APC PDU.\n" }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 factory_reset_brocade_switch

A device action that factory resets a brocade switch.

=cut
sub factory_reset_brocade_switch
{
  print "This action will require a reset. This will take at least 3 minutes.\n";
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "erase startup-config\r", output => "Erase startup-config Done.|config empty." },
    { input => "reload\r", output => "Are you sure?" },
    { input => "y\r", output => "Do you want to continue the reload anyway?" },
    { input => "y\r", output => "Rebooting|Reload request sent" },
    { input => "\r\r", output => "(Router|Switch)>", timeout => 300, wait_for_output => 1, bytes_to_read => 16384 }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 setup_vlan_brocade_switch

A device action that sets up vlan for a brocade switch.

=cut
sub setup_vlan_brocade_switch
{
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "configure terminal\r", output => "(Router|Switch)\Q(config)" },
    { input => "show vlan\r\03\r\r", output => "Total PORT-VLAN entries" },
    { input => "vlan 100 name bcn\r", output => "(Router|Switch)\Q-(config-vlan-100)" },
    { input => "untag ethernet 1/3/1 ethernet 1/3/5 ethernet 2/3/1 ethernet 2/3/5 ethernet 1/1/1 to 1/1/12 ethernet 2/1/1 to 2/1/12\r\r", output => "\Qethe 1/1/1 to 1/1/12 ethe 1/3/1 ethe 1/3/5 ethe 2/1/1 to 2/1/12 ethe 2/3/1 ethe 2/3/5" },
    { input => "vlan 200 name sn\r", output => "(Router|Switch)\Q(config-vlan-200)" },
    { input => "untag ethernet 1/3/2 ethernet 1/3/6 ethernet 2/3/2 ethernet 2/3/6 ethernet 1/1/13 to 1/1/16 ethernet 2/1/13 to 2/1/16\r", output => "\Qethe 1/1/13 to 1/1/16 ethe 1/3/2 ethe 1/3/6 ethe 2/1/13 to 2/1/16 ethe 2/3/2 ethe 2/3/6" },
    { input => "vlan 300 name ifn\r", output => "(Router|Switch)\Q(config-vlan-300)" },
    { input => "untag ethernet 1/3/3 to 1/3/4 ethernet 1/3/7 to 1/3/8 ethernet 2/3/3 to 2/3/4 ethernet 2/3/7 to 2/3/8 ethernet 1/1/17 to 1/1/24 ethernet 2/1/17 to 2/1/24\r", output => "\Qethe 1/1/17 to 1/1/24 ethe 1/3/3 to 1/3/4 ethe 1/3/7 to 1/3/8 ethe 2/1/17 to 2/1/24 ethe 2/3/3 to 2/3/4 ethe 2/3/7 to 2/3/8" },
    { input => "exit\r", output => "(Router|Switch)\Q(config)" },
    { input => "show vlan\r\03\r\r", output => "\QTotal PORT-VLAN entries: 4" },
    { input => "write memory\r\r", output => "Write startup-config done|\QRouter(config)", bytes_to_read => 8192, timeout => 60 },
    { input => "exit\r", output => "(Router|Switch)\#" },
    { input => "exit\r", output => "(Router|Switch)>" }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 setup_stack_brocade_switch

A device action that sets up the stack for a brocade switch.

=cut
sub setup_stack_brocade_switch
{
  print "This action will require a reset. This will take at least 3 minutes.\n";
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "configure terminal\r", output => "(Router|Switch)\Q(config)" },
    { input => "stack enable\r", output => "" },
    { input => "exit\r", output => "(Router|Switch)\#" },
    { input => "stack secure-setup\r", output => "Discovering the stack topology", wait_time => 10, bytes_to_read => 8192, skip => { goto => 8, output => "No new units found" } },
    { input => "y\r", output => "Do you accept the unit id", wait_time => 5, bytes_to_read => 8192 },
    { input => "y\r", output => "Election|(Router|Switch)\#" },
    { input => "write memory\r", output => "Write startup-config done|(Router|Switch)\#", timeout => 60 },
    { input => "reload\r", output => "Are you sure" },
    { input => "y\r", output => "Rebooting|Reload request sent" },
    { input => "\r\r", output => "(Router|Switch)>", timeout => 300, wait_for_output => 1, bytes_to_read => 16384 },
    { input => "show stack\r", output => "\Qalone: standalone", bytes_to_read => 8192 },
  ];
  my $output = $parameter->{device_interaction}($parameter);
  my $mac_address = get_mac_address_from_stack_output({output => $output});

  $parameter->{to_check} = [
    { input => "exit\renable\r", output => "(Router|Switch)\#" },
    { input => "configure terminal\r", output => "(Router|Switch)\Q(config)" },
    { input => "hitless-failover enable\r", output => "(Router|Switch)\Q(config)" },
    { input => "stack mac $mac_address\r", output => "(Router|Switch)\Q(config)" },
    { input => "stack unit 2\r", output => "(Router|Switch)\Q(config-unit-2)" },
    { input => "priority 128\r", output => "", wait_time => 121 },
    { input => "exit\r", output => "(Router|Switch)\Q(config)" },
    { input => "write memory\r", output => "Write startup-config done|(Router|Switch)", timeout => 60 },
    { input => "show stack\r", output => "\QCurrent stack management MAC is $mac_address", bytes_to_read => 8192, wait_time => 2 },
    { input => "exit\r", output => "(Router|Switch)\Q\#" },
    { input => "exit\r", output => "(Router|Switch)\Q>" }
  ];
  $parameter->{device_interaction}($parameter);
}

sub get_mac_address_from_stack_output
{
  my $parameter = shift;
  my $output = defined $parameter->{output} ? $parameter->{output} : "";
  my $mac_address;

  if ($output)
  {
    my @lines = split(/\n/, $output);
    $mac_address = "";

    foreach my $line (@lines)
    {
      if (!($line =~ /^\s+$/))
      {
        my @columns = split(/\s+/, trim($line));
        if ($columns[0] =~ /^\d.*$/ && $columns[6] eq "local")
        {
          $mac_address = $columns[4];
          last;
        }
      }
    }
  }

  return $mac_address;
}

=head2 set_password_brocade_switch

A device action that sets passwords for a brocade switch.

=cut
sub set_password_brocade_switch
{
  my $parameter = shift;
  my $root_password = defined $parameter->{root_password} ? $parameter->{root_password} : "";
  my $alteeve_password = defined $parameter->{alteeve_password} ? $parameter->{alteeve_password} : "";
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "configure terminal\r", output => "(Router|Switch)\Q(config)" },
    { input => "enable super-user-password $root_password\r", output => "(Router|Switch)\Q(config)"},
    { input => "enable user disable-on-login-failure 10\r", output => "(Router|Switch)\Q(config)"},
    { input => "user alteeve privilege 0 $alteeve_password\r", output => "(Router|Switch)\Q(config)"},
    { input => "aaa authentication web-server default local\r", output => "(Router|Switch)\Q(config)"},
    { input => "write memory\r\r", output => "Write startup-config done|(Router|Switch)\Q(config)", bytes_to_read => 8192, timeout => 60 },
    { input => "exit\r", output => "(Router|Switch)\#" },
    { input => "exit\r", output => "(Router|Switch)>" }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 enable_snmp_brocade_switch

A device action that enables SNMP Write for a brocade switch.

=cut
sub enable_snmp_brocade_switch
{
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "configure terminal\r", output => "(Router|Switch)\Q(config)" },
    { input => "snmp-server community public rw\r", output => "(Router|Switch)\Q(config)" },
    { input => "write memory\r\r", output => "Write startup-config done|(Router|Switch)\Q(config)", bytes_to_read => 8192, timeout => 60 },
    { input => "exit\r", output => "(Router|Switch)\#" },
    { input => "exit\r", output => "(Router|Switch)>" }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 unform_stack_all_brocade_switch

A device action that removes stack configuration from all brocade switches.

=cut
sub unform_stack_all_brocade_switch
{
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "stack unconfigure all\r", output => "Will dismantle the entire stack and recover pre-stacking startup config. Are you sure? (enter 'y' or 'n'): "},
    { input => "y", output=> "However, it can be turned into a member by an active unit running secure-setup"},
    { input => "\r", output=> "(Router|Switch)\#"},
    { input => "write memory\r\r", output => "Write startup-config done|(Router|Switch)\Q(config)", bytes_to_read => 8192, timeout => 60 },
    { input => "exit\r", output => "(Router|Switch)\#" },
    { input => "exit\r", output => "(Router|Switch)>" }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 unform_stack_member_brocade_switch

A device action that removes stack configuration from a specified Brocade member switch.

=cut
sub unform_stack_member_brocade_switch
{
  my $parameter = shift;
  my $member_id = defined $parameter->{member_id} ? $parameter->{member_id} : "";
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "stack unconfigure $member_id\r", output=> "Will recover pre-stacking startup config of this unit, and reset it. Are you sure? (enter 'y' or 'n'): "},
    { input => "y", output=> "Stack 2 deletes stack bootup flash and recover startup-config.txt from .old"},
    { input => "\r", output=> "(Router|Switch)\#"},
    { input => "exit\r", output => "(Router|Switch)\#" },
    { input => "exit\r", output => "(Router|Switch)>" }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 set_ip_brocade_switch

A device action that sets the IP address and subnet for a brocade switch.

=cut
sub set_ip_brocade_switch
{
  my $parameter = shift;
  my $switch_ip_address = defined $parameter->{switch_ip_address} ? $parameter->{switch_ip_address} : "";
  my $switch_subnet_address = defined $parameter->{switch_subnet_address} ? $parameter->{switch_subnet_address} : "255.255.0.0";
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "Switch>", error_check => { message => "Error: Brocade switch is not running the correct firmware type. Please flash to a current S version.", output => "Router"} },
    { input => "enable\r", output => "Switch\#" },
    { input => "configure terminal\r", output => "Switch\Q(config)" },
    { input => "ip address $switch_ip_address $switch_subnet_address\r", output => "Switch\Q(config)" },
    { input => "write memory\r\r", output => "Write startup-config done|Switch\Q(config)", bytes_to_read => 8192, timeout => 60 },
    { input => "exit\r", output => "Switch\#" },
    { input => "exit\r", output => "Switch>" }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 set_jumbo_frames_brocade_switch

A device action that enables jumbo frames for a brocade switch.

=cut
sub set_jumbo_frames_brocade_switch
{
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "n\rexit\rexit\rexit\r", output => "", message => "Bringing it back to the beginning..." },
    { input => "\r\r", output => "(Router|Switch)>" },
    { input => "enable\r", output => "(Router|Switch)\#" },
    { input => "configure terminal\r", output => "(Router|Switch)\Q(config)" },
    { input => "jumbo\r", output => "Jumbo mode setting requires a reload to take effect!"},
    { input => "write memory\r", output => "Write startup-config done|(Router|Switch)\Q(config)", bytes_to_read => 8192, timeout => 60 },
    { input => "exit\r", output => "(Router|Switch)\#" },
    { input => "reload\r", output => "Are you sure" },
    { input => "y\r", output => "Rebooting|Reload request sent" },
    { input => "\r\r", output => "(Router|Switch)>", timeout => 300, wait_for_output => 1, bytes_to_read => 16384 }
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 configure_ip_apc_ups

A device action that sets the ip, gateway, and subnet for an APC UPS.

=cut
sub set_ip_apc_ups
{
  my $parameter = shift;
  my $ip = defined $parameter->{ip} ? $parameter->{ip} : "";
  my $subnet = defined $parameter->{subnet} ? $parameter->{subnet} : "";
  my $gateway = defined $parameter->{gateway} ? $parameter->{gateway} : "";
  my $striker_dash1_ip = defined $parameter->{striker_dash1_ip} ? $parameter->{striker_dash1_ip} : "";
  $parameter->{to_check} = [
    { input => "\e", output => "", message => "Bringing it back to the beginning..." },
    { input => "\e", output => "" },
    { input => "\equit\r", output => "" },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4 },
    { input => "apc\r", output => "Password  :", timeout => 4 },
    { input => "apc\r", output => "apc>" },
    { input => "tcpip -i $ip -s $subnet -g $gateway\r", output => "E002: Success" },
    { input => "reboot\r", output => "Enter 'YES' to continue or <ENTER> to cancel : " },
    { input => "YES\r", output => "Rebooting...", reconnect => 1, reconnect_timeout => 120 },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4 },
    { input => "apc\r", output => "Password  :", timeout => 4 },
    { input => "apc\r", output => "apc>" },
    { input => "ping $striker_dash1_ip\r", output => "Reply from $striker_dash1_ip" },
    { input => "quit\r", output => "Bye" },
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 enable_snmp_apc_ups

A device action that enables SNMP for an APC UPS.

=cut
sub enable_snmp_apc_ups
{
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "\e", output => "", message => "Bringing it back to the beginning..." },
    { input => "\e", output => "" },
    { input => "\equit\r", output => "" },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4 },
    { input => "apc\r", output => "Password  :", timeout => 4 },
    { input => "apc\r", output => "apc>" },
    { input => "snmp -S enable\r", output => "E002: Success" },
    { input => "reboot\r", output => "Enter 'YES' to continue or <ENTER> to cancel : " },
    { input => "YES\r", output => "Rebooting...", reconnect => 1, reconnect_timeout => 120 },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4 },
    { input => "apc\r", output => "Password  :", timeout => 4 },
    { input => "apc\r", output => "apc>" },
    { input => "quit\r", output => "Bye" },
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 factory_reset_apc_ups

A device action that resets an APC UPS to factory defaults.

=cut
sub factory_reset_apc_ups
{
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "\e", output => "", message => "Bringing it back to the beginning..." },
    { input => "\e", output => "" },
    { input => "\equit\r", output => "" },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4 },
    { input => "apc\r", output => "Password  :", timeout => 4},
    { input => "apc\r", output => "apc>" },
    { input => "resetToDef -p all\r", output => "Enter 'YES' to continue or <ENTER> to cancel : "},
    { input => "YES\r", output => "Please wait..." },
    { input => "reboot\r", output => "Enter 'YES' to continue or <ENTER> to cancel : " },
    { input => "YES\r", output => "Rebooting...", reconnect => 1, reconnect_timeout => 120 },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4 },
    { input => "apc\r", output => "Password  :", timeout => 4 },
    { input => "apc\r", output => "apc>" },
    { input => "quit\r", output => "Bye" },
  ];
  $parameter->{device_interaction}($parameter);
}

=head2 testing_apc_ups

A device action for testing if the connection worked.

=cut
sub testing_apc_ups
{
  my $parameter = shift;
  $parameter->{to_check} = [
    { input => "\e", output => "", message => "Bringing it back to the beginning..." },
    { input => "\e", output => "" },
    { input => "\equit\r", output => "" },
    { input => "\r\r\r\r", output => "User Name :", timeout => 4 },
    { input => "apc\r", output => "Password  :", timeout => 4 },
    { input => "apc\r", output => "apc>" },
    { input => "?\r", output => "Device Commands:" },
    { input => "quit\r", output => "Bye" },
  ];
  $parameter->{device_interaction}($parameter);
}

1;
