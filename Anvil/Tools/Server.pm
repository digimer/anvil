package Anvil::Tools::Server;
# 
# This module contains methods used to manager servers
# 

use strict;
use warnings;
use Scalar::Util qw(weaken isweak);
use Data::Dumper;

our $VERSION  = "3.0.0";
my $THIS_FILE = "Server.pm";

### Methods;
# boot
# find
# get_status
# migrate
# shutdown

=pod

=encoding utf8

=head1 NAME

Anvil::Tools::Server

Provides all methods related to (virtual) servers.

=head1 SYNOPSIS

 use Anvil::Tools;

 # Get a common object handle on all Anvil::Tools modules.
 my $anvil = Anvil::Tools->new();
 
 # Access to methods using '$anvil->Server->X'. 
 # 
 # 

=head1 METHODS

Methods in this module;

=cut
sub new
{
	my $class = shift;
	my $self  = {
	};
	
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
		weaken($self->{HANDLE}{TOOLS});
	}
	
	return ($self->{HANDLE}{TOOLS});
}

#############################################################################################################
# Public methods                                                                                            #
#############################################################################################################

=head2 boot

This takes a server name and tries to boot it (using C<< virsh create /mnt/shared/definition/<server>.xml >>. It requires that any supporting systems already be started (ie: DRBD resource is up).

If booted, C<< 1 >> is returned. Otherwise, C<< 0 >> is returned.

 my ($booted) = $anvil->Server->boot({server => "test_server"});

Parameters;

=head3 definition (optional, see below for default)

This is the full path to the XML definition file to use to boot the server.

By default, the definition file used will be named C<< <server>.xml >> in the C<< path::directories::shared::deinitions >> directory. 

=head3 server (required)

This is the name of the server, as it appears in C<< virsh >>.

=cut
sub boot
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	my $server     = defined $parameter->{server}     ? $parameter->{server}     : "";
	my $definition = defined $parameter->{definition} ? $parameter->{definition} : "";
	my $success    = 0;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		server     => $server, 
		definition => $definition, 
	}});
	
	if (not $server)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Server->boot()", parameter => "server" }});
		return(1);
	}
	if (not $definition)
	{
		$definition = $anvil->data->{path}{directories}{shared}{definitions}."/".$server.".xml";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { efinition => $definition }});
	}
	
	# Is this a local call or a remote call?
	my ($output, $return_code) = $anvil->System->call({
		debug      => $debug, 
		shell_call => $anvil->data->{path}{exe}{virsh}." create ".$definition,
	});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		output      => $output,
		return_code => $return_code,
	}});
	
	# Wait up to five seconds for the server to appear.
	my $wait = 5;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'wait' => $wait }});
	while($wait)
	{
		$anvil->Server->find({debug => $debug});
		if ((exists $anvil->data->{server}{location}{$server}) && ($anvil->data->{server}{location}{$server}{host}))
		{
			# Success!
			$wait    = 0;
			$success = 1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				'wait'  => $wait,
				success => $success, 
			}});
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0421", variables => { 
				server => $server, 
				host   => $anvil->data->{server}{location}{$server}{host},
			}});
		}
		
		if ($wait)
		{
			$wait--;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'wait' => $wait }});
			sleep 1;
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { success => $success }});
	return($success);
}

=head2 find

This will look on the local or a remote machine for the list of servers that are running. 

The list is stored as; 

 server::location::<server>::status = <status>
 server::location::<server>::host   = <hostname>

Parameters;

=head3 password (optional)

This is the password to use when connecting to a remote machine. If not set, but C<< target >> is, an attempt to connect without a password will be made.

=head3 port (optional)

This is the TCP port to use when connecting to a remote machine. If not set, but C<< target >> is, C<< 22 >> will be used.

=head3 remote_user (optional, default 'root')

If C<< target >> is set, this will be the user we connect to the remote machine as.

=head3 target (optional)

This is the IP or host name of the machine to read the version of. If this is not set, the local system's version is checked.

=cut
sub find
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	my $password    = defined $parameter->{password}    ? $parameter->{password}    : "";
	my $port        = defined $parameter->{port}        ? $parameter->{port}        : "";
	my $remote_user = defined $parameter->{remote_user} ? $parameter->{remote_user} : "root";
	my $target      = defined $parameter->{target}      ? $parameter->{target}      : "local";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		password    => $anvil->Log->secure ? $password : $anvil->Words->string({key => "log_0186"}),
		port        => $port, 
		remote_user => $remote_user, 
		target      => $target, 
	}});
	
	# Clear any old data
	if (exists $anvil->data->{server}{location})
	{
		delete $anvil->data->{server}{location};
	}
	
	my $host_type    = $anvil->System->get_host_type({debug => $debug});
	my $host         = $anvil->_hostname;
	my $virsh_output = "";
	my $return_code  = "";
	if (($target) && ($target ne "local") && ($target ne $anvil->_hostname) && ($target ne $anvil->_short_hostname))
	{
		# Remote call.
		($host, my $error, my $host_return_code) = $anvil->Remote->call({
			debug       => 2, 
			password    => $password, 
			shell_call  => $anvil->data->{path}{exe}{hostnamectl}." --static", 
			target      => $target,
			remote_user => "root", 
		});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			host             => $host,
			error            => $error,
			host_return_code => $host_return_code, 
		}});
		($virsh_output, $error, $return_code) = $anvil->Remote->call({
			debug       => 2, 
			password    => $password, 
			shell_call  => $anvil->data->{path}{exe}{virsh}." list --all", 
			target      => $target,
			remote_user => "root", 
		});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			virsh_output => $virsh_output,
			error        => $error,
			return_code  => $return_code, 
		}});
	}
	else
	{
		($virsh_output, my $return_code) = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{virsh}." list --all"});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			virsh_output => $virsh_output,
			return_code  => $return_code,
		}});
	}
	
	foreach my $line (split/\n/, $virsh_output)
	{
		$line = $anvil->Words->clean_spaces({string => $line});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { line => $line }});
		
		if ($line =~ /^\d+ (.*) (.*?)$/)
		{
			my $server                                           = $1;
			   $anvil->data->{server}{location}{$server}{status} = $2;
			   $anvil->data->{server}{location}{$server}{host}   = $host;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::location::${server}::status" => $anvil->data->{server}{location}{$server}{status}, 
				"server::location::${server}::host"   => $anvil->data->{server}{location}{$server}{host}, 
			}});
		}
	}
	
	return(0);
}

=head2 get_status

This reads in a server's XML definition file from disk, if available, and from memory, if the server is running. The XML is analyzed and data is stored under 'server::<server_name>::from_disk::x' for data from the on-disk XML and 'server::<server_name>::from_memory::x'. 

Any pre-existing data on the server is flushed before the new information is processed.

Parameters;

=head3 password (optional)

This is the password to use when connecting to a remote machine. If not set, but C<< target >> is, an attempt to connect without a password will be made.

=head3 port (optional)

This is the TCP port to use when connecting to a remote machine. If not set, but C<< target >> is, C<< 22 >> will be used.

=head3 remote_user (optional, default 'root')

If C<< target >> is set, this will be the user we connect to the remote machine as.

=head3 server (required)

This is the name of the server we're gathering data on.

=head3 target (optional)

This is the IP or host name of the machine to read the version of. If this is not set, the local system's version is checked.

=cut
sub get_status
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	my $password    = defined $parameter->{password}    ? $parameter->{password}    : "";
	my $port        = defined $parameter->{port}        ? $parameter->{port}        : "";
	my $remote_user = defined $parameter->{remote_user} ? $parameter->{remote_user} : "root";
	my $server      = defined $parameter->{server}      ? $parameter->{server}      : "";
	my $target      = defined $parameter->{target}      ? $parameter->{target}      : "local";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		password    => $anvil->Log->secure ? $password : $anvil->Words->string({key => "log_0186"}),
		port        => $port, 
		remote_user => $remote_user, 
		target      => $target, 
	}});
	
	if (not $server)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Server->get_status()", parameter => "server" }});
		return(1);
	}
	if (exists $anvil->data->{server}{$server})
	{
		delete $anvil->data->{server}{$server};
	}
	$anvil->data->{server}{$server}{from_memory}{host} = "";
	
	# We're going to map DRBD devices to resources, so we need to collect that data now. 
	$anvil->DRBD->get_devices({
		debug       => $debug,
		password    => $password,
		port        => $port, 
		remote_user => $remote_user, 
		target      => $target, 
	});
	
	# Is this a local call or a remote call?
	my $shell_call = $anvil->data->{path}{exe}{virsh}." dumpxml ".$server;
	my $host       = $anvil->_short_hostname;
	if (($target) && ($target ne "local") && ($target ne $anvil->_hostname) && ($target ne $anvil->_short_hostname))
	{
		# Remote call.
		$host = $target;
		($anvil->data->{server}{$server}{from_memory}{xml}, my $error, $anvil->data->{server}{$server}{from_memory}{return_code}) = $anvil->Remote->call({
			debug       => $debug, 
			shell_call  => $shell_call, 
			target      => $target,
			port        => $port, 
			password    => $password,
			remote_user => $remote_user, 
		});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			error                                     => $error,
			"server::${server}::from_memory::xml"         => $anvil->data->{server}{$server}{from_memory}{xml},
			"server::${server}::from_memory::return_code" => $anvil->data->{server}{$server}{from_memory}{return_code},
		}});
	}
	else
	{
		# Local.
		($anvil->data->{server}{$server}{from_memory}{xml}, $anvil->data->{server}{$server}{from_memory}{return_code}) = $anvil->System->call({shell_call => $shell_call});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			"server::${server}::from_memory::xml"         => $anvil->data->{server}{$server}{from_memory}{xml},
			"server::${server}::from_memory::return_code" => $anvil->data->{server}{$server}{from_memory}{return_code},
		}});
	}
	
	# If the return code was non-zero, we can't parse the XML.
	if ($anvil->data->{server}{$server}{from_memory}{return_code})
	{
		$anvil->data->{server}{$server}{from_memory}{xml} = "";
	}
	else
	{
		$anvil->data->{server}{$server}{from_memory}{host} = $host;
		$anvil->Server->_parse_definition({
			debug      => $debug,
			host       => $host,
			server     => $server, 
			source     => "from_memory",
			definition => $anvil->data->{server}{$server}{from_memory}{xml}, 
		});
	}
	
	# Now get the on-disk XML.
	($anvil->data->{server}{$server}{from_disk}{xml}) = $anvil->Storage->read_file({
		debug       => $debug, 
		password    => $password,
		port        => $port, 
		remote_user => $remote_user, 
		target      => $target, 
		force_read  => 1,
		file        => $anvil->data->{path}{directories}{shared}{definitions}."/".$server.".xml",
	});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		"server::${server}::from_disk::xml" => $anvil->data->{server}{$server}{from_disk}{xml},
	}});
	if (($anvil->data->{server}{$server}{from_disk}{xml} eq "!!errer!!") or (not $anvil->data->{server}{$server}{from_disk}{xml}))
	{
		# Failed to read it.
		$anvil->data->{server}{$server}{from_disk}{xml} = "";
	}
	else
	{
		$anvil->Server->_parse_definition({
			debug      => $debug,
			host       => $host,
			server     => $server, 
			source     => "from_disk",
			definition => $anvil->data->{server}{$server}{from_disk}{xml}, 
		});
	}
	
	return(0);
}

=head2 shutdown

This takes a server name and tries to shut it down. If the server was found locally, the shut down is requested and this method will wait for the server to actually shut down before returning.

If shut down, C<< 1 >> is returned. If the server wasn't found or another problem occurs, C<< 0 >> is returned.

 my ($shutdown) = $anvil->Server->shutdown({server => "test_server"});

Parameters;

=head3 force (optional, default '0')

Normally, a graceful shutdown is requested. This requires that the guest respond to ACPI power button events. If the guest won't respond, or for some other reason you want to immediately force the server off, set this to C<< 1 >>.

B<WARNING>: Setting this to C<< 1 >> results in the immediate shutdown of the server! Same as if you pulled the power out of a traditional machine.

=head3 server (required)

This is the name of the server (as it appears in C<< virsh >>) to shut down.

=head3 wait (optional, default '0')

By default, this method will wait indefinetly for the server to shut down before returning. If this is set to a non-zero number, the method will wait that number of seconds for the server to shut dwwn. If the server is still not off by then, C<< 0 >> is returned.

=cut
sub shutdown
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	my $server = defined $parameter->{server} ? $parameter->{server} : "";
	my $force  = defined $parameter->{force}  ? $parameter->{force}  : 0;
	my $wait   = defined $parameter->{'wait'} ? $parameter->{'wait'} : 0;
	my $success = 0;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		force  => $force, 
		server => $server, 
	}});
	
	if (not $server)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Server->shutdown()", parameter => "server" }});
		return($success);
	}
	if (($wait) && ($wait =~ /\D/))
	{
		# Bad value.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0422", variables => { server => $server, 'wait' => $wait }});
		return($success);
	}
	
	# Is the server running? 
	$anvil->Server->find({debug => $debug});
	
	# And?
	if (exists $anvil->data->{server}{location}{$server})
	{
		my $shutdown = 1;
		my $status   = $anvil->data->{server}{location}{$server}{status};
		my $task     = "shutdown";
		if ($force)
		{
			$task = "destroy";
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, key => "log_0424", variables => { server => $server }});
		}
		else
		{
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0425", variables => { server => $server }});
		}
		if ($status eq "shut off")
		{
			# Already off. 
			$success = 1;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0423", variables => { server => $server }});
			return($success);
		}
		elsif ($status eq "paused")
		{
			# The server is paused. Resume it, wait a few, then proceed with the shutdown.
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 2, key => "log_0314", variables => { server => $server }});
			my ($output, $return_code) = $anvil->System->call({shell_call =>  $anvil->data->{path}{exe}{virsh}." resume $server"});
			if ($return_code)
			{
				# Looks like virsh isn't running.
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 0, priority => "err", key => "log_0315", variables => { 
					server      => $server,
					return_code => $return_code, 
					output      => $output, 
				}});
				$anvil->nice_exit({exit_code => 1});
			}
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 2, key => "log_0316"});
			sleep 3;
		}
		elsif ($status eq "pmsuspended")
		{
			# The server is suspended. Resume it, wait a few, then proceed with the shutdown.
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 2, key => "log_0317", variables => { server => $server }});
			my ($output, $return_code) = $anvil->System->call({shell_call =>  $anvil->data->{path}{exe}{virsh}." dompmwakeup $server"});
			if ($return_code)
			{
				# Looks like virsh isn't running.
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 0, priority => "err", key => "log_0318", variables => { 
					server      => $server,
					return_code => $return_code, 
					output      => $output, 
				}});
				$anvil->nice_exit({exit_code => 1});
			}
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 2, key => "log_0319"});
			sleep 30;
		}
		elsif (($status eq "idle") or ($status eq "crashed"))
		{
			# The server needs to be destroyed.
			$task = "destroy";
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 2, key => "log_0322", variables => { 
				server => $server,
				status => $status, 
			}});
		}
		elsif ($status eq "in shutdown")
		{
			# The server is already shutting down
			$shutdown = 0;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 2, key => "log_0320", variables => { server => $server }});
		}
		elsif ($status ne "running")
		{
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 0, priority => "err", key => "log_0325", variables => { 
				server => $server,
				status => $status, 
			}});
			return($success);
		}
		
		# Shut it down.
		if ($shutdown)
		{
			my ($output, $return_code) = $anvil->System->call({
				debug      => $debug, 
				shell_call => $anvil->data->{path}{exe}{virsh}." ".$task." ".$server,
			});
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				output      => $output,
				return_code => $return_code,
			}});
		}
	}
	else
	{
		# Server wasn't found, assume it's off.
		$success = 1;
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0423", variables => { server => $server }});
		return($success);
	}
	
	# Wait indefinetely for the server to exit.
	my $stop_waiting = 0;
	if ($wait)
	{
		$stop_waiting = time + $wait;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { stop_waiting => $stop_waiting }});
	};
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 'wait' => $wait }});
	until($success)
	{
		# Update
		$anvil->Server->find({debug => $debug});
		if ((exists $anvil->data->{server}{location}{$server}) && ($anvil->data->{server}{location}{$server}{status}))
		{
			my $status = $anvil->data->{server}{location}{$server}{status};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { status => $status }});
			
			if ($status eq "shut off")
			{
				# Success! It should be undefined, but we're not the place to worry about 
				# that.
				$success = 1;
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0426", variables => { server => $server }});
			}
		}
		else
		{
			# Success!
			$success = 1;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0426", variables => { server => $server }});
		}
		
		if (($stop_waiting) && (time > $stop_waiting))
		{
			# Give up waiting.
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0427", variables => { 
				server => $server,
				'wait' => $wait,
			}});
		}
		else
		{
			# Sleep a second and then try again.
			sleep 1;
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { success => $success }});
	return($success);
}

=head2 migrate

This will migrate (push or pull) a server from one node to another. If the migration was successful, C<< 1 >> is returned. Otherwise, C<< 0 >> is returned with a (hopefully) useful error being logged.

NOTE: It is assumed that sanity checks are completed before this method is called.

Parameters;

=head3 server (required)

This is the name of the server being migrated.

=head3 source (optional)

This is the host name (or IP) of the host that we're pulling the server from.

If set, the server will be pulled.

=head3 target (optional, defaukt is the full local hostname)

This is the host name (or IP) Of the host that the server will be pushed to, if C<< source >> is not set. When this is not passed, the local full host name is used as default.

=cut
sub migrate
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	my $server  = defined $parameter->{server} ? $parameter->{server} : "";
	my $source  = defined $parameter->{source} ? $parameter->{source} : "";
	my $target  = defined $parameter->{target} ? $parameter->{target} : $anvil->_hostname;
	my $success = 0;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		server => $server, 
		source => $source, 
		target => $target, 
	}});
	
	if (not $server)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Server->migrate()", parameter => "server" }});
		return($success);
	}
	
	# Enable dual-primary for any resources we know about for this server.
	foreach my $resource (sort {$a cmp $b} keys %{$anvil->data->{server}{$server}{resource}})
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { resource => $resource }});
		my ($return_code) = $anvil->DRBD->allow_two_primaries({
			debug    => $debug, 
			resource => $resource, 
		});
	}

	my $migration_command = $anvil->data->{path}{exe}{virsh}." migrate --undefinesource --tunnelled --p2p --live ".$server." qemu+ssh://".$target."/system";
	if ($source)
	{
		$migration_command = $anvil->data->{path}{exe}{virsh}." -c qemu+ssh://root\@".$source."/system migrate --undefinesource --tunnelled --p2p --live ".$server." qemu+ssh://".$target."/system";
	}
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { migration_command => $migration_command }});
	
	# Call the migration now
	my ($output, $return_code) = $anvil->System->call({shell_call => $migration_command});
	if ($return_code)
	{
		# Something went wrong.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 0, priority => "err", key => "log_0353", variables => { 
			server      => $server, 
			target      => $target, 
			return_code => $return_code, 
			output      => $output, 
		}});
	}
	else
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, 'print' => 1, level => 2, key => "log_0354"});
		
		$success = 1;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { success => $success }});
	}
	
	# Switch off dual-primary.
	foreach my $resource (sort {$a cmp $b} keys %{$anvil->data->{server}{$server}{resource}})
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { resource => $resource }});
		$anvil->DRBD->reload_defaults({
			debug    => $debug, 
			resource => $resource, 
		});
	}
	
	return($success);
}

# =head3
# 
# Private Functions;
# 
# =cut

#############################################################################################################
# Private functions                                                                                         #
#############################################################################################################

### NOTE: This is a work in progress. As of now, it parses out what ocf:alteeve:server needs.
# This pulls apart specific data out of a definition file. 
sub _parse_definition
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	# Source is required.
	my $server     = defined $parameter->{server}     ? $parameter->{server}     : "";
	my $source     = defined $parameter->{source}     ? $parameter->{source}     : "";
	my $definition = defined $parameter->{definition} ? $parameter->{definition} : "";
	my $host       = defined $parameter->{host}       ? $parameter->{host}       : $anvil->_short_hostname;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		server     => $server,
		source     => $source, 
		definition => $definition, 
		host       => $host, 
	}});
	
	if (not $server)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Server->_parse_definition()", parameter => "server" }});
		return(1);
	}
	if (not $source)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Server->_parse_definition()", parameter => "source" }});
		return(1);
	}
	if (not $definition)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Server->_parse_definition()", parameter => "definition" }});
		return(1);
	}
	
	my $xml        = XML::Simple->new();
	my $server_xml = "";
	eval { $server_xml = $xml->XMLin($definition, KeyAttr => {}, ForceArray => 1) };
	if ($@)
	{
		chomp $@;
		my $error =  "[ Error ] - The was a problem parsing: [$definition]. The error was:\n";
		   $error .= "===========================================================\n";
		   $error .= $@."\n";
		   $error .= "===========================================================\n";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", list => { error => $error }});
		$anvil->nice_exit({exit_code => 1});
	}
	
	$anvil->data->{server}{$server}{$source}{parsed} = $server_xml;
	#print Dumper $server_xml;
	#die;
	
	# Pull out some basic server info.
	$anvil->data->{server}{$server}{$source}{info}{uuid}         = $server_xml->{uuid}->[0];
	$anvil->data->{server}{$server}{$source}{info}{name}         = $server_xml->{name}->[0];
	$anvil->data->{server}{$server}{$source}{info}{on_poweroff}  = $server_xml->{on_poweroff}->[0];
	$anvil->data->{server}{$server}{$source}{info}{on_crash}     = $server_xml->{on_crash}->[0];
	$anvil->data->{server}{$server}{$source}{info}{on_reboot}    = $server_xml->{on_reboot}->[0];
	$anvil->data->{server}{$server}{$source}{info}{boot_menu}    = $server_xml->{os}->[0]->{bootmenu}->[0]->{enable};
	$anvil->data->{server}{$server}{$source}{info}{architecture} = $server_xml->{os}->[0]->{type}->[0]->{arch};
	$anvil->data->{server}{$server}{$source}{info}{machine}      = $server_xml->{os}->[0]->{type}->[0]->{machine};
	$anvil->data->{server}{$server}{$source}{info}{id}           = exists $server_xml->{id} ? $server_xml->{id} : 0;
	$anvil->data->{server}{$server}{$source}{info}{emulator}     = $server_xml->{devices}->[0]->{emulator}->[0];
	$anvil->data->{server}{$server}{$source}{info}{acpi}         = exists $server_xml->{features}->[0]->{acpi} ? 1 : 0;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		"server::${server}::${source}::info::uuid"         => $anvil->data->{server}{$server}{$source}{info}{uuid},
		"server::${server}::${source}::info::name"         => $anvil->data->{server}{$server}{$source}{info}{name},
		"server::${server}::${source}::info::on_poweroff"  => $anvil->data->{server}{$server}{$source}{info}{on_poweroff},
		"server::${server}::${source}::info::on_crash"     => $anvil->data->{server}{$server}{$source}{info}{on_crash},
		"server::${server}::${source}::info::on_reboot"    => $anvil->data->{server}{$server}{$source}{info}{on_reboot},
		"server::${server}::${source}::info::architecture" => $anvil->data->{server}{$server}{$source}{info}{architecture},
		"server::${server}::${source}::info::machine"      => $anvil->data->{server}{$server}{$source}{info}{machine},
		"server::${server}::${source}::info::boot_menu"    => $anvil->data->{server}{$server}{$source}{info}{boot_menu},
		"server::${server}::${source}::info::id"           => $anvil->data->{server}{$server}{$source}{info}{id},
		"server::${server}::${source}::info::emulator"     => $anvil->data->{server}{$server}{$source}{info}{emulator},
		"server::${server}::${source}::info::acpi"         => $anvil->data->{server}{$server}{$source}{info}{acpi},
	}});
	
	# CPU
	$anvil->data->{server}{$server}{$source}{cpu}{total_cores}    = $server_xml->{vcpu}->[0]->{content};
	$anvil->data->{server}{$server}{$source}{cpu}{sockets}        = $server_xml->{cpu}->[0]->{topology}->[0]->{sockets};
	$anvil->data->{server}{$server}{$source}{cpu}{cores}          = $server_xml->{cpu}->[0]->{topology}->[0]->{cores};
	$anvil->data->{server}{$server}{$source}{cpu}{threads}        = $server_xml->{cpu}->[0]->{topology}->[0]->{threads};
	$anvil->data->{server}{$server}{$source}{cpu}{model_name}     = $server_xml->{cpu}->[0]->{model}->[0]->{content};
	$anvil->data->{server}{$server}{$source}{cpu}{model_fallback} = $server_xml->{cpu}->[0]->{model}->[0]->{fallback};
	$anvil->data->{server}{$server}{$source}{cpu}{match}          = $server_xml->{cpu}->[0]->{match};
	$anvil->data->{server}{$server}{$source}{cpu}{vendor}         = $server_xml->{cpu}->[0]->{vendor}->[0];
	$anvil->data->{server}{$server}{$source}{cpu}{mode}           = $server_xml->{cpu}->[0]->{mode};
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		"server::${server}::${source}::cpu::total_cores"    => $anvil->data->{server}{$server}{$source}{cpu}{total_cores},
		"server::${server}::${source}::cpu::sockets"        => $anvil->data->{server}{$server}{$source}{cpu}{sockets},
		"server::${server}::${source}::cpu::cores"          => $anvil->data->{server}{$server}{$source}{cpu}{cores},
		"server::${server}::${source}::cpu::threads"        => $anvil->data->{server}{$server}{$source}{cpu}{threads},
		"server::${server}::${source}::cpu::model_name"     => $anvil->data->{server}{$server}{$source}{cpu}{model_name},
		"server::${server}::${source}::cpu::model_fallback" => $anvil->data->{server}{$server}{$source}{cpu}{model_fallback},
		"server::${server}::${source}::cpu::match"          => $anvil->data->{server}{$server}{$source}{cpu}{match},
		"server::${server}::${source}::cpu::vendor"         => $anvil->data->{server}{$server}{$source}{cpu}{vendor},
		"server::${server}::${source}::cpu::mode"           => $anvil->data->{server}{$server}{$source}{cpu}{mode},
	}});
	foreach my $hash_ref (@{$server_xml->{cpu}->[0]->{feature}})
	{
		my $name                                                         = $hash_ref->{name};
		   $anvil->data->{server}{$server}{$source}{cpu}{feature}{$name} = $hash_ref->{policy};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			"server::${server}::${source}::cpu::feature::${name}" => $anvil->data->{server}{$server}{$source}{cpu}{feature}{$name},
		}});
		
	}
	
	# Power Management
	$anvil->data->{server}{$server}{$source}{pm}{'suspend-to-disk'} = $server_xml->{pm}->[0]->{'suspend-to-disk'}->[0]->{enabled};
	$anvil->data->{server}{$server}{$source}{pm}{'suspend-to-mem'}  = $server_xml->{pm}->[0]->{'suspend-to-mem'}->[0]->{enabled};
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		"server::${server}::${source}::pm::suspend-to-disk" => $anvil->data->{server}{$server}{$source}{pm}{'suspend-to-disk'},
		"server::${server}::${source}::pm::suspend-to-mem"  => $anvil->data->{server}{$server}{$source}{pm}{'suspend-to-mem'},
	}});
	
	# RAM - 'memory' is as set at boot, 'currentMemory' is the RAM used at polling (so only useful when 
	#       running). In the Anvil!, we don't support memory ballooning, so we're use whichever is 
	#       higher.
	my $current_ram_value = $server_xml->{currentMemory}->[0]->{content};
	my $current_ram_unit  = $server_xml->{currentMemory}->[0]->{unit};
	my $current_ram_bytes = $anvil->Convert->human_readable_to_bytes({size => $current_ram_value, type => $current_ram_unit});
	my $ram_value         = $server_xml->{memory}->[0]->{content};
	my $ram_unit          = $server_xml->{memory}->[0]->{unit};
	my $ram_bytes         = $anvil->Convert->human_readable_to_bytes({size => $ram_value, type => $ram_unit});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		current_ram_value => $current_ram_value,
		current_ram_unit  => $current_ram_unit,
		current_ram_bytes => $anvil->Convert->add_commas({number => $current_ram_bytes})." (".$anvil->Convert->bytes_to_human_readable({'bytes' => $current_ram_bytes}).")",
		ram_value         => $ram_value,
		ram_unit          => $ram_unit,
		ram_bytes         => $anvil->Convert->add_commas({number => $ram_bytes})." (".$anvil->Convert->bytes_to_human_readable({'bytes' => $ram_bytes}).")",
	}});
	
	$anvil->data->{server}{$server}{$source}{memory} = $current_ram_bytes > $ram_bytes ? $current_ram_bytes : $ram_bytes;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		"server::${server}::${source}::memory" => $anvil->Convert->add_commas({number => $anvil->data->{server}{$server}{$source}{memory}})." (".$anvil->Convert->bytes_to_human_readable({'bytes' => $anvil->data->{server}{$server}{$source}{memory}}).")",
	}});
	
	# Clock info
	$anvil->data->{server}{$server}{$source}{clock}{offset} = $server_xml->{clock}->[0]->{offset};
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		"server::${server}::${source}::clock::offset" => $anvil->data->{server}{$server}{$source}{clock}{offset},
	}});
	foreach my $hash_ref (@{$server_xml->{clock}->[0]->{timer}})
	{
		my $name = $hash_ref->{name};
		foreach my $variable (keys %{$hash_ref})
		{
			next if $variable eq "name";
			$anvil->data->{server}{$server}{$source}{clock}{$name}{$variable} = $hash_ref->{$variable};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::clock::${name}::${variable}" => $anvil->data->{server}{$server}{$source}{clock}{$name}{$variable},
			}});
		}
	}
	
	# Pull out my channels
	foreach my $hash_ref (@{$server_xml->{devices}->[0]->{channel}})
	{
		my $type = $hash_ref->{type};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { type => $type }});
		if ($type eq "unix")
		{
			# Bus stuff
			my $address_type       = $hash_ref->{address}->[0]->{type};
			my $address_controller = $hash_ref->{address}->[0]->{controller};
			my $address_bus        = $hash_ref->{address}->[0]->{bus};
			my $address_port       = $hash_ref->{address}->[0]->{port};
			
			# Store
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{source}{mode}        = defined $hash_ref->{source}->[0]->{mode} ? $hash_ref->{source}->[0]->{mode} : "";
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{source}{path}        = defined $hash_ref->{source}->[0]->{path} ? $hash_ref->{source}->[0]->{path} : "";
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{alias}               = defined $hash_ref->{alias}->[0]->{name}  ? $hash_ref->{alias}->[0]->{name}  : "";
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{type}       = $address_type;
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{bus}        = $address_bus;
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{controller} = $address_controller;
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{port}       = $address_port;
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{target}{type}        = $hash_ref->{target}->[0]->{type};
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{target}{'state'}     = defined $hash_ref->{target}->[0]->{'state'} ? $hash_ref->{target}->[0]->{'state'} : "";
			$anvil->data->{server}{$server}{$source}{device}{channel}{unix}{target}{name}        = $hash_ref->{target}->[0]->{name};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::channel::unix::source::mode"        => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{source}{mode},
				"server::${server}::${source}::device::channel::unix::source::path"        => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{source}{path},
				"server::${server}::${source}::device::channel::unix::alias"               => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{alias},
				"server::${server}::${source}::device::channel::unix::address::type"       => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{type},
				"server::${server}::${source}::device::channel::unix::address::bus"        => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{bus},
				"server::${server}::${source}::device::channel::unix::address::controller" => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{controller},
				"server::${server}::${source}::device::channel::unix::address::port"       => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{address}{port},
				"server::${server}::${source}::device::channel::unix::target::type"        => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{target}{type},
				"server::${server}::${source}::device::channel::unix::target::state"       => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{target}{'state'},
				"server::${server}::${source}::device::channel::unix::target::name"        => $anvil->data->{server}{$server}{$source}{device}{channel}{unix}{target}{name},
			}});
			
			### TODO: Store the parts in some format that allows representing it better to the user and easier to find "open slots".
			# Add to system bus list
# 			$anvil->data->{server}{$server}{$source}{address}{$address_type}{controller}{$address_controller}{bus}{$address_bus}{port}{$address_port} = "channel - ".$type;
# 			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
# 				"server::${server}::${source}::address::${address_type}::controller::${address_controller}::bus::${address_bus}::port::${address_port}" => $anvil->data->{server}{$server}{$source}{address}{$address_type}{controller}{$address_controller}{bus}{$address_bus}{port}{$address_port},
# 			}});
		}
		elsif ($type eq "spicevmc")
		{
			# Bus stuff
			my $address_type       = $hash_ref->{address}->[0]->{type};
			my $address_controller = $hash_ref->{address}->[0]->{controller};
			my $address_bus        = $hash_ref->{address}->[0]->{bus};
			my $address_port       = $hash_ref->{address}->[0]->{port};
			
			# Store
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{alias}               = defined $hash_ref->{alias}->[0]->{name} ? $hash_ref->{alias}->[0]->{name} : "";
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{type}       = $address_type;
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{bus}        = $address_bus;
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{controller} = $address_controller;
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{port}       = $address_port;
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{target}{type}        = $hash_ref->{target}->[0]->{type};
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{target}{'state'}     = defined $hash_ref->{target}->[0]->{'state'} ? $hash_ref->{target}->[0]->{'state'} : "";
			$anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{target}{name}        = $hash_ref->{target}->[0]->{name};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::channel::spicevmc::alias"               => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{alias},
				"server::${server}::${source}::device::channel::spicevmc::address::type"       => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{type},
				"server::${server}::${source}::device::channel::spicevmc::address::bus"        => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{bus},
				"server::${server}::${source}::device::channel::spicevmc::address::controller" => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{controller},
				"server::${server}::${source}::device::channel::spicevmc::address::port"       => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{address}{port},
				"server::${server}::${source}::device::channel::spicevmc::target::type"        => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{target}{type},
				"server::${server}::${source}::device::channel::spicevmc::target::state"       => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{target}{'state'},
				"server::${server}::${source}::device::channel::spicevmc::target::name"        => $anvil->data->{server}{$server}{$source}{device}{channel}{spicevmc}{target}{name},
			}});
			
			### TODO: Store the parts in some format that allows representing it better to the user and easier to find "open slots".
			# Add to system bus list
# 			$anvil->data->{server}{$server}{$source}{address}{$address_type}{controller}{$address_controller}{bus}{$address_bus}{port}{$address_port} = "channel - ".$type;
# 			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
# 				"server::${server}::${source}::address::${address_type}::controller::${address_controller}::bus::${address_bus}::port::${address_port}" => $anvil->data->{server}{$server}{$source}{address}{$address_type}{controller}{$address_controller}{bus}{$address_bus}{port}{$address_port},
# 			}});
		}
	}
	
	# Pull out console data
	foreach my $hash_ref (@{$server_xml->{devices}->[0]->{console}})
	{
		$anvil->data->{server}{$server}{$source}{device}{console}{type}        = $hash_ref->{type};
		$anvil->data->{server}{$server}{$source}{device}{console}{tty}         = defined $hash_ref->{tty}                 ? $hash_ref->{tty}                 : "";
		$anvil->data->{server}{$server}{$source}{device}{console}{alias}       = defined $hash_ref->{alias}->[0]->{name}  ? $hash_ref->{alias}->[0]->{name}  : "";
		$anvil->data->{server}{$server}{$source}{device}{console}{source}      = defined $hash_ref->{source}->[0]->{path} ? $hash_ref->{source}->[0]->{path} : "";
		$anvil->data->{server}{$server}{$source}{device}{console}{target_type} = $hash_ref->{target}->[0]->{type};
		$anvil->data->{server}{$server}{$source}{device}{console}{target_port} = $hash_ref->{target}->[0]->{port};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			"server::${server}::${source}::device::console::type"        => $anvil->data->{server}{$server}{$source}{device}{console}{type},
			"server::${server}::${source}::device::console::tty"         => $anvil->data->{server}{$server}{$source}{device}{console}{tty},
			"server::${server}::${source}::device::console::alias"       => $anvil->data->{server}{$server}{$source}{device}{console}{alias},
			"server::${server}::${source}::device::console::source"      => $anvil->data->{server}{$server}{$source}{device}{console}{source},
			"server::${server}::${source}::device::console::target_type" => $anvil->data->{server}{$server}{$source}{device}{console}{target_type},
			"server::${server}::${source}::device::console::target_port" => $anvil->data->{server}{$server}{$source}{device}{console}{target_port},
		}});
	}
	
	# Controllers is a big chunk
	foreach my $hash_ref (@{$server_xml->{devices}->[0]->{controller}})
	{
		my $type             = $hash_ref->{type};
		my $index            = $hash_ref->{'index'};
		my $ports            = exists $hash_ref->{ports}                     ? $hash_ref->{ports}                    : "";
		my $target_chassis   = exists $hash_ref->{target}                    ? $hash_ref->{target}->[0]->{chassis}   : "";
		my $target_port      = exists $hash_ref->{target}                    ? $hash_ref->{target}->[0]->{port}      : "";
		my $address_type     = defined $hash_ref->{address}->[0]->{type}     ? $hash_ref->{address}->[0]->{type}     : "";
		my $address_domain   = defined $hash_ref->{address}->[0]->{domain}   ? $hash_ref->{address}->[0]->{domain}   : "";
		my $address_bus      = defined $hash_ref->{address}->[0]->{bus}      ? $hash_ref->{address}->[0]->{bus}      : "";
		my $address_slot     = defined $hash_ref->{address}->[0]->{slot}     ? $hash_ref->{address}->[0]->{slot}     : "";
		my $address_function = defined $hash_ref->{address}->[0]->{function} ? $hash_ref->{address}->[0]->{function} : "";
		
		# Model is weird, it can be at '$hash_ref->{model}->[X]' or '$hash_ref->{model}->[Y]->{name}'
		# as 'model' is both an attribute and a child element.
		$hash_ref->{model} = "" if not defined $hash_ref->{model};
		my $model = "";
		if (not ref($hash_ref->{model}))
		{
			$model = $hash_ref->{model};
		}
		else
		{
			foreach my $entry (@{$hash_ref->{model}})
			{
				if (ref($entry))
				{
					$model = $entry->{name} if $entry->{name};
				}
				else
				{
					$model = $entry if $entry;
				}
			}
		}
		
		# Store the data
		$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{alias} = defined $hash_ref->{alias}->[0]->{name} ? $hash_ref->{alias}->[0]->{name} : "";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			"server::${server}::${source}::device::controller::${type}::index::${index}::alias" => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{alias},
		}});
		if ($model)
		{
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{model} = $model;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::controller::${type}::index::${index}::model" => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{model},
			}});
		}
		if ($ports)
		{
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{ports} = $ports;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::controller::${type}::index::${index}::ports" => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{ports},
			}});
		}
		if ($target_chassis)
		{
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{target}{chassis} = $target_chassis;
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{target}{port}    = $target_port;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::controller::${type}::index::${index}::target::chassis" => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{target}{chassis},
				"server::${server}::${source}::device::controller::${type}::index::${index}::target::port"    => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{target}{port},
			}});
		}
		if ($address_type)
		{
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{type}     = $address_type;
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{domain}   = $address_domain;
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{bus}      = $address_bus;
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{slot}     = $address_slot;
			$anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{function} = $address_function;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::controller::${type}::index::${index}::address::type"     => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{type},
				"server::${server}::${source}::device::controller::${type}::index::${index}::address::domain"   => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{domain},
				"server::${server}::${source}::device::controller::${type}::index::${index}::address::bus"      => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{bus},
				"server::${server}::${source}::device::controller::${type}::index::${index}::address::slot"     => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{slot},
				"server::${server}::${source}::device::controller::${type}::index::${index}::address::function" => $anvil->data->{server}{$server}{$source}{device}{controller}{$type}{'index'}{$index}{address}{function},
			}});
			
			### TODO: Store the parts in some format that allows representing it better to the user and easier to find "open slots".
			# Add to system bus list
			# Controller type: [pci], alias: (pci.2), index: [2]
			# - Model: [pcie-root-port]
			# - Target chassis: [2], port: [0x11]
			# - Bus type: [pci], domain: [0x0000], bus: [0x00], slot: [0x02], function: [0x1]
			#      server::test_server::from_memory::address::virtio-serial::controller::0::bus::0::port::2: [channel - spicevmc]
# 			$anvil->data->{server}{$server}{$source}{address}{$address_type}{controller}{$type}{bus}{$address_bus}{bus}{$address_bus}{slot}{$address_slot}{function}{$address_function}{domain} = $address_domain;
# 			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
# 				"server::${server}::${source}::address::${address_type}::controller::${type}::bus::${address_bus}::slot::${address_slot}::function::${address_function}::domain" => $anvil->data->{server}{$server}{$source}{address}{$address_type}{controller}{$type}{bus}{$address_bus}{bus}{$address_bus}{slot}{$address_slot}{function}{$address_function}{domain},
# 			}});
		}
	}
	
	# Find what drives (disk and "optical") this server uses.
	foreach my $hash_ref (@{$server_xml->{devices}->[0]->{disk}})
	{
		#print Dumper $hash_ref;
		my $device        = $hash_ref->{device};
		my $device_target = $hash_ref->{target}->[0]->{dev};
		my $type          = defined $hash_ref->{type}                 ? $hash_ref->{type}                 : "";
		my $alias         = defined $hash_ref->{alias}->[0]->{name}   ? $hash_ref->{alias}->[0]->{name}   : "";
		my $device_bus    = defined $hash_ref->{target}->[0]->{bus}   ? $hash_ref->{target}->[0]->{bus}   : "";
		my $address_type  = defined $hash_ref->{address}->[0]->{type} ? $hash_ref->{address}->[0]->{type} : "";
		my $address_bus   = defined $hash_ref->{address}->[0]->{bus}  ? $hash_ref->{address}->[0]->{bus}  : "";
		my $boot_order    = defined $hash_ref->{boot}->[0]->{order}   ? $hash_ref->{boot}->[0]->{order}   : 99;
		my $driver_name   = defined $hash_ref->{driver}->[0]->{name}  ? $hash_ref->{driver}->[0]->{name}  : "";
		my $driver_type   = defined $hash_ref->{driver}->[0]->{type}  ? $hash_ref->{driver}->[0]->{type}  : "";
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			device        => $device,
			type          => $type,
			alias         => $alias, 
			device_target => $device_target, 
			device_bus    => $device_bus, 
			address_type  => $address_type, 
			address_bus   => $address_bus, 
			boot_order    => $boot_order, 
			driver_name   => $driver_name, 
			driver_type   => $driver_type,
		}});
		
		### NOTE: Live migration won't work unless the '/dev/drbdX' devices are block. If they come 
		###       up as 'file', virsh will refuse to migrate with a lack of shared storage error.
		# A device path can come from 'dev' or 'file'.
		my $device_path = "";
		if (defined $hash_ref->{source}->[0]->{dev})
		{
			$device_path = $hash_ref->{source}->[0]->{dev};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { device_path => $device_path }});
		}
		else
		{
			$device_path = $hash_ref->{source}->[0]->{file};
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { device_path => $device_path }});
		}
		
		# Record common data
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{alias}         = $alias;
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{boot_order}    = $boot_order;
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{type}          = $type;
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{type} = $address_type;
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{bus}  = $address_bus;
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{name}  = $driver_name;
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{device_bus}    = $device_bus;
		$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{type}  = $driver_type;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			"server::${server}::${source}::device::${device}::target::${device_target}::address::type" => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{type},
			"server::${server}::${source}::device::${device}::target::${device_target}::address::bus"  => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{bus},
			"server::${server}::${source}::device::${device}::target::${device_target}::alias"         => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{alias},
			"server::${server}::${source}::device::${device}::target::${device_target}::boot_order"    => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{boot_order},
			"server::${server}::${source}::device::${device}::target::${device_target}::device_bus"    => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{device_bus},
			"server::${server}::${source}::device::${device}::target::${device_target}::driver::name"  => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{name},
			"server::${server}::${source}::device::${device}::target::${device_target}::driver::type"  => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{type},
			"server::${server}::${source}::device::${device}::target::${device_target}::type"          => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{type},
		}});
		
		# Record type-specific data
		if ($device eq "disk")
		{
			my $address_slot     = defined $hash_ref->{address}->[0]->{slot}     ? $hash_ref->{address}->[0]->{slot}     : "";
			my $address_domain   = defined $hash_ref->{address}->[0]->{domain}   ? $hash_ref->{address}->[0]->{domain}   : "";
			my $address_function = defined $hash_ref->{address}->[0]->{function} ? $hash_ref->{address}->[0]->{function} : "";
			my $driver_io        = defined $hash_ref->{driver}->[0]->{io}        ? $hash_ref->{driver}->[0]->{io}        : "";
			my $driver_cache     = defined $hash_ref->{driver}->[0]->{cache}     ? $hash_ref->{driver}->[0]->{cache}     : "";
			
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{domain}   = $address_domain;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{slot}     = $address_slot;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{function} = $address_function;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{path}              = $device_path;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{io}        = $driver_io;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{cache}     = $driver_cache;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::${device}::target::${device_target}::address::domain"   => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{domain},
				"server::${server}::${source}::device::${device}::target::${device_target}::address::slot"     => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{slot},
				"server::${server}::${source}::device::${device}::target::${device_target}::address::function" => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{function},
				"server::${server}::${source}::device::${device}::target::${device_target}::path"              => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{path},
				"server::${server}::${source}::device::${device}::target::${device_target}::driver::io"        => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{io},
				"server::${server}::${source}::device::${device}::target::${device_target}::driver::cache"     => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{driver}{cache},
			}});
			
			my $on_lv    = defined $anvil->data->{drbd}{config}{$host}{drbd_path}{$device_path}{on}       ? $anvil->data->{drbd}{config}{$host}{drbd_path}{$device_path}{on}       : "";
			my $resource = defined $anvil->data->{drbd}{config}{$host}{drbd_path}{$device_path}{resource} ? $anvil->data->{drbd}{config}{$host}{drbd_path}{$device_path}{resource} : "";
			$anvil->data->{server}{$server}{device}{$device_path}{on_lv}    = $on_lv;
			$anvil->data->{server}{$server}{device}{$device_path}{resource} = $resource;
			$anvil->data->{server}{$server}{device}{$device_path}{target}   = $device_target;
			$anvil->data->{server}{$server}{resource}{$resource}            = 1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				host                                                  => $host,
				"server::${server}::device::${device_path}::on_lv"    => $anvil->data->{server}{$server}{device}{$device_path}{on_lv},
				"server::${server}::device::${device_path}::resource" => $anvil->data->{server}{$server}{device}{$device_path}{resource},
				"server::${server}::device::${device_path}::target"   => $anvil->data->{server}{$server}{device}{$device_path}{target},
				"server::${server}::resource::${resource}"            => $anvil->data->{server}{$server}{resource}{$resource}, 
			}});
			
			# Keep a list of DRBD resources used by this server.
			my $drbd_resource                                                  = $anvil->data->{server}{$server}{device}{$device_path}{resource};
			   $anvil->data->{server}{$server}{drbd}{resource}{$drbd_resource} = 1;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::drbd::resource::${drbd_resource}" => $anvil->data->{server}{$server}{drbd}{resource}{$drbd_resource},
			}});
			
			### TODO: Store the parts in some format that allows representing it better to the user and easier to find "open slots".
# 			$anvil->data->{server}{$server}{$source}{address}{$device_bus}{bus}{$address_bus}{bus}{$address_bus}{slot}{$address_slot}{function}{$address_function}{domain} = $address_domain;
# 			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
# 				"server::${server}::${source}::address::${address_type}::controller::${type}::bus::${address_bus}::slot::${address_slot}::function::${address_function}::domain" => $anvil->data->{server}{$server}{$source}{address}{$address_type}{controller}{$type}{bus}{$address_bus}{bus}{$address_bus}{slot}{$address_slot}{function}{$address_function}{domain},
# 			}});
		}
		else
		{
			# Looks like IDE is no longer supported on RHEL 8.
			my $address_controller = $hash_ref->{address}->[0]->{controller};
			my $address_unit       = $hash_ref->{address}->[0]->{unit};
			my $address_target     = $hash_ref->{address}->[0]->{target};
			
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{controller} = $address_controller;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{unit}       = $address_unit;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{target}     = $address_target;
			$anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{path}                = $device_path;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
				"server::${server}::${source}::device::${device}::target::${device_target}::address::controller" => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{controller},
				"server::${server}::${source}::device::${device}::target::${device_target}::address::unit"       => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{unit},
				"server::${server}::${source}::device::${device}::target::${device_target}::address::target"     => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{address}{target},
				"server::${server}::${source}::device::${device}::target::${device_target}::path"                => $anvil->data->{server}{$server}{$source}{device}{$device}{target}{$device_target}{path},
			}});
		
		}
	}
	
	# Pull out console data
	foreach my $hash_ref (@{$server_xml->{devices}->[0]->{interface}})
	{
		#print Dumper $hash_ref;
		my $mac = $hash_ref->{mac}->[0]->{address};
		
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{bridge}            = $hash_ref->{source}->[0]->{bridge};
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{alias}             = defined $hash_ref->{alias}->[0]->{name} ? $hash_ref->{alias}->[0]->{name} : "";
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{target}            = defined $hash_ref->{target}->[0]->{dev} ? $hash_ref->{target}->[0]->{dev} : "";
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{model}             = $hash_ref->{model}->[0]->{type};
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{bus}      = $hash_ref->{address}->[0]->{bus};
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{domain}   = $hash_ref->{address}->[0]->{domain};
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{type}     = $hash_ref->{address}->[0]->{type};
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{slot}     = $hash_ref->{address}->[0]->{slot};
		$anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{function} = $hash_ref->{address}->[0]->{function};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
			"server::${server}::${source}::device::interface::${mac}::bridge"            => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{bridge},
			"server::${server}::${source}::device::interface::${mac}::alias"             => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{alias},
			"server::${server}::${source}::device::interface::${mac}::target"            => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{target},
			"server::${server}::${source}::device::interface::${mac}::model"             => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{model},
			"server::${server}::${source}::device::interface::${mac}::address::bus"      => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{bus},
			"server::${server}::${source}::device::interface::${mac}::address::domain"   => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{domain},
			"server::${server}::${source}::device::interface::${mac}::address::type"     => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{type},
			"server::${server}::${source}::device::interface::${mac}::address::slot"     => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{slot},
			"server::${server}::${source}::device::interface::${mac}::address::function" => $anvil->data->{server}{$server}{$source}{device}{interface}{$mac}{address}{function},
		}});
	}
	
	return(0);
}