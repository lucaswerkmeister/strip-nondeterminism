#
# Copyright 2015 Lucas Werkmeister
#
# This file is part of strip-nondeterminism.
#
# strip-nondeterminism is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# strip-nondeterminism is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with strip-nondeterminism.  If not, see <http://www.gnu.org/licenses/>.
#
package File::StripNondeterminism::handlers::car;

use strict;
use warnings;

use Archive::Zip;
use File::Basename;
use File::StripNondeterminism::handlers::zip;
use File::StripNondeterminism::handlers::jar;
use POSIX qw(strftime);

# Default timestamp for Bundle-Version if not explicitly specified: 2010-01-01 00:00:00.
# (Work on the Ceylon Java backend started in July 2010,
# so there should be no real .car files older than this.)
use constant DEFAULT_CAR_TIMESTAMP => 1262300400;

sub _car_normalize_manifest {
	my ($filename) = @_;

	open(my $fh, '<', $filename) or die "Unable to open $filename for reading: $!";
	my $tempfile = File::Temp->new(DIR => dirname($filename));

	my $modified = 0;

	while (defined(my $line = <$fh>)) {
		# Bundle-Version is <ceylon-version>.v<timestamp>, e.g.
        # Bundle-Version: 1.0.0.v20150101-1215
		if ($line =~ /^Bundle-Version:/) {
            my ($version,$real_timestamp) = $line =~ /Bundle-Version: (.*)\.(.*)/;
            my $deterministic_timestamp = strftime('%Y%m%d-%H%M', gmtime($File::StripNondeterminism::canonical_time // DEFAULT_CAR_TIMESTAMP));
            print $tempfile "Bundle-Version: $version.v$deterministic_timestamp\n";
			$modified = 1;
			next;
		}
		print $tempfile $line;
	}

	if ($modified) {
		# Rename temporary file over the file
		chmod((stat($fh))[2] & 07777, $tempfile->filename);
		rename($tempfile->filename, $filename) or die "$filename: unable to overwrite: rename: $!";
		$tempfile->unlink_on_destroy(0);
	}
	return $modified;
}

sub _car_normalize_timestamped_comments {
	my ($filename) = @_;

	open(my $fh, '<', $filename) or die "Unable to open $filename for reading: $!";
	my $tempfile = File::Temp->new(DIR => dirname($filename));

	my $modified = 0;

	while (defined(my $line = <$fh>)) {
        # strip away any line starting with '#': comment, some contain timestamp
		if ($line =~ /^#/) {
			$modified = 1;
			next;
		}
		print $tempfile $line;
	}

	if ($modified) {
		# Rename temporary file over the file
		chmod((stat($fh))[2] & 07777, $tempfile->filename);
		rename($tempfile->filename, $filename) or die "$filename: unable to overwrite: rename: $!";
		$tempfile->unlink_on_destroy(0);
	}
	return $modified;
}

sub _car_normalize_member {
    my ($member) = @_; # $member is a ref to an Archive::Zip::Member
    return if $member->isDirectory();

    if ($member->fileName() eq 'META-INF/MANIFEST.MF') {
        File::StripNondeterminism::handlers::zip::normalize_member($member,
				\&_car_normalize_manifest);        
    } elsif ($member->fileName() eq 'META-INF/mapping.txt' ||
        $member->fileName() =~ /^META-INF\/maven\/.*\/pom\.properties$/) {
        File::StripNondeterminism::handlers::zip::normalize_member($member,
				\&_car_normalize_timestamped_comments);
    } else {
        File::StripNondeterminism::handlers::jar::_jar_normalize_member($member);
    }
}

sub normalize {
	my ($car_filename) = @_;
	return File::StripNondeterminism::handlers::zip::normalize($car_filename,
							filename_cmp => \&File::StripNondeterminism::handlers::jar::_jar_filename_cmp,
							member_normalizer => \&_car_normalize_member);
}

1;
