package ESX::Backup::Config;

use strict;
use warnings;

use constant TRUE => 1;
use constant FALSE => 0;

use Carp;
use Log::Log4perl;
use Data::Dumper;
use Config::Simple;

require Exporter;
use base 'Exporter';

our @EXPORT = ();

my $logger = Log::Log4perl->get_logger(__PACKAGE__);

sub new {
    my ( $class, %params ) = @_;

    my $self = bless {
        _filename => $params{File},
        conf => new Config::Simple($params{File}),
    }, $class;

    return $self;
}

sub _Parse_Server {
    my $server_def = shift;
    my $server_hash = {};

    if ($server_def =~ /([^\[]+)(\[(.*?)]){0,1}$/) {
        $server_hash->{host} = $1;
        if ($2) {
            my $server_conf = $3;
            while ($server_conf =~ /((?:\\.|[^=,]+)*)=("(?:\\.|[^"\\]+)*"|(?:\\.|[^,"\\]+)*)/g) {
                    $server_hash->{$1} = $2;
            }
        }
    }

    return $server_hash;
}

#return list of server hashes with user and passwords.
sub Get_Servers {
    my $self = shift;

    my $main_config = $self->{conf}->param(-block=>'main');
    my @servers_conf = ();

    if (ref($main_config->{servers}) eq 'ARRAY') {
        @servers_conf = @{$main_config->{servers}};
    } else {
        @servers_conf =  $main_config->{servers};
    }

    my @servers = ();
    foreach my $server_def (@servers_conf) {
        my $server = _Parse_Server($server_def);
        foreach (@{['user', 'pass']}) {
            $server->{$_} = $main_config->{'default_'.$_} unless $server->{$_};
        }
        push @servers, $server;
    }

    return \@servers;
}

# config expects vm@server as block
sub Get_Vm {
    my ($self, $vm, $server) = @_;

    my $main_config = $self->{conf}->param(-block=>'main');
    my $vm_config = $self->{conf}->param(
        -block => sprintf("%s@%s", $vm, $server),
    );

    if (%$vm_config) {
        # apply defaults if not set
        foreach (@{['backup_days', 'rotation_count', 'powerdown_wait']}) {
            $vm_config->{$_} =
                $main_config->{'default_'.$_} unless $vm_config->{$_};
        }

        # make sure backup_days is always an array_ref
        if (ref($vm_config->{backup_days}) ne 'ARRAY') {
            $vm_config->{backup_days} = [$vm_config->{backup_days}];
        }
    }

    return $vm_config;
}

sub Add_Disabled_Vm {
    my ($self, $vm, $server, $comment) = @_;

    open(VM_CONF,">>" . $self->{_filename}) || croak("Cannot Open File");
    printf VM_CONF "\n[%s@%s]\n", $vm, $server;
    print VM_CONF ";$_\n" foreach(split '\n', $comment);
    print VM_CONF "enabled = 0\n";
    close(VM_CONF);

    #reload config
    $self->{conf} = new Config::Simple($self->{_filename});
}

sub Get_Log_Config_File {
    my ($self) = @_;
    
    return $self->{conf}->param(-block=>'main')->{log_config};
}

# disabled as comments are deleted and quotes are not retained.
=pod
sub Add_Vm {
    my ($self, $vm, $server, $config) = @_;

    $self->{conf}->param(
        -block => sprintf("%s@%s", $vm, $server),
        -values => $config,
    );

    $self->{conf}->save();
}

sub Disable_Vm {
    my ($self, $vm, $server) = @_;

    my $vm_conf = $self->Get_Vm($vm, $server);

    $vm_conf->{disabled} = TRUE;

    $self->Add_Vm($vm, $server, $vm_conf);
}
=cut

1;