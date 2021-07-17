package Anvil::Tools;
# 
# This is the "root" package that manages the sub modules and controls access to their methods.
# 

BEGIN
{
	our $VERSION = "3.0.0";
	# This suppresses the 'could not find ParserDetails.ini in /PerlApp/XML/SAX' warning message in 
	# XML::Simple calls.
	#$ENV{HARNESS_ACTIVE} = 1;
}

use strict;
use warnings;
use Scalar::Util qw(weaken isweak);
use Time::HiRes;
use Data::Dumper;
use CGI;
my $THIS_FILE = "Tools.pm";

### Methods;
# data
# environment
# nice_exit
# refresh
# _add_hash_reference
# _anvil_version
# _make_hash_reference
# _set_defaults
# _set_paths

use utf8;
binmode(STDERR, ':encoding(utf-8)');
binmode(STDOUT, ':encoding(utf-8)');

# I intentionally don't use EXPORT, @ISA and the like because I want my "subclass"es to be accessed in a
# somewhat more OO style. I know some may wish to strike me down for this, but I like the idea of accessing
# methods via their containing module's name. (A La: C<< $anvil->Module->method >> rather than C<< $anvil->method >>).
use Anvil::Tools::Account;
use Anvil::Tools::Alert;
use Anvil::Tools::Cluster;
use Anvil::Tools::Convert;
use Anvil::Tools::Database;
use Anvil::Tools::DRBD;
use Anvil::Tools::Email;
use Anvil::Tools::Get;
use Anvil::Tools::Job;
use Anvil::Tools::Log;
use Anvil::Tools::Network;
use Anvil::Tools::Remote;
use Anvil::Tools::ScanCore;
use Anvil::Tools::Server;
use Anvil::Tools::Striker;
use Anvil::Tools::Storage;
use Anvil::Tools::System;
use Anvil::Tools::Template;
use Anvil::Tools::Words;
use Anvil::Tools::Validate;

=pod

=encoding utf8

=head1 NAME

Anvil::Tools

Provides a common oject handle to all Anvil::Tools::* module methods and handles invocation configuration. 

=head1 SYNOPSIS

 use Anvil::Tools;

 # Get a common object handle on all Anvil::Tools::* modules.
 my $anvil = Anvil::Tools->new();
 
 # Again, but this time sets some initial values in the '$anvil->data' hash.
 my $anvil = Anvil::Tools->new(
 {
 	data		=>	{
 		foo		=>	"",
 		bar		=>	[],
 		baz		=>	{},
 	},
 });
 
 # This example gets the handle and also sets the default user and log 
 # languages as Japanese, sets a custom log file and sets the log level to 
 # '2'.
 my $anvil = Anvil::Tools->new(
 {
 	'Log'		=>	{
 		user_language	=>	"jp",
 		log_language	=>	"jp"
 		level		=>	2,
 	},
 });

=head1 DESCRIPTION

The Anvil::Tools module and all sub-modules are designed for use by Alteeve-based applications. It can be used as a general framework by anyone interested.

Core features are;

* Supports per user, per logging language selection where translations from from XML-formatted "String" files that support UTF8 and variable substitutions.
* Support for command-line and HTML output. Skinning support for HTML-based user interfaces.
* Redundant database access, resynchronization and archiving.
* Highly-native with minimal use of external perl modules and compiled code.

=head1 METHODS

Methods in the core module;

=cut

# The constructor through which all other module's methods will be accessed.
sub new
{
	my $class     = shift;
	my $parameter = shift;
	my $self      = {
		HANDLE				=>	{
			ACCOUNT				=>	Anvil::Tools::Account->new(),
			ALERT				=>	Anvil::Tools::Alert->new(),
			CLUSTER				=>	Anvil::Tools::Cluster->new(),
			CONVERT				=>	Anvil::Tools::Convert->new(),
			DATABASE			=>	Anvil::Tools::Database->new(),
			DRBD				=>	Anvil::Tools::DRBD->new(),
			EMAIL				=>	Anvil::Tools::Email->new(),
			GET				=>	Anvil::Tools::Get->new(),
			LOG				=>	Anvil::Tools::Log->new(),
			JOB				=>	Anvil::Tools::Job->new(),
			NETWORK				=>	Anvil::Tools::Network->new(),
			REMOTE				=>	Anvil::Tools::Remote->new(),
			SCANCORE			=>	Anvil::Tools::ScanCore->new(),
			SERVER				=>	Anvil::Tools::Server->new(),
			STRIKER				=>	Anvil::Tools::Striker->new(),
			STORAGE				=>	Anvil::Tools::Storage->new(),
			SYSTEM				=>	Anvil::Tools::System->new(),
			TEMPLATE			=>	Anvil::Tools::Template->new(),
			WORDS				=>	Anvil::Tools::Words->new(),
			VALIDATE			=>	Anvil::Tools::Validate->new(),
			# This is to be removed before development ends.
			'log'			=>	{
				main			=>	"",
			},
		},
		DATA				=>	{},
		ENV_VALUES			=>	{
			ENVIRONMENT			=>	'cli',
		},
		HOST				=>	{
			# This is the host's UUID. It should never be manually set.
			UUID			=>	"",
			ANVIL_VERSION		=>	"",
		},
	};
	
	# Bless you!
	bless $self, $class;
	
	# This isn't needed, but it makes the code below more consistent with and portable to other modules.
	my $anvil = $self; 
	weaken($anvil);	# Helps avoid memory leaks. See Scalar::Utils
	
	# Get a handle on the various submodules
	$anvil->Account->parent($anvil);
	$anvil->Alert->parent($anvil);
	$anvil->Cluster->parent($anvil);
	$anvil->Convert->parent($anvil);
	$anvil->Database->parent($anvil);
	$anvil->DRBD->parent($anvil);
	$anvil->Email->parent($anvil);
	$anvil->Get->parent($anvil);
	$anvil->Log->parent($anvil);
	$anvil->Job->parent($anvil);
	$anvil->Network->parent($anvil);
	$anvil->Remote->parent($anvil);
	$anvil->ScanCore->parent($anvil);
	$anvil->Server->parent($anvil);
	$anvil->Striker->parent($anvil);
	$anvil->Storage->parent($anvil);
	$anvil->System->parent($anvil);
	$anvil->Template->parent($anvil);
	$anvil->Words->parent($anvil);
	$anvil->Validate->parent($anvil);
	
	# Set some system paths and system default variables
	$anvil->_set_defaults();
	$anvil->_set_paths();
	
	# Record the start time.
	$anvil->data->{ENV_VALUES}{START_TIME} = Time::HiRes::time;
	
	# Set passed parameters if needed.
	my $debug = 3;
	if (ref($parameter) eq "HASH")
	{
		# Local parameters...
		if ($parameter->{log_level})
		{
			$anvil->Log->level({set => $parameter->{log_level}});
		}
		if ($parameter->{log_secure})
		{
			$anvil->Log->secure({set => $parameter->{log_secure}});
		}
		if ($parameter->{debug})
		{
			$debug = $parameter->{debug};
		}
	}
	elsif ($parameter)
	{
		# Um...
		print $THIS_FILE." ".__LINE__."; Anvil::Tools->new() invoked with an invalid parameter. Expected a hash reference, but got: [$parameter]\n";
		exit(1);
	}
	
	# This will help clean up if we catch a signal.
	$SIG{INT}  = sub { $anvil->catch_sig({signal => "INT"});  };
	$SIG{TERM} = sub { $anvil->catch_sig({signal => "TERM"}); };
	
	# This sets the environment this program is running in.
	if ($ENV{SERVER_NAME})
	{
		$anvil->environment("html");
		
		# There is no PWD environment variable, so we'll use 'DOCUMENT_ROOT' as 'PWD'
		$ENV{PWD} = $ENV{DOCUMENT_ROOT};
	}
	else
	{
		$anvil->environment("cli");
	}
	
	# Setup my '$anvil->data' hash right away so that I have a place to store the strings hash.
	$anvil->data($parameter->{data}) if $parameter->{data};
	
	# Initialize the list of directories to seach.
	$anvil->Storage->search_directories({debug => $debug, initialize => 1});
	
	# I need to read the initial words early.
	$anvil->Words->read({debug => $debug});
	
	# If the local './anvil.conf' file exists, read it in.
	if (-r $anvil->data->{path}{configs}{'anvil.conf'})
	{
		$anvil->Storage->read_config({debug => 3, file => $anvil->data->{path}{configs}{'anvil.conf'}});
		
		### TODO: Should anvil.conf override parameters?
		# Let parameters override config file values.
		if ($parameter->{log_level})
		{
			$anvil->Log->level({set => $parameter->{log_level}});
		}
		if ($parameter->{log_secure})
		{
			$anvil->Log->secure({set => $parameter->{log_secure}});
		}
	}
	
	# Get the local host UUID.
	$anvil->Get->host_uuid({debug => $debug});
	
	# Read in any command line switches.
	$anvil->Get->switches({debug => $debug});
	
	# Read in the local Anvil! version.
	#...
	
	return ($self);
}

#############################################################################################################
# Public methods                                                                                            #
#############################################################################################################


=head2 data

This is the method used to access the main hash reference that all user-accessible values are stored in. This includes words, configuration file variables and so forth.

When called without an argument, it returns the existing '$anvil->data' hash reference.

 my $anvil = $anvil->data();

When called with a hash reference as the argument, it sets '$anvil->data' to the new hash.

 my $some_hash = {};
 my $anvil        = $anvil->data($some_hash);

Data can be entered into or access by treating '$anvil->data' as a normal hash reference.

 my $anvil = Anvil::Tools->new(
 {
 	data		=>	{
 		foo		=>	"",
 		bar		=>	[6, 4, 12],
 		baz		=>	{
			animal		=>	"Cat",
			thing		=>	"Boat",
		},
 	},
 });
 
 # Copy the 'Cat' value into the $animal variable.
 my $animal = $anvil->data->{baz}{animal};
 
 # Set 'A thing' in 'foo'.
 $anvil->data->{foo} = "A thing";

The C<< $anvil >> variable is set inside all modules and acts as shared storage for variables, values and references in all modules. It acts as the core storage for most applications using Anvil::Tools.

=cut
sub data
{
	my ($anvil) = shift;
	
	# Pick up the passed in hash, if any.
	$anvil->{DATA} = shift if $_[0];
	
	return ($anvil->{DATA});
}

=head2 environment

This is the method used to check or set whether the program is outputting to command line or a browser.

When called without an argument, it returns the current environment.

 if ($anvil->environment() eq "cli")
 {
 	# format for STDOUT
 }
 elsif ($anvil->environment() eq "html")
 {
 	# Use the template system to output HTML
 }

When called with a string as the argument, that string will be set as the environment string.

 $anvil->environment("cli");

Technically, any string can be used, however only 'cli' or 'html' are used by convention.

=cut
sub environment
{
	my ($anvil) = shift; 
	weaken($anvil);
	
	# Pick up the passed in delimiter, if any.
	if ($_[0])
	{
		$anvil->data->{ENV_VALUES}{ENVIRONMENT} = shift;
		
		# Load the CGI stuff if we're in a browser
		if ($anvil->data->{ENV_VALUES}{ENVIRONMENT} eq "html")
		{
			CGI::Carp->import(qw(fatalsToBrowser));
		}
	}
	
	return ($anvil->data->{ENV_VALUES}{ENVIRONMENT});
}

=head2 nice_exit

This is a simple method to exit cleanly, closing database connections and exiting with the set exit code.

Parameters;

=head3 exit_code (optional)

If set, this will be the exit code. The default is to exit with code C<< 0 >>.

=cut
sub nice_exit
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	my $exit_code = defined $parameter->{exit_code} ? $parameter->{exit_code} : 0;
	
	# Close database connections (if any).
	$anvil->Database->disconnect({debug => $debug});
	
	# Report the runtime.
	my $end_time = Time::HiRes::time;
	my $run_time = $end_time - $anvil->data->{ENV_VALUES}{START_TIME};
	my $caller   = ($0 =~ /^.*\/(.*)$/)[0];
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		's1:ENV_VALUES::START_TIME' => $anvil->data->{ENV_VALUES}{START_TIME}, 
		's2:end_time'               => $end_time, 
		's3:run_time'               => $run_time, 
		's4:caller'                 => $caller,
	}});
	$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $debug, key => "log_0135", variables => { 'caller' => $caller, runtime => $run_time }});
	
	my ($package, $filename, $line) = caller;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		's1:package'  => $package, 
		's2:filename' => $filename, 
		's3:line'     => $line,
	}});
	
	# Close the log file.
	if ($anvil->data->{HANDLE}{'log'}{main})
	{
		close $anvil->data->{HANDLE}{'log'}{main};
		$anvil->data->{HANDLE}{'log'}{main} = "";
	}
	
	exit($exit_code);
}

=head2 refresh

This method re-reads the configuration file and resets paths, defaults and re-reads the words file(s).

=cut
sub refresh
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self;
	my $debug     = defined $parameter->{debug} ? $parameter->{debug} : 3;
	
	$anvil->_set_paths();
	$anvil->_set_defaults();	# This reset the log level
	$anvil->Storage->read_config();	# This reset the log level also
	$anvil->Get->switches;		# Re-read to let switches override again.
	$anvil->Words->read();
	
	return(0);
}

#############################################################################################################
# Public methods used to access sub modules.                                                                #
#############################################################################################################

=head1 Submodule Access Methods

The methods below are used to access methods of submodules using 'C<< $anvil->Module->method() >>'.

=cut

=head2 Account

Access the C<Acount.pm> methods via 'C<< $anvil->Alert->method >>'.

=cut
sub Account
{
	my $self = shift;
	
	return ($self->{HANDLE}{ACCOUNT});
}

=head2 Alert

Access the C<Alert.pm> methods via 'C<< $anvil->Alert->method >>'.

=cut
sub Alert
{
	my $self = shift;
	
	return ($self->{HANDLE}{ALERT});
}

=head2 Cluster

Access the C<Cluster.pm> methods via 'C<< $anvil->Cluster->method >>'.

=cut
sub Cluster
{
	my $self = shift;
	
	return ($self->{HANDLE}{CLUSTER});
}

=head2 Convert

Access the C<Convert.pm> methods via 'C<< $anvil->Convert->method >>'.

=cut
sub Convert
{
	my $self = shift;
	
	return ($self->{HANDLE}{CONVERT});
}

=head2 Database

Access the C<Database.pm> methods via 'C<< $anvil->Database->method >>'.

=cut
sub Database
{
	my $self = shift;
	
	return ($self->{HANDLE}{DATABASE});
}

=head2 DRBD

Access the C<DRBD.pm> methods via 'C<< $anvil->DRBD->method >>'.

=cut
sub DRBD
{
	my $self = shift;
	
	return ($self->{HANDLE}{DRBD});
}

=head2 Email

Access the C<Email.pm> methods via 'C<< $anvil->Email->method >>'.

=cut
sub Email
{
	my $self = shift;
	
	return ($self->{HANDLE}{EMAIL});
}

=head2 Get

Access the C<Get.pm> methods via 'C<< $anvil->Get->method >>'.

=cut
sub Get
{
	my $self = shift;
	
	return ($self->{HANDLE}{GET});
}

=head2 Job

Access the C<Job.pm> methods via 'C<< $anvil->Log->method >>'.

=cut
sub Job
{
	my $self = shift;
	
	return ($self->{HANDLE}{JOB});
}

=head2 Log

Access the C<Log.pm> methods via 'C<< $anvil->Log->method >>'.

=cut
sub Log
{
	my $self = shift;
	
	return ($self->{HANDLE}{LOG});
}

=head2 Network

Access the C<Network.pm> methods via 'C<< $anvil->Network->method >>'.

=cut
sub Network
{
	my $self = shift;
	
	return ($self->{HANDLE}{NETWORK});
}

=head2 Remote

Access the C<Remote.pm> methods via 'C<< $anvil->Remote->method >>'.

=cut
sub Remote
{
	my $self = shift;
	
	return ($self->{HANDLE}{REMOTE});
}

=head2 ScanCore

Access the C<ScanCore.pm> methods via 'C<< $anvil->ScanCore->method >>'.

=cut
sub ScanCore
{
	my $self = shift;
	
	return ($self->{HANDLE}{SCANCORE});
}

=head2 Server

Access the C<Server.pm> methods via 'C<< $anvil->Server->method >>'.

=cut
sub Server
{
	my $self = shift;
	
	return ($self->{HANDLE}{SERVER});
}

=head2 Striker

Access the C<Striker.pm> methods via 'C<< $anvil->Striker->method >>'.

=cut
sub Striker
{
	my $self = shift;
	
	return ($self->{HANDLE}{STRIKER});
}

=head2 Storage

Access the C<Storage.pm> methods via 'C<< $anvil->Storage->method >>'.

=cut
sub Storage
{
	my $self = shift;
	
	return ($self->{HANDLE}{STORAGE});
}

=head2 System

Access the C<System.pm> methods via 'C<< $anvil->System->method >>'.

=cut
sub System
{
	my $self = shift;
	
	return ($self->{HANDLE}{SYSTEM});
}

=head2 Template

Access the C<Template.pm> methods via 'C<< $anvil->Template->method >>'.

=cut
sub Template
{
	my $self = shift;
	
	return ($self->{HANDLE}{TEMPLATE});
}

=head2 Words

Access the C<Words.pm> methods via 'C<< $anvil->Words->method >>'.

=cut
sub Words
{
	my $self = shift;
	
	return ($self->{HANDLE}{WORDS});
}

=head2 Validate

Access the C<Validate.pm> methods via 'C<< $anvil->Validate->method >>'.

=cut
sub Validate
{
	my $self = shift;
	
	return ($self->{HANDLE}{VALIDATE});
}


=head1 Private Functions;

These methods generally should never be called from a program using Anvil::Tools. However, we are not your boss.

=cut

#############################################################################################################
# Private methods                                                                                           #
#############################################################################################################

=head2 _add_hash_reference

This is a helper to the '$anvil->_make_hash_reference' method. It is called each time a new string is to be created as a new hash key in the passed hash reference.

NOTE: Contributed by Shaun Fryer and Viktor Pavlenko by way of Toronto Perl Mongers.

=cut
sub _add_hash_reference
{
	my $self  = shift;
	my $href1 = shift;
	my $href2 = shift;
	
	for my $key (keys %$href2)
	{
		if (ref $href1->{$key} eq 'HASH')
		{
			$self->_add_hash_reference( $href1->{$key}, $href2->{$key} );
		}
		else
		{
			$href1->{$key} = $href2->{$key};
		}
	}
}

=head2 _anvil_version

=cut
sub _anvil_version
{
	my $self  = shift;
	my $anvil = $self;
	
	$anvil->{HOST}{ANVIL_VERSION}  = "" if not defined $anvil->{HOST}{ANVIL_VERSION};
	$anvil->{HOST}{SCHEMA_VERSION} = "" if not defined $anvil->{HOST}{SCHEMA_VERSION};
	if ($anvil->{HOST}{ANVIL_VERSION} eq "")
	{
		# Try to read the local Anvil! version.
		($anvil->{HOST}{ANVIL_VERSION}, $anvil->{HOST}{SCHEMA_VERSION}) = $anvil->Get->anvil_version();
	}
	
	return($anvil->{HOST}{ANVIL_VERSION}, $anvil->{HOST}{SCHEMA_VERSION});
}

=head2 _get_hash_reference

This is called when we need to parse a double-colon separated string into two or more elements which represent keys in the 'C<< $anvil->data >>' hash. Once suitably split up, the value is read and returned.

For example;

 $anvil->data->{foo}{bar} = "baz";
 my $value = $anvil->_get_hash_reference({ key => "foo::bar" });

The 'C<< $value >>' now contains "C<< baz >>".

NOTE: If the key is not found, 'C<< undef >>' is returned.

Parameters;

=head3 key (required)

This is the key to return the value for. If it is not passed, or if it does not have 'C<< :: >>' in it, 'C<< undef >>' will be returned.

=cut
sub _get_hash_reference
{
	# 'href' is the hash reference I am working on.
	my $self      = shift;
	my $parameter = shift;
	my $anvil        = $self;
	
	die "$THIS_FILE ".__LINE__."; The hash key string: [".$parameter->{key}."] doesn't seem to be valid. It should be a string in the format 'foo::bar::baz'.\n" if $parameter->{key} !~ /::/;
	
	# Split up the keys.
	my $key   = $parameter->{key} ? $parameter->{key} : "";
	my $value = undef;	# We return 'undef' so that the caller can tell the difference between an empty string versus nothing found.
	if ($key =~ /::/)
	{
		my @keys     = split /::/, $key;
		my $last_key = pop @keys;
		
		# Re-order the array.
		my $current_hash_ref = $anvil->data;
		foreach my $key (@keys)
		{
			$current_hash_ref = $current_hash_ref->{$key};
		}
		
		$value = $current_hash_ref->{$last_key};
	}
	
	return ($value);
}

=head2 _make_hash_reference

This takes a string with double-colon seperators and divides on those double-colons to create a hash reference where each element is a hash key.

NOTE: Contributed by Shaun Fryer and Viktor Pavlenko by way of Toronto Perl Mongers.

=cut
sub _make_hash_reference
{
	my $self       = shift;
	my $href       = shift;
	my $key_string = shift;
	my $value      = shift;
	
	my @keys            = split /::/, $key_string;
	my $last_key        = pop @keys;
	my $_href           = {};
	$_href->{$last_key} = $value;
	while (my $key = pop @keys)
	{
		my $elem      = {};
		$elem->{$key} = $_href;
		$_href        = $elem;
	}
	$self->_add_hash_reference($href, $_href);
}

=head2 _set_defaults

This sets default variable values for the program.

=cut
sub _set_defaults
{
	my ($anvil) = shift;
	
	$anvil->data->{scancore} = {
		timing				=>	{
			# Delay between DB connection attempts when no databases are available?
			agent_runtime			=>	30,
			db_retry_interval		=>	2,
			# Delay between scans?
			run_interval			=>	60,
		},
		database			=>	{
			# This is the number of hours, after which, transient data (like temperature and 
			# power data) is considered "old" and gets deleted from the database.
			age_out				=>	24,
		},
	};
	$anvil->data->{sys} = {
		apache				=>	{
			user				=>	"admin",
		},
		daemon				=>	{
			dhcpd				=>	"dhcpd.service",
			firewalld			=>	"firewalld.service",
			httpd				=>	"httpd.service",
			postgresql			=>	"postgresql.service",
			tftp				=>	"tftp.socket",
		},
		daemons				=>	{
			restart_firewalld		=>	1,
		},
		database			=>	{
			archive				=>	{
				compress			=>	1,
				count				=>	50000,
				directory			=>	"/usr/local/anvil/archives/",
				division			=>	6000,
				trigger				=>	100000,
			},
			connections				=>	0,
			failed_connection_log_level	=>	1,
			local_lock_active		=>	0,
			local_uuid			=>	"",
			locking_reap_age		=>	300,
			log_transactions		=>	0,
			maximum_batch_size		=>	25000,
			name				=>	"anvil",
			read_uuid			=>	"",
			test_table			=>	"hosts",
			timestamp			=>	"",
			user				=>	"admin",
			use_handle			=>	"",
		},
		host_type			=>	"",
		host_uuid			=>	"",
		language			=>	"en_CA",
		'log'				=>	{
			date				=>	1,
			# Stores the '-v|...|-vvv' so that shell calls can be run at the same level as the 
			# avtive program when set by the user at the command line.
			level				=>	"",
			# This is set to '1' when a log call might become recursive.
			disable				=>	0,
		},
		manage				=>	{
			firewall			=>	1,
		},
		password			=>	{
			algorithm			=>	"sha512",
			hash_count			=>	500000,
			salt_length			=>	16,
		},
		privacy				=>	{
			strong				=>	0,
		},
		# On actual RHEL systems, this will be used to ensure that given repos are enabled on given 
		# machines types. Obviously, this requires that the host has been subscribed.
		rhel				=>	{
			repos				=>	{
				common				=>	["codeready-builder-for-rhel-8-x86_64-rpms"],
				dashboard			=>	[],
				dr				=>	[],
				node				=>	["rhel-8-for-x86_64-highavailability-rpms"],
			},
		},
		servers				=>	{
			# This is the list of OSes short in the user's short list of OS types to 
			# optimize for. The full the list is available by running: 
			# /usr/bin/osinfo-query os
			os_short_list			=>	"rhel5.11, rhel6.10, rhel7.9, rhel8.3, win10, win2k16, win2k19",
		},
		terminal			=>	{
			columns				=>	80,
			stty				=>	"",
		},
		use_base2			=>	1,
		user				=>	{
			name				=>	"admin",
			cookie_valid			=>	0,
			language			=>	"en_CA",
			skin				=>	"alteeve",
		},
		# This is data filled from the active user's database table.
		users				=>	{
			user_name			=>	"",
			user_password_hash		=>	"", 
			user_salt			=>	"", 
			user_algorithm			=>	"", 
			user_hash_count			=>	"", 
			user_language			=>	"", 
			user_is_admin			=>	"", 
			user_is_experienced		=>	"", 
			user_is_trusted			=>	"", 
		},
	};
	$anvil->data->{defaults} = {
		database	=>	{
			locking		=>	{
				reap_age	=>	300,
			}
		},
		language	=>	{
			# Default language for all output shown to a user.
			output		=>	'en_CA',
		},
		limits		=>	{
			# This is the maximum number of times we're allow to loop when injecting variables 
			# into a string being processed in Anvil::Tools::Words->string();
			string_loops	=>	1000,
		},
		'log'		=>	{
			db_transactions	=>	0,
			facility	=>	"local0",
			language	=>	"en_CA",
			level		=>	1,
			secure		=>	0,
			server		=>	"",
			tag		=>	"anvil",
		},
		# NOTE: These are here to allow foreign users to override western defaults in anvil.conf.
		kickstart	=>	{
			keyboard	=>	"--vckeymap=us --xlayouts='us'",
			password	=>	"Initial1",
			timezone	=>	"Etc/GMT --isUtc",
		},
		# See 'striker' -> 'sub generate_ip()' function comments for details on how m3 IPs are handled.
		network		=>	{
			# BCN starts at 10.200(+n)/16
			bcn		=>	{
				network             => "10.200.0.0",
				subnet_mask         => "255.255.0.0",
				switch_octet3       => "1",
				pdu_octet3          => "2",
				ups_octet3          => "3",
				striker_octet3	    => "4",
				striker_ipmi_octet3 => "5",
			},
			dns		=>	"8.8.8.8, 8.8.4.4",
			# The IFN will not be under our control. So for suggestion to the user purpose only, 
			# IFN starts at 10.255/16
			ifn		=>	{
				network	       => "10.255.0.0",
				subnet_mask    => "255.255.0.0",
				striker_octet3 => "4",
			},
			# SN starts at 10.100(+n)/16
			sn		=>	{
				network     => "10.100.0.0",
				subnet_mask => "255.255.0.0",
			},
			test		=>	{
				domains		=>	["alteeve.com", "redhat.com", "google.com"],
			},
		},
		template	=>	{
			html		=>	"alteeve",
		},
	};
	
	return(0);
}

=head2 _set_paths

This sets default paths to many system commands, checking to make sure the binary exists at the path and, if not, try to find it.

=cut
sub _set_paths
{
	my ($anvil) = shift;
	
	# Executables
	$anvil->data->{path} = {
			configs			=>	{
				'alteeve-release.repo'		=>	"/etc/yum.repos.d/alteeve-release.repo",
				'anvil.conf'			=>	"/etc/anvil/anvil.conf",
				'anvil.version'			=>	"/etc/anvil/anvil.version",
				'autoindex.conf'		=>	"/etc/httpd/conf.d/autoindex.conf", 
				'cib.xml'			=>	"/var/lib/pacemaker/cib/cib.xml",
				'corosync.conf'			=>	"/etc/corosync/corosync.conf",
				'dhcpd.conf'			=>	"/etc/dhcp/dhcpd.conf",
				'dnf.conf'			=>	"/etc/dnf/dnf.conf",
				'firewalld.conf'		=>	"/etc/firewalld/firewalld.conf",
				'global-common.conf'		=>	"/etc/drbd.d/global_common.conf",
				hostname			=>	"/etc/hostname", 
				hosts				=>	"/etc/hosts", 
				'httpd.conf'			=>	"/etc/httpd/conf/httpd.conf", 
				'journald_anvil'		=>	"/etc/systemd/journald.conf.d/anvil.conf",
				'journald.conf'			=>	"/etc/systemd/journald.conf", 
				'lvm.conf'			=>	"/etc/lvm/lvm.conf",
				'pg_hba.conf'			=>	"/var/lib/pgsql/data/pg_hba.conf",
				'postgresql.conf'		=>	"/var/lib/pgsql/data/postgresql.conf",
				pxe_default			=>	"/var/lib/tftpboot/pxelinux.cfg/default",
				pxe_uefi			=>	"/var/lib/tftpboot/pxelinux.cfg/uefi",
				pxe_grub			=>	"/var/lib/tftpboot/grub.cfg",
				postfix_main			=>	"/etc/postfix/main.cf",
				postfix_relay_password		=>	"/etc/postfix/relay_password",
				ssh_config			=>	"/etc/ssh/ssh_config",
				'type.striker'			=>	"/etc/anvil/type.striker",
				'type.dr'			=>	"/etc/anvil/type.dr",
				'type.node'			=>	"/etc/anvil/type.node",
			},
			data			=>	{
				'.htpasswd'			=>	"/etc/httpd/.htpasswd",
				'chrony.conf'			=>	"/etc/chrony.conf",
				group				=>	"/etc/group",
				issue				=>	"/etc/issue",
				httpd_conf			=>	"/etc/httpd/conf/httpd.conf",
				host_ssh_key			=>	"/etc/ssh/ssh_host_ecdsa_key.pub",
				host_uuid			=>	"/etc/anvil/host.uuid",
				network_cache			=>	"/tmp/network_cache.anvil",
				passwd				=>	"/etc/passwd",
				'redhat-release'		=>	"/etc/redhat-release",
				fences_unified_metadata		=>	"/var/www/html/fences_unified_metadata.xml",
			},
			directories		=>	{
				alert_emails			=>	"/var/spool/anvil",
				anvil				=>	"/etc/anvil",
				backups				=>	"/root/anvil-backups",
				bonds				=>	"/proc/net/bonding",
				'cgi-bin'			=>	"/var/www/cgi-bin",
				drbd_resources			=>	"/etc/drbd.d/",
				fence_agents			=>	"/usr/sbin",
				firewalld_services		=>	"/usr/lib/firewalld/services",
				firewalld_zones_etc		=>	"/etc/firewalld/zones",		# Changes when firewall-cmd ... --permanent is used.
				firewalld_zones			=>	"/usr/lib/firewalld/zones",
				html				=>	"/var/www/html",
				ifcfg				=>	"/etc/sysconfig/network-scripts",
				journald			=>	"/var/log/journal", 
				resource_status			=>	"/sys/kernel/debug/drbd/resources",
				scan_agents			=>	"/usr/sbin/scancore-agents",
				shared				=>	{
					archives			=>	"/mnt/shared/archives",
					base				=>	"/mnt/shared",
					definitions			=>	"/mnt/shared/definitions",
					files				=>	"/mnt/shared/files",
					incoming			=>	"/mnt/shared/incoming",
					provision			=>	"/mnt/shared/provision",
					temp				=>	"/mnt/shared/temp",
				},
				skins				=>	"/var/www/html/skins",
				status				=>	"/var/www/html/status",
				syslinux			=>	"/usr/share/syslinux",
				tftpboot			=>	"/var/lib/tftpboot",
				tools				=>	"/usr/sbin",
				units				=>	"/usr/lib/systemd/system",
			},
			exe			=>	{
				'alteeve-repo-setup'		=>	"/usr/sbin/alteeve-repo-setup",
				'anvil-boot-server'		=>	"/usr/sbin/anvil-boot-server",
				'anvil-change-password'		=>	"/usr/sbin/anvil-change-password",
				'anvil-check-memory'		=>	"/usr/sbin/anvil-check-memory",
				'anvil-configure-host'		=>	"/usr/sbin/anvil-configure-host",
				'anvil-daemon'			=>	"/usr/sbin/anvil-daemon",
				'anvil-delete-server'		=>	"/usr/sbin/anvil-delete-server",
				'anvil-download-file'		=>	"/usr/sbin/anvil-download-file",
				'anvil-file-details'		=>	"/usr/sbin/anvil-file-details",
				'anvil-join-anvil'		=>	"/usr/sbin/anvil-join-anvil",
				'anvil-maintenance-mode'	=>	"/usr/sbin/anvil-maintenance-mode",
				'anvil-manage-firewall'		=>	"/usr/sbin/anvil-manage-firewall",
				'anvil-manage-keys'		=>	"/usr/sbin/anvil-manage-keys",
				'anvil-manage-power'		=>	"/usr/sbin/anvil-manage-power",
				'anvil-migrate-server'		=>	"/usr/sbin/anvil-migrate-server",
				'anvil-parse-fence-agents'	=>	"/usr/sbin/anvil-parse-fence-agents",
				'anvil-provision-server'	=>	"/usr/sbin/anvil-provision-server",
				'anvil-report-memory'		=>	"/usr/sbin/anvil-report-memory",
				'anvil-safe-start'		=>	"/usr/sbin/anvil-safe-start",
				'anvil-safe-stop'		=>	"/usr/sbin/anvil-safe-stop",
				'anvil-shutdown-server'		=>	"/usr/sbin/anvil-shutdown-server",
				'anvil-sync-shared'		=>	"/usr/sbin/anvil-sync-shared",
				'anvil-update-files'		=>	"/usr/sbin/anvil-update-files",
				'anvil-update-states'		=>	"/usr/sbin/anvil-update-states",
				'anvil-update-system'		=>	"/usr/sbin/anvil-update-system",
				blockdev			=>	"/usr/sbin/blockdev",
				bridge				=>	"/usr/sbin/bridge",
				bzip2				=>	"/usr/bin/bzip2",
				'call_striker-get-peer-data'	=>	"/usr/sbin/call_striker-get-peer-data",
				cat				=>	"/usr/bin/cat",
				'chmod'				=>	"/usr/bin/chmod",
				'chown'				=>	"/usr/bin/chown",
				chronyc				=>	"/usr/bin/chronyc",
				cibadmin			=>	"/usr/sbin/cibadmin",
				'corosync-quorumtool'		=>	"/usr/sbin/corosync-quorumtool", 
				cp				=>	"/usr/bin/cp",
				createdb			=>	"/usr/bin/createdb",
				createrepo_c			=>	"/usr/bin/createrepo_c",
				createuser			=>	"/usr/bin/createuser",
				crm_error			=>	"/usr/sbin/crm_error",
				crm_resource			=>	"/usr/sbin/crm_resource",
				crm_mon				=>	"/usr/sbin/crm_mon",
				df				=>	"/usr/bin/df",
				dmidecode			=>	"/usr/sbin/dmidecode",
				dnf				=>	"/usr/bin/dnf",
				drbdadm				=>	"/usr/sbin/drbdadm",
				drbdsetup			=>	"/usr/sbin/drbdsetup",
				echo				=>	"/usr/bin/echo",
				ethtool				=>	"/usr/sbin/ethtool",
				expect				=>	"/usr/bin/expect", 
				fence_pacemaker			=>	"/usr/sbin/fence_pacemaker",
				'firewall-cmd'			=>	"/usr/bin/firewall-cmd",
				free				=>	"/usr/bin/free",
				gcc				=>	"/usr/bin/gcc",
				getent				=>	"/usr/bin/getent",
				gethostip			=>	"/usr/bin/gethostip",
				'grep'				=>	"/usr/bin/grep", 
				groupadd			=>	"/usr/sbin/groupadd",
				head				=>	"/usr/bin/head",
				hostnamectl			=>	"/usr/bin/hostnamectl",
				hpacucli			=>	"/usr/sbin/hpacucli",
				htpasswd			=>	"/usr/bin/htpasswd",
				ifdown				=>	"/sbin/ifdown",
				ifup				=>	"/sbin/ifup",
				ip				=>	"/usr/sbin/ip",
				'ipmi-oem'			=>	"/usr/sbin/ipmi-oem",
				ipmitool			=>	"/usr/bin/ipmitool",
				'iptables-save'			=>	"/usr/sbin/iptables-save",
				journalctl			=>	"/usr/bin/journalctl",
				logger				=>	"/usr/bin/logger",
				ls				=>	"/usr/bin/ls",
				lsblk				=>	"/usr/bin/lsblk",
				lshw				=>	"/usr/sbin/lshw",
				lspci				=>	"/usr/sbin/lspci",
				lvchange			=>	"/usr/sbin/lvchange",
				lvcreate			=>	"/usr/sbin/lvcreate",
				lvdisplay			=>	"/usr/sbin/lvdisplay",
				lvremove			=>	"/usr/sbin/lvremove",
				lvrename			=>	"/usr/sbin/lvrename",
				lvs				=>	"/usr/sbin/lvs", 
				lvscan				=>	"/usr/sbin/lvscan", 
				mailx				=>	"/usr/bin/mailx",
				man				=>	"/usr/bin/man",
				md5sum				=>	"/usr/bin/md5sum",
				'mkdir'				=>	"/usr/bin/mkdir",
				modifyrepo_c			=>	"/usr/bin/modifyrepo_c",
				mv				=>	"/usr/bin/mv",
				nmap				=>	"/usr/bin/nmap",
				nmcli				=>	"/bin/nmcli",
				ocf_alteeve			=>	"/usr/lib/ocf/resource.d/alteeve/server",
				openssl				=>	"/usr/bin/openssl", 
				'osinfo-query'			=>	"/usr/bin/osinfo-query",
				passwd				=>	"/usr/bin/passwd",
				pcs				=>	"/usr/sbin/pcs",
				perccli64			=>	"/opt/MegaRAID/perccli/perccli64",
				ping				=>	"/usr/bin/ping",
				pgrep				=>	"/usr/bin/pgrep",
				ps				=>	"/usr/bin/ps",
				psql				=>	"/usr/bin/psql",
				'postgresql-setup'		=>	"/usr/bin/postgresql-setup",
				postmap				=>	"/usr/sbin/postmap",
				postqueue			=>	"/usr/sbin/postqueue",
				pwd				=>	"/usr/bin/pwd",
				pvs				=>	"/usr/sbin/pvs",
				pvscan				=>	"/usr/sbin/pvscan",
				rm				=>	"/usr/bin/rm",
				rpm				=>	"/usr/bin/rpm",
				rsync				=>	"/usr/bin/rsync",
				sed				=>	"/usr/bin/sed", 
				'shutdown'			=>	"/usr/sbin/shutdown",
				snmpget				=>	"/usr/bin/snmpget",
				snmpset				=>	"/usr/bin/snmpset",
				'ssh-keygen'			=>	"/usr/bin/ssh-keygen",
				'ssh-keyscan'			=>	"/usr/bin/ssh-keyscan",
				'stat'				=>	"/usr/bin/stat",
				stonith_admin			=>	"/usr/sbin/stonith_admin",
				storcli64			=>	"/opt/MegaRAID/storcli/storcli64",
				strings				=>	"/usr/bin/strings",
				'striker-auto-initialize-all'	=>	"/usr/sbin/striker-auto-initialize-all",
				'striker-get-peer-data'		=>	"/usr/sbin/striker-get-peer-data",
				'striker-initialize-host'	=>	"/usr/sbin/striker-initialize-host",
				'striker-manage-install-target'	=>	"/usr/sbin/striker-manage-install-target",
				'striker-manage-peers'		=>	"/usr/sbin/striker-manage-peers",
				'striker-manage-vnc-pipes'	=>	"/usr/sbin/striker-manage-vnc-pipes",
				'striker-open-ssh-tunnel'	=>	"/usr/sbin/striker-open-ssh-tunnel",
				'striker-parse-oui'		=>	"/usr/sbin/striker-parse-oui",
				'striker-prep-database'		=>	"/usr/sbin/striker-prep-database",
				'striker-scan-network'		=>	"/usr/sbin/striker-scan-network",
				stty				=>	"/usr/bin/stty",
				su				=>	"/usr/bin/su",
				'subscription-manager'		=>	"/usr/sbin/subscription-manager",
				swapon				=>	"/usr/sbin/swapon",
				systemctl			=>	"/usr/bin/systemctl",
				timeout				=>	"/usr/bin/timeout",
				touch				=>	"/usr/bin/touch",
				tput				=>	"/usr/bin/tput", 
				'tr'				=>	"/usr/bin/tr",
				uname				=>	"/usr/bin/uname",
				unzip				=>	"/usr/bin/unzip",
				useradd				=>	"/usr/sbin/useradd",
				usermod				=>	"/usr/sbin/usermod",
				uuidgen				=>	"/usr/bin/uuidgen",
				virsh				=>	"/usr/bin/virsh",
				'virt-install'			=>	"/usr/bin/virt-install",
				wipefs				=>	"/usr/sbin/wipefs", 
				vgs				=>	"/usr/sbin/vgs",
				vgscan				=>	"/usr/sbin/vgscan",
				wc				=>	"/usr/bin/wc",
				wget				=>	"/usr/bin/wget",
				yum				=>	"/usr/bin/yum",
			},
			json			=>	{
				all_status			=>	"all_status.json",
				files				=>	"files.json",
			},
			'lock'			=>	{
				database			=>	"/tmp/anvil-tools.database.lock",
			},
			'log'			=>	{
				main				=>	"/var/log/anvil.log",
				alert				=>	"/var/log/anvil.alert.log",
			},
			proc			=>	{
				cpuinfo				=>	"/proc/cpuinfo",
				meminfo				=>	"/proc/meminfo",
				uptime				=>	"/proc/uptime",
			},
			secure			=>	{
				postgres_pgpass			=>	"/var/lib/pgsql/.pgpass",
			},
			sql			=>	{
				'anvil.sql'			=>	"/usr/share/anvil/anvil.sql",
			},
			systemd			=>	{
				httpd_enabled_symlink		=>	"/etc/systemd/system/multi-user.target.wants/httpd.service",
				tftp_enabled_symlink		=>	"/etc/systemd/system/sockets.target.wants/tftp.socket",
			},
			urls			=>	{
				skins				=>	"/skins",
				oui_file			=>	"http://standards.ieee.org/develop/regauth/oui/oui.txt",
				alteeve_repo			=>	"https://www.alteeve.com/an-repo/m3/anvil-release-latest.noarch.rpm",
			},
			words			=>	{
				'words.xml'			=>	"/usr/share/anvil/words.xml",
			},
	};
	
	# Make sure we actually have the requested files.
	foreach my $type (sort {$a cmp $b} keys %{$anvil->data->{path}})
	{
		# We don't look for urls because they're relative to the domain. We also don't look for 
		# configs as we might find backups.
		next if $type eq "urls";
		next if $type eq "configs";
		foreach my $file (sort {$a cmp $b} keys %{$anvil->data->{path}{$type}})
		{
			if (not -e $anvil->data->{path}{$type}{$file})
			{
				my $full_path = $anvil->Storage->find({file => $file});
				if (($full_path) && ($full_path ne "#!not_found!#"))
				{
					$anvil->data->{path}{$type}{$file} = $full_path;
				}
			}
		}
	};
	
	return(0);
}

=head1 Exit Codes

=head2 C<1>

Anvil::Tools->new() passed something other than a hash reference.

=head2 C<2>

Failed to find the requested file in C<< Anvil::Tools::Storage->find >> and 'fatal' was set.

=head1 Requirements

The following packages are required on EL7.

* C<expect>
* C<httpd>
* C<mailx>
* C<perl-Test-Simple>
* C<policycoreutils-python>
* C<postgresql>
* C<syslinux>
* C<perl-XML-Simple>

=head1 Recommended Packages

The following packages provide non-critical functionality. 

* C<subscription-manager>

=cut


# This catches SIGINT and SIGTERM and fires out an email before shutting down.
sub catch_sig
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self;
	my $signal    = $parameter->{signal} ? $parameter->{signal} : "";
	
	if ($signal)
	{
		print "\n\nProcess with PID: [$$] exiting on SIG".$signal.".\n";
		
		if ($anvil->data->{sys}{terminal}{stty})
		{
			# Restore the terminal.
			print "Restoring the terminal\n";
			$anvil->System->call({shell_call => $anvil->data->{path}{exe}{stty}." ".$anvil->data->{sys}{terminal}{stty}});
		}
	}
	
	# Exit with '0' so shutdowns from systemd doesn't think we failed.
	$anvil->nice_exit({exit_code => 0});
}


1;
