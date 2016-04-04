#!/usr/bin/perl

#
# Synology Download station file handling 
#
# This script will look in the database if a download has finished and then extract, move the file(s) to the desired location.
# It will auto delete files so be very carefull when use it. You may loose data.
# Usage: ./download_handle.pl
#
#
# DISCLAIMER: 
#
# (C) 2013 by Maurice van Kruchten (mauricevankruchten@gmail.com)
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation;
# either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
# See the GNU General Public License for more details.
#
# http://www.gnu.org/licenses/gpl-3.0.txt

############### Commandline arguments check if they are valid.
# You can add more arguments. arguments_value[x] is set to 1 if an argument is passed. Where x is the position in the arguments array starting at 0.
# If an invalid argument is passed help screen will be printed and the script will exit.
@arguments_info = ("show this help","remove all paused items from the database if the download, extraction and moving the files is completed",
		"extra debug info in the log file");
@arguments = ("-help","-remove-paused","-debug");

for ($i=0;$i<=$#ARGV;$i++) {
	$p = 0;
	for ($j=0;$j<=$#arguments;$j++) {
		if ($ARGV[$i] eq $arguments[$j]) {
			$arguments_value[$j] = 1;
		}
		else {
			$arguments_value[$j] = 0;
			$p++;
		}
	}
	# check if the argument is valid, else print the help.
	if ($p > $#arguments) {
		$arguments_value[0] = 1;
	}
}

if ($arguments_value[0]) {
	print "\nArgument list info download.pl:\n\n";
	print "Usage: ./download.pl argument1 argument2 ...\n\n";
	for ($i=0;$i<=$#arguments;$i++) {
		print "$arguments[$i] --> $arguments_info[$i]\n";
	}
	exit 1;
}
############### begin of declaring arrays for where to move what, just add more if you want. Note the trailing "/" for the paths. 
# Don't change mode 0 except for the path. It is used as a fallback when no mode is found or if there is mixed content.
# change the script_path below for where you have the script.
$script_path =  "/volume1/Extensions/scripts/"; 


$exclude_file_path = $script_path . "exclude";
@exclude_array = ("*.[n,N][f,F][o,O]","*.[s,S][f,F][v,V]");
@exclude_rar_array = ("*\.[r,R][0-9]","*\.[r,R][0-9][0-9]","*\.[r,R][0-9][0-9][0-9]","*\.[r,R][a,A][r,R]");
$include_file_path = $script_path . "include";
@include_array = ();

$mode = -1;

### mixed --> 0
$dest_array[0] = "/volume1/movie/ready/";
$file_ext_array[0] = "";

### video --> 1
$dest_array[1] = "/volume1/video/3000GbXBMC/tempvideo/";
$file_ext_array[1] = "mpg,avi,mkv,mp4,mov";

### music --> 2
$dest_array[2] = "/volume1/music/";
$file_ext_array[2] = "mp3,flac,ogg";

### iso --> 3
$dest_array[3] = "/volume1/video/3000GbXBMC/games/";
$file_ext_array[3] = "iso";

############### end of declaring arrays for where to move what

print "#################### Starting download_handle script ###########################";

### Set global variable paths, database stuff etc

$base_path = '/volume1/';
$unrar = '/bin/unrar';
$psql_path = '/bin/psql';
$DB_user = 'admin';
$DB_pwd = '';
$DB_name = 'download';

### Read seeding downloads
@result_array = split(';', read_database(8));
print "Status 8 result @result_array\n";
extract_move_files(8);
### Read completed downloads
@result_array = split(";", read_database(5));
print "Status 5 result @result_array\n";
extract_move_files(5);
### Read paused downloads
if ($arguments_value[1]) {
	@result_array = split(";", read_database(3));
	print "Status 3 result @result_array\n";
	extract_move_files(3);
}
### extract and move the files to the required location.

sub extract_move_files {
for ( $i=1 ;$i < $#result_array ; $i++ ) {
$mode = -1;
my @temp = split ('/', $result_array[$i]);
my $file_name = @temp[$#temp];
my $download_path = $base_path . @result_array[$i];
my $file_done = $download_path . "/done";
my $rsync_path = $download_path . "/";

### check if it is a file or dir
if (-f $download_path) {
	print "yes it is a file\n";
	}
	else
	{
	print "nope it is a directory\n";
	}


### check if it is already extracted or copied to the new location
if (-f $file_done) {
	print "YES\n";
	if (@_[0] == 5 || @_[0] == 3) {
		# Status completed time to remove everything.
		delete_database($file_name);
		if (system("rm -rf '$download_path'") != 0) {
			print "Failed to remove $download_path\n";
			}
		}
	next;
	}

### make a list of all the files(extensions) so we can see what type we are dealing with and which files need to be extracted
@norar_files=();
if (-e $download_path) {
	### First see if we have rar files
	@rarlist_array = check_for_rar($download_path);
	@files = ();
	if ($rarlist_array[0] ne "") {
		my $rar_file = "";
		my $j = 0;
		while ($j<=$#rarlist_array) {
			# TODO: what happens if the rar contains a directory with the files inside? if "lb" will list all files following should work. 

			$rar_file = `$unrar lb '$rarlist_array[$j]'`;
			@rar_file_array = split("\n",$rar_file);
			my @already_exists = grep {/$rar_file_array[0]/} @files; #check if the file already exists, another tricky thing. TODO: improve
			if ($rar_file_array[0] ne "" && $#already_exists == -1) {
				push(@files, @rar_file_array);
				$j++;
			}
			else {
			# cleanup the rarlist so we only keep files that can be extracted keep track of the list of files that can not be extracted.
				if ($#already_exists == -1) {
					push(@norar_files, $rarlist_array[$j]);
				}
			splice(@rarlist_array, $j, 1);
			}
		}
		
		if ($files[0] ne "") {
			check_files_ext();
		}

	}
	}
	else {
	print "Directory $download_path does not exist\n";
	print "Files don't exist. We are going to delete the entry $file_name in the database\n";
	delete_database($file_name);
	next;
	}
	

if ($mode !=0 ) {
	@files = ();
	my $result = `find "$download_path" -type f |grep -Eiv '\\.r[0-9]\$|\\.r[0-9][0-9]\$|\\.r[0-9][0-9][0-9]\$|\\.rar\$'`;
	print "Other files then rar --> $result\n";
	@files = split ("\n",$result);
	check_files_ext();
	}	
if ($mode < 0) {
	# We don't know what it is so make it mixed mode.
	$mode = 0;
	}

print "mode = $mode\n";


my $dest_path = $dest_array[$mode] . $file_name;
if (system("mkdir -p '$dest_path'") != 0 ) {
	print "mkdir -p '$dest_path' Failed\n";
	}

if ($rarlist_array[0] ne "") {
	for ($j=0;$j<=$#rarlist_array;$j++) {
		if (system("$unrar e '$rarlist_array[$j]' '$dest_path'" ) != 0) {
			print "unrar failed $dest_path $rarlist_array[$j]\n";
			# Push the failed rar files to the include array so we can rsync them.
			push(@norar_files,$rarlist_array[$j]);

		}
		else {
			@exclude_rar_array = ("*\.[r,R][0-9]","*\.[r,R][0-9][0-9]","*\.[r,R][0-9][0-9][0-9]","*\.[r,R][a,A][r,R]");
			print "unrar successfull $dest_path $rarlist_array[$j]\n";
		}
	} #end of for loop $j
}


### NOTE: below is not perfect, because we include and exclude based on filename expressions. It could also match a subfolder or if duplicate filenames are used in subfolders.
### Include will have the upper hand. So what is included with the include file will not be excluded with the exclude file.

# Clean up norar_files array by removing paths and replace extension with ".*"
for ($j=0;$j<=$#norar_files;$j++) {
	my @temp1_array = split ("\/",$norar_files[$j]);
	# split the filename to remove the extension.
	my @temp_array = split(/\./,$temp1_array[$#temp1_array]);
	$norar_files[$j] = join("\.",@temp_array[0 .. $#temp_array-1]) . "\.*";	
}
# push the arrays to include and exclude array for writing the files.
push (@include_array,@norar_files);
print "include_array = @include_array\n";
push (@exclude_array,@exclude_rar_array);
print "exclude_array = @exclude_array\n";

# write the include file.
@write_line = ();
@write_line = @include_array;
write_file($include_file_path);
# write the exclude file.
@write_line = ();
@write_line = @exclude_array;
write_file($exclude_file_path);
		
# using rsync for the rest of the files -extracted archives and -predefined files to skip. @norar_files include
if ( system("rsync -ar --progress --include-from='$include_file_path' --exclude-from='$exclude_file_path' '$rsync_path' '$dest_path'") != 0 ) {
		print "rsync -ar --include-from='$include_file_path' --exclude-from='$exclude_file_path' $rsync_path $dest_path failed\n";
	}
	else {
		print "rsync -ar --include-from='$include_file_path' --exclude-from='$exclude_file_path' $rsync_path $dest_path succesfull\n";
		if ( system("touch '$file_done'") != 0 ) {
			print "touch $file_done failed\n";
			next;
		}
		else {
			print "touch $file_done succesfull for $rsync_path\n";
			next;
		}
	}

}

} # end sub extract_move_files

### Read database returns a list with full path from the torrents downloading depending on which state is passed. For reference the states are listed below.
# states = {1:'WAITING', 2:'ACTIVE', 3:'PAUSED', 4:'COMPLETING', 5:'COMPLETE', 6:'CHECKING', 8:'SEEDING', 101:'ERROR', 107:'TIMEOUT'}
sub read_database {
my $result  = `$psql_path -d $DB_name $DB_user -c "SELECT destination,filename FROM download_queue where status=@_[0]" -P format=unaligned -R "\;"`;
$result =~ s/\|/\//g;
return $result;
}

### Delete an entry from the database. Filename must be passed. Note that if there are 2 or more entries with the same filename ie from different users all will be deleted.
# For me this is not a problem, but if you don't want this to happen you will need to also keep track of the user instead of only the filenames.
sub delete_database {
my $result  = `$psql_path -d $DB_name $DB_user -c "DELETE FROM download_queue WHERE filename = '@_[0]'" -P format=unaligned -R "\;"`;
# Log the output to see if it was succesfull
print "Deleting '@_[0]' from database --> $result\n";
return $result;
}

### Check the file extensions to set mode from the global array @files.

sub check_files_ext {

		for ($j=0;$j <= $#files;$j++) {
		my @temp = split(/\./,$files[$j]);
		my $ext = $temp[$#temp];
		if ($arguments_value[2]) { 
			print "ext= $ext\n";
		}
		for ($k=1;$k <= $#file_ext_array;$k++) {
			if ($file_ext_array[$k] =~ /$ext/i) {
				if ($mode > 0 && $mode != $k) {
					# We have a mixed mode
					$mode = 0;
					return;
					}
				$mode = $k;
			}
		
		
		}	
	}
	}
### Check for rar files.
sub check_for_rar {
		# only get files with extension .r1 or .r12 or .r123 or .rar case is ignored
		my $result = `find "@_[0]" -type f |grep -Ei '\\.r[0-9]\$|\\.r[0-9][0-9]\$|\\.r[0-9][0-9][0-9]\$|\\.rar\$'`;
		my @resultrar_array = split("\n",$result);
		my @rarlist_sub_array = ();
		my @rarlist_array1 = ();
		# make an array of the different rar files.
		for ($k=0;$k<=$#resultrar_array;$k++) {
			# first split the path to get the filename so we are sure we don't have problems when a "." exists in the dir name.
			my @temp1_array = split ("\/",$resultrar_array[$k]);
			# split the filename so we can cut off the extension.
			my @temp_array = split(/\./,$temp1_array[$#temp1_array]);
			print "THIS $temp1_array[$#temp1_array]\n";
			my $temp = join("\.",@temp_array[0 .. $#temp_array-1]);
			$same_file = 0;
			for ($j=0;$j<=$#rarlist_array1;$j++) {
				if ($temp eq $temprarlist_array[$j]) {
					$same_file = 1;
					last;
					}
					else {
					$same_file = 0;
					}
				}
			if (!$same_file) {
				my $temp1 = join("\/",@temp1_array[0 .. $#temp1_array-1]);
				push(@rarlist_array1,$temp1 . "/" . $temp . "\." . @temp_array[$#temparray]);
				push(@temprarlist_array, $temp);				
				}
			}
		print "Rar file list from @_[0] --> @rarlist_array1\n";	
		return @rarlist_array1;
	}
### Write file from a global array @write_line, full path filename of the file to write is passed in the function.	
sub write_file {
	unlink @_[0];
	open (MY_FILE, ">>@_[0]");
	for ($j=0;$j<=$#write_line;$j++) {

		print MY_FILE "$write_line[$j]\n";
	
	}	
	close MY_FILE;
}	
print "#################### Stopping download_handle script ###########################\n";

