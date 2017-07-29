package AN::Tools::Database;
# 
# This module contains methods related to databases.
# 

use strict;
use warnings;
use DBI;
use Data::Dumper;

our $VERSION  = "3.0.0";
my $THIS_FILE = "Database.pm";

### Methods;
# configure_pgsql
# connect
# disconnect
# get_local_id
# initialize
# insert_or_update_states
# insert_or_update_variables
# locking
# mark_active
# query
# read_variable
# write
# _find_behind_database
# _mark_database_as_behind
# _test_access

=pod

=encoding utf8

=head1 NAME

AN::Tools::Database

Provides all methods related to managing and accessing databases.

=head1 SYNOPSIS

 use AN::Tools;

 # Get a common object handle on all AN::Tools modules.
 my $an = AN::Tools->new();
 
 # Access to methods using '$an->Database->X'. 
 # 
 # Example using 'get_local_id()';
 my $local_id = $an->Database->get_local_id;

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

# Get a handle on the AN::Tools object. I know that technically that is a sibling module, but it makes more 
# sense in this case to think of it as a parent.
sub parent
{
	my $self   = shift;
	my $parent = shift;
	
	$self->{HANDLE}{TOOLS} = $parent if $parent;
	
	return ($self->{HANDLE}{TOOLS});
}


#############################################################################################################
# Public methods                                                                                            #
#############################################################################################################

=head2 configure_pgsql

This configures the local database server. Specifically, it checks to make sure the daemon is running and starts it if not. It also checks the 'pg_hba.conf' configuration to make sure it is set properly to listen on this machine's IP addresses and interfaces.

If the system is already configured, this method will do nothing, so it is safe to call it at any time.

If there is a problem, C<< undef >> is returned.

Parameters;

=head3 id (required)

This is the ID of the local database in the local configuration file that will be used to configure the local system.

=cut
sub configure_pgsql
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $id = defined $parameter->{id} ? $parameter->{id} : "";
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { id => $id }});
	
	if (not $id)
	{
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Database->configure_pgsql()", parameter => "id" }});
		return(undef);
	}
	
	# If we're not running with root access, return.
	if (($< != 0) && ($> != 0))
	{
		# This is a minor error as it will be hit by every unpriviledged program that connects to the
		# database(s).
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, priority => "alert", key => "log_0113"});
		return(undef);
	}
	
	# First, is it running?
	my $running = $an->System->check_daemon({daemon => "postgresql"});
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { running => $running }});
	
	if (not $running)
	{
		# Do we need to initialize the databae?
		if (not -e $an->data->{path}{configs}{'pg_hba.conf'})
		{
			# Initialize.
			my $output = $an->System->call({shell_call => $an->data->{path}{exe}{'postgresql-setup'}." initdb", source => $THIS_FILE, line => __LINE__});
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { output => $output }});
			
			# Did it succeed?
			if (not -e $an->data->{path}{configs}{'pg_hba.conf'})
			{
				# Failed... 
				$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0050"});
				return(undef);
			}
			else
			{
				# Initialized!
				$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0055"});
				
				# Enable it on boot.
				my $return_code = $an->System->enable_daemon({daemon => "postgresql"});
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { return_code => $return_code }});
			}
		}
	}
	
	# Setup postgresql.conf, if needed
	my $postgresql_conf        = $an->Storage->read_file({file => $an->data->{path}{configs}{'postgresql.conf'}});
	my $update_postgresql_file = 1;
	my $new_postgresql_conf    = "";
	foreach my $line (split/\n/, $postgresql_conf)
	{
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { line => $line }});
		if ($line =~ /^listen_addresses = '\*'/)
		{
			# No need to update.
			$update_postgresql_file = 0;
			last;
		}
		elsif ($line =~ /^#listen_addresses = 'localhost'/)
		{
			# Inject the new listen_addresses
			$new_postgresql_conf .= "# This has been changed by AN::Tools::Database->configure_pgsql() to enable\n";
			$new_postgresql_conf .= "# listening on all interfaces.\n";
			$new_postgresql_conf .= "#listen_addresses = 'localhost'\n";
			$new_postgresql_conf .= "listen_addresses = '*'\n";
		}
		$new_postgresql_conf .= $line."\n";
	}
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { update_postgresql_file => $update_postgresql_file }});
	if ($update_postgresql_file)
	{
		# Back up the existing one, if needed.
		my $postgresql_backup = $an->data->{path}{directories}{backups}."/pgsql/postgresql.conf";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { postgresql_backup => $postgresql_backup }});
		if (not -e $postgresql_backup)
		{
			$an->Storage->copy_file({source => $an->data->{path}{configs}{'postgresql.conf'}, target => $postgresql_backup});
		}
		
		# Write the updated one.
		$an->Storage->write_file({
			file      => $an->data->{path}{configs}{'postgresql.conf'}, 
			body      => $new_postgresql_conf,
			user      => "postgres", 
			group     => "postgres",
			mode      => "0600",
			overwrite => 1,
		});
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0056", variables => { file => $an->data->{path}{configs}{'postgresql.conf'} }});
	}
	
	# Setup pg_hba.conf now, if needed.
	my $pg_hba_conf        = $an->Storage->read_file({file => $an->data->{path}{configs}{'pg_hba.conf'}});
	my $update_pg_hba_file = 1;
	my $new_pg_hba_conf    = "";
	foreach my $line (split/\n/, $pg_hba_conf)
	{
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { line => $line }});
		if ($line =~ /^host\s+all\s+all\s+\all\s+md5$/)
		{
			# No need to update.
			$update_pg_hba_file = 0;
			last;
		}
		elsif ($line =~ /^# TYPE\s+DATABASE/)
		{
			# Inject the new listen_addresses
			$new_pg_hba_conf .= $line."\n";
			$new_pg_hba_conf .= "host\tall\t\tall\t\tall\t\t\tmd5\n";
		}
		else
		{
			$new_pg_hba_conf .= $line."\n";
		}
	}
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { update_pg_hba_file => $update_pg_hba_file }});
	if ($update_pg_hba_file)
	{
		# Back up the existing one, if needed.
		my $pg_hba_backup = $an->data->{path}{directories}{backups}."/pgsql/pg_hba.conf";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { pg_hba_backup => $pg_hba_backup }});
		if (not -e $pg_hba_backup)
		{
			$an->Storage->copy_file({source => $an->data->{path}{configs}{'pg_hba.conf'}, target => $pg_hba_backup});
		}
		
		# Write the new one.
		$an->Storage->write_file({
			file      => $an->data->{path}{configs}{'pg_hba.conf'}, 
			body      => $new_pg_hba_conf,
			user      => "postgres", 
			group     => "postgres",
			mode      => "0600",
			overwrite => 1,
		});
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0057", variables => { file => $an->data->{path}{configs}{'postgresql.conf'} }});
	}
	
	# Start or restart the daemon?
	if (not $running)
	{
		# Start the daemon.
		my $return_code = $an->System->start_daemon({daemon => "postgresql"});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { return_code => $return_code }});
		if ($return_code eq "0")
		{
			# Started the daemon.
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0059"});
		}
		else
		{
			# Failed to start
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0094"});
			return(undef);
		}
	}
	elsif (($update_postgresql_file) or ($update_pg_hba_file))
	{
		# Reload
		my $return_code = $an->System->start_daemon({daemon => "postgresql"});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { return_code => $return_code }});
		if ($return_code eq "0")
		{
			# Reloaded the daemon.
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0112"});
		}
		else
		{
			# Failed to reload
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0111"});
		}
	}
	
	### TODO: This might be a security issue... We create the file owned as root with 600 permissions, 
	###       but if we're not doing something write, we might still be exposing the password for a 
	###       moment... 
	# Create the .pgpass file, if needed.
	my $created_pgpass = 0;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, secure => 1, list => { 
		'path::secure::postgres_pgpass' => $an->data->{path}{secure}{postgres_pgpass},
		"database::${id}::password"     => $an->data->{database}{$id}{password}, 
	}});
	if ((not -e $an->data->{path}{secure}{postgres_pgpass}) && ($an->data->{database}{$id}{password}))
	{
		my $body = "*:*:*:postgres:".$an->data->{database}{$id}{password}."\n";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, secure => 1, list => { body => $body }});
		$an->Storage->write_file({
			file      => $an->data->{path}{secure}{postgres_pgpass},  
			body      => $body,
			user      => "postgres", 
			group     => "postgres",
			mode      => "0600",
			overwrite => 1,
			secure    => 1,
		});
		if (-e $an->data->{path}{secure}{postgres_pgpass})
		{
			$created_pgpass = 1;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { created_pgpass => $created_pgpass }});
		}
	}
	
	# Does the database user exist?
	my $create_user   = 1;
	my $scancore_user = $an->data->{database}{$id}{user};
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { scancore_user => $scancore_user }});
	if (not $scancore_user)
	{
		# No database user defined
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0099", variables => { id => $id }});
		return(undef);
	}
	my $user_list = $an->System->call({shell_call => $an->data->{path}{exe}{su}." - postgres -c \"".$an->data->{path}{exe}{psql}." template1 -c 'SELECT usename, usesysid FROM pg_catalog.pg_user;'\"", source => $THIS_FILE, line => __LINE__});
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { user_list => $user_list }});
	foreach my $line (split/\n/, $user_list)
	{
		if ($line =~ /^ $scancore_user\s+\|\s+(\d+)/)
		{
			# User exists already
			my $id = $1;
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0060", variables => { user => $scancore_user, id => $id }});
			$create_user = 0;
			last;
		}
	}
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { create_user => $create_user }});
	if ($create_user)
	{
		# Create the user
		my $create_output = $an->System->call({shell_call => $an->data->{path}{exe}{su}." - postgres -c \"".$an->data->{path}{exe}{createuser}." --no-superuser --createdb --no-createrole $scancore_user\"", source => $THIS_FILE, line => __LINE__});
		my $user_list     = $an->System->call({shell_call => $an->data->{path}{exe}{su}." - postgres -c \"".$an->data->{path}{exe}{psql}." template1 -c 'SELECT usename, usesysid FROM pg_catalog.pg_user;'\"", source => $THIS_FILE, line => __LINE__});
		my $user_exists   = 0;
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { create_output => $create_output, user_list => $user_list }});
		foreach my $line (split/\n/, $user_list)
		{
			if ($line =~ /^ $scancore_user\s+\|\s+(\d+)/)
			{
				# Success!
				my $id = $1;
				$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0095", variables => { user => $scancore_user, id => $id }});
				$user_exists = 1;
				last;
			}
		}
		if (not $user_exists)
		{
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0096", variables => { user => $scancore_user }});
			return(undef);
		}
		
		# Update/set the passwords.
		if ($an->data->{database}{$id}{password})
		{
			foreach my $user ("postgres", $scancore_user)
			{
				my $update_output = $an->System->call({secure => 1, shell_call => $an->data->{path}{exe}{su}." - postgres -c \"".$an->data->{path}{exe}{psql}." template1 -c \\\"ALTER ROLE $user WITH PASSWORD '".$an->data->{database}{$id}{password}."';\\\"\"", source => $THIS_FILE, line => __LINE__});
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, secure => 1, list => { update_output => $update_output }});
				foreach my $line (split/\n/, $user_list)
				{
					if ($line =~ /ALTER ROLE/)
					{
						# Password set
						$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0100", variables => { user => $user }});
					}
				}
			}
		}
	}
	
	# Create the database, if needed.
	my $create_database   = 1;
	my $scancore_database = $an->data->{database}{$id}{name};
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "database::${id}::name" => $an->data->{database}{$id}{name} }});
	
	my $database_list = $an->System->call({shell_call => $an->data->{path}{exe}{su}." - postgres -c \"".$an->data->{path}{exe}{psql}." template1 -c 'SELECT datname FROM pg_catalog.pg_database;'\"", source => $THIS_FILE, line => __LINE__});
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { database_list => $database_list }});
	foreach my $line (split/\n/, $database_list)
	{
		if ($line =~ /^ $scancore_database$/)
		{
			# Database already exists.
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0105", variables => { database => $scancore_database }});
			$create_database = 0;
			last;
		}
	}
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { create_database => $create_database }});
	if ($create_database)
	{
		my $create_output = $an->System->call({shell_call => $an->data->{path}{exe}{su}." - postgres -c \"".$an->data->{path}{exe}{createdb}."  --owner $scancore_user $scancore_database\"", source => $THIS_FILE, line => __LINE__});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { create_output => $create_output }});
		
		my $database_exists = 0;
		my $database_list   = $an->System->call({shell_call => $an->data->{path}{exe}{su}." - postgres -c \"".$an->data->{path}{exe}{psql}." template1 -c 'SELECT datname FROM pg_catalog.pg_database;'\"", source => $THIS_FILE, line => __LINE__});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { database_list => $database_list }});
		foreach my $line (split/\n/, $database_list)
		{
			if ($line =~ /^ $scancore_database$/)
			{
				# Database created
				$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0110", variables => { database => $scancore_database }});
				$database_exists = 1;
				last;
			}
		}
		if (not $database_exists)
		{
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0109", variables => { database => $scancore_database }});
			return(undef);
		}
	}
	
	# Remove the temporary password file.
	if (($created_pgpass) && (-e $an->data->{path}{secure}{postgres_pgpass}))
	{
		unlink $an->data->{path}{secure}{postgres_pgpass};
		if (-e $an->data->{path}{secure}{postgres_pgpass})
		{
			# Failed to unlink the file.
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0107"});
		}
	}
	
	return(0);
}

=head2 connect_to_databases

This method tries to connect to all databases it knows of. To define databases for a machine to connect to, load a configuration file with the following parameters;

 database::1::host			=	an-striker01.alteeve.com
 database::1::port			=	5432
 database::1::name			=	scancore
 database::1::user			=	admin
 database::1::password			=	Initial1
 database::1::ping_before_connect	=	1
 
 database::2::host			=	an-striker02.alteeve.com
 database::2::port			=	5432
 database::2::name			=	scancore
 database::2::user			=	admin
 database::2::password			=	Initial1
 database::2::ping_before_connect	=	1

The C<< 1 >> and C<< 2 >> are the IDs of the given databases. They can be any number and do not need to be sequential, they just need to be unique. 

This module will return the number of databases that were successfully connected to. This makes it convenient to check and exit if no databases are available using a check like;

 my $database_count = $an->Database->connect({file => $THIS_FILE});
 if($database_count)
 {
 	# Connected to: [$database_count] database(s)!
 }
 else
 {
 	# No databases available, exiting.
 }

Parameters;

=head3 source (optional)

The C<< source >> parameter is used to check the special C<< updated >> table one all connected databases to see when that source (program name, usually) last updated a given database. If the date stamp is the same on all connected databases, nothing further happens. If one of the databases differ, however, a resync will be requested.

If not defined, the core database will be checked.

If this is not set, no attempt to resync the database will be made.

=head3 sql_file (optional)

This is the SQL schema file that will be used to initialize the database, if the C<< test_table >> isn't found in a given database that is connected to. By default, this is C<< path::sql::Tools.sql >> (C<< /usr/share/perl/AN/Tools.sql >> by default). 

=head3 tables (optional)

This is an optional hash reference of tables and their host UUID columns to specifically check when connecting to databases. If specified, the table's most recent C<< modified_date >> time stamp will be read (specifically; C<< SELECT modified_date FROM history.$table WHERE $host_uuid_column = 'sys::host_uuid' ORDER BY modified_date DESC LIMIT 1 >>) and if a table doesn't return, or any of the time stamps are missing, a resync will be requested.

Example use;

 $an->Database->connect({
	tables => {
		upses         => "ups_host_uuid",
		ups_batteries => "ups_battery_host_uuid",
	},
 });

If you want to specify a table that is not linked to a host, set the hash variable's value as an empty string.

 $an->Database->connect({
	tables => {
		servers => "",
	},
 });

=head3 test_table (optional)

Once connected to the database, a query is made to see if the database needs to be initialized. Usually this is C<< defaults::sql::test_table >> (C<< hosts>> by default). 

If you set this table manually, it will be checked and if the table doesn't exist on a connected database, the database will be initialized with the C<< sql_file >> parameter's file.

=cut
sub connect
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $source     = defined $parameter->{source}     ? $parameter->{source}     : "core";
	my $sql_file   = defined $parameter->{sql_file}   ? $parameter->{sql_file}   : $an->data->{path}{sql}{'Tools.sql'};
	my $tables     = defined $parameter->{tables}     ? $parameter->{tables}     : "";
	my $test_table = defined $parameter->{test_table} ? $parameter->{test_table} : $an->data->{defaults}{sql}{test_table};
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		source     => $source, 
		sql_file   => $sql_file, 
		tables     => $tables, 
		test_table => $test_table, 
	}});
	
	$an->data->{sys}{db_timestamp} = "" if not defined $an->data->{sys}{db_timestamp};
	
	# We need the host_uuid before we connect.
	if (not $an->data->{sys}{host_uuid})
	{
		$an->data->{sys}{host_uuid} = $an->Get->host_uuid;
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "sys::host_uuid" => $an->data->{sys}{host_uuid} }});
	}
	
	# This will be used in a few cases where the local DB ID is needed (or the lack of it being set 
	# showing we failed to connect to the local DB).
	$an->data->{sys}{local_db_id} = "";
	
	# This will be set to '1' if either DB needs to be initialized or if the last_updated differs on any node.
	$an->data->{sys}{database}{resync_needed} = 0;
	
	# Now setup or however-many connections
	my $seen_connections       = [];
	my $connections            = 0;
	my $failed_connections     = [];
	my $successful_connections = [];
	foreach my $id (sort {$a cmp $b} keys %{$an->data->{database}})
	{
		my $driver   = "DBI:Pg";
		my $host     = $an->data->{database}{$id}{host}     ? $an->data->{database}{$id}{host}     : ""; # This should fail
		my $port     = $an->data->{database}{$id}{port}     ? $an->data->{database}{$id}{port}     : 5432;
		my $name     = $an->data->{database}{$id}{name}     ? $an->data->{database}{$id}{name}     : ""; # This should fail
		my $user     = $an->data->{database}{$id}{user}     ? $an->data->{database}{$id}{user}     : ""; # This should fail
		my $password = $an->data->{database}{$id}{password} ? $an->data->{database}{$id}{password} : "";
		
		# If not set, we will always ping before connecting.
		if ((not exists $an->data->{database}{$id}{ping_before_connect}) or (not defined $an->data->{database}{$id}{ping_before_connect}))
		{
			$an->data->{database}{$id}{ping_before_connect} = 1;
		}
		
		# Make sure the user didn't specify the same target twice.
		my $target_host = "$host:$port";
		my $duplicate   = 0;
		foreach my $existing_host (sort {$a cmp $b} @{$seen_connections})
		{
			if ($existing_host eq $target_host)
			{
				# User is connecting to the same target twice.
				$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0053", variables => { target => $target_host }});
				$duplicate = 1;
			}
		}
		if (not $duplicate)
		{
			push @{$seen_connections}, $target_host;
		}
		next if $duplicate;
		
		# Log what we're doing.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0054", variables => { 
			id       => $id,
			driver   => $driver,
			host     => $host,
			port     => $port,
			name     => $name,
			user     => $user,
			password => $an->Log->secure ? $password : "--",
		}});
		
		# Assemble my connection string
		my $db_connect_string = "$driver:dbname=$name;host=$host;port=$port";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			db_connect_string                      => $db_connect_string, 
			"database::${id}::ping_before_connect" => $an->data->{database}{$id}{ping_before_connect},
		}});
		if ($an->data->{database}{$id}{ping_before_connect})
		{
			# Can I ping?
			my ($pinged) = $an->System->ping({ping => $host, count => 1});
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { pinged => $pinged }});
			if (not $pinged)
			{
				# Didn't ping and 'database::<id>::ping_before_connect' not set. Record this 
				# is the failed connections array.
				$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => "log_0063", variables => { id => $id }});
				push @{$failed_connections}, $id;
				next;
			}
		}
		
		# Before we try to connect, see if this is a local database and, if so, make sure it's setup.
		if (($host eq $an->_hostname)       or 
		    ($host eq $an->_short_hostname) or 
		    ($host eq "localhost")          or 
		    ($host eq "127.0.0.1")          or 
		(not $an->data->{sys}{read_db_id}))
		{
			$an->data->{sys}{read_db_id} = $id;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "sys::read_db_id" => $an->data->{sys}{read_db_id} }});
			
			# Set it up (or update it) if needed. This method just returns if nothing is needed.
			$an->Database->configure_pgsql({id => $id});
		}
		
		# Connect!
		my $dbh = "";
		### NOTE: The Database->write() method, when passed an array, will automatically disable 
		###       autocommit, do the bulk write, then commit when done.
		# We connect with fatal errors, autocommit and UTF8 enabled.
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			db_connect_string => $db_connect_string, 
			user              => $user, 
		}});
		eval { $dbh = DBI->connect($db_connect_string, $user, $password, {
			RaiseError     => 1,
			AutoCommit     => 1,
			pg_enable_utf8 => 1
		}); };
		if ($@)
		{
			# Something went wrong...
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => "log_0064", variables => { 
				id   => $id,
				host => $host,
				name => $name,
			}});

			push @{$failed_connections}, $id;
			my $message_key = "log_0065";
			my $variables   = { dbi_error => $DBI::errstr };
			if (not defined $DBI::errstr)
			{
				# General error
				$variables = { dbi_error => $@ };
			}
			elsif ($DBI::errstr =~ /No route to host/)
			{
				$message_key = "log_0066";
				$variables   = { target => $host, port => $port };
			}
			elsif ($DBI::errstr =~ /no password supplied/)
			{
				$message_key = "log_0067";
				$variables   = { id => $id };
			}
			elsif ($DBI::errstr =~ /password authentication failed for user/)
			{
				$message_key = "log_0068";
				$variables   = { 
					id   => $id,
					name => $name,
					host => $host,
					user => $user,
				};
			}
			elsif ($DBI::errstr =~ /Connection refused/)
			{
				$message_key = "log_0069";
				$variables   = { 
					name => $name,
					host => $host,
					port => $port,
				};
			}
			elsif ($DBI::errstr =~ /Temporary failure in name resolution/i)
			{
				$message_key = "log_0070";
				$variables   = { 
					name => $name,
					host => $host,
					port => $port,
				};
			}
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => $message_key, variables => $variables });
		}
		elsif ($dbh =~ /^DBI::db=HASH/)
		{
			# Woot!
			$connections++;
			push @{$successful_connections}, $id;
			$an->data->{cache}{db_fh}{$id} = $dbh;
			
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0071", variables => { 
				host => $host,
				port => $port,
				name => $name,
				id   => $id,
			}});
			
			if (not $an->data->{sys}{use_db_fh})
			{
				$an->data->{sys}{use_db_fh} = $dbh;
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 'sys::use_db_fh' => $an->data->{sys}{use_db_fh} }});
			}
			
			# Now that I have connected, see if my 'hosts' table exists.
			my $query = "SELECT COUNT(*) FROM pg_catalog.pg_tables WHERE tablename=".$an->data->{sys}{use_db_fh}->quote($test_table)." AND schemaname='public';";
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
			
			my $count = $an->Database->query({id => $id, query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
			
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { count => $count }});
			if ($count < 1)
			{
				# Need to load the database.
				$an->Database->initialize({id => $id, sql_file => $sql_file});
			}
			
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				"sys::read_db_id"   => $an->data->{sys}{read_db_id}, 
				"cache::db_fh::$id" => $an->data->{cache}{db_fh}{$id}, 
			}});
			
			# Set the first ID to be the one I read from later. Alternatively, if this host is 
			# local, use it.
			if (($host eq $an->_hostname)       or 
			    ($host eq $an->_short_hostname) or 
			    ($host eq "localhost")          or 
			    ($host eq "127.0.0.1")          or 
			    (not $an->data->{sys}{read_db_id}))
			{
				$an->data->{sys}{read_db_id}  = $id;
				$an->data->{sys}{local_db_id} = $id;
				$an->data->{sys}{use_db_fh}   = $an->data->{cache}{db_fh}{$id};
				
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
					"sys::read_db_id" => $an->data->{sys}{read_db_id}, 
					"sys::use_db_fh"  => $an->data->{sys}{use_db_fh}
				}});
			}
			
			# Get a time stamp for this run, if not yet gotten.
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				"cache::db_fh::$id" => $an->data->{cache}{db_fh}{$id}, 
				"sys::db_timestamp" => $an->data->{sys}{db_timestamp},
			}});
			
			# Pick a timestamp for this run, if we haven't yet.
			if (not $an->data->{sys}{db_timestamp})
			{
				my $query = "SELECT cast(now() AS timestamp with time zone)";
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
				
				$an->data->{sys}{db_timestamp} = $an->Database->query({id => $id, query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "sys::db_timestamp" => $an->data->{sys}{db_timestamp} }});
			}
			
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				"sys::read_db_id"   => $an->data->{sys}{read_db_id},
				"sys::use_db_fh"    => $an->data->{sys}{use_db_fh},
				"sys::db_timestamp" => $an->data->{sys}{db_timestamp},
			}});
		}
	}
	
	# Do I have any connections? Don't die, if not, just return.
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { connections => $connections }});
	if (not $connections)
	{
		# Failed to connect to any database. Log this, print to the caller and return.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0091"});
		return($connections);
	}
	
	# Report any failed DB connections
	foreach my $id (@{$failed_connections})
	{
		# Copy my alert hash before I delete the id.
		my $error_array = [];
		
		# Delete this DB so that we don't try to use it later.
		my $say_server = $an->data->{database}{$id}{host}.":".$an->data->{database}{$id}{port}." -> ".$an->data->{database}{$id}{name};
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => "log_0092", variables => { server => $say_server, id => $id }});
		
		# Delete it from the list of known databases for this run.
		delete $an->data->{database}{$id};
		
		# If I've not sent an alert about this DB loss before, send one now.
		my $set = $an->Alert->check_alert_sent({
			type		=>	"set",
			set_by		=>	$THIS_FILE,
			record_locator	=>	$id,
			name		=>	"connect_to_db",
			modified_date	=>	$an->data->{sys}{db_timestamp},
		});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { set => $set }});
		
		if ($set)
		{
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { error_array => $error_array }});
			foreach my $hash (@{$error_array})
			{
				my $message_key       = $hash->{message_key};
				my $message_variables = $hash->{message_variables};
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
					hash              => $hash, 
					message_key       => $message_key, 
					message_variables => $message_variables, 
				}});
				
				# These are warning level alerts.
				$an->Alert->register_alert({
					alert_level		=>	"warning", 
					alert_set_by		=>	$THIS_FILE,
					alert_title_key		=>	"alert_title_0003",
					alert_message_key	=>	$message_key,
					alert_message_variables	=>	$message_variables,
				});
			}
		}
	}
	
	# Send an 'all clear' message if a now-connected DB previously wasn't.
	foreach my $id (@{$successful_connections})
	{
		# Query to see if the newly connected host is in the DB yet. If it isn't, don't send an
		# alert as it'd cause a duplicate UUID error.
		my $query = "SELECT COUNT(*) FROM hosts WHERE host_name = ".$an->data->{sys}{use_db_fh}->quote($an->data->{database}{$id}{host}).";";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});

		my $count = $an->Database->query({id => $id, query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { count => $count }});
		
		if ($count > 0)
		{
			my $cleared = $an->Alert->check_alert_sent({
				type		=>	"clear",
				sent_by		=>	$THIS_FILE,
				record_locator	=>	$id,
				name		=>	"connect_to_db",
				modified_date	=>	$an->data->{sys}{db_timestamp},
			});
			if ($cleared)
			{
				$an->Alert->register_alert({
					alert_level		=>	"warning", 
					alert_agent_name	=>	"ScanCore",
					alert_title_key		=>	"an_alert_title_0006",
					alert_message_key	=>	"cleared_log_0055",
					alert_message_variables	=>	{
						name			=>	$an->data->{database}{$id}{name},
						host			=>	$an->data->{database}{$id}{host},
						port			=>	$an->data->{database}{$id}{port} ? $an->data->{database}{$id}{port} : 5432,
					},
				});
			}
		}
	}

	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "sys::host_uuid" => $an->data->{sys}{host_uuid} }});
	if ($an->data->{sys}{host_uuid} !~ /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
	{
		# derp. bad UUID
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0103"});
		
		# Disconnect and set the connection count to '0'.
		$an->Database->disconnect();
		$connections = 0;
	}
	
	# For now, we just find which DBs are behind and let each agent deal with bringing their tables up to
	# date.
	$an->Database->_find_behind_databases({
		source => $source, 
		tables => $tables,
	});
	
	# Hold if a lock has been requested.
	$an->Database->locking();
	
	# Mark that we're not active.
	$an->Database->mark_active({set => 1});
	
	return($connections);
}

=head2

This cleanly closes any open file handles to all connected databases and clears some internal database related variables.

=cut
sub disconnect
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $marked_inactive = 0;
	foreach my $id (sort {$a cmp $b} keys %{$an->data->{database}})
	{
		# Don't do anything if there isn't an active file handle for this DB.
		next if ((not $an->data->{cache}{db_fh}{$id}) or ($an->data->{cache}{db_fh}{$id} !~ /^DBI::db=HASH/));
		
		# Clear locks and mark that we're done running.
		if (not $marked_inactive)
		{
			$an->Database->mark_active({set => 0});
			$an->Database->locking({release => 1});
			$marked_inactive = 1;
		}
		
		$an->data->{cache}{db_fh}{$id}->disconnect;
		delete $an->data->{cache}{db_fh}{$id};
	}
	
	# Delete the stored DB-related values.
	delete $an->data->{sys}{db_timestamp};
	delete $an->data->{sys}{use_db_fh};
	delete $an->data->{sys}{read_db_id};
	
	return(0);
}

=head2 get_local_id

This returns the database ID from 'C<< striker.conf >>' based on matching the 'C<< database::<id>::host >>' to the local machine's host name or one of the active IP addresses on the host.

 # Get the local ID
 my $local_id = $an->Database->get_local_id;

This will return a blank string if no match is found.

=cut
sub get_local_id
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $local_id        = "";
	my $network_details = $an->Get->network_details;
	foreach my $id (sort {$a cmp $b} keys %{$an->data->{database}})
	{
		if ($network_details->{hostname} eq $an->data->{database}{$id}{host})
		{
			$local_id = $id;
			last;
		}
	}
	if (not $local_id)
	{
		foreach my $interface (sort {$a cmp $b} keys %{$network_details->{interface}})
		{
			my $ip_address  = $network_details->{interface}{$interface}{ip};
			my $subnet_mask = $network_details->{interface}{$interface}{netmask};
			foreach my $id (sort {$a cmp $b} keys %{$an->data->{database}})
			{
				if ($ip_address eq $an->data->{database}{$id}{host})
				{
					$local_id = $id;
					last;
				}
			}
		}
	}
	
	return($local_id);
}

=head2 initialize

This will initialize a database using a given file.

=cut
sub initialize
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $id       = $parameter->{id}       ? $parameter->{id}       : $an->data->{sys}{read_db_id};
	my $sql_file = $parameter->{sql_file} ? $parameter->{sql_file} : $an->data->{path}{sql}{'Tools.sql'};
	my $success  = 1;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		id       => $id, 
		sql_file => $sql_file, 
	}});
	
	# This just makes some logging cleaner below.
	my $say_server = $an->data->{database}{$id}{host}.":".$an->data->{database}{$id}{port}." -> ".$an->data->{database}{$id}{name};
	
	if (not $id)
	{
		# No database to talk to...
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0077"});
		return(0);
	}
	elsif (not defined $an->data->{cache}{db_fh}{$id})
	{
		# Database handle is gone.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0078", variables => { id => $id }});
		return(0);
	}
	if (not $sql_file)
	{
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0079", variables => { 
			server => $say_server,
			id     => $id, 
		}});
		return(0);
	}
	elsif (not -e $sql_file)
	{
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0080", variables => { 
			server   => $say_server,
			id       => $id, 
			sql_file => $sql_file, 
		}});
		return(0);
	}
	elsif (not -r $sql_file)
	{
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0081", variables => { 
			server   => $say_server,
			id       => $id, 
			sql_file => $sql_file, 
		}});
		return(0);
	}
	
	# Tell the user we need to initialize
	$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0082", variables => { 
		server   => $say_server,
		id       => $id, 
		sql_file => $sql_file, 
	}});
	
	# Read in the SQL file and replace #!variable!name!# with the database owner name.
	my $user = $an->data->{database}{$id}{user};
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { user => $user }});
	
	my $sql = $an->Storage->read_file({file => $sql_file});
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { ">> sql" => $sql }});
	
	$sql =~ s/#!variable!user!#/$user/sg;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "<< sql" => $sql }});
	
	### NOTE: Left off here
	# Now that I am ready, disable autocommit, write and commit.
	$an->Database->write({id => $id, query => $sql, source => $THIS_FILE, line => __LINE__});
	
	$an->data->{sys}{db_initialized}{$id} = 1;
	
	# Mark that we need to update the DB.
	$an->data->{sys}{database}{resync_needed} = 1;
	
	return($success);
};

=head2 insert_or_update_states

This updates (or inserts) a record in the 'states' table. The C<< state_uuid >> referencing the database row will be returned.

If there is an error, an empty string is returned.

Parameters;

=head3 state_uuid (optional)

This is the C<< state_uuid >> to update. If it is not specified but the C<< state_name >> is, a check will be made to see if an entry already exists. If so, that row will be UPDATEd. If not, a random UUID will be generated and a new entry will be INSERTed.

=head3 state_name (required)

This is the C<< state_name >> to INSERT or UPDATE. If a C<< state_uuid >> is passed, then the C<< state_name >> can be changed.

=head3 state_host_uuid (optional)

This is the host's UUID that this state entry belongs to. If not passed, C<< sys::host_uuid >> will be used.

=head3 state_note (optional)

This is an optional note related to this state entry.

=cut 
sub insert_or_update_states
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $state_uuid      = $parameter->{state_uuid}      ? $parameter->{state_uuid}      : "";
	my $state_name      = $parameter->{state_name}      ? $parameter->{state_name}      : "";
	my $state_host_uuid = $parameter->{state_host_uuid} ? $parameter->{state_host_uuid} : $an->data->{sys}{host_uuid};
	my $state_note      = $parameter->{state_note}      ? $parameter->{state_note}      : "NULL";
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		state_uuid      => $state_uuid, 
		state_name      => $state_name, 
		state_host_uuid => $state_host_uuid, 
		state_note      => $state_note, 
	}});
	
	if (not $state_name)
	{
		# Throw an error and exit.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Database->insert_or_update_states()", parameter => "state_name" }});
		return("");
	}
	if (not $state_host_uuid)
	{
		# Throw an error and exit.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0108"});
		return("");
	}
	
	# If we don't have a UUID, see if we can find one for the given state server name.
	if (not $state_uuid)
	{
		my $query = "
SELECT 
    state_uuid 
FROM 
    states 
WHERE 
    state_name      = ".$an->data->{sys}{use_db_fh}->quote($state_name)." 
AND 
    state_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($state_host_uuid)." 
;";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
		
		my $results = $an->Database->query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			results => $results, 
			count   => $count, 
		}});
		foreach my $row (@{$results})
		{
			$state_uuid = $row->[0];
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { state_uuid => $state_uuid }});
		}
	}
	
	# If I still don't have an state_uuid, we're INSERT'ing .
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { state_uuid => $state_uuid }});
	if (not $state_uuid)
	{
		# It's possible that this is called before the host is recorded in the database. So to be
		# safe, we'll return without doing anything if there is no host_uuid in the database.
		my $hosts = $an->ScanCore->get_hosts();
		my $found = 0;
		foreach my $hash_ref (@{$hosts})
		{
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				"hash_ref->{host_uuid}" => $hash_ref->{host_uuid}, 
				"sys::host_uuid"        => $an->data->{sys}{host_uuid}, 
			}});
			if ($hash_ref->{host_uuid} eq $an->data->{sys}{host_uuid})
			{
				$found = 1;
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { found => $found }});
			}
		}
		if (not $found)
		{
			# We're out.
			return("");
		}
		
		# INSERT
		   $state_uuid = $an->Get->uuid();
		my $query      = "
INSERT INTO 
    states 
(
    state_uuid, 
    state_name,
    state_host_uuid, 
    state_note, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($state_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($state_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($state_host_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($state_note).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
		$an->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query the rest of the values and see if anything changed.
		my $query = "
SELECT 
    state_name,
    state_host_uuid, 
    state_note 
FROM 
    states 
WHERE 
    state_uuid = ".$an->data->{sys}{use_db_fh}->quote($state_uuid)." 
;";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
		
		my $results = $an->Database->query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			results => $results, 
			count   => $count, 
		}});
		foreach my $row (@{$results})
		{
			my $old_state_name         =         $row->[0];
			my $old_state_host_uuid    =         $row->[1];
			my $old_state_note         = defined $row->[2] ? $row->[2] : "NULL";
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				old_state_name      => $old_state_name, 
				old_state_host_uuid => $old_state_host_uuid, 
				old_state_note      => $old_state_note, 
			}});
			
			# Anything change?
			if (($old_state_name      ne $state_name)      or 
			    ($old_state_host_uuid ne $state_host_uuid) or 
			    ($old_state_note      ne $state_note))
			{
				# Something changed, save.
				my $query = "
UPDATE 
    states 
SET 
    state_name       = ".$an->data->{sys}{use_db_fh}->quote($state_name).", 
    state_host_uuid  = ".$an->data->{sys}{use_db_fh}->quote($state_host_uuid).",  
    state_note       = ".$an->data->{sys}{use_db_fh}->quote($state_note).", 
    modified_date    = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    state_uuid       = ".$an->data->{sys}{use_db_fh}->quote($state_uuid)." 
";
				$query =~ s/'NULL'/NULL/g;
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
				$an->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
			}
		}
	}
	
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { state_uuid => $state_uuid }});
	return($state_uuid);
}

=head2 insert_or_update_variables

This updates (or inserts) a record in the 'variables' table. The C<< state_uuid >> referencing the database row will be returned.

Unlike the other methods of this type, this method can be told to update the 'variable_value' only. This is so because the section, description and default columns rarely ever change. If this is set and the variable name is new, an INSERT will be done the same as if it weren't set, with the unset columns set to NULL.

If there is an error, C<< undef >> is returned.

Parameters;

=head3 variable_uuid (optional)

If this is passed, the variable will be updated using this UUID, which allows the C<< variable_name >> to be changed.

=head3 variable_name (optional)

This is the name of variable to be inserted or updated. 

B<NOTE>: This paramter is only optional if C<< variable_uuid >> is used. Otherwise this parameter is required.

=head3 variable_value (optional)

This is the value to set the variable to. If it is empty, the variable's value will be set to empty.

=head3 variable_default (optional)

If this is set, it changes the default value for the given variable. This is used to tell the user what the default was or enable resetting to defaults.

=head3 variable_description (optional)

This can be set to a string key that explains what this variable does when presenting this variable to a user.

=head3 variable_section (option)

If this is set, it will group this variable with other variables in the same section when displaying this variable to the user.

=head3 variable_source_uuid (optional)

This is an optional field to mark a source UUID that this variable belongs to. By default, a variable applies to everything that reads it, but if this is set, the variable can be restricted to just a given record. This is often used to tag the variable to a particular host by setting the host UUID, but it could also be a UUID of an entry in another database table, when C<< variable_source_table >> is used. Ultimately, this can be used however you want.

=head3 variable_source_table (optional)

This is an optional database table name that the variables relates to. Generally it is used along side C<< variable_source_uuid >>, but that isn't required.

=head3 update_value_only (optional)

When set to C<< 1 >>, this method will only update the variable's C<< variable_value >> column. Any other parameters are used to help locate the variable to update only.

=cut
sub insert_or_update_variables
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $variable_uuid         = defined $parameter->{variable_uuid}         ? $parameter->{variable_uuid}         : "";
	my $variable_name         = defined $parameter->{variable_name}         ? $parameter->{variable_name}         : "";
	my $variable_value        = defined $parameter->{variable_value}        ? $parameter->{variable_value}        : "NULL";
	my $variable_default      = defined $parameter->{variable_default}      ? $parameter->{variable_default}      : "NULL";
	my $variable_description  = defined $parameter->{variable_description}  ? $parameter->{variable_description}  : "NULL";
	my $variable_section      = defined $parameter->{variable_section}      ? $parameter->{variable_section}      : "NULL";
	my $variable_source_uuid  = defined $parameter->{variable_source_uuid}  ? $parameter->{variable_source_uuid}  : "NULL";
	my $variable_source_table = defined $parameter->{variable_source_table} ? $parameter->{variable_source_table} : "NULL";
	my $update_value_only     = defined $parameter->{update_value_only}     ? $parameter->{update_value_only}     : 1;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		variable_uuid         => $variable_uuid, 
		variable_name         => $variable_name, 
		variable_value        => $variable_value, 
		variable_default      => $variable_default, 
		variable_description  => $variable_description, 
		variable_section      => $variable_section, 
		variable_source_uuid  => $variable_source_uuid, 
		variable_source_table => $variable_source_table, 
		update_value_only     => $update_value_only, 
	}});
	
	# We'll need either the name or UUID.
	if ((not $variable_name) && (not $variable_uuid))
	{
		# Neither given, throw an error and return.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0037"});
		return(undef);
	}
	
	# If we have a variable UUID but not a name, read the variable name. If we don't have a UUID, see if
	# we can find one for the given variable name.
	if (($an->Validate->is_uuid({uuid => $variable_uuid})) && (not $variable_name))
	{
		my $query = "
SELECT 
    variable_name 
FROM 
    variables 
WHERE 
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
		
		$variable_name = $an->Database->query({query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		$variable_name = "" if not defined $variable_name;
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { variable_name => $variable_name }});
	}
	
	if (($variable_name) && (not $variable_uuid))
	{
		my $query = "
SELECT 
    variable_uuid 
FROM 
    variables 
WHERE 
    variable_name = ".$an->data->{sys}{use_db_fh}->quote($variable_name);
		if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
		{
			$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
		}
		$query .= ";";
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
		
		my $results = $an->Database->query({query => $query, source => $THIS_FILE, line => __LINE__});
		my $count   = @{$results};
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			results => $results, 
			count   => $count,
		}});
		foreach my $row (@{$results})
		{
			$variable_uuid = $row->[0];
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { variable_uuid => $variable_uuid }});
		}
	}
	
	# If I still don't have an variable_uuid, we're INSERT'ing .
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { variable_uuid => $variable_uuid }});
	if (not $variable_uuid)
	{
		# INSERT
		   $variable_uuid = $an->Get->uuid();
		my $query         = "
INSERT INTO 
    variables 
(
    variable_uuid, 
    variable_name, 
    variable_value, 
    variable_default, 
    variable_description, 
    variable_section, 
    variable_source_uuid, 
    variable_source_table, 
    modified_date 
) VALUES (
    ".$an->data->{sys}{use_db_fh}->quote($variable_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_name).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_value).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_default).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_description).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_section).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid).", 
    ".$an->data->{sys}{use_db_fh}->quote($variable_source_table).", 
    ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})."
);
";
		$query =~ s/'NULL'/NULL/g;
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
		
		$an->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
	}
	else
	{
		# Query only the value
		if ($update_value_only)
		{
			my $query = "
SELECT 
    variable_value 
FROM 
    variables 
WHERE 
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
			if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
			{
				$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
			}
			$query .= ";";
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
			
			my $results = $an->Database->query({query => $query, source => $THIS_FILE, line => __LINE__});
			my $count   = @{$results};
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				results => $results, 
				count   => $count,
			}});
			foreach my $row (@{$results})
			{
				my $old_variable_value = defined $row->[0] ? $row->[0] : "";
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { old_variable_value => $old_variable_value }});
				
				# Anything change?
				if ($old_variable_value ne $variable_value)
				{
					# Variable changed, save.
					my $query = "
UPDATE 
    variables 
SET 
    variable_value = ".$an->data->{sys}{use_db_fh}->quote($variable_value).", 
    modified_date  = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    variable_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
					if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
					{
						$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
					}
					$query .= ";";
					$query =~ s/'NULL'/NULL/g;
					$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
					
					$an->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
				}
			}
		}
		else
		{
			# Query the rest of the values and see if anything changed.
			my $query = "
SELECT 
    variable_name, 
    variable_value, 
    variable_default, 
    variable_description, 
    variable_section 
FROM 
    variables 
WHERE 
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid)." 
;";
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
			
			my $results = $an->Database->query({query => $query, source => $THIS_FILE, line => __LINE__});
			my $count   = @{$results};
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				results => $results, 
				count   => $count,
			}});
			foreach my $row (@{$results})
			{
				my $old_variable_name        = $row->[0];
				my $old_variable_value       = $row->[1] ? $row->[1] : "NULL";
				my $old_variable_default     = $row->[2] ? $row->[2] : "NULL";
				my $old_variable_description = $row->[3] ? $row->[3] : "NULL";
				my $old_variable_section     = $row->[4] ? $row->[4] : "NULL";
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
					old_variable_name        => $old_variable_name, 
					old_variable_value       => $old_variable_value, 
					old_variable_default     => $old_variable_default, 
					old_variable_description => $old_variable_description, 
					old_variable_section     => $old_variable_section, 
				}});
				
				# Anything change?
				if (($old_variable_name        ne $variable_name)        or 
				    ($old_variable_value       ne $variable_value)       or 
				    ($old_variable_default     ne $variable_default)     or 
				    ($old_variable_description ne $variable_description) or 
				    ($old_variable_section     ne $variable_section))
				{
					# Something changed, save.
					my $query = "
UPDATE 
    variables 
SET 
    variable_name        = ".$an->data->{sys}{use_db_fh}->quote($variable_name).", 
    variable_value       = ".$an->data->{sys}{use_db_fh}->quote($variable_value).", 
    variable_default     = ".$an->data->{sys}{use_db_fh}->quote($variable_default).", 
    variable_description = ".$an->data->{sys}{use_db_fh}->quote($variable_description).", 
    variable_section     = ".$an->data->{sys}{use_db_fh}->quote($variable_section).", 
    modified_date        = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{db_timestamp})." 
WHERE 
    variable_uuid        = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid)." 
";
					$query =~ s/'NULL'/NULL/g;
					$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { query => $query }});
					
					$an->Database->write({query => $query, source => $THIS_FILE, line => __LINE__});
				}
			}
		}
	}
	
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { variable_uuid => $variable_uuid }});
	return($variable_uuid);
}



=head2 locking

This handles requesting, releasing and waiting on locks.

If it is called without any parameters, it will act as a pauser that halts the program until any existing locks are released.

Parameters;

=head3 request (optional)

When set to C<< 1 >>, a log request will be made. If an existing lock exists, it will wait until the existing lock clears before requesting the lock and returning.

=head3 release (optional)

When set to C<< 1 >>, an existing lock held by this machine will be release.

=head3 renew (optional)

When set to C<< 1 >>, an existing lock held by this machine will be renewed.

=head3 check (optional)

This checks to see if a lock is in place and, if it is, the lock string is returned (in the format C<< <host_name>::<source_uuid>::<unix_time_stamp> >> that requested the active lock.

=cut
sub locking
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $request     = defined $parameter->{request}     ? $parameter->{request}     : 0;
	my $release     = defined $parameter->{release}     ? $parameter->{release}     : 0;
	my $renew       = defined $parameter->{renew}       ? $parameter->{renew}       : 0;
	my $check       = defined $parameter->{check}       ? $parameter->{check}       : 0;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		request => $request, 
		release => $release, 
		renew   => $renew, 
		check   => $check, 
	}});
	
	# These are used to ID this lock.
	my $source_name = $an->_hostname;
	my $source_uuid = $an->data->{sys}{host_uuid};
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		source_name => $source_name, 
		source_uuid => $source_uuid, 
	}});
	
	### TODO: Left off here
	my $set            = 0;
	my $variable_name  = "lock_request";
	my $variable_value = $source_name."::".$source_uuid."::".time;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		variable_name  => $variable_name, 
		variable_value => $variable_value, 
	}});
	
	# Make sure we have a sane lock age
	if ((not defined $an->data->{database}{locking}{reap_age}) or 
	    (not $an->data->{database}{locking}{reap_age})         or 
	    ($an->data->{database}{locking}{reap_age} =~ /\D/)
	)
	{
		$an->data->{database}{locking}{reap_age} = $an->data->{defaults}{database}{locking}{reap_age};
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "database::locking::reap_age" => $an->data->{database}{locking}{reap_age} }});
	}
	
	# If I have been asked to check, we will return the variable_uuid if a lock is set.
	if ($check)
	{
		my ($lock_value, $variable_uuid, $modified_date) = $an->Database->read_variable({variable_name => $variable_name});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			lock_value    => $lock_value, 
			variable_uuid => $variable_uuid, 
			modified_date => $modified_date, 
		}});
		
		return($lock_value);
	}
	
	# If I've been asked to clear a lock, do so now.
	if ($release)
	{
		# We check to see if there is a lock before we clear it. This way we don't log that we 
		# released a lock unless we really released a lock.
		my ($lock_value, $variable_uuid, $modified_date) = $an->Database->read_variable({variable_name => $variable_name});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			lock_value    => $lock_value, 
			variable_uuid => $variable_uuid, 
			modified_date => $modified_date, 
		}});
		
		if ($lock_value)
		{
			my $variable_uuid = $an->ScanCore->insert_or_update_variables({
				variable_name     => $variable_name,
				variable_value    => "",
				update_value_only => 1,
			});
			$an->data->{sys}{local_lock_active} = 0;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				variable_uuid            => $variable_uuid, 
				"sys::local_lock_active" => $an->data->{sys}{local_lock_active}, 
			}});
			
			# Log that the lock has been released.
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0039", variables => { host => $an->_hostname }});
		}
		
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { set => $set }});
		return($set);
	}
	
	# If I've been asked to renew, do so now.
	if ($renew)
	{
		# Yup, do it.
		my $variable_uuid = $an->ScanCore->insert_or_update_variables({
			variable_name     => $variable_name,
			variable_value    => $variable_value,
			update_value_only => 1,
		});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { variable_uuid => $variable_uuid }});
		
		if ($variable_uuid)
		{
			$set = 1;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { set => $set }});
		}
		$an->data->{sys}{local_lock_active} = time;
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			variable_uuid            => $variable_uuid, 
			"sys::local_lock_active" => $an->data->{sys}{local_lock_active}, 
		}});
		
		# Log that we've renewed the lock.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0044", variables => { host => $an->_hostname }});
		
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { set => $set }});
		return($set);
	}
	
	# We always check for, and then wait for, locks. Read in the locks, if any. If any are set and they are 
	# younger than database::locking::reap_age, we'll hold.
	my $waiting = 1;
	while ($waiting)
	{
		# Set the 'waiting' to '0'. If we find a lock, we'll set it back to '1'.
		$waiting = 0;
		
		# See if we had a lock.
		my ($lock_value, $variable_uuid, $modified_date) = $an->Database->read_variable({variable_name => $variable_name});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			waiting       => $waiting, 
			lock_value    => $lock_value, 
			variable_uuid => $variable_uuid, 
			modified_date => $modified_date, 
		}});
		if ($lock_value =~ /^(.*?)::(.*?)::(\d+)/)
		{
			my $lock_source_name = $1;
			my $lock_source_uuid = $2;
			my $lock_time        = $3;
			my $current_time     = time;
			my $timeout_time     = $lock_time + $an->data->{database}{locking}{reap_age};
			my $lock_age         = $current_time - $lock_time;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				lock_source_name => $lock_source_name, 
				lock_source_uuid => $lock_source_uuid, 
				current_time     => $current_time, 
				lock_time        => $lock_time, 
				timeout_time     => $timeout_time, 
				lock_age         => $lock_age, 
			}});
			
			# If the lock is stale, delete it.
			if ($current_time > $timeout_time)
			{
				# The lock is stale.
				my $variable_uuid = $an->ScanCore->insert_or_update_variables({
					variable_name     => $variable_name,
					variable_value    => "",
					update_value_only => 1,
				});
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { variable_uuid => $variable_uuid }});
			}
			# Only wait if this isn't our own lock.
			elsif ($lock_source_uuid ne $source_uuid)
			{
				# Mark 'wait', set inactive and sleep.
				$an->Database->mark_active({set => 0});
				
				$waiting = 1;
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
					lock_source_uuid => $lock_source_uuid, 
					source_uuid      => $source_uuid, 
					waiting          => $waiting, 
				}});
				sleep 5;
			}
		}
	}
	
	# If I am here, there are no pending locks. Have I been asked to set one?
	if ($request)
	{
		# Yup, do it.
		my $variable_uuid = $an->ScanCore->insert_or_update_variables({
			variable_name     => $variable_name,
			variable_value    => $variable_value,
			update_value_only => 1,
		});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { variable_uuid => $variable_uuid }});
		
		if ($variable_uuid)
		{
			$set = 1;
			$an->data->{sys}{local_lock_active} = time;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				set                      => $set, 
				variable_uuid            => $variable_uuid, 
				"sys::local_lock_active" => $an->data->{sys}{local_lock_active}, 
			}});
			
			# Log that we've got the lock.
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0045", variables => { host => $an->_hostname }});
		}
	}
	
	# Now return.
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { set => $set }});
	return($set);
}

=head2 mark_active

This sets or clears that the caller is about to work on the database

Parameters;

=head3 set (optional, default C<< 1 >>)

If set to c<< 0 >>, 

=cut
sub mark_active
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $set = defined $parameter->{set} ? $parameter->{set} : 1;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { set => $set }});
	
	# If I haven't connected to a database yet, why am I here?
	if (not $an->data->{sys}{read_db_id})
	{
		return(0);
	}
	
	my $value = "false";
	if ($set)
	{
		$value = "true";
	}
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { value => $value }});
	
	my $state_uuid = $an->Database->insert_or_update_states({
		state_name      => "db_in_use",
		state_host_uuid => $an->data->{sys}{host_uuid},
		state_note      => $value,
	});
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { state_uuid => $state_uuid }});
	
	return($state_uuid);
}

=head2 query

This performs a query and returns an array reference of array references (from C<< DBO->fetchall_arrayref >>). The first array contains all the returned rows and each row is an array reference of columns in that row.

If an error occurs, C<< undef >> will be returned.

For example, given the query;

 scancore=# SELECT host_uuid, host_name, host_type FROM hosts ORDER BY host_name ASC;
               host_uuid               |        host_name         | host_type 
 --------------------------------------+--------------------------+-----------
  e27fc9a0-2656-4aaf-80e6-fedb3c339037 | an-a01n01.alteeve.com    | node
  4bea6ddd-c3ff-43e9-8e9e-b2dea1923145 | an-a01n02.alteeve.com    | node
  ff852db7-c77a-403b-877f-91f85f3ad95c | an-striker01.alteeve.com | dashboard
  2dd5aab1-65d6-4416-9bc1-98dc344aa08b | an-striker02.alteeve.com | dashboard
 (4 rows)

The returned array would have four values, one for each returned row. Each row would be an array reference containing three values, one per row. So given the above example;

 my $rows = $an->Database->query({query => "SELECT host_uuid, host_name, host_type FROM hosts ORDER BY host_name ASC;"});
 foreach my $columns (@{$results})
 {
 	my $host_uuid = $columns->[0];
 	my $host_name = $columns->[1];
 	my $host_type = $columns->[2];
	print "Host: [$host_name] (UUID: [$host_uuid], type: [$host_type]).\n";
 }

Would print;

 Host: [an-a01n01.alteeve.com] (UUID: [e27fc9a0-2656-4aaf-80e6-fedb3c339037], type: [node]).
 Host: [an-a01n02.alteeve.com] (UUID: [4bea6ddd-c3ff-43e9-8e9e-b2dea1923145], type: [node]).
 Host: [an-striker01.alteeve.com] (UUID: [ff852db7-c77a-403b-877f-91f85f3ad95c], type: [dashboard]).
 Host: [an-striker02.alteeve.com] (UUID: [2dd5aab1-65d6-4416-9bc1-98dc344aa08b], type: [dashboard]).

B<NOTE>: Do not sort the array references; They won't make any sense as the references are randomly created pointers. The arrays will be returned in the order of the returned data, so do your sorting in the query itself.

Parameters;

=head3 id (optional)

By default, the local database will be queried (if run on a machine with a database). Otherwise, the first database successfully connected to will be used for queries (as stored in C<< $an->data->{sys}{read_db_id} >>).

If you want to read from a specific database, though, you can set this parameter to the ID of the database (C<< database::<id>::host). If you specify a read from a database that isn't available, C<< undef >> will be returned.

=head3 line (optional)

To help with logging the source of a query, C<< line >> can be set to the line number of the script that requested the query. It is generally used along side C<< source >>.

=head3 query (required)

This is the SQL query to perform.

B<NOTE>: ALWAYS use C<< $an->data->{sys}{use_db_fh}->quote(...)>> when preparing data coming from ANY external source! Otherwise you'll end up XKCD 327'ing your database eventually...

=head3 secure (optional, defaul '0')

If set, the query will be treated as containing sensitive data and will only be logged if C<< $an->Log->secure >> is enabled.

=head3 source (optional)

To help with logging the source of a query, C<< source >> can be set to the name of the script that requested the query. It is generally used along side C<< line >>.


=cut
sub query
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $id     = $parameter->{id}     ? $parameter->{id}     : $an->data->{sys}{read_db_id};
	my $line   = $parameter->{line}   ? $parameter->{line}   : __LINE__;
	my $query  = $parameter->{query}  ? $parameter->{query}  : "";
	my $secure = $parameter->{secure} ? $parameter->{secure} : 0;
	my $source = $parameter->{source} ? $parameter->{source} : $THIS_FILE;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		id                    => $id, 
		"cache::db_fh::${id}" => $an->data->{cache}{db_fh}{$id}, 
		line                  => $line, 
		query                 => ((not $an->Log->secure) && ($secure)) ? $query : "--", 
		secure                => $secure, 
		source                => $source, 
	}});
	
	# Make logging code a little cleaner
	my $say_server = $an->data->{database}{$id}{host}.":".$an->data->{database}{$id}{port}." -> ".$an->data->{database}{$id}{name};
	
	if (not $id)
	{
		# No database to talk to...
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0072"});
		return(undef);
	}
	elsif (not defined $an->data->{cache}{db_fh}{$id})
	{
		# Database handle is gone.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0073", variables => { id => $id }});
		return(undef);
	}
	if (not $query)
	{
		# No query
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0084", variables => { 
			server => $say_server,
		}});
		return(undef);
	}
	
	### TODO:  If I am still alive check if any locks need to be renewed.
	#$an->Database->check_lock_age;
	
	### TODO: Do I need to log the transaction?
	#if ($an->Log->db_transactions())
	if (1)
	{
		$an->Log->entry({source => $source, line => $line, secure => $secure, level => 2, key => "log_0074", variables => { 
			id    => $id, 
			query => $query, 
		}});
	}
	
	# Test access to the DB before we do the actual query
	$an->Database->_test_access({ id => $id });
	
	# Do the query.
	my $DBreq = $an->data->{cache}{db_fh}{$id}->prepare($query) or $an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0075", variables => { 
			query    => ((not $an->Log->secure) && ($secure)) ? $query : "--", 
			server   => $say_server,
			db_error => $DBI::errstr, 
		}});
	
	# Execute on the query
	$DBreq->execute() or $an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0076", variables => { 
			query    => ((not $an->Log->secure) && ($secure)) ? $query : "--", 
			server   => $say_server,
			db_error => $DBI::errstr, 
		}});
	
	# Return the array
	return($DBreq->fetchall_arrayref());
}

=head2 read_variable

This reads a variable from the C<< variables >> table. Be sure to only use the reply from here to override what might have been set in a config file. This method always returns the data from the database itself.

The method returns an array reference containing, in order, the variable's value, database UUID and last modified date stamp.

If anything goes wrong, C<< undef >> is returned.

Parameters;

=head3 variable_uuid (optional)

If specified, this specifies the variable UUID to read. When this parameter is specified, the C<< variable_name >> parameter is ignored.

=head3 variable_name

=cut
sub read_variable
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $variable_uuid         = $parameter->{variable_uuid}         ? $parameter->{variable_uuid}         : undef;
	my $variable_name         = $parameter->{variable_name}         ? $parameter->{variable_name}         : "";
	my $variable_source_uuid  = $parameter->{variable_source_uuid}  ? $parameter->{variable_source_uuid}  : "NULL";
	my $variable_source_table = $parameter->{variable_source_table} ? $parameter->{variable_source_table} : "NULL";
	my $id                    = $parameter->{id}                    ? $parameter->{id}                    : $an->data->{sys}{read_db_id};
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		variable_uuid         => $variable_uuid, 
		variable_name         => $variable_name, 
		variable_source_uuid  => $variable_source_uuid, 
		variable_source_table => $variable_source_table, 
	}});
	
	# Do we have either the 
	if ((not $variable_name) && (not $variable_uuid))
	{
		# Throw an error and exit.
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0036"});
		return(undef, undef, undef);
	}
	
	# If we don't have a UUID, see if we can find one for the given SMTP server name.
	my $query = "
SELECT 
    variable_value, 
    variable_uuid, 
    round(extract(epoch from modified_date)) 
FROM 
    variables 
WHERE ";
	if ($variable_uuid)
	{
		$query .= "
    variable_uuid = ".$an->data->{sys}{use_db_fh}->quote($variable_uuid);
	}
	else
	{
		$query .= "
    variable_name         = ".$an->data->{sys}{use_db_fh}->quote($variable_name);
		if (($variable_source_uuid ne "NULL") && ($variable_source_table ne "NULL"))
		{
			$query .= "
AND 
    variable_source_uuid  = ".$an->data->{sys}{use_db_fh}->quote($variable_source_uuid)." 
AND 
    variable_source_table = ".$an->data->{sys}{use_db_fh}->quote($variable_source_table)." 
";
		}
	}
	$query .= ";";
	$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0074", variables => { query => $query }});
	
	my $variable_value = undef;
	my $modified_date  = undef;
	my $results        = $an->Database->query({id => $id, query => $query, source => $THIS_FILE, line => __LINE__});
	my $count          = @{$results};
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		results => $results, 
		count   => $count,
	}});
	foreach my $row (@{$results})
	{
		$variable_value = defined $row->[0] ? $row->[0] : "";
		$variable_uuid  =         $row->[1];
		$modified_date  =         $row->[2];
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0074", variables => { 
			results => $results, 
			count   => $count,
		}});
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			variable_value => $variable_value, 
			variable_uuid  => $variable_uuid, 
			modified_date  => $modified_date, 
		}});
	}
	
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		variable_value => $variable_value, 
		variable_uuid  => $variable_uuid, 
		modified_date  => $modified_date, 
	}});
	return($variable_value, $variable_uuid, $modified_date);
}


=head2 write

This records data to one or all of the databases. If an ID is passed, the query is written to one database only. Otherwise, it will be written to all DBs.

=cut
sub write
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $id      = $parameter->{id}      ? $parameter->{id}     : $an->data->{sys}{read_db_id};
	my $line    = $parameter->{line}    ? $parameter->{line}   : __LINE__;
	my $query   = $parameter->{query}   ? $parameter->{query}  : "";
	my $secure  = $parameter->{secure}  ? $parameter->{secure} : 0;
	my $source  = $parameter->{source}  ? $parameter->{source} : $THIS_FILE;
	my $reenter = $parameter->{reenter} ? $parameter->{reenter} : "";
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		id                    => $id, 
		"cache::db_fh::${id}" => $an->data->{cache}{db_fh}{$id}, 
		line                  => $line, 
		query                 => ((not $an->Log->secure) && ($secure)) ? $query : "--", 
		secure                => $secure, 
		source                => $source, 
		reenter               => $reenter,
	}});
	
	# Make logging code a little cleaner
	my $say_server = $an->data->{database}{$id}{host}.":".$an->data->{database}{$id}{port}." -> ".$an->data->{database}{$id}{name};
	
	# We don't check if ID is set here because not being set simply means to write to all available DBs.
	if (not $query)
	{
		# No query
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0085", variables => { server => $say_server }});
		return(undef);
	}
	
	# TODO: If I am still alive check if any locks need to be renewed.
	#$an->Database->check_lock_age;
	
	# This array will hold either just the passed DB ID or all of them, if no ID was specified.
	my @db_ids;
	if ($id)
	{
		push @db_ids, $id;
	}
	else
	{
		foreach my $id (sort {$a cmp $b} keys %{$an->data->{cache}{db_fh}})
		{
			push @db_ids, $id;
		}
	}
	
	# Sort out if I have one or many queries.
	my $limit     = 25000;
	my $count     = 0;
	my $query_set = [];
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "sys::database::maximum_batch_size" => $an->data->{sys}{database}{maximum_batch_size} }});
	if ($an->data->{sys}{database}{maximum_batch_size})
	{
		if ($an->data->{sys}{database}{maximum_batch_size} =~ /\D/)
		{
			# Bad value.
			$an->data->{sys}{database}{maximum_batch_size} = 25000;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "sys::database::maximum_batch_size" => $an->data->{sys}{database}{maximum_batch_size} }});
		}
		
		# Use the set value now.
		$limit = $an->data->{sys}{database}{maximum_batch_size};
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { limit => $limit }});
	}
	if (ref($query) eq "ARRAY")
	{
		# Multiple things to enter.
		$count = @{$query};
		
		# If I am re-entering, then we'll proceed normally. If not, and if we have more than 10k 
		# queries, we'll split up the queries into 10k chunks and re-enter.
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			count   => $count, 
			limit   => $limit, 
			reenter => $reenter, 
		}});
		if (($count > $limit) && (not $reenter))
		{
			my $i    = 0;
			my $next = $limit;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { i => $i, 'next' => $next }});
			foreach my $this_query (@{$query})
			{
				push @{$query_set}, $this_query;
				$i++;
				
				if ($i > $next)
				{
					# Commit this batch.
					foreach my $id (@db_ids)
					{
						# Commit this chunk to this DB.
						$an->Database->write({id => $id, query => $query_set, source => $THIS_FILE, line => $line, reenter => 1});
						
						### TODO: Rework this so that we exit here (so that we can 
						###       send an alert) if the RAM use is too high.
						# This can get memory intensive, so check our RAM usage and 
						# bail if we're eating too much.
						#my $ram_use = $an->System->check_memory({ program_name => $THIS_FILE });
						
						# Wipe out the old set array, create it as a new anonymous array and reset 'i'.
						undef $query_set;
						$query_set =  [];
						$i         =  0;
					}
				}
			}
		}
		else
		{
			# Not enough to worry about or we're dealing with a chunk, proceed as normal.
			foreach my $this_query (@{$query})
			{
				push @{$query_set}, $this_query;
			}
		}
	}
	else
	{
		push @{$query_set}, $query;
	}
	foreach my $id (@db_ids)
	{
		# Test access to the DB before we do the actual query
		$an->Database->_test_access({id => $id});
		
		# Do the actual query(ies)
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0085", variables => { 
			id    => $id, 
			count => $count, 
		}});
		if ($count)
		{
			# More than one query, so start a transaction block.
			$an->data->{cache}{db_fh}{$id}->begin_work;
		}
		
		foreach my $query (@{$query_set})
		{
			# TODO: Record the query
			#if ($an->Log->db_transactions())
			if (1)
			{
				$an->Log->entry({source => $source, line => $line, secure => $secure, level => 2, key => "log_0074", variables => { 
					id    => $id, 
					query => $query, 
				}});
			}
			
			if (not $an->data->{cache}{db_fh}{$id})
			{
				$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0089", variables => { id => $id }});
				next;
			}
			
			# Do the do.
			$an->data->{cache}{db_fh}{$id}->do($query) or $an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0090", variables => { 
					query    => ((not $an->Log->secure) && ($secure)) ? $query : "--", 
					server   => $say_server,
					db_error => $DBI::errstr, 
				}});
		}
		
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { count => $count }});
		if ($count)
		{
			# Commit the changes.
			$an->data->{cache}{db_fh}{$id}->commit();
		}
	}
	
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { count => $count }});
	if ($count)
	{
		# Free up some memory.
		undef $query_set;
	}
	
	return(0);
}

# =head3
# 
# Private Functions;
# 
# =cut

#############################################################################################################
# Private functions                                                                                         #
#############################################################################################################

=head2 _find_behind_databases

This returns the most up to date database ID, the time it was last updated and an array or DB IDs that are behind.

If there is a problem, C<< undef >> is returned.

Parameters;

=head3 source (required)

This is used the same as in C<< Database->connect >>'s C<< source >> parameter. Please read that for usage information.

=head3 tables (optional)

This is used the same as in C<< Database->connect >>'s C<< tables >> parameter. Please read that for usage information.

=cut
sub _find_behind_databases
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $source = $parameter->{source} ? $parameter->{source} : "";
	my $tables = $parameter->{tables} ? $parameter->{tables} : "";
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		source => $source, 
		tables => $tables, 
	}});
	
	# This should always be set, but just in case...
	if (not $source)
	{
		$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Database->_find_behind_databases()", parameter => "source" }});
		return(undef);
	}
	
	# Look at all the databases and find the most recent time stamp (and the ID of the DB).
	$an->data->{sys}{database}{source_db_id}        = 0;
	$an->data->{sys}{database}{source_updated_time} = 0;
	foreach my $id (sort {$a cmp $b} keys %{$an->data->{database}})
	{
		my $name = $an->data->{database}{$id}{name};
		my $user = $an->data->{database}{$id}{user};
		
		# Read the table's last modified_date
		my $query = "
SELECT 
    round(extract(epoch from modified_date)) 
FROM 
    updated 
WHERE 
    updated_host_uuid = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})."
AND
    updated_by = ".$an->data->{sys}{use_db_fh}->quote($source).";";
		
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			id    => $id, 
			query => $query, 
		}});
		my $last_updated = $an->Database->query({id => $id, query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
		   $last_updated = 0 if not defined $last_updated;
		   
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			last_updated                         => $last_updated, 
			"sys::database::source_updated_time" => $an->data->{sys}{database}{source_updated_time}, 
		}});
		if ($last_updated > $an->data->{sys}{database}{source_updated_time})
		{
			$an->data->{sys}{database}{source_updated_time} = $last_updated;
			$an->data->{sys}{database}{source_db_id}        = $id;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				"sys::database::source_db_id"        => $an->data->{sys}{database}{source_db_id}, 
				"sys::database::source_updated_time" => $an->data->{sys}{database}{source_updated_time}, 
			}});
		}
		
		# Get the last updated time for this database (and source).
		$an->data->{database}{$id}{last_updated} = $last_updated;
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			"sys::database::source_updated_time" => $an->data->{sys}{database}{source_updated_time}, 
			"sys::database::source_db_id"        => $an->data->{sys}{database}{source_db_id}, 
			"database::${id}::last_updated"      => $an->data->{database}{$id}{last_updated}
		}});
		
		# If we have a tables hash, look into them, too.
		if (ref($tables) eq "HASH")
		{
			foreach my $table (sort {$a cmp $b} keys %{$tables})
			{
				# I'm going to both check the number of entries in the history schema 
				my $table_name  = $an->data->{sys}{use_db_fh}->quote($table);
				   $table_name  =~ s/'(.*?)'/$1/;
				my $host_column =  $an->data->{sys}{use_db_fh}->quote($tables->{$table});
				   $host_column =~ s/'(.*?)'/$1/;
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
					table_name  => $table_name, 
					host_column => $host_column,
				}});
		
				my $query       =  "
SELECT 
    round(extract(epoch from modified_date)) 
FROM 
    history.$table_name ";
				if ($host_column)
				{
					$query .= "
WHERE 
    $host_column = ".$an->data->{sys}{use_db_fh}->quote($an->data->{sys}{host_uuid})."
";
				}
				$query .= "
ORDER BY 
    modified_date DESC
;";
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
					id    => $id, 
					query => $query, 
				}});
				
				my $last_updated = $an->Database->query({id => $id, query => $query, source => $THIS_FILE, line => __LINE__})->[0]->[0];
				   $last_updated = 0 if not defined $last_updated;
				   
				$an->data->{database}{$id}{tables}{$table}{last_updated} = $last_updated;
				$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
					"database::${id}::tables::${table}::last_updated" => $an->data->{database}{$id}{tables}{$table}{last_updated}, 
				}});
			}
		}
	}
	
	# Find which DB is most up to date.
	$an->data->{sys}{database}{to_update} = {};
	foreach my $id (sort {$a cmp $b} keys %{$an->data->{database}})
	{
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
			"sys::database::source_updated_time" => $an->data->{sys}{database}{source_updated_time}, 
			"database::${id}::last_updated"      => $an->data->{database}{$id}{last_updated}, 
		}});
		if ($an->data->{sys}{database}{source_updated_time} > $an->data->{database}{$id}{last_updated})
		{
			# This database is behind
			$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => "log_0104", variables => {
				id     => $id,
				source => $source,
			}});
			
			# A database is behind, resync
			$an->Database->_mark_database_as_behind({id => $id});
		}
		else
		{
			# This database is up to date (so far).
			$an->data->{sys}{database}{to_update}{$id}{behind} = 0;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
				"sys::database::to_update::${id}::behind" => $an->data->{sys}{database}{to_update}{$id}{behind}, 
			}});
		}
		
		# If we don't yet need a resync, and if we were passed one or more tables, check those tables
		# for differences
		if ((not $an->data->{sys}{database}{resync_needed}) && (ref($tables) eq "HASH"))
		{
			foreach my $table (sort {$a cmp $b} keys %{$tables})
			{
				if (not defined $an->data->{sys}{database}{tables}{$table}{last_updated})
				{
					# First we've seen, set the general updated time to this entry
					$an->data->{sys}{database}{tables}{$table}{last_updated} = $an->data->{database}{$id}{tables}{$table}{last_updated};
					$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
						"sys::database::tables::${table}::last_updated" => $an->data->{sys}{database}{tables}{$table}{last_updated}
					}});
				}
				
				if ($an->data->{sys}{database}{tables}{$table}{last_updated} > $an->data->{database}{$id}{tables}{$table}{last_updated})
				{
					# This database is behind
					$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, priority => "alert", key => "log_0106", variables => {
						id     => $id,
						source => $source,
						table  => $table, 
					}});
				}
				
				# Mark it as behind.
				$an->Database->_mark_database_as_behind({id => $id});
			}
		}
	}
	
	return(0);
}

=head2 _mark_database_as_behind

This method marks that a resync is needed and, if needed, switches the database this machine will read from.

Parameters;

=head3 id

This is the C<< id >> of the database being marked as "behind".

=cut
sub _mark_database_as_behind
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $id = $parameter->{id} ? $parameter->{id} : "";
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { id => $id }});
	
	$an->data->{sys}{database}{to_update}{$id}{behind} = 1;
	$an->data->{sys}{database}{resync_needed}          = 1;
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		"sys::database::to_update::${id}::behind" => $an->data->{sys}{database}{to_update}{$id}{behind}, 
		"sys::database::resync_needed"            => $an->data->{sys}{database}{resync_needed}, 
	}});
		
	# We can't trust this database for reads, so switch to another database for reads if
	# necessary.
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { 
		id                => $id, 
		"sys::read_db_id" => $an->data->{sys}{read_db_id}, 
	}});
	if ($id eq $an->data->{sys}{read_db_id})
	{
		# Switch.
		$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { ">> sys::read_db_id" => $an->data->{sys}{read_db_id} }});
		foreach my $this_id (sort {$a cmp $b} keys %{$an->data->{database}})
		{
			next if $this_id eq $id;
			$an->data->{sys}{read_db_id} = $this_id;
			$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { "<< sys::read_db_id" => $an->data->{sys}{read_db_id} }});
			last;
		}
	}
	
	return(0);
}

=head2 _test_access

This method takes a database ID and performs a simple C<< SELECT 1 >> query, wrapped in a ten second C<< alarm >>. If the database has died, the query will hang and the C<< alarm >> will fire, killing this program. If the call returns, the C<< alarm >> is cancelled.

This exists to handle the loss of a database mid-run where a normal query, which isn't wrapped in a query, could hang indefinately.

=cut
sub _test_access
{
	my $self      = shift;
	my $parameter = shift;
	my $an        = $self->parent;
	
	my $id = $parameter->{id} ? $parameter->{id} : "";
	$an->Log->variables({source => $THIS_FILE, line => __LINE__, level => 2, list => { id => $id }});
	
	# Make logging code a little cleaner
	my $say_server = $an->data->{database}{$id}{host}.":".$an->data->{database}{$id}{port}." -> ".$an->data->{database}{$id}{name};
	
	# Log our test
	$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0087", variables => { server => $say_server }});
	
	my $query = "SELECT 1";
	my $DBreq = $an->data->{cache}{db_fh}{$id}->prepare($query) or $an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0075", variables => { 
			query    => $query, 
			server   => $say_server,
			db_error => $DBI::errstr, 
		}});
	
	# Give the test query a few seconds to respond, just in case we have some latency to a remote DB.
	alarm(10);
	$DBreq->execute() or $an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0076", variables => { 
			query    => $query, 
			server   => $say_server,
			db_error => $DBI::errstr, 
		}});
	# If we're here, we made contact.
	alarm(0);
	
	# Success!
	$an->Log->entry({source => $THIS_FILE, line => __LINE__, level => 2, key => "log_0088"});
	
	return(0);
}