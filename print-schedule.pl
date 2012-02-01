#!/usr/bin/perl

use strict;
use warnings;

use lib './lib';

use ESX::Backup::Config;
use Data::Dumper;

my $config = ESX::Backup::Config->new(File => '/etc/esx-backup/esx-backup.conf');

my $servers = {};

foreach(keys %{$config->Dump}) {
    if (/^(.*?)@(.*)\..*?$/) {
        my $host = $2;
        my $vm = $1;
        $servers->{$host}->{lc $vm} = $config->Get_Vm($vm, $host);
    }
}

foreach (keys %$servers) {
    my $server = $_;
    print "$server - Backup Schedule\n\n";
    print "DAYS      HIST   VM\n";
    foreach (sort keys %{$servers->{$server}}) {
        my $vm = $_;
        my $enabled = $servers->{$server}->{$vm}->{enabled};
        printf(
            "%s%s%s%s%s%s%s - %4s - %s\n",
            ( $enabled && grep ( /^mon$/, @{$servers->{$server}->{$vm}->{backup_days}} ) ? 'm' : ' '),
            ( $enabled && grep ( /^tue$/, @{$servers->{$server}->{$vm}->{backup_days}} ) ? 't' : ' '),
            ( $enabled && grep ( /^wed$/, @{$servers->{$server}->{$vm}->{backup_days}} ) ? 'w' : ' '),
            ( $enabled && grep ( /^thu$/, @{$servers->{$server}->{$vm}->{backup_days}} ) ? 't' : ' '),
            ( $enabled && grep ( /^fri$/, @{$servers->{$server}->{$vm}->{backup_days}} ) ? 'f' : ' '),
            ( $enabled && grep ( /^sat$/, @{$servers->{$server}->{$vm}->{backup_days}} ) ? 's' : ' '),
            ( $enabled && grep ( /^sun$/, @{$servers->{$server}->{$vm}->{backup_days}} ) ? 's' : ' '),
            $servers->{$server}->{$vm}->{rotation_count},
            $vm,
        );
    }
}
