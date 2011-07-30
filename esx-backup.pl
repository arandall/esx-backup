#!/usr/bin/perl

use strict;
use warnings;

use lib './lib';

use Log::Log4perl;
use Data::Dumper;
use ESX::SSH;
use ESX::Backup::Config;

my $logger = Log::Log4perl->get_logger('Main');

my $config = ESX::Backup::Config->new(File => '/etc/esx-backup/esx-backup.conf');
Log::Log4perl::init_and_watch($config->Get_Log_Config_File(), 30 );



my @backups_to_preform = ();

foreach (@{$config->Get_Servers()}) {
    my $host = $_->{host};
    my $ssh = ESX::SSH->new(
        Host => $host,
        User => $_->{user},
        Pass => $_->{pass},
    );
    
    $logger->info(sprintf("Perorming backup on %s", $host));
    
    my $vm_list = $ssh->Get_Vm_List($host);
    
    foreach (keys %$vm_list) {
        my $vm = $vm_list->{$_};
        
        my $vm_backup_config = $config->Get_Vm($vm->{name}, $host);
        
        # does vm exist in config?
        if (!%{$vm_backup_config}) {
            my $warning_string = sprintf(
                "New virtual machine '%s' on host '%s' found,"
                . " added to config as DISABLED\n"
                , $vm->{name}
                , $host
            );
            # print so that cron sends email
            print $warning_string;
            $logger->warn($warning_string);
            
            # Disable will also add if not already in config.
            $config->Add_Disabled_Vm($vm->{name}, $host, $vm->{comment});
            next;
        }
    
        # do we need to backup?
        my @week_days = qw(sun mon tue wed thr fri sat);
        my ($sec, $min, $hr, $day, $month, $year, $weekday, $dayofyr, $junk_yuk) = localtime(time);
        
        if (!$vm_backup_config->{enabled}) {
            $logger->info(
                sprintf(
                    "Skipping disabled vm '%s'", 
                    $vm->{name}, 
                    $host
                )
            );
        } elsif (grep ! /^$week_days[$weekday]$/, @{$vm_backup_config->{backup_days}}) {
            $logger->info(
                sprintf(
                    "Skipping vm '%s' as its only backed up on '%s'", 
                    $vm->{name}, 
                    join ",", @{$vm_backup_config->{backup_days}},
                )
            );
        } else {
            push @backups_to_preform, [
                $vm->{name}, 
                $vm_backup_config->{rotation_count},
                $vm_backup_config->{powerdown_wait},
            ];
        }
    }
    
    # now actually do the backups!
    foreach (@backups_to_preform) {
        my @backup_params = @{$_};
        if ($ssh->Backup_Vm(@backup_params)) {
            printf("Error during backup of %s\n", $backup_params[0]);
        }
    }
}