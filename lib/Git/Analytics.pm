package Git::Analytics;

use strict;
use warnings;
use Carp qw(carp croak verbose);

use DateTime;
use File::Spec;
use JSON::XS;
use Text::CSV_XS;


sub new {
	my ( $class, %args )= @_;
	my $self = {};
	$self->{vl} = $args{verbose_level} // 3;
	$self->{json_obj} = JSON::XS->new->canonical(1)->pretty(1)->utf8(0)->relaxed(1);
	bless $self, $class;
}

sub load_data {
    my ( $self, $fpath ) = @_;
    local $/;
    open( my $f, '<:utf8', $fpath ) || croak "Can't open file '$fpath': $!\n";
    my $raw = <$f>;
    return $self->{json_obj}->decode($raw);
}

sub save_data {
	my ( $self, $fpath, $data ) = @_;
    open( my $fh, '>:utf8', $fpath ) || croak "Can't open file '$fpath' for write: $!\n";
    print $fh $self->{json_obj}->encode( $data );
    close( $fh ) || croak "Write to file '$fpath' failed: $!\n";
    return 1;
}

sub get_files_sum_stat {
    my ( $self, $items, $is_merge ) = @_;
    my $added = 0;
    my $modified = 0;
    my $deleted = 0;
    foreach my $item ( @$items ) {
        next unless ref $item->{parents} eq 'ARRAY';
        my $first_parent_status = $item->{parents}[0]{status};
        # Added (A), Copied (C), Deleted (D), Modified (M), Renamed (R),
        # have their type (i.e. regular file, symlink, submodule, …) changed (T).
        if ( $first_parent_status eq 'M' || $first_parent_status eq 'R' || $first_parent_status eq 'T' ) {
            $modified++;
        } elsif ( $first_parent_status eq 'A' || $first_parent_status eq 'C' ) {
            $added++;
        } elsif ( $first_parent_status eq 'D' ) {
            $deleted++;
        } else {
            croak "Unknown first parent status '$first_parent_status'.\n";
        }
    }
    return ( $added, $modified, $deleted );
}

sub get_lines_sum_stat {
    my ( $self, $item_stats, $is_merge ) = @_;
    return ( 0, 0 ) if $is_merge;
    return ( 0, 0 ) unless ref $item_stats eq 'HASH';

    my $added = 0;
    my $removed = 0;
    foreach my $stat_data ( values %$item_stats ) {
        # No git stat about binary files.
        next unless defined $stat_data->{lines_added};

        $added += $stat_data->{lines_added};
        $removed += $stat_data->{lines_removed};
    }
    return ( $added, $removed );
}

sub get_project_state {
	my ( $self, $project ) = @_;

    my $state_fpath = 'data-cache/git-analytics-state-commits.json';

    my $state;
    if ( -f $state_fpath ) {
        $state = $self->load_data( $state_fpath );
        print "max_id: $state->{max_id}\n" if $self->{vl} >= 4;
    } else {
        $state = {
            max_id => 0,
            projects => {},
        };
    }
    $state->{projects}{ $project } = 'data-cache/git-analytics-state/commits-'.$project.'.json'
        unless exists $state->{projects}{ $project };

    my $project_state_fpath = $state->{projects}{ $project };
    my $project_state;
    if ( -f $project_state_fpath ) {
        $project_state = $self->load_data( $project_state_fpath );
    } else {
        $project_state = {
            done_sha => {},
        };
    }

    return ( $state_fpath, $state, $project_state_fpath, $project_state );
}

sub open_out_csv_file {
	my ( $self, $csv_out_fpath ) = @_;

    open( my $fh, ">>:encoding(utf8)", $csv_out_fpath )
		|| croak("Can't open '$csv_out_fpath' for write/append: $!");
	$self->{csv_fh} = $fh;

    my $csv = Text::CSV_XS->new();
    $csv->eol("\n");
	$self->{csv_obj} = $csv;
}

sub print_header_to_csv {
	my ( $self ) = @_;

    my @head_row = qw/
        id project
        author_date committer_date
        commit_author commit_author_email commit_committer commit_committer_email
        merge parents
        files_a files_m files_d lines_add lines_rm
    /;
    $self->{csv_obj}->print( $self->{csv_fh}, \@head_row );
}

sub gmtime_to_ymd {
    my ( $self, $gmtime ) = @_;
    my $dt = DateTime->from_epoch( epoch => $gmtime );
    return $dt->ymd;
}

sub process_one {
    my ( $self, $project, $git_lograw_obj, %args ) = @_;

    print "Runnnig update for project '$project'.\n" if $self->{vl} >= 4;
	my ( $state_fpath, $state, $project_state_fpath, $project_state ) = $self->get_project_state( $project );

    print "Loading log.\n" if $self->{vl} >= 4;
    my $log = $git_lograw_obj->get_log(
        $project_state->{done_sha},
        # debug_sha => '12fb9b9153933e0a8c907ccca91b92fe829a5de6',
    );

    croak "Probably parsing error.\n" unless ref $log eq 'ARRAY';
    print "Found " . (scalar @$log) . " new commit log items.\n" if $self->{vl} >= 4;
    unless ( scalar @$log ) {
        print "Nothing to do.\n" if $self->{vl} >= 4;
        return undef;
    }

    my $max_id = $state->{max_id};
    my $done_sha = $project_state->{done_sha};
    LOG_COMMIT: foreach my $log_num ( 0..$#$log ) {
        my $commit = $log->[ $log_num ];

        my $rcommit_sha = $commit->{commit};
        next if exists $done_sha->{ $rcommit_sha };

        $max_id++;
        $done_sha->{ $rcommit_sha } = $max_id;

        my $author_dt_str = $self->gmtime_to_ymd( $commit->{author}{gmtime} );
        my $committer_dt_str = $self->gmtime_to_ymd( $commit->{committer}{gmtime} );

        my $num_of_parents = scalar @{ $commit->{parents} };
        my $is_merge = ( $num_of_parents >= 2 );
        my ( @files_sum_stat ) = $self->get_files_sum_stat( $commit->{items}, $is_merge );
        my ( @lines_sum_stat ) = $self->get_lines_sum_stat( $commit->{stat}, $is_merge );

        $self->{csv_obj}->print( $self->{csv_fh}, [
            $max_id, $project,
            $author_dt_str, $committer_dt_str,
            $commit->{author}{name}, $commit->{author}{email},
            $commit->{committer}{name}, $commit->{committer}{email},
            $is_merge ? '1' : '0', $num_of_parents,
            @files_sum_stat, @lines_sum_stat
        ] );
    }

    $state->{max_id} = $max_id;

    $self->save_data( $state_fpath, $state );
    $self->save_data( $project_state_fpath, $project_state );
    return 1;
}


sub close_csv_file {
	my $self = shift;
	$self->{csv_fh}->close();
	$self->{csv_obj} = undef;
}

1;
