#!/usr/bin/perl
# ==============================================================================
# Script Name  : dusk.pl
# Author       : Jake Morgan
# Created      : 07-Mar-2025
# Version      : 1.1
# Description  : DUSK (Disk Usage SKanner) is an interactive disk usage
#                scanning and navigation tool written in Perl. It performs a one‑time
#                recursive scan (using du -a -b) to cache the entire file and directory
#                tree, then lets you navigate the tree via an interactive terminal menu.
#
#                Each file and directory is displayed with a human-readable size, a bar graph
#                representing its relative disk usage, and a type indicator ("D" for directory,
#                "F" for file). When a file is selected, an info box displays detailed file information,
#                including output from the external `file` command.
#
# Usage        :
#   ./dusk.pl                 # Start from root (/)
#   ./dusk.pl --pwd           # Start from the current working directory
#   ./dusk.pl --path <dir>    # Start from a specified directory
#
# Cautions     : This tool caches the entire disk usage map in memory; it may be resource intensive.
#                For best performance, run it on specific absolute paths rather than scanning the whole root.
#
# Dependencies : Perl modules:
#                  - Term::ReadKey
#                  - Getopt::Long
#                  - Storable
#                  - POSIX
# ==============================================================================

use strict;
use warnings;
use Term::ReadKey;
die "Not running interactively!\n" unless -t STDIN;
use Getopt::Long;
use File::Basename;
use Storable qw(store retrieve);
use POSIX qw(strftime);
use Term::ReadKey qw(GetTerminalSize);

$| = 1;  # unbuffered output
my $DEBUG = 0;  # Set to 1 for extra debug prints

# ----------------------------------------------------------------------------
# Parameter Parsing: --pwd to start from current directory,
#                    --path <dir> to start from a specified directory.
# Defaults to "/" if none provided.
# ----------------------------------------------------------------------------
my $start_dir = "/";
my $pwd  = 0;
my $path = "";
GetOptions("pwd"    => \$pwd,
           "path=s" => \$path);
if ($pwd) {
    chomp($start_dir = `pwd`);
} elsif ($path) {
    $start_dir = $path;
}

# Normalize paths (remove trailing slash, except for root)
sub normalize_path {
    my $p = shift;
    $p =~ s{/$}{} unless $p eq '/';
    return $p;
}
$start_dir = normalize_path($start_dir);

# ----------------------------------------------------------------------------
# Determine temporary cache file location.
# ----------------------------------------------------------------------------
my $tmpdir = $ENV{'TMPDIR'} // '/tmp';
my $cache_file = "$tmpdir/dusk_cache.$$";

# ----------------------------------------------------------------------------
# Subroutine: human_size
# Converts a size in bytes to a human-readable string.
# ----------------------------------------------------------------------------
sub human_size {
    my $bytes = shift;
    return "0B" if $bytes == 0;
    my @units = qw(B KB MB GB TB);
    my $unit = 0;
    while ($bytes >= 1024 && $unit < @units - 1) {
        $bytes /= 1024;
        $unit++;
    }
    return sprintf("%.1f%s", $bytes, $units[$unit]);
}

# ----------------------------------------------------------------------------
# Subroutine: build_cache_tree
#
# Runs a one-time scan with "du -a -b" starting at $start_dir,
# building a cached tree:
#   %nodes: key = full path, value = { path => ..., size => ... }
#   %tree : key = parent directory, value = arrayref of child node refs.
#
# Children are sorted descending by size.
# The structure is stored via Storable.
# ----------------------------------------------------------------------------
sub build_cache_tree {
    my ($start) = @_;
    my %nodes;
    my %tree;
    $start = normalize_path($start);
    $nodes{$start} = { path => $start, size => 0 };

    my $pid = fork();
    if (!defined $pid) {
        die "Cannot fork: $!";
    } elsif ($pid == 0) {
        open(my $du, "-|", "du -a -b " . quotemeta($start) . " 2>/dev/null")
          or die "Cannot run du: $!";
        while (<$du>) {
            chomp;
            my ($size, $p) = split(/\s+/, $_, 2);
            $p = normalize_path($p);
            $nodes{$p} = { path => $p, size => $size };
            next if $p eq $start;
            my $parent = normalize_path(dirname($p));
            push @{ $tree{$parent} }, $nodes{$p};
        }
        close($du);
        for my $parent (keys %tree) {
            my @sorted = sort { $b->{size} <=> $a->{size} } @{ $tree{$parent} };
            $tree{$parent} = \@sorted;
        }
        my $cache = { start => $start, tree => \%tree, nodes => \%nodes };
        store($cache, $cache_file) or die "Cannot store cache: $!";
        exit(0);
    } else {
        my @spinner = ('|', '/', '-', '\\');
        my $i = 0;
        while (1) {
            my $kid = waitpid($pid, 1);
            last if $kid > 0;
            print "\rDUSK is Scanning $start ... $spinner[$i]";
            $i = ($i + 1) % scalar(@spinner);
            sleep 0.2;
        }
        print "\rrDUSK Scanning completed for: $start               \n";
    }
    my $cache = retrieve($cache_file);
    unlink $cache_file;
    return $cache;
}

# Build the cached tree once.
my $cache = build_cache_tree($start_dir);
my $tree  = $cache->{tree};
my $nodes = $cache->{nodes};

# ----------------------------------------------------------------------------
# Subroutine: show_file_info
#
# Displays an info box for a file, including owner, group, size, timestamps,
# file type, and the output of the 'file' command.
# ----------------------------------------------------------------------------
sub show_file_info {
    my $file = shift;
    my @stat = stat($file);
    unless (@stat) {
        print "Error getting file info for $file\n";
        return;
    }
    my $size = human_size($stat[7]);
    my $mtime = strftime("%Y-%m-%d %H:%M:%S", localtime($stat[9]));
    my $ctime = strftime("%Y-%m-%d %H:%M:%S", localtime($stat[10]));
    my $uid = $stat[4];
    my $gid = $stat[5];
    my $owner = getpwuid($uid) // $uid;
    my $group = getgrgid($gid) // $gid;
    my $mode = sprintf("%04o", $stat[2] & 07777);
    my $type = (-d $file) ? "Directory" : (-f $file) ? "File" : "Other";
    my $file_cmd_output = `file "$file"`;
    chomp($file_cmd_output);

    print "\033[2J\033[H";
    print "========= DUSK =========\n";									   
    print "=== File Information ===\n";
    print "Path        : $file\n";
    print "Type        : $type\n";
    print "Size        : $size\n";
    print "Permissions : $mode\n";
    print "Owner       : $owner\n";
    print "Group       : $group\n";
    print "Modified    : $mtime\n";
    print "Changed     : $ctime\n";
    print "File info   : $file_cmd_output\n";
    print "-------------------------\n";
    print "Press any key to return to menu...";
    ReadMode('cbreak');
    ReadKey(0);
    ReadMode('normal');
}

# ----------------------------------------------------------------------------
# Subroutine: print_menu
# Clears the screen and prints the menu.
# Parameters: current directory, menu array ref, selected index,
#             window_start, available lines.
# ----------------------------------------------------------------------------
sub print_menu {
    my ($current_dir, $menu_ref, $selected, $window_start, $available) = @_;
    my ($cols, $rows) = GetTerminalSize(*STDOUT);
    print "\033[2J\033[H";  # clear screen and reposition cursor
    print "=== DUSK: Disk Usage SKanner ($current_dir) ===\n";
    print "Use ↑/↓ to navigate, ENTER to select, or 'q' to quit\n";
    print "--------------------------------\n";
    for (my $i = $window_start; $i < @$menu_ref && $i < $window_start + $available; $i++) {
        my $line = $menu_ref->[$i];
        $line = sprintf("%-${cols}s", $line);  # pad to full terminal width
        if ($i == $selected) {
            # Invert the entire line.
            print "\033[7m$line\033[0m\n";
        } else {
            print "$line\n";
        }
    }
}

# ----------------------------------------------------------------------------
# Subroutine: menu_select
#
# Displays the menu and returns the selected item.
# Implements a scrolling viewport with hard stops (no wrapping).
# ----------------------------------------------------------------------------
sub menu_select {
    my ($current, $menu_ref) = @_;
    my $selected = 0;  # start at top
    my $window_start = 0;
    my ($cols, $rows) = GetTerminalSize(*STDOUT);
    my $available = $rows - 3;
    $available = 1 if $available < 1;
    ReadMode('cbreak');
    while (1) {
        if ($selected < $window_start) {
            $window_start = $selected;
        }
        if ($selected >= $window_start + $available) {
            $window_start = $selected - $available + 1;
        }
        print_menu($current, $menu_ref, $selected, $window_start, $available);
        my $key = ReadKey(0);
        if (!defined $key) { next; }
        if ($key eq "q") {
            ReadMode('normal');
            exit(0);
        } elsif ($key eq "\n") {
            ReadMode('normal');
            return $menu_ref->[$selected];
        } elsif ($key eq "\e") {
            my $seq = ReadKey(0);
            if (defined $seq and $seq eq "[") {
                my $arrow = ReadKey(0);
                if ($arrow eq "A") {  # Up arrow; hard stop at 0.
                    $selected-- if $selected > 0;
                } elsif ($arrow eq "B") {  # Down arrow; hard stop at end.
                    $selected++ if $selected < scalar(@$menu_ref) - 1;
                }
            }
        }
    }
}

# ----------------------------------------------------------------------------
# Subroutine: interactive_menu
#
# Uses the cached tree to display a menu of the current directory's contents.
# Lists both files and directories with a bar-graph, type column, and a new column
# indicating the file type ("D" for directory, "F" for file).
# If a file is selected, its info box is displayed.
# ----------------------------------------------------------------------------
sub interactive_menu {
    my $current = shift;
    $current = normalize_path($current);
    while (1) {
        my @menu;
        # Add "Go up one level" if not at the top.
        if ($current ne $cache->{start}) {
            push @menu, "Go up one level";
        }
        # Get all items (files and directories) in the current directory.
        my $children = $tree->{$current} || [];
        # Sort items by size descending.
        my @all = sort { $b->{size} <=> $a->{size} } @$children;
        
        # Compute maximum size among these items.
        my $max_size = 0;
        foreach my $item (@all) {
            $max_size = $item->{size} if $item->{size} > $max_size;
        }
        my $bar_width = 20;
        if (@all) {
            foreach my $item (@all) {
                my $hr = human_size($item->{size});
                my $ratio = $max_size > 0 ? $item->{size} / $max_size : 0;
                my $bar_length = int($ratio * $bar_width);
                my $bar = '#' x $bar_length;
                my $bar_field = sprintf("[%-${bar_width}s]", $bar);
                my $type = (-d $item->{path}) ? "D" : "F";
                # Format: SIZE, bar, type, full path.
                push @menu, sprintf("%-8s %s %-1s %s", $hr, $bar_field, $type, $item->{path});
            }
        } else {
            push @menu, "[No files or subdirectories]";
        }
        push @menu, "Exit";
        
        # If there are many items, simulate a scanning progress indicator.
        if (scalar(@menu) > 50) {
            print "\rLoading directory contents, please wait...";
            sleep(0.5);
        }
        
        my $choice = menu_select($current, \@menu);
        if ($choice eq "Exit") {
            print "\nExiting DUSK...\n";
            exit(0);
        } elsif ($choice eq "Go up one level") {
            $current = normalize_path(dirname($current));
            print STDERR "[DEBUG] New current directory: $current\n" if $DEBUG;
        } elsif ($choice eq "[No files or subdirectories]") {
            # Remain in current directory.
        } else {
            # Expected format: "SIZE   [BAR] TYPE FULL_PATH"
            if ($choice =~ /^\S+\s+\[.*?\]\s+(\S)\s+(.*\S)\s*$/) {
                my $item_type = $1;
                my $newpath = normalize_path($2);
                if ($item_type eq "F") {
                    show_file_info($newpath);
                } elsif ($item_type eq "D") {
                    $current = $newpath;
                }
            }
        }
        # Loop refreshes menu with updated $current.
    }
}

# ----------------------------------------------------------------------------
# Main Execution: Start interactive navigation from the cached start directory.
# ----------------------------------------------------------------------------
interactive_menu($cache->{start});
