package Anvil::Tools::Storage;
# 
# This module contains methods used to handle storage related tasks
# 

use strict;
use warnings;
use Data::Dumper;
use Scalar::Util qw(weaken isweak);

our $VERSION  = "3.0.0";
my $THIS_FILE = "Storage.pm";

### Methods;
# change_mode
# change_owner
# check_md5sums
# copy_file
# find
# make_directory
# read_config
# read_file
# read_mode
# record_md5sums
# search_directories
# write_file

=pod

=encoding utf8

=head1 NAME

Anvil::Tools::Storage

Provides all methods related to storage on a system.

=head1 SYNOPSIS

 use Anvil::Tools;

 # Get a common object handle on all Anvil::Tools modules.
 my $anvil = Anvil::Tools->new();
 
 # Access to methods using '$anvil->Storage->X'. 
 # 
 # Example using 'find()';
 my $foo_path = $anvil->Storage->find({file => "foo"});

=head1 METHODS

Methods in this module;

=cut
sub new
{
	my $class = shift;
	my $self  = {
		SEARCH_DIRECTORIES	=>	\@INC,
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
		weaken($self->{HANDLE}{TOOLS});;
	}
	
	return ($self->{HANDLE}{TOOLS});
}


#############################################################################################################
# Public methods                                                                                            #
#############################################################################################################

=head2 change_mode

This changes the mode of a file or directory.

 $anvil->Storage->change_mode({target => "/tmp/foo", mode => "0644"});

If it fails to write the file, an alert will be logged.

Parameters;

=head3 target (required)

This is the file or directory to change the mode on.

=head3 mode (required)

This is the numeric mode to set on the file. It expects four digits to cover the sticky bit, but will work with three digits.

=cut
sub change_mode
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $target = defined $parameter->{target} ? $parameter->{target} : "";
	my $mode   = defined $parameter->{mode}   ? $parameter->{mode}   : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		target => $target,
		mode   => $mode,
	}});
	
	my $error = 0;
	if (not $target)
	{
		# No target...
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Storage->change_mode()", parameter => "target" }});
		$error = 1;
	}
	if (not $mode)
	{
		# No mode...
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Storage->change_mode()", parameter => "mode" }});
		$error = 1;
	}
	elsif (($mode !~ /^\d\d\d$/) && ($mode !~ /^\d\d\d\d$/))
	{
		# Invalid mode
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0038", variables => { mode => $mode }});
		$error = 1;
	}
	
	if (not $error)
	{
		my $shell_call = $anvil->data->{path}{exe}{'chmod'}." $mode $target";
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0011", variables => { shell_call => $shell_call }});
		open (my $file_handle, $shell_call." 2>&1 |") or $anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0014", variables => { shell_call => $shell_call, error => $! }});
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0017", variables => { line => $line }});
		}
		close $file_handle;
	}
	
	return(0);
}

=head2 change_owner

This changes the owner and/or group of a file or directory.

 $anvil->Storage->change_owner({target => "/tmp/foo", mode => "0644"});

If it fails to write the file, an alert will be logged and 'C<< 1 >>' will be returned. Otherwise, 'C<< 0 >>' will be returned.

Parameters;

=head3 target (required)

This is the file or directory to change the mode on.

=head3 group (optional)

This is the group name or UID to set the target to.

=head3 user (optional)

This is the user name or UID to set the target to.

=cut
sub change_owner
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $target = defined $parameter->{target} ? $parameter->{target} : "";
	my $group  = defined $parameter->{group}  ? $parameter->{group}  : "";
	my $user   = defined $parameter->{user}   ? $parameter->{user}   : "";
	my $debug  = 3;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		target => $target,
		group  => $group,
		user   => $user,
	}});
	
	# Make sure the user and group and just one digit or word.
	$user  =~ s/^(\S+)\s.*$/$1/;
	$group =~ s/^(\S+)\s.*$/$1/;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { 
		group => $group, 
		user  => $user,
	}});
	
	my $string = "";
	my $error  = 0;
	if (not $target)
	{
		# No target...
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Storage->change_owner()", parameter => "target" }});
		$error = 1;
	}
	if (not -e $target)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0051", variables => {target => $target }});
		$error = 1;
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { user => $user }});
	if ($user ne "")
	{
		$string = $user;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { string => $string }});
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { group => $group }});
	if ($group ne "")
	{
		$string .= ":".$group;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { string => $string }});
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { error => $error, string => $string }});
	if ((not $error) && ($string ne ""))
	{
		my $shell_call = $anvil->data->{path}{exe}{'chown'}." $string $target";
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $debug, key => "log_0011", variables => { shell_call => $shell_call }});
		open (my $file_handle, $shell_call." 2>&1 |") or $anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0014", variables => { shell_call => $shell_call, error => $! }});
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => $debug, key => "log_0017", variables => { line => $line }});
		}
		close $file_handle;
	}
	
	return($error);
}

=head2 check_md5sums

This is one half of a tool to let daemons detect when something they use has changed on disk and restart if any changes are found.

This checks the md5sum of the calling application and all perl modules that are loaded and compares them against the sums seem earlier via C<< record_md5sums >>. If any sums don't match, C<< 1 >> is returned. If no changes were seen, C<< 0 >> is returned.

=cut
sub check_md5sums
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# We'll set this if anything has changed.
	my $exit   = 0;
	my $caller = $0;
	
	# Have we changed?
	$anvil->data->{md5sum}{$caller}{now} = $anvil->Get->md5sum({file => $0});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		"md5sum::${caller}::start_time" => $anvil->data->{md5sum}{$caller}{start_time},
		"md5sum::${caller}::now"        => $anvil->data->{md5sum}{$caller}{now},
	}});
	
	if ($anvil->data->{md5sum}{$caller}{now} ne $anvil->data->{md5sum}{$caller}{start_time})
	{
		# Exit.
		$exit = 1;
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "warn", key => "message_0013", variables => { file => $0 }});
	}
	
	# What about our modules?
	foreach my $module (sort {$a cmp $b} keys %INC)
	{
		my $module_file = $INC{$module};
		my $module_sum  = $anvil->Get->md5sum({file => $module_file});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			module      => $module,
			module_file => $module_file, 
			module_sum  => $module_sum,
		}});
		
		$anvil->data->{md5sum}{$module_file}{now} = $module_sum;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			"md5sum::${module_file}::start_time" => $anvil->data->{md5sum}{$module_file}{start_time},
			"md5sum::${module_file}::now"        => $anvil->data->{md5sum}{$module_file}{now},
		}});
		if ($anvil->data->{md5sum}{$module_file}{start_time} ne $anvil->data->{md5sum}{$module_file}{now})
		{
			# Changed.
			$exit = 1;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "warn", key => "message_0013", variables => { file => $module_file }});
		}
	}
	
	# Record sums for word files.
	foreach my $file (sort {$a cmp $b} keys %{$anvil->data->{words}})
	{
		my $words_sum = $anvil->Get->md5sum({file => $file});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			file      => $file,
			words_sum => $words_sum, 
		}});
		
		$anvil->data->{md5sum}{$file}{now} = $words_sum;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			"md5sum::${file}::start_time" => $anvil->data->{md5sum}{$file}{start_time}, 
			"md5sum::${file}::now"        => $anvil->data->{md5sum}{$file}{now}, 
		}});
		if ($anvil->data->{md5sum}{$file}{start_time} ne $anvil->data->{md5sum}{$file}{now})
		{
			$exit = 1;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "warn", key => "message_0013", variables => { file => $file }});
		}
	}
	
	# Exit?
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 'exit' => $exit }});
	return($exit);
}

=head2 copy_file

This copies a file, with a few additional checks like creating the target directory if it doesn't exist, aborting if the file has already been backed up before, etc.

 # Example
 $anvil->Storage->copy_file({source => "/some/file", target => "/another/directory/file"});

Parameters;

=head3 overwrite (optional)

If this is set to 'C<< 1 >>', and if the target file exists, it will be replaced.

If this is not passed and the target exists, this module will return 'C<< 3 >>'.

=head3 source (required)

This is the source file. If it isn't specified, 'C<< 1 >>' will be returned. If it doesn't exist, this method will return 'C<< 4 >>'.

=head3 target (required)

This is the target *B<file>*, not the directory to put it in. The target file name can be different from the source file name.

if this is not specified, 'C<< 2 >>' will be returned.

=cut
sub copy_file
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $overwrite = defined $parameter->{overwrite} ? $parameter->{overwrite} : 0;
	my $source    = defined $parameter->{source}    ? $parameter->{source}    : "";
	my $target    = defined $parameter->{target}    ? $parameter->{target}    : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		overwrite => $overwrite,
		source    => $source, 
		target    => $target,
	}});
	
	if (not $source)
	{
		# No source passed.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Storage->copy_file()", parameter => "source" }});
		return(1);
	}
	elsif (not -e $source)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0052", variables => { source => $source }});
		return(4);
	}
	if (not $target)
	{
		# No target passed.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Storage->copy_file()", parameter => "target" }});
		return(2);
	}
	
	# If the target exists, abort
	if ((-e $target) && (not $overwrite))
	{
		# This isn't an error.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 1, key => "log_0046", variables => {
			source => $source,
			target => $target,
		}});
		return(3);
	}
	
	# Make sure the target directory exists and create it, if not.
	my ($directory, $file) = ($target =~ /^(.*)\/(.*)$/);
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		directory => $directory, 
		file      => $file,
	}});
	if (not -e $directory)
	{
		$anvil->Storage->make_directory({
			directory => $directory,
			group     => $(,	# Real UID
			user      => $<,	# Real GID
			mode      => "0750",
		});
	}
	
	# Now backup the file.
	my $output = $anvil->System->call({shell_call => $anvil->data->{path}{exe}{'cp'}." -af $source $target"});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { output => $output }});
	
	return(0);
}

=head2 find

This searches for the given file on the system. It will search in the directories returned by C<< $anvil->Storage->search_directories() >>.

Example to search for 'C<< foo >>';

 $anvil->Storage->find({file => "foo"});

Same, but error out if the file isn't found.

 $anvil->Storage->find({
 	file  => "foo",
 	fatal => 1,
 });

If it fails to find the file and C<< fatal >> isn't set to 'C<< 1 >>', 'C<< 0 >>' is returned.

Parameters;

=head3 file (required)

This is the name of the file to search for.

=cut
sub find
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# WARNING: Don't call Log from here! It causes it to abort
	my $debug = 0;
	my $file  = defined $parameter->{file}  ? $parameter->{file}  : "";
	print $THIS_FILE." ".__LINE__."; [ Debug] - file: [$file]\n" if $debug;
	
	# Each full path and file name will be stored here before the test.
	my $full_path = "#!not_found!#";
	if ($file)
	{
		foreach my $directory (@{$anvil->Storage->search_directories()})
		{
			# If "directory" is ".", expand it.
			print $THIS_FILE." ".__LINE__."; [ Debug] - >> directory: [$directory]\n" if $debug;
			if (($directory eq ".") && ($ENV{PWD}))
			{
				$directory = $ENV{PWD};
				print $THIS_FILE." ".__LINE__."; [ Debug] - << directory: [$directory]\n" if $debug;
			}
			
			# Put together the initial path
			my $test_path = $directory."/".$file;
			print $THIS_FILE." ".__LINE__."; [ Debug] - >> test_path: [$test_path]\n" if $debug;

			# Clear double-delimiters.
			$test_path =~ s/\/+/\//g;
			print $THIS_FILE." ".__LINE__."; [ Debug] - << test_path: [$test_path]\n" if $debug;
			if (-f $test_path)
			{
				# Found it!
				$full_path = $test_path;
				print $THIS_FILE." ".__LINE__."; [ Debug] - >> full_path: [$full_path]\n" if $debug;
				last;
			}
		}
		print $THIS_FILE." ".__LINE__."; [ Debug] - << full_path: [$full_path]\n" if $debug;
	}
	
	# Return
	print $THIS_FILE." ".__LINE__."; [ Debug] - full_path: [$full_path]\n" if $debug;
	return ($full_path);
}

=head2 make_directory

This creates a directory (and any parent directories).

 $anvil->Storage->make_directory({directory => "/foo/bar/baz", owner => "me", grou[ => "me", group => 755});

If it fails to create the directory, an alert will be logged.

Parameters;

=head3 directory (required)

This is the name of the directory to create.

=head3 group (optional)

This is the group name or group ID to set the ownership of the directory to.

=head3 mode (optional)

This is the numeric mode to set on the file. It expects four digits to cover the sticky bit, but will work with three digits.

=head3 user (optional)

This is the user name or user ID to set the ownership of the directory to.

=cut
sub make_directory
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $directory = defined $parameter->{directory} ? $parameter->{directory} : "";
	my $group     = defined $parameter->{group}     ? $parameter->{group}     : "";
	my $mode      = defined $parameter->{mode}      ? $parameter->{mode}      : "";
	my $user      = defined $parameter->{user}      ? $parameter->{user}      : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		directory => $directory,
		group     => $group, 
		mode      => $mode,
		user      => $user,
	}});
	
	# Make sure the user and group and just one digit or word.
	$user  =~ s/^(\S+)\s.*$/$1/;
	$group =~ s/^(\S+)\s.*$/$1/;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		group     => $group, 
		user      => $user,
	}});
	
	# Break the directories apart.
	my $working_directory = "";
	foreach my $this_directory (split/\//, $directory)
	{
		next if not $this_directory;
		$working_directory .= "/$this_directory";
		$working_directory =~ s/\/\//\//g;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { working_directory => $working_directory }});
		if (not -e $working_directory)
		{
			# Directory doesn't exist, so create it.
			my $shell_call = $anvil->data->{path}{exe}{'mkdir'}." ".$working_directory;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0011", variables => { shell_call => $shell_call }});
			open (my $file_handle, $shell_call." 2>&1 |") or $anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0014", variables => { shell_call => $shell_call, error => $! }});
			while(<$file_handle>)
			{
				chomp;
				my $line = $_;
				$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0017", variables => { line => $line }});
			}
			close $file_handle;
			
			if ($mode)
			{
				$anvil->Storage->change_mode({target => $working_directory, mode => $mode});
			}
			if (($user) or ($group))
			{
				$anvil->Storage->change_owner({target => $working_directory, user => $user, group => $group});
			}
		}
	}
	
	return(0);
}

=head2 read_config

This method is used to read 'Anvil::Tools' style configuration files. These configuration files are in the format:

 # This is a comment for the 'a::b::c' variable
 a::b::c = x

A configuration file can be read in like this;

 $anvil->Storage->read_config({file => "test.conf"});

In this example, the file 'C<< test.conf >>' will be searched for in the directories returned by 'C<< $anvil->Storage->search_directories >>'. 

Any line starting with '#' is a comment and is ignored. Preceding white spaces are allowed and also ignored.

Any line in the format 'x = y' is treated as a variable / value pair, split on the first 'C<< = >>'. Whitespaces on either side of the 'C<< = >>' are removed and ignored. However, anything after the first non-whitespace character is treated as data an unmolested. This includes addition 'C<< = >>' characters, white spaces and so on. The exception is that trailing white spaces are cropped and ignored. If nothing comes after the 'C<< = >>', the variable is set to a blank string.

Successful read will return 'C<< 0 >>'. Non-0 is an error;
C<< 0 >> = OK
C<< 1 >> = Invalid or missing file name
C<< 2 >> = File not found
C<< 3 >> = File not readable

Parameters;

=head3 file (required)

This is the configuration file to read. 

If the 'C<< file >>' parameter starts with 'C<< / >>', the exact path to the file is used. Otherwise, this method will search for the file in the list of directories returned by 'C<< $anvil->Storage->search_directories >>'. The first match is read in.

All variables are stored in the root of 'C<< $anvil->data >>', allowing for configuration files to override internally set variables.

For example, if you set:
 
 $anvil->data->{a}{b}{c} = "1";

Then you read in a config file with:

 a::b::c = x

Then 'C<< $anvil->data->{a}{b}{c} >>' will now contain 'C<< x >>'.

=cut
sub read_config
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# Setup default values
	my $file        = defined $parameter->{file} ? $parameter->{file} : 0;
	my $return_code = 0;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { file => $file }});
	
	if (not $file)
	{
		# No file to read
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0032"});
		$return_code = 1;
	}
	
	# If I have a file name that isn't a full path, find it.
	if (($file) && ($file !~ /^\//))
	{
		# Find the file, if possible. If not found, we'll not alter what the user passed in and hope
		# it is relative to where we are.
		my $path = $anvil->Storage->find({ file => $file });
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { path => $path }});
		if ($path ne "#!not_found!#")
		{
			# Update the file
			$file = $path;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { file => $file }});
		}
	}
	
	if ($file)
	{
		if (not -e $file)
		{
			# The file doesn't exist
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0033", variables => { file => $file }});
			$return_code = 2;
		}
		elsif (not -r $file)
		{
			# The file can't be read
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0034", variables => { 
				file => $file,
				user => getpwuid($<),
				uid  => $<,
			}});
			$return_code = 3;
		}
		else
		{
			# Read it in!
			my $count = 0;
			open (my $file_handle, "<$file") or die "Can't read: [$file], error was: $!\n";
			while (<$file_handle>)
			{
				chomp;
				my $line =  $_;
				$line =~ s/^\s+//;
				$line =~ s/\s+$//;
				$count++;
				next if ((not $line) or ($line =~ /^#/));
				next if $line !~ /=/;
				my ($variable, $value) = split/=/, $line, 2;
				$variable =~ s/\s+$//;
				$value    =~ s/^\s+//;
				if (not $variable)
				{
					$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0035", variables => { 
						file  => $file,
						count => $count,
						line  => $line,
					}});
				}
				
				$anvil->_make_hash_reference($anvil->data, $variable, $value);
			}
			close $file_handle;
		}
	}
	
	return($return_code);
}

=head2 read_file

This reads in a file and returns the contents of the file as a single string variable.

 my $body = $anvil->Storage->read_file({file => "/tmp/foo"});

If it fails to find the file, or the file is not readable, 'C<< !!error!! >>' is returned.

Parameters;

=head3 cache (optional)

This is an optional parameter that controls whether the file is cached in case something else tries to read the same file later. By default, all read files are cached. Set this to C<< 0 >> to disable caching. This should only be needed when reading large files.

=head3 file (required)

This is the name of the file to read.

=head3 force_read (optional)

This is an otpional parameter that, if set, forces the file to be read, bypassing cache if it exists. Set this to C<< 1 >> to bypass the cache.

=cut
sub read_file
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $body       = "";
	my $cache      = defined $parameter->{cache}      ? $parameter->{cache}      : 1;
	my $file       = defined $parameter->{file}       ? $parameter->{file}       : "";
	my $force_read = defined $parameter->{force_read} ? $parameter->{force_read} : 0;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		cache      => $cache, 
		file       => $file,
		force_read => $force_read, 
	}});
	
	if (not $file)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Storage->read_file()", parameter => "file" }});
		return("!!error!!");
	}
	elsif (not -e $file)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0021", variables => { file => $file }});
		return("!!error!!");
	}
	elsif (not -r $file)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0022", variables => { file => $file }});
		return("!!error!!");
	}
	
	# If I've read this before, don't read it again.
	if ((exists $anvil->data->{cache}{file}{$file}) && (not $force_read))
	{
		# Use the cache
		$body = $anvil->data->{cache}{file}{$file};
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { body => $body }});
	}
	else
	{
		# Read from disk.
		my $shell_call = $file;
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0012", variables => { shell_call => $shell_call }});
		open (my $file_handle, "<", $shell_call) or $anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0015", variables => { shell_call => $shell_call, error => $! }});
		while(<$file_handle>)
		{
			chomp;
			my $line = $_;
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, key => "log_0023", variables => { line => $line }});
			$body .= $line."\n";
		}
		close $file_handle;
		$body =~ s/\n$//s;
		
		if ($cache)
		{
			$anvil->data->{cache}{file}{$file} = $body;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { "cache::file::$file" => $anvil->data->{cache}{file}{$file} }});
		}
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { body => $body }});
	return($body);
}

=head2 read_mode

This reads a file or directory's mode (sticky-bit and ownership) and returns the mode as a four-digit string (ie: 'c<< 0644 >>', 'C<< 4755 >>', etc.

 my $mode = $anvil->Storage->read_mode({file => "/tmp/foo"});

If it fails to find the file, or the file is not readable, 'C<< 0 >>' is returned.

Parameters;

=head3 file (required)

This is the name of the file or directory to check the mode of.

=cut
sub read_mode
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $debug  = 1;
	my $target = defined $parameter->{target} ? $parameter->{target} : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { target => $target }});
	
	if (not $target)
	{
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0020", variables => { method => "Storage->read_mode()", parameter => "target" }});
		return(1);
	}
	
	# Read the mode and convert it to digits.
	my $mode = (stat($target))[2];
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { mode => $mode }});
	
	# Return the full mode, unless it is a directory or file. In those cases, return the last four digits.
	my $say_mode = $mode;
	if (-d $target)
	{
		# Directory - five digits
		$say_mode =  sprintf("%04o", $mode);
		$say_mode =~ s/^\d(\d\d\d\d)$/$1/;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { say_mode => $say_mode }});
	}
	elsif (-f $target)
	{
		# File - six digits
		$say_mode =  sprintf("%04o", $mode);
		$say_mode =~ s/^\d\d(\d\d\d\d)$/$1/;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { say_mode => $say_mode }});
	}
	
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => $debug, list => { mode => $mode, say_mode => $say_mode }});
	return($say_mode);
}

=head2 record_md5sums

This is one half of a tool to let daemons detect when something they use has changed on disk and restart if any changes are found.

This records the md5sum of the calling application and all perl modules that are loaded. The values stored here will be compared against C<< check_md5sums >> later.

=cut
sub record_md5sums
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $caller = $0;
	$anvil->data->{md5sum}{$caller}{start_time} = $anvil->Get->md5sum({file => $0});
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { "md5sum::${caller}::start_time" => $anvil->data->{md5sum}{$caller}{start_time} }});
	foreach my $module (sort {$a cmp $b} keys %INC)
	{
		my $module_file = $INC{$module};
		my $module_sum  = $anvil->Get->md5sum({file => $module_file});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			module      => $module,
			module_file => $module_file, 
			module_sum  => $module_sum,
		}});
		
		$anvil->data->{md5sum}{$module_file}{start_time} = $module_sum;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { "md5sum::${module_file}::start_time" => $anvil->data->{md5sum}{$module_file}{start_time} }});
	}
	
	# Record sums for word files.
	foreach my $file (sort {$a cmp $b} keys %{$anvil->data->{words}})
	{
		my $words_sum = $anvil->Get->md5sum({file => $file});
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			file      => $file,
			words_sum => $words_sum, 
		}});
		
		$anvil->data->{md5sum}{$file}{start_time} = $words_sum;
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { "md5sum::${file}::start_time" => $anvil->data->{md5sum}{$file}{start_time} }});
	}
	
	return(0);
}

=head2 search_directories

This method returns an array reference of directories to search within for files and directories.

Parameters;

=head3 directories (optional)

This accepts either an array reference of directories to search, or a comma-separated string of directories to search (which will be converted to an array). When passed, this sets the internal list of directories to search. 

By default, it is set to all directories in C<< @INC >>, 'C<< path::directories::tools >> (our tools) and the C<< $ENV{'PATH'} >> variables, minus directories that don't actually exist. The returned array is sorted alphabetically.

=head3 initialize (optional)

If this is set, the list of directories to search will be set to 'C<< @INC >>' + 'C<< $ENV{'PATH'} >>' + 'C<< path::directories::tools >>'.

NOTE: You don't need to call this manually unless you want to reset the list. Invoking Anvil::Tools->new() causes this to be called automatically.

=cut 
sub search_directories
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	# Set a default if nothing was passed.
	my $array      = defined $parameter->{directories} ? $parameter->{directories} : "";
	my $initialize = defined $parameter->{initialize}  ? $parameter->{initialize}  : "";
	
	# If the array is a CSV of directories, convert it now.
	if ($array =~ /,/)
	{
		# CSV, convert to an array.
		my @new_array = split/,/, $array;
		   $array     = \@new_array;
	}
	elsif (($initialize) or (($array) && (ref($array) ne "ARRAY")))
	{
		if (not $initialize)
		{
			# Not initializing and an array was passed that isn't.
			$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "alert", key => "log_0031", variables => { array => $array }});
		}
		
		# Create a new array containing the '$ENV{'PATH'}' directories and the @INC directories.
		my @new_array = split/:/, $ENV{'PATH'} if $ENV{'PATH'} =~ /:/;
		foreach my $directory (@INC)
		{
			push @new_array, $directory;
		}
		
		# Add the tools directory
		push @new_array, $anvil->data->{path}{directories}{tools};
		$array = \@new_array;
	}
	
	# Store the new array, if set.
	if (ref($array) eq "ARRAY")
	{
		# Dedupe and sort.
		my $sorted_array     = [];
		my $seen_directories = {};
		foreach my $directory (sort {$a cmp $b} @{$array})
		{
			next if not defined $directory;
			
			# Convert '.' to $ENV{PWD}
			if ($directory eq ".")
			{
				# When run from systemd, there is no PWD environment variable, so we'll do a system call.
				if ($ENV{PWD})
				{
					$directory = $ENV{PWD};
				}
				else
				{
					# pwd returns '/', which isn't helpful, so we'll skip this.
					next;
				}
			}
			
			# Skip duplicates
			next if exists $seen_directories->{$directory};
			
			# Skip non-existent directories
			next if not -d $directory;
			
			# Record this directory.
			$seen_directories->{$directory} = 1;
			push @{$sorted_array}, $directory;
		}
		$array = $sorted_array;
		
		$self->{SEARCH_DIRECTORIES} = $array;
	}
	
	# Debug
	foreach my $directory (@{$self->{SEARCH_DIRECTORIES}})
	{
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { directory => $directory }});
	}
	
	return ($self->{SEARCH_DIRECTORIES});
}

=head2 write_file

This writes out a file on the local system. It can optionally set the mode as well.

 $anvil->Storage->write_file({file => "/tmp/foo", body => "some data", mode => 0644});

If it fails to write the file, an alert will be logged.

Parameters;

=head3 body (optional)

This is the contents of the file. If it is blank, an empty file will be created (similar to using 'C<< touch >>' on the command line).

=head3 file (required)

This is the name of the file to write.

NOTE: The file must include the full directory it will be written into.

=head3 group (optional)

This is the group name or group ID to set the ownership of the file to.

=head3 mode (optional)

This is the numeric mode to set on the file. It expects four digits to cover the sticky bit, but will work with three digits.

=head3 overwrite (optional)

Normally, if the file already exists, it won't be overwritten. Setting this to 'C<< 1 >>' will cause the file to be overwritten.

=head3 secure (optional)

If set to 'C<< 1 >>', the body is treated as containing secure data for logging purposes.

=head3 user (optional)

This is the user name or user ID to set the ownership of the file to.

=cut
sub write_file
{
	my $self      = shift;
	my $parameter = shift;
	my $anvil     = $self->parent;
	
	my $body      = defined $parameter->{body}      ? $parameter->{body}      : "";
	my $file      = defined $parameter->{file}      ? $parameter->{file}      : "";
	my $group     = defined $parameter->{group}     ? $parameter->{group}     : "";
	my $mode      = defined $parameter->{mode}      ? $parameter->{mode}      : "";
	my $overwrite = defined $parameter->{overwrite} ? $parameter->{overwrite} : 0;
	my $secure    = defined $parameter->{secure}    ? $parameter->{secure}    : "";
	my $user      = defined $parameter->{user}      ? $parameter->{user}      : "";
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, secure => $secure, list => { 
		body      => $body,
		file      => $file,
		group     => $group, 
		mode      => $mode,
		overwrite => $overwrite,
		secure    => $secure,
		user      => $user,
	}});
	
	# Make sure the user and group and just one digit or word.
	$user  =~ s/^(\S+)\s.*$/$1/;
	$group =~ s/^(\S+)\s.*$/$1/;
	$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
		group     => $group, 
		user      => $user,
	}});
	
	my $error = 0;
	if ((-e $file) && (not $overwrite))
	{
		# Nope.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0040", variables => { file => $file }});
		$error = 1;
	}
	
	if ($file !~ /^\/\w/)
	{
		# Not a fully defined path, abort.
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, priority => "err", key => "log_0041", variables => { file => $file }});
		$error = 1;
	}
	
	if (not $error)
	{
		# Break the directory off the file.
		my ($directory, $file_name) = ($file =~ /^(\/.*)\/(.*)$/);
		$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { 
			directory => $directory,
			file_name => $file_name,
		}});
		
		if (not -e $directory)
		{
			# Don't pass the mode as the file's mode is likely not executable.
			$anvil->Storage->make_directory({
				directory => $directory,
				group     => $group, 
				user      => $user,
			});
		}
		
		# If 'secure' is set, the file will probably contain sensitive data so touch the file and set
		# the mode before writing it.
		if ($secure)
		{
			my $shell_call = $anvil->data->{path}{exe}{touch}." ".$file;
			$anvil->Log->variables({source => $THIS_FILE, line => __LINE__, level => 3, list => { shell_call => $shell_call }});
			
			$anvil->System->call({shell_call => $shell_call});
			$anvil->Storage->change_mode({target => $file, mode => $mode});
		}
		
		# Now write the file.
		my $shell_call = $file;
		$anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 3, secure => $secure, key => "log_0013", variables => { shell_call => $shell_call }});
		open (my $file_handle, ">", $shell_call) or $anvil->Log->entry({source => $THIS_FILE, line => __LINE__, level => 0, secure => $secure, priority => "err", key => "log_0016", variables => { shell_call => $shell_call, error => $! }});
		print $file_handle $body;
		close $file_handle;
		
		if ($mode)
		{
			$anvil->Storage->change_mode({target => $file, mode => $mode});
		}
		if (($user) or ($group))
		{
			$anvil->Storage->change_owner({target => $file, user => $user, group => $group});
		}
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

1;
