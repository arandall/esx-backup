package ESX::SSH;

use strict;
use warnings;

use Carp;
use Net::SSH::Perl;
use Log::Log4perl;

use constant BACKUP_SCRIPT => '/vmfs/volumes/backup/ghettoVCB/ghettoVCB.sh';
use constant TRUE => 1;
use constant FALSE => 0;

require Exporter;
use base 'Exporter';

our @EXPORT = ();

my $logger = Log::Log4perl->get_logger(__PACKAGE__);

sub new {
    my ( $class, %params ) = @_;

    my $self = bless {
        host => $params{Host},
        user => $params{User},
        pass => $params{Pass},
        _ssh => undef,
        # probably a better way but this one logs to log rather than
        # returning scalar
        _ssh_log => undef,
    }, $class;

    $self->Connect();

    return $self;
}

# connect to ESXi server via SSH.
sub Connect {
    my ($self) = @_;

    $self->{_ssh} = Net::SSH::Perl->new($self->{host});
    if ($self->{_ssh}->login($self->{user}, $self->{pass})) {
        $logger->info(
            sprintf("Connection established to %s@%s",
                $self->{user}, $self->{host}
            )
        );
    }

    $self->{_ssh_log} = Net::SSH::Perl->new($self->{host});
    if ($self->{_ssh_log}->login($self->{user}, $self->{pass})) {
        $logger->info(
            sprintf("Connection established to %s@%s (log)",
                $self->{user}, $self->{host}
            )
        );
    }

    $self->{_ssh_log}->register_handler(
        "stdout",
        sub {
            my($channel, $buffer) = @_;
            my $ssh_log_prefix = 'ghettoVCB.sh: ';
            my $bytes = $buffer->bytes;
            $bytes =~ s/\r/\n/g;

            # if info line remove date
            # eg. 2011-07-30 17:54:38 -- info: CONFIG - VM_SNAPSHOT_QUIESCE = 0
            if ($bytes =~ /^\d+\-\d+\-\d+ \d+:\d+:\d+ -- (.*)/) {
                foreach (split /\n/, $1) {
                    $bytes = $ssh_log_prefix . $_;
                }
            }

            if ($bytes) {
                foreach my $line (split /\n/, $bytes) {
                    # only show Clone lines if modulus of 10. and add prefix string.
                    if ($line =~ /Clone: (\d+)%/) {
                        next if ($1 % 10);
                        $line = $ssh_log_prefix . $line;
                    }                    
                    $line =~ s/^\s+//;
                    $line =~ s/\s+$//;
                    $logger->info($line) if ($line);
                }
            }
        }
    );
    $self->{_ssh_log}->register_handler(
        "stderr",
        sub {
            my($channel, $buffer) = @_;
            $logger->error($buffer->bytes);
        }
    );
}

sub Get_Vm_List {
    my ($self) = @_;

    my ($stdout, $stderr, $exit) = $self->{_ssh}->cmd('/bin/vim-cmd vmsvc/getallvms');

    croak "Unable to run vim-cmd on host" if ($exit);

    # vim-cmd uses spaces to pad text and comments with
    # \n continue after first line use regexp to find
    # vm entry then assume other lines are comments.
    my $list = {};
    my $current_vm;
    foreach (split /\n/, $stdout) {
        # skip header line
        next if (/^Vmid/);

        if (/^(\d+)\s+(.*?)\s+\[(.*?)\] (.*?)\s+(.*?)\s+(.*?)\s+(.*?)\s*$/) {
            $current_vm = $1;
            $list->{$current_vm} = {
                vmid => $1,
                name => $2,
                datastore => $3,
                file => $4,
                guest_os => $5,
                version => $6,
                comment => $7,
            };
        } else {
            my $comment_line = "\n$_";
            $comment_line =~ s/\s+$//;
            $list->{$current_vm}->{comment} .= $comment_line;
        }
    }

    return $list;
}

sub Backup_Vm {
    my ($self, $vm_name, $rotation_count, $powerdown_wait) = @_;

    croak "Hostname is not defined" unless($vm_name);
    croak "Rotation Count must be an integer"
        unless($rotation_count and $rotation_count =~ /^\d+$/);

    $rotation_count ||= 2; #set default

    my $backup_cmd = sprintf(
        "%s -h '%s' -r %u",
        BACKUP_SCRIPT,
        $vm_name,
        $rotation_count
    );

    if ($powerdown_wait) {
        croak "Powerdown wait time must be an integer"
            unless ($powerdown_wait =~ /^\d+$/);

        $backup_cmd .= sprintf(" -p %u", $powerdown_wait);
    }

    $logger->info("Attempting to backup $vm_name");
    $logger->debug("Executing: '$backup_cmd' on $vm_name");

    my $exit = $self->{_ssh_log}->cmd($backup_cmd);

    $logger->info("Backup of $vm_name complete");

    $logger->error("Error during backup of $vm_name") if $exit;

    return($exit);
}

1;