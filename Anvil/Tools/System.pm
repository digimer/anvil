package Anvil::Tools::System;
# 
# This module contains methods used to handle common system tasks.
# 

use strict;
use warnings;
use Data::Dumper;
use Net::SSH2;
use Scalar::Util qw(weaken isweak);
use Time::HiRes qw(gettimeofday tv_interval);

our $VERSION  = "3.0.0";
my $THIS_FILE = "System.pm";

### Methods;
# call
# check_daemon
# check_memory
# determine_host_type
# enable_daemon
# get_ips
# is_local
# manage_firewall
# ping
# read_ssh_config
# remote_call
# reload_daemon
# start_daemon
# stop_daemon
# _load_firewalld_zones
# _load_specific_firewalld_zone
# _match_port_to_service

=pod

=encoding utf8

=head1 NAME

Anvil::Tools::System

Provides all methods related to storage on a system.

=head1 SYNOPSIS

 use Anvil::Tools;

 # Get a common object handle on all Anvil::Tools modules.
 my $anvil = Anvil::Tools->new();
 
 # Access to methods using '$anvil->System->X'. 
 # 
 # Example using 'system_call()';
 my $hostname = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{hostname}});

=head1 METHODS

Methods in this module;

=cut
sub new
{
	my $class = shift;
	my $self  = {};
	
	bless $self, $class;
	
	return ($self);
}

# Get a handle on the Anvil::Tools object. I know that technically that is a sibling module, but it makes more 
# sense in this case to think of it as a parent.
sub parent
{
	my $self   = shift;
	my $parent = shift;
	
	$self->{HANDLE}{TOOLS} = $parent if $parent;
	
	# Defend against memory leads. See Scalar::Util'.
	if (not isweak($self->{HANDLE}{TOOLS}))
	{
		weaken($self->{HANDLE}{TOOLS});;
	}
	
	return ($self->{HANDLE}{TOOLS});
}


#############################################################################################################
# Public methods                                                                                            #
#############################################################################################################

=head2 call

This method makes a system call and returns the output (with the last new-line removed). If there is a problem, 'C<< #!error!# >>' is returned and the error will be logged.

Parameters;

=head3 line (optional)

This is the line number of the source file that called this method. Useful for logging and debugging.

=head3 secure (optional)

If set to 'C<< 1 >>', the shell call will be treated as if it contains a password or other sensitive data for logging.

=head3 shell_call (required)

This is the shell command to call.

=head3 source (optional)

This is the name of the source file calling this method. Useful for logging and debugging.

=cut
sub call
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $debug      = defined $parameter->{debug}      ? $parameter->{debug}      : 3;
	my $line       = defined $parameter->{line}       ? $parameter->{line}       : __LINE__;
	my $shell_call = defined $parameter->{shell_call} ? $parameter->{shell_call} : "";
	my $secure     = defined $parameter->{secure}     ? $parameter->{secure}     : 0;
	my $source     = defined $parameter->{source}     ? $parameter->{source}     : $THIS_FILE;
	$anvil->Log->variables({source => $source, line => $line, level => $debug, secure => $secure, list => { shell_call => $shell_call }});
	
	my $output = "#!error!#";
	if (not $shell_call)
	{
		# wat?
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0043"});
	}
	else
	{
		# If this is an executable, make sure the program exists.
		my $found = 1;
		if (($shell_call =~ /^(\/.*?) /) or ($shell_call =~ /^(\/.*)/))
		{
			my $program = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, secure => $secure, list => { program => $program }});
			if (not -e $program)
			{
				$found = 0;
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => "log_0141", variable => {
					program    => $program,
					shell_call => $shell_call,
				}});
			}
			elsif (not -x $program)
			{
				$found = 0;
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => "log_0142", variable => {
					program    => $program,
					shell_call => $shell_call,
				}});
			}
		}
		
		if ($found)
		{
			# Make the system call
			$output = "";
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $debug, secure => $secure, key => "log_0011", variables => { shell_call => $shell_call }});
			open (my $file_handle, $shell_call." 2>&1 |") or $anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, secure => $secure, priority => "err", key => "log_0014", variables => { shell_call => $shell_call, error => $! }});
			while(<$file_handle>)
			{
				chomp;
				my $line = $_;
				$line =~ s/\n$//;
				$line =~ s/\r$//;
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $debug, secure => $secure, key => "log_0017", variables => { line => $line }});
				$output .= $line."\n";
			}
			close $file_handle;
			chomp($output);
			$output =~ s/\n$//s;
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, secure => $secure, list => { output => $output }});
	return($output);
}

=head2 check_daemon

This method checks to see if a daemon is running or not. If it is, it returns 'C<< 1 >>'. If the daemon isn't running, it returns 'C<< 0 >>'. If the daemon wasn't found, 'C<< 2 >>' is returned.

Parameters;

=head3 daemon (required)

This is the name of the daemon to check.

=cut
sub check_daemon
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $return     = 2;
	my $daemon     = defined $parameter->{daemon} ? $parameter->{daemon} : "";
	my $say_daemon = $daemon =~ /\.service$/ ? $daemon : $daemon.".service";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { daemon => $daemon, say_daemon => $say_daemon }});
	
	my $output = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{systemctl}." status ".$say_daemon."; ".$anvil->data->{path}{exe}{'echo'}." return_code:\$?"});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
	foreach my $line (split/\n/, $output)
	{
		if ($line =~ /return_code:(\d+)/)
		{
			my $return_code = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { return_code => $return_code }});
			if ($return_code eq "3")
			{
				# Stopped
				$return = 0;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'return' => $return }});
			}
			elsif ($return_code eq "0")
			{
				# Running
				$return = 1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'return' => $return }});
			}
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'return' => $return }});
	return($return);
}

=head2 check_memory

# Not yet written...

=cut
sub check_memory
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $program_name = defined $parameter->{program_name} ? $parameter->{program_name} : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { program_name => $program_name }});
	if (not $program_name)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0086"});
		return("");
	}
	
	my $used_ram = 0;
	
	my $output = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{''}." --program $program_name"});
	foreach my $line (split/\n/, $output)
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { line => $line }});
		if ($line =~ /= (\d+) /)
		{
			$used_ram = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { used_ram => $used_ram }});
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { used_ram => $used_ram }});
	return($used_ram);
}

=head2 determine_host_type

This method tries to determine the host type and returns a value suitable for use is the C<< hosts >> table.

First, it looks to see if C<< sys::host_type >> is set and, if so, uses that string as it is. 

If that isn't set, it then looks at the short host name. The following rules are used, in order;

1. If the host name ends in C<< n<digits> >> or C<< node<digits> >>, C<< node >> is returned.
2. If the host name ends in C<< striker<digits> >> or C<< dashboard<digits> >>, C<< dashboard >> is returned.
3. If the host name ends in C<< dr<digits> >>, C<< dr >> is returned.

=cut
sub determine_host_type
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $host_type = "";
	my $host_name = $anvil->_short_hostname;
	   $host_type = "unknown";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		host_type        => $host_type,
		host_name        => $host_name,
		"sys::host_type" => $anvil->data->{sys}{host_type},
	}});
	if ($anvil->data->{sys}{host_type})
	{
		$host_type = $anvil->data->{sys}{host_type};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { host_type => $host_type }});
	}
	elsif (($host_name =~ /n\d+$/) or ($host_name =~ /node\d+$/))
	{
		$host_type = "node";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { host_type => $host_type }});
	}
	elsif (($host_name =~ /striker\d+$/) or ($host_name =~ /dashboard\d+$/))
	{
		$host_type = "dashboard";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { host_type => $host_type }});
	}
	elsif ($host_name =~ /dr\d+$/)
	{
		$host_type = "dr";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { host_type => $host_type }});
	}
	
	return($host_type);
}

=head2 enable_daemon

This method enables a daemon (so that it starts when the OS boots). The return code from the start request will be returned.

If the return code for the enable command wasn't read, C<< !!error!! >> is returned.

Parameters;

=head3 daemon (required)

This is the name of the daemon to enable.

=cut
sub enable_daemon
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $return     = undef;
	my $daemon     = defined $parameter->{daemon} ? $parameter->{daemon} : "";
	my $debug      = defined $parameter->{debug}  ? $parameter->{debug}  : 3;
	my $say_daemon = $daemon =~ /\.service$/ ? $daemon : $daemon.".service";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { daemon => $daemon, say_daemon => $say_daemon }});
	
	my $output = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{systemctl}." enable ".$say_daemon." 2>&1; ".$anvil->data->{path}{exe}{'echo'}." return_code:\$?"});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { output => $output }});
	foreach my $line (split/\n/, $output)
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { line => $line }});
		if ($line =~ /return_code:(\d+)/)
		{
			$return = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'return' => $return }});
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'return' => $return }});
	return($return);
}

=head2 get_ips

This method checks the local system for interfaces with IP addresses and stores them in C<< sys::network::interface::<iface_name>::ip >> and C<< sys::network::interface::<iface_name>::subnet >>

=cut
sub get_ips
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0125", variables => { method => "System->get_ips()" }});
	
	my $debug    = 3;
	my $in_iface = "";
	my $ip_addr  = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{ip}." addr list"});
	foreach my $line (split/\n/, $ip_addr)
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { line => $line }});
		if ($line =~ /^\d+: (.*?): /)
		{
			$in_iface = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { in_iface => $in_iface }});
			
			$anvil->data->{sys}{networks}{$in_iface}{ip}     = "" if not defined $anvil->data->{sys}{networks}{$in_iface}{ip};
			$anvil->data->{sys}{networks}{$in_iface}{subnet} = "" if not defined $anvil->data->{sys}{networks}{$in_iface}{subnet};
			$anvil->data->{sys}{networks}{$in_iface}{mac}    = "" if not defined $anvil->data->{sys}{networks}{$in_iface}{mac};
		}
		next if not $in_iface;
		next if $in_iface eq "lo";
		if ($line =~ /inet (.*?)\/(.*?) /)
		{
			my $ip   = $1;
			my $cidr = $2;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { ip => $ip, cidr => $cidr }});
			
			my $subnet = $cidr;
			if (($cidr =~ /^\d{1,2}$/) && ($cidr >= 0) && ($cidr <= 32))
			{
				# Convert to subnet
				$subnet = $anvil->Convert->cidr({cidr => $cidr});
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { subnet => $subnet }});
			}
			
			$anvil->data->{sys}{networks}{$in_iface}{ip}     = $ip;
			$anvil->data->{sys}{networks}{$in_iface}{subnet} = $subnet;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
				"s1:sys::networks::${in_iface}::ip"     => $anvil->data->{sys}{networks}{$in_iface}{ip},
				"s2:sys::networks::${in_iface}::subnet" => $anvil->data->{sys}{networks}{$in_iface}{subnet},
			}});
		}
		if ($line =~ /ether ([0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}) /i)
		{
			$anvil->data->{sys}{networks}{$in_iface}{mac} = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { "sys::networks::${in_iface}::mac" => $anvil->data->{sys}{networks}{$in_iface}{mac} }});
		}
	}

	return(0);
}

=head2 is_local

This method takes a host name or IP address and looks to see if it matches the local system. If it does, it returns C<< 1 >>. Otherwise it returns C<< 0 >>.

Parameters;

=head3 host (required)

This is the host name (or IP address) to check against the local system.

=cut
sub is_local
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0125", variables => { method => "System->_is_local()" }});
	
	my $host = $parameter->{host} ? $parameter->{host} : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { host => $host }});
	
	my $is_local = 0;
	if (($host eq $anvil->_hostname)       or 
	    ($host eq $anvil->_short_hostname) or 
	    ($host eq "localhost")          or 
	    ($host eq "127.0.0.1"))
	{
		# It's local
		$is_local = 1;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { is_local => $is_local }});
	}
	else
	{
		# Get the list of current IPs and see if they match.
		my $network = $anvil->Get->network_details;
		foreach my $interface (keys %{$network->{interface}})
		{
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { "network->interface::${interface}::ip" => $network->{interface}{$interface}{ip} }});
			if ($host eq $network->{interface}{$interface}{ip})
			{
				$is_local = 1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { is_local => $is_local }});
				last;
			}
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { is_local => $is_local }});
	return($is_local);
}

=head2 manage_firewall

This method manages a firewalld firewall.

B<NOTE>: This is pretty basic at this time. Capabilities will be added over time so please expect changes to this method.

Parameters;

=head3 task (optional)

If set to C<< open >>, it will open the corresponding C<< port >>. If set to C<< close >>, it will close the corresponding C<< port >>. If set to c<< check >>, the state of the given C<< port >> is returned.

The default is C<< check >>.

=head3 port_number (required)

This is the port number to work on.

If not specified, C<< service >> is required.

=head3 protocol (optional)

This can be c<< tcp >> or C<< upd >> and is used to specify what protocol to use with the C<< port >>, when specified. The default is C<< tcp >>.

=cut
### TODO: This is slooooow. We need to be able to get more data per system call.
###       - Getting better...
sub manage_firewall
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $task        = defined $parameter->{task}        ? $parameter->{task}        : "check";
	my $port_number = defined $parameter->{port_number} ? $parameter->{port_number} : "";
	my $protocol    = defined $parameter->{protocol}    ? $parameter->{protocol}    : "tcp";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		task        => $task,
		port_number => $port_number,
		protocol    => $protocol, 
	}});
	
	# Make sure we have a port or service.
	if (not $port_number)
	{
		# ...
		return("!!error!!");
	}
	if (($protocol ne "tcp") && ($protocol ne "udp"))
	{
		# Bad protocol
		return("!!error!!");
	}
	
	# This will be set if the port is found to be open.
	my $open = 0;
	
	# Checking the iptables rules in memory is very fast, relative to firewall-cmd. So we'll do an 
	# initial check there to see if the port in question is listed.
	my $shell_call = $anvil->data->{path}{exe}{'iptables-save'};
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
	
	my $iptables = $anvil->System->call({shell_call => $shell_call});
	foreach my $line (split/\n/, $iptables)
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { line => $line }});
		if (($line =~ /-m $protocol /) && ($line =~ /--dport $port_number /) && ($line =~ /ACCEPT/))
		{
			$open = 1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open }});
			last;
		}
	}
	
	# If the port is open and the task is 'check' or 'open', we're done and can return now and save a lot
	# of time.
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'task' => $task, 'open' => $open }});
	if ((($task eq "check") or ($task eq "open")) && ($open))
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open }});
		return($open);
	}
	
	# Make sure firewalld is running.
	my $firewalld_running = $anvil->System->check_daemon({daemon => "firewalld"});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { firewalld_running => $firewalld_running }});
	if (not $firewalld_running)
	{
		if ($anvil->data->{sys}{daemons}{restart_firewalld})
		{
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0127"});
			my $return_code = $anvil->System->start_daemon({daemon => "firewalld"});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { return_code => $return_code }});
			if ($return_code)
			{
				# non-0 means something went wrong.
				return("!!error!!");
			}
		}
		else
		{
			# We've been asked to leave it off.
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0128"});
			return(0);
		}
	}

	
	# Before we do anything, what zone is active?
	my $active_zone = "";
	if (not $active_zone)
	{
		my $shell_call = $anvil->data->{path}{exe}{'firewall-cmd'}." --get-active-zones";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
		
		my $output = $anvil->System->call({shell_call => $shell_call});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
		foreach my $line (split/\n/, $output)
		{
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { line => $line }});
			if ($line !~ /\s/)
			{
				$active_zone = $line;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { active_zone => $active_zone }});
			}
			last;
		}
	}
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { active_zone  => $active_zone }});
	
	# If I still don't know what the active zone is, we're done.
	if (not $active_zone)
	{
		return("!!error!!");
	}
	
	# If we have an active zone, see if the requested port is open.
	my $zone_file = $anvil->data->{path}{directories}{firewalld_zones}."/".$active_zone.".xml";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { zone_file => $zone_file }});
	if (not -e $zone_file)
	{
		#...
		return($open);
	}
	
	# Read the XML to see what services are opened already and translate those into port numbers and 
	# protocols.
	my $open_services = [];
	my $xml           = XML::Simple->new();
	my $body          = "";
	eval { $body = $xml->XMLin($zone_file, KeyAttr => { language => 'name', key => 'name' }, ForceArray => [ 'service' ]) };
	if ($@)
	{
		chomp $@;
		my $error =  "[ Error ] - The was a problem reading: [$zone_file]. The error was:\n";
		   $error .= "===========================================================\n";
		   $error .= $@."\n";
		   $error .= "===========================================================\n";
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", raw => $error});
	}
	else
	{
		# Parse the already-opened services
		foreach my $hash_ref (@{$body->{service}})
		{
			# Load the details of this service.
			my $service = $hash_ref->{name};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service => $service }});
			$anvil->System->_load_specific_firewalld_zone({service => $hash_ref->{name}});
			push @{$open_services}, $service;
		}
		
		# Now loop through the open services, protocols and ports looking for the one passed in by 
		# the caller. If found, the port is already open.
		foreach my $service (sort {$a cmp $b} @{$open_services})
		{
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service => $service }});
			foreach my $this_protocol ("tcp", "udp")
			{
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { this_protocol => $this_protocol }});
				foreach my $this_port (sort {$a cmp $b} @{$anvil->data->{firewalld}{zones}{by_name}{$service}{tcp}})
				{
					$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { this_port => $this_port }});
					if (($port_number eq $this_port) && ($this_protocol eq $protocol))
					{
						# Opened already (as the recorded service).
						$open = $service;
						$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open }});
						last if $open;
					}
					last if $open;
				}
				last if $open;
			}
			last if $open;
		}
	}
	
	# We're done if we were just checking. However, if we've been asked to open a currently closed port,
	# or vice versa, make the change before returning.
	my $changed = 0;
	if (($task eq "open") && (not $open))
	{
		# Map the port to a service, if possible.
		my $service = $anvil->System->_match_port_to_service({port => $port_number});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service => $service }});
		
		# Open the port
		if ($service)
		{
			my $shell_call = $anvil->data->{path}{exe}{'firewall-cmd'}." --permanent --add-service ".$service;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
			
			my $output = $anvil->System->call({shell_call => $shell_call});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
			if ($output eq "success")
			{
				$open    = 1;
				$changed = 1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open, changed => $changed }});
			}
			else
			{
				# Something went wrong...
				return("!!error!!");
			}
		}
		else
		{
			my $shell_call = $anvil->data->{path}{exe}{'firewall-cmd'}." --permanent --add-port ".$port_number."/".$protocol;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
			
			my $output = $anvil->System->call({shell_call => $shell_call});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
			if ($output eq "success")
			{
				$open    = 1;
				$changed = 1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open, changed => $changed }});
			}
			else
			{
				# Something went wrong...
				return("!!error!!");
			}
		}
	}
	elsif (($task eq "close") && ($open))
	{
		# Map the port to a service, if possible.
		my $service = $anvil->System->_match_port_to_service({port => $port_number});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service => $service }});
		
		# Close the port
		if ($service)
		{
			my $shell_call = $anvil->data->{path}{exe}{'firewall-cmd'}." --permanent --remove-service ".$service;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
			
			my $output = $anvil->System->call({shell_call => $shell_call});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
			if ($output eq "success")
			{
				$open    = 0;
				$changed = 1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open, changed => $changed }});
			}
			else
			{
				# Something went wrong...
				return("!!error!!");
			}
		}
		else
		{
			my $shell_call = $anvil->data->{path}{exe}{'firewall-cmd'}." --permanent --remove-port ".$port_number."/".$protocol;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
			
			my $output = $anvil->System->call({shell_call => $shell_call});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
			if ($output eq "success")
			{
				$open    = 0;
				$changed = 1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open, changed => $changed }});
			}
			else
			{
				# Something went wrong...
				return("!!error!!");
			}
		}
	}
	
	# If we made a change, reload.
	if ($changed)
	{
		$anvil->System->reload_daemon({daemon => "firewalld"});
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'open' => $open }});
	return($open);
}

=head2 ping

This method will attempt to ping a target, by hostname or IP, and returns C<< 1 >> if successful, and C<< 0 >> if not.

Example;

 # Test access to the internet. Allow for three attempts to account for network jitter.
 my $pinged = $anvil->System->ping({
 	ping  => "google.ca", 
 	count => 3,
 });
 
 # Test 9000-byte jumbo-frame access to a target over the BCN.
 my $jumbo_to_peer = $anvil->System->ping({
 	ping     => "an-a01n02.bcn", 
 	count    => 1, 
 	payload  => 9000, 
 	fragment => 0,
 });
 
 # Check to see if an Anvil! node has internet access
 my $pinged = $anvil->System->ping({
 	target   => "an-a01n01.alteeve.com",
 	port     => 22,
	password => "super secret", 
 	ping     => "google.ca", 
 	count    => 3,
 });

Parameters;

=head3 count (optional, default '1')

This tells the method how many time to try to ping the target. The method will return as soon as any ping attemp succeeds (unlike pinging from the command line, which always pings the requested count times).

=head3 debug (optional, default '3')

This is an optional way to alter to level at which this method is logged. Useful when the caller is trying to debug a problem. Generally this can be ignored.

=head3 fragment (optional, default '1')

When set to C<< 0 >>, the ping will fail if the packet has to be fragmented. This is meant to be used along side C<< payload >> for testing MTU sizes.

=head3 password (optional)

This is the password used to access a remote machine. This is used when pinging from a remote machine to a given ping target.

=head3 payload (optional)

This can be used to force the ping packet size to a larger number of bytes. It is most often used along side C<< fragment => 0 >> as a way to test if jumbo frames are working as expected.

B<NOTE>: The payload will have 28 bytes removed to account for ICMP overhead. So if you want to test an MTU of '9000', specify '9000' here. You do not need to account for the ICMP overhead yourself.

=head3 port (optional, default '22')

This is the port used to access a remote machine. This is used when pinging from a remote machine to a given ping target.

B<NOTE>: See C<< System->remote_call >> for additional information on specifying the SSH port as part of the target.

=head3 target (optional)

This is the host name or IP address of a remote machine that you want to run the ping on. This is used to test a remote machine's access to a given ping target.

=cut
sub ping
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
# 	my $start_time = [gettimeofday];
# 	print "Start time: [".$start_time->[0].".".$start_time->[1]."]\n";
# 	
# 	my $ping_time = tv_interval ($start_time, [gettimeofday]);
# 	print "[".$ping_time."] - Pinged: [$host]\n";
	
	# If we were passed a target, try pinging from it instead of locally
	my $count    = $parameter->{count}    ? $parameter->{count}    : 1;	# How many times to try to ping it? Will exit as soon as one succeeds
	my $debug    = $parameter->{debug}    ? $parameter->{deug}     : 3;
	my $fragment = $parameter->{fragment} ? $parameter->{fragment} : 1;	# Allow fragmented packets? Set to '0' to check MTU.
	my $password = $parameter->{password} ? $parameter->{password} : "";
	my $payload  = $parameter->{payload}  ? $parameter->{payload}  : 0;	# The size of the ping payload. Use when checking MTU.
	my $ping     = $parameter->{ping}     ? $parameter->{ping}     : "";
	my $port     = $parameter->{port}     ? $parameter->{port}     : "";
	my $target   = $parameter->{target}   ? $parameter->{target}   : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		count    => $count, 
		fragment => $fragment, 
		payload  => $payload, 
		password => $anvil->Log->secure ? $password : "--",
		ping     => $ping, 
		port     => $port, 
		target   => $target, 
	}});
	
	# If the payload was set, take 28 bytes off to account for ICMP overhead.
	if ($payload)
	{
		$payload -= 28;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { payload => $payload }});
	}
	
	# Build the call. Note that we use 'timeout' because if there is no connection and the hostname is 
	# used to ping and DNS is not available, it could take upwards of 30 seconds time timeout otherwise.
	my $shell_call = $anvil->data->{path}{exe}{timeout}." 1 ".$anvil->data->{path}{exe}{'ping'}." -W 1 -n $ping -c 1";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { shell_call => $shell_call }});
	if (not $fragment)
	{
		$shell_call .= " -M do";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { shell_call => $shell_call }});
	}
	if ($payload)
	{
		$shell_call .= " -s $payload";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { shell_call => $shell_call }});
	}
	$shell_call .= " || ".$anvil->data->{path}{exe}{echo}." timeout";
	
	my $pinged            = 0;
	my $average_ping_time = 0;
	foreach my $try (1..$count)
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { count => $count, try => $try }});
		last if $pinged;
		
		my $output = "";
		
		# If the 'target' is set, we'll call over SSH unless 'target' is 'local' or our hostname.
		if (($target) && ($target ne "local") && ($target ne $anvil->_hostname) && ($target ne $anvil->_short_hostname))
		{
			### Remote calls
			$output = $anvil->System->remote_call({
				shell_call => $shell_call, 
				target     => $target,
				port       => $port, 
				password   => $password,
			});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { output => $output }});
		}
		else
		{
			### Local calls
			$output = $anvil->System->call({shell_call => $shell_call});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { output => $output }});
		}
		
		foreach my $line (split/\n/, $output)
		{
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { line => $line }});
			if ($line =~ /(\d+) packets transmitted, (\d+) received/)
			{
				# This isn't really needed, but might help folks watching the logs.
				my $pings_sent     = $1;
				my $pings_received = $2;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
					pings_sent     => $pings_sent,
					pings_received => $pings_received, 
				}});
				
				if ($pings_received)
				{
					# Contact!
					$pinged = 1;
					$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { pinged => $pinged }});
				}
				else
				{
					# Not yet... Sleep to give time for transient network problems to 
					# pass.
					sleep 1;
				}
			}
			if ($line =~ /min\/avg\/max\/mdev = .*?\/(.*?)\//)
			{
				$average_ping_time = $1;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { average_ping_time => $average_ping_time }});
			}
		}
	}
	
	# 0 == Ping failed
	# 1 == Ping success
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		pinged            => $pinged,
		average_ping_time => $average_ping_time,
	}});
	return($pinged, $average_ping_time);
}

=head2 read_ssh_config

This reads /etc/ssh/ssh_config and notes hosts with defined ports. When found, the associated port will be automatically used for a given host name or IP address.

Matches will have their ports stored in C<< hosts::<host_name>::port >>.

This method takes no parameters.

=cut
sub read_ssh_config
{
	my $self = shift;
	my $anvil   = $self->parent;
	
	# This will hold the raw contents of the file.
	my $this_host                   = "";
	   $anvil->data->{raw}{ssh_config} = $anvil->Storage->read_file({file => $anvil->data->{path}{configs}{ssh_config}});
	foreach my $line (split/\n/, $anvil->data->{raw}{ssh_config})
	{
		$line =~ s/#.*$//;
		$line =~ s/\s+$//;
		next if not $line;
		
		if ($line =~ /^host (.*)/i)
		{
			$this_host = $1;
			next;
		}
		next if not $this_host;
		if ($line =~ /port (\d+)/i)
		{
			my $port = $1;
			$anvil->data->{hosts}{$this_host}{port} = $port;
		}
	}
	
	return(0);
}

=head2 remote_call

This does a remote call over SSH. The connection is held open and the file handle for the target is cached and re-used unless a specific ssh_fh is passed or a request to close the connection is received. 

Example;

 # Call 'hostname' on a node.
 my ($error, $output) = $anvil->System->remote_call({
 	target     => "an-a01n01.alteeve.com",
 	user       => "admin",
 	password   => "super secret password",
 	shell_call => "/usr/bin/hostname",
 });
 
 # Make a call with sensitive data that you want logged only if $anvil->Log->secure is set and close the 
 # connection when done.
 my ($error, $output) = $anvil->System->remote_call({
 	target     => "an-a01n01.alteeve.com",
 	user       => "root", 
 	password   => "super secret password",
 	shell_call => "/usr/sbin/fence_ipmilan -a an-a01n02.ipmi -l admin -p \"super secret password\" -o status",
 	secure     => 1,
	close      => 1, 
 });

B<NOTE>: By default, a connection to a target will be held open and cached to increase performance for future connections. 

Parameters;

=head3 close (optional, default '0')

If set, the connection to the target will be closed at the end of the call.

=head3 log_level (optional, default C<< 3 >>)

If set, the method will use the given log level. Valid values are integers between C<< 0 >> and C<< 4 >>.

=head3 no_cache (optional, default C<< 0 >>)

If set, and if an existing cached connection is open, it will be closed and a new connection to the target will be established.

=head3 password (optional)

This is the password used to connect to the remote target as the given user.

B<NOTE>: Passwordless SSH is supported. If you can ssh to the target as the given user without a password, then no password needs to be given here.

=head3 port (optional, default C<< 22 >>)

This is the TCP port to use when connecting to the C<< target >>. The default is port 22.

B<NOTE>: See C<< target >> for optional port definition.

=head3 secure (optional, default C<< 0 >>)

If set, the C<< shell_call >> is treated as containing sensitive data and will not be logged unless C<< $anvil->Log->secure >> is enabled.

=head3 shell_call (required)

This is the command to run on the target machine as the target user.

=head3 target (required)

This is the host name or IP address of the target machine that the C<< shell_call >> will be run on.

B<NOTE>: If the target matches an entry in '/etc/ssh/ssh_config', the port defined there is used. If the port is set as part of the target name, the port in 'ssh_config' is ignored.

B<NOTE>: If the C<< target >> is presented in the format C<< target:port >>, the port will be separated from the target and used as the TCP port. If the C<< port >> parameter is set, however, the port split off the C<< target >> will be ignored.

=head3 user (optional, default 'root')

This is the user account on the C<< target >> to connect as and to run the C<< shell_call >> as. The C<< password >> if so this user's account on the C<< target >>.

=cut
sub remote_call
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# Get the target and port so that we can create the ssh_fh key
	my $log_level  = defined $parameter->{log_level} ? $parameter->{log_level} : 3;
	if (($log_level !~ /^\d$/) or ($log_level < 0) or ($log_level > 4))
	{
		# Invalid log level, set 2.
		$log_level = 3;
	}
	
	my $port       = defined $parameter->{port}   ? $parameter->{port}   : 22;
	my $target     = defined $parameter->{target} ? $parameter->{target} : "";
	my $ssh_fh_key = $target.":".$port;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { 
		port   => $port, 
		target => $target,
	}});
	
	# This will store the SSH file handle for the given target after the initial connection.
	$anvil->data->{cache}{ssh_fh}{$ssh_fh_key} = defined $anvil->data->{cache}{ssh_fh}{$ssh_fh_key} ? $anvil->data->{cache}{ssh_fh}{$ssh_fh_key} : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { "cache::ssh_fh::${ssh_fh_key}" => $anvil->data->{cache}{ssh_fh}{$ssh_fh_key} }});
	
	# Now pick up the rest of the variables.
	my $close      = defined $parameter->{'close'}    ? $parameter->{'close'}    : 0;
	my $no_cache   = defined $parameter->{no_cache}   ? $parameter->{no_cache}   : 0;
	my $password   = defined $parameter->{password}   ? $parameter->{password}   : $anvil->data->{sys}{root_password};
	my $secure     = defined $parameter->{secure}     ? $parameter->{secure}     : 0;
	my $shell_call = defined $parameter->{shell_call} ? $parameter->{shell_call} : "";
	my $user       = defined $parameter->{user}       ? $parameter->{user}       : "root";
	my $start_time = time;
	my $ssh_fh     = $anvil->data->{cache}{ssh_fh}{$ssh_fh_key};
	# NOTE: The shell call might contain sensitive data, so we show '--' if 'secure' is set and $anvil->Log->secure is not.
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { 
		'close'    => $close, 
		password   => $anvil->Log->secure ? $password : "--", 
		secure     => $secure, 
		shell_call => ((not $anvil->Log->secure) && ($secure)) ? "--" : $shell_call,
		ssh_fh     => $ssh_fh,
		start_time => $start_time, 
		user       => $user,
	}});
	
	if (not $shell_call)
	{
		# No shell call
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Systeme->remote_call()", parameter => "shell_call" }});
		return("!!error!!");
	}
	if (not $target)
	{
		# No target
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Systeme->remote_call()", parameter => "target" }});
		return("!!error!!");
	}
	if (not $user)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Systeme->remote_call()", parameter => "user" }});
		return("!!error!!");
	}
	
	# If the user didn't pass a port, but there is an entry in 'hosts::<host>::port', use it.
	if ((not $parameter->{port}) && ($anvil->data->{hosts}{$target}{port}))
	{
		$port = $anvil->data->{hosts}{$target}{port};
	}
	
	# Break out the port, if needed.
	my $state;
	my $error;
	if ($target =~ /^(.*):(\d+)$/)
	{
		$target = $1;
		$port   = $2;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { 
			port   => $port, 
			target => $target,
		}});
		
		# If the user passed a port, override this.
		if ($parameter->{port} =~ /^\d+$/)
		{
			$port = $parameter->{port};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { port => $port }});
		}
	}
	else
	{
		# In case the user is using ports in /etc/ssh/ssh_config, we'll want to check for an entry.
		$anvil->System->read_ssh_config();
		
		$anvil->data->{hosts}{$target}{port} = "" if not defined $anvil->data->{hosts}{$target}{port};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { "hosts::${target}::port" => $anvil->data->{hosts}{$target}{port} }});
		if ($anvil->data->{hosts}{$target}{port} =~ /^\d+$/)
		{
			$port = $anvil->data->{hosts}{$target}{port};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { port => $port }});
		}
	}
	
	# Make sure the port is valid.
	if ($port eq "")
	{
		$port = 22;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { port => $port }});
	}
	elsif ($port !~ /^\d+$/)
	{
		$port = getservbyname($port, 'tcp');
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { port => $port }});
	}
	if ((not defined $port) or (($port !~ /^\d+$/) or ($port < 0) or ($port > 65536)))
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0058", variables => { port => $port }});
		return("!!error!!");
	}
	
	# If the target is a host name, convert it to an IP.
	if (not $anvil->Validate->is_ipv4({ip => $target}))
	{
		my $new_target = $anvil->Convert->hostname_to_ip({host_name => $target});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { new_target => $new_target }});
		if ($new_target)
		{
			$target = $new_target;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { target => $target }});
		}
	}
	
	# If the user set 'no_cache', don't use any existing 'ssh_fh'.
	if (($no_cache) && ($ssh_fh))
	{
		# Close the connection.
		$ssh_fh->disconnect();
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $log_level, key => "message_0010", variables => { target => $target }});
		
		# For good measure, blank both variables.
		$anvil->data->{cache}{ssh_fh}{$ssh_fh_key} = "";
		$ssh_fh                                 = "";
	}
	
	# These will be merged into a single 'output' array before returning.
	my $stdout_output = [];
	my $stderr_output = [];
	
	# If I don't already have an active SSH file handle, connect now.
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { ssh_fh => $ssh_fh }});
	
	if ($ssh_fh !~ /^Net::SSH2/)
	{
		### NOTE: Nevermind, timeout isn't supported... >_< Find a newer version if IO::Socket::IP?
		### TODO: Make the timeout user-configurable to handle slow connections. Make it 
		###       'sys::timeout::{all|host} = x'
		my $start_time = [gettimeofday];
		$ssh_fh = Net::SSH2->new(timeout => 1000);
		if (not $ssh_fh->connect($target, $port))
		{
			
			my $connect_time = tv_interval ($start_time, [gettimeofday]);
			print "[".$connect_time."] - Connection failed time to: [$target:$port]\n";
			
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", list => { 
				user       => $user,
				target     => $target, 
				port       => $port, 
				shell_call => $shell_call,
				error      => $@,
			}});
			
			# We'll now try to get a more useful message for the user and logs.
			my $message_key = "message_0005";
			my $variables   = { target => $target };
			if ($@ =~ /Bad hostname/i)
			{
				$message_key = "message_0001";
			}
			elsif ($@ =~ /Connection refused/i)
			{
				$message_key = "message_0002";
				$variables   = {
					target => $target,
					port   => $port,
					user   => $user,
				};
			}
			elsif ($@ =~ /No route to host/)
			{
				$message_key = "message_0003";
			}
			elsif ($@ =~ /timeout/)
			{
				$message_key = "message_0004";
			}
			$error = $anvil->Words->string({key => $message_key, variables => $variables});
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => $message_key, variables => $variables});
		}
		
		my $connect_time = tv_interval ($start_time, [gettimeofday]);
		print "[".$connect_time."] - Connect time to: [$target:$port]\n";
		
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { error => $error, ssh_fh => $ssh_fh }});
		if (not $error)
		{
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { 
				user     => $user,
				password => $anvil->Log->secure ? $password : "--", 
			}});
			if (not $ssh_fh->auth_password($user, $password)) 
			{
				# Can we log in without a password?
				my $user           = getpwuid($<);
				my $home_directory = $anvil->Get->users_home({user => $user});
				my $public_key     = $home_directory."/.ssh/id_rsa.pub";
				my $private_key    = $home_directory."/.ssh/id_rsa";
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { 
					user           => $user,
					home_directory => $home_directory, 
					public_key     => $public_key, 
					private_key    => $private_key,
				}});
				
				if ($ssh_fh->auth_publickey($user, $public_key, $private_key)) 
				{
					# We're in! Record the file handle for this target.
					$anvil->data->{cache}{ssh_fh}{$ssh_fh_key} = $ssh_fh;
					$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { "cache::ssh_fh::${ssh_fh_key}" => $anvil->data->{cache}{ssh_fh}{$ssh_fh_key} }});
					
					# Log that we got in without a password.
					$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $log_level, key => "log_0062", variables => { target => $target }});
				}
				else
				{
					# This is for the user
					$error = $anvil->Words->string({key => "message_0006", variables => { target => $target }});
					$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "message_0006", variables => { target => $target }});
				}
			}
			else
			{
				# We're in! Record the file handle for this target.
				$anvil->data->{cache}{ssh_fh}{$ssh_fh_key} = $ssh_fh;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { "cache::ssh_fh::${ssh_fh_key}" => $anvil->data->{cache}{ssh_fh}{$ssh_fh_key} }});
				
				# Record our success
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $log_level, key => "message_0007", variables => { target => $target }});
			}
		}
	}
	
	### Special thanks to Rafael Kitover (rkitover@gmail.com), maintainer of Net::SSH2, for helping me
	### sort out the polling and data collection in this section.
	#
	# Open a channel and make the call.
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { 
		error  => $error, 
		ssh_fh => $ssh_fh, 
	}});
	if (($ssh_fh =~ /^Net::SSH2/) && (not $error))
	{
		# We need to open a channel every time for 'exec' calls. We want to keep blocking off, but we
		# need to enable it for the channel() call.
		   $ssh_fh->blocking(1);
		my $channel = $ssh_fh->channel();
		   $ssh_fh->blocking(0);
		
		# Make the shell call
		if (not $channel)
		{
			# ... or not.
			$ssh_fh = "";
			$error  = $anvil->Words->string({key => "message_0008", variables => { target => $target }});
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "message_0008", variables => { target => $target }});
		}
		else
		{
			### TODO: Timeout if the call doesn't respond in X seconds, closing the filehandle if hit.
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, secure => $secure, list => { 
				channel    => $channel, 
				shell_call => $shell_call, 
			}});
			$channel->exec("$shell_call");
			
			# This keeps the connection open when the remote side is slow to return data, like in
			# '/etc/init.d/rgmanager stop'.
			my @poll = {
				handle => $channel,
				events => [qw/in err/],
			};
			
			# We'll store the STDOUT and STDERR data here.
			my $stdout = "";
			my $stderr = "";
			
			# Not collect the data.
			while(1)
			{
				$ssh_fh->poll(250, \@poll);
				
				# Read in anything from STDOUT
				while($channel->read(my $chunk, 80))
				{
					$stdout .= $chunk;
				}
				while ($stdout =~ s/^(.*)\n//)
				{
					my $line = $1;
					   $line =~ s/\r//g;	# Remove \r from things like output of daemon start/stops.
					$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, secure => $secure, list => { "STDOUT:line" => $line }});
					push @{$stdout_output}, $line;
				}
				
				# Read in anything from STDERR
				while($channel->read(my $chunk, 80, 1))
				{
					$stderr .= $chunk;
				}
				while ($stderr =~ s/^(.*)\n//)
				{
					my $line = $1;
					$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, secure => $secure, list => { "STDERR:line" => $line }});
					push @{$stderr_output}, $line;
				}
				
				# Exit when we get the end-of-file.
				last if $channel->eof;
			}
			if ($stdout)
			{
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, secure => $secure, list => { stdout => $stdout }});
				push @{$stdout_output}, $stdout;
			}
			if ($stderr)
			{
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, secure => $secure, list => { stderr => $stderr }});
				push @{$stderr_output}, $stderr;
			}
		}
	}
	
	# Merge the STDOUT and STDERR
	my $output = [];
	
	foreach my $line (@{$stderr_output}, @{$stdout_output})
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, secure => $secure, list => { line => $line }});
		push @{$output}, $line;
	}
	
	# Close the connection if requested.
	if ($close)
	{
		if ($ssh_fh)
		{
			# Close it.
			$ssh_fh->disconnect();
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $log_level, key => "message_0009", variables => { target => $target }});
		}
		
		# For good measure, blank both variables.
		$anvil->data->{cache}{ssh_fh}{$ssh_fh_key} = "";
		$ssh_fh                                  = "";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, list => { "cache::ssh_fh::${ssh_fh_key}" => $anvil->data->{cache}{ssh_fh}{$ssh_fh_key} }});
	}
	
	$error = "" if not defined $error;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $log_level, secure => $secure, list => { 
		error  => $error,
		ssh_fh => $ssh_fh, 
		output => $output, 
	}});
	return($error, $output);
};

=head2 reload_daemon

This method reloads a daemon (typically to pick up a change in configuration). The return code from the start request will be returned.

If the return code for the reload command wasn't read, C<< !!error!! >> is returned. If it did reload, C<< 0 >> is returned. If the reload failed, a non-0 return code will be returned.

Parameters;

=head3 daemon (required)

This is the name of the daemon to reload.

=cut
sub reload_daemon
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $return     = undef;
	my $daemon     = defined $parameter->{daemon} ? $parameter->{daemon} : "";
	my $say_daemon = $daemon =~ /\.service$/ ? $daemon : $daemon.".service";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { daemon => $daemon, say_daemon => $say_daemon }});
	
	my $shell_call = $anvil->data->{path}{exe}{systemctl}." reload ".$say_daemon."; ".$anvil->data->{path}{exe}{'echo'}." return_code:\$?";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
	
	my $output = $anvil->System->call({shell_call => $shell_call});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
	foreach my $line (split/\n/, $output)
	{
		if ($line =~ /return_code:(\d+)/)
		{
			$return = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'return' => $return }});
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'return' => $return }});
	return($return);
}

=head2 start_daemon

This method starts a daemon. The return code from the start request will be returned.

If the return code for the start command wasn't read, C<< !!error!! >> is returned.

Parameters;

=head3 daemon (required)

This is the name of the daemon to start.

=cut
sub start_daemon
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $return     = undef;
	my $debug      = defined $parameter->{debug}  ? $parameter->{debug}  : 3;
	my $daemon     = defined $parameter->{daemon} ? $parameter->{daemon} : "";
	my $say_daemon = $daemon =~ /\.service$/ ? $daemon : $daemon.".service";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { daemon => $daemon, say_daemon => $say_daemon }});
	
	my $output = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{systemctl}." start ".$say_daemon."; ".$anvil->data->{path}{exe}{'echo'}." return_code:\$?", debug => $debug});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { output => $output }});
	foreach my $line (split/\n/, $output)
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { line => $line }});
		if ($line =~ /return_code:(\d+)/)
		{
			$return = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'return' => $return }});
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'return' => $return }});
	return($return);
}

=head2 stop_daemon

This method stops a daemon. The return code from the stop request will be returned.

If the return code for the stop command wasn't read, C<< !!error!! >> is returned.

Parameters;

=head3 daemon (required)

This is the name of the daemon to stop.

=cut
sub stop_daemon
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $return     = undef;
	my $daemon     = defined $parameter->{daemon} ? $parameter->{daemon} : "";
	my $say_daemon = $daemon =~ /\.service$/ ? $daemon : $daemon.".service";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { daemon => $daemon, say_daemon => $say_daemon }});
	
	my $output = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{systemctl}." stop ".$say_daemon."; ".$anvil->data->{path}{exe}{'echo'}." return_code:\$?"});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
	foreach my $line (split/\n/, $output)
	{
		if ($line =~ /return_code:(\d+)/)
		{
			$return = $1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'return' => $return }});
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'return' => $return }});
	return($return);
}


# =head3
# 
# Private Functions;
# 
# =cut

#############################################################################################################
# Private functions                                                                                         #
#############################################################################################################

=head2 _load_firewalld_zones

This reads in the XML files for all of the firewalld zones.

It takes no arguments.

=cut
sub _load_firewalld_zones
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $directory = $anvil->data->{path}{directories}{firewalld_services};
	$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0018", variables => { directory => $directory }});
	if (not -d $directory)
	{
		# Missing directory...
		return("!!error!!");
	}
	
	$anvil->data->{sys}{firewalld}{services_loaded} = 0 if not defined $anvil->data->{sys}{firewalld}{services_loaded};
	return(0) if $anvil->data->{sys}{firewalld}{services_loaded};
	
	local(*DIRECTORY);
	opendir(DIRECTORY, $directory);
	while(my $file = readdir(DIRECTORY))
	{
		next if $file !~ /\.xml$/;
		my $full_path = $directory."/".$file;
		my $service   = ($file =~ /^(.*?)\.xml$/)[0];
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			full_path => $full_path,
			service   => $service, 
		}});
		
		$anvil->System->_load_specific_firewalld_zone({service => $service});
	}
	closedir DIRECTORY;
	
	# Set this so we don't waste time calling this again.
	$anvil->data->{sys}{firewalld}{services_loaded} = 1;
	
	return(0);
}

=head2 _load_specific_firewalld_zone

This takes the name of a service (with or without the C<< .xml >> suffix) and reads it into the C<< $anvil->data >> hash.

Data will be stored as:

* C<< firewalld::zones::by_name::<service>::name = Short name >>
* C<< firewalld::zones::by_name::<service>::tcp  = <array of port numbers> >>
* C<< firewalld::zones::by_name::<service>::tcp  = <array of port numbers> >>
* C<< firewalld::zones::by_port::<tcp or udp>::<port number> = <service> >>

The 'C<< service >> name is the service file name, minus the C<< .xml >> suffix.

If there is a problem, C<< !!error!! >> will be returned.

Parameters;

=head3 service (required)

This is the name of the service to read in. It expects the file to be in the C<< path::directories::firewalld_services >> diretory. If the service name doesn't end in C<< .xml >>, that suffix will be added automatically.

=cut
sub _load_specific_firewalld_zone
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $service = defined $parameter->{service} ? $parameter->{service} : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service => $service }});
	
	if (not $service)
	{
		# No service name
		return("!!error!!");
	}
	
	if ($service !~ /\.xml$/)
	{
		$service .= ".xml";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service => $service }});
	}
	
	# We want the service name to be the file name without the '.xml' suffix.
	my $service_name = ($service =~ /^(.*?)\.xml$/)[0];
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service_name => $service_name }});
	
	my $full_path = $anvil->data->{path}{directories}{firewalld_services}."/".$service;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { full_path => $full_path }});
	if (not -e $full_path)
	{
		# File not found
		return("!!error!!");
	}
	
	my $xml  = XML::Simple->new();
	my $body = "";
	eval { $body = $xml->XMLin($full_path, KeyAttr => { language => 'name', key => 'name' }, ForceArray => [ 'port' ]) };
	if ($@)
	{
		chomp $@;
		my $error =  "[ Error ] - The was a problem reading: [$full_path]. The error was:\n";
		   $error .= "===========================================================\n";
		   $error .= $@."\n";
		   $error .= "===========================================================\n";
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", raw => $error});
	}
	else
	{
		my $name = $body->{short};
		$anvil->data->{firewalld}{zones}{by_name}{$service_name}{name} = $name;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { "firewalld::zones::by_name::${service_name}::name" => $anvil->data->{firewalld}{zones}{by_name}{$service_name}{name} }});
		
		if ((not defined $anvil->data->{firewalld}{zones}{by_name}{$service_name}{tcp}) or (ref($anvil->data->{firewalld}{zones}{by_name}{$service_name}{tcp}) ne "ARRAY"))
		{
			$anvil->data->{firewalld}{zones}{by_name}{$service_name}{tcp} = [];
		}
		if ((not defined $anvil->data->{firewalld}{zones}{by_name}{$service_name}{udp}) or (ref($anvil->data->{firewalld}{zones}{by_name}{$service_name}{udp}) ne "ARRAY"))
		{
			$anvil->data->{firewalld}{zones}{by_name}{$service_name}{udp} = [];
		}
		
		foreach my $hash_ref (@{$body->{port}})
		{
			my $this_port     = $hash_ref->{port};
			my $this_protocol = $hash_ref->{protocol};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
				this_port     => $this_port,
				this_protocol => $this_protocol,
			}});
			
			# Is this a range?
			if ($this_port =~ /^(\d+)-(\d+)$/)
			{
				# Yup.
				my $start = $1;
				my $end   = $2;
				$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
					start => $start,
					end   => $end,
				}});
				foreach my $port ($start..$end)
				{
					$anvil->data->{firewalld}{zones}{by_port}{$this_protocol}{$port} = $service_name;
					push @{$anvil->data->{firewalld}{zones}{by_name}{$service_name}{$this_protocol}}, $port;
				}
			}
			else
			{
				# Nope
				$anvil->data->{firewalld}{zones}{by_port}{$this_protocol}{$this_port} = $service_name;
				push @{$anvil->data->{firewalld}{zones}{by_name}{$service_name}{$this_protocol}}, $this_port;
			}
		}
	}
	
	return(0);
}

=head2 _match_port_to_service

This takes a port number and returns the service name, if it matches one of them. Otherwise it returns an empty string.

Parameters;

=head3 port (required) 

This is the port number to match.

=head3 protocol (optional)

This is the protocol to match, either C<< tcp >> or C<< udp >>. If this is not specified, C<< tcp >> is used.

=cut
# NOTE: We read the XML files instead of use 'firewall-cmd' directly because reading the files is about 30x 
#       faster.
sub _match_port_to_service
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $port     = defined $parameter->{port}     ? $parameter->{port}     : "";
	my $protocol = defined $parameter->{protocol} ? $parameter->{protocol} : "tcp";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		port     => $port, 
		protocol => $protocol,
	}});
	
	# Do we already know about this service?
	my $service_name = "";
	if ((exists $anvil->data->{firewalld}{zones}{by_port}{$protocol}{$port}) && ($anvil->data->{firewalld}{zones}{by_port}{$protocol}{$port}))
	{
		# Yay!
		$service_name = $anvil->data->{firewalld}{zones}{by_port}{$protocol}{$port};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service_name => $service_name }});
	}
	else
	{
		# Load all zones and look
		$anvil->System->_load_firewalld_zones;
		if ((exists $anvil->data->{firewalld}{zones}{by_port}{$protocol}{$port}) && ($anvil->data->{firewalld}{zones}{by_port}{$protocol}{$port}))
		{
			# Got it now.
			$service_name = $anvil->data->{firewalld}{zones}{by_port}{$protocol}{$port};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service_name => $service_name }});
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { service_name => $service_name }});
	return($service_name);
}

1;
