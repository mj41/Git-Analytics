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
	$self->{also_commits_files} = $args{also_commits_files} // 0;
	$self->{data_cache_dir} = $args{data_cache_dir} || 'data-cache';
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
	my ( $self, $project_alias ) = @_;

    my $state_fpath = File::Spec->catfile(
		$self->{data_cache_dir}, 'git-analytics-state-commits.json'
	);

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

    my $state_dir = File::Spec->catdir( $self->{data_cache_dir}, 'git-analytics-state' );
    unless ( -d $state_dir ) {
		mkdir($state_dir) || croak "Can't create directory '$state_dir': $!\n";
    }
    $state->{projects}{ $project_alias } = File::Spec->catfile(
		 $state_dir, 'commits-'.$project_alias.'.json'
	) unless exists $state->{projects}{ $project_alias };

    my $project_state_fpath = $state->{projects}{ $project_alias };
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

sub open_out_csv_files {
	my ( $self, $csv_out_fpath, $cfiles_csv_out_fpath ) = @_;

	if ( $self->{also_commits_files} ) {
		croak "Missing fpath to CSV for details of commits file.\n" unless $cfiles_csv_out_fpath;
	}

    open( my $fh, ">>:encoding(utf8)", $csv_out_fpath )
		|| croak("Can't open '$csv_out_fpath' for write/append: $!");
	$self->{csv_fh} = $fh;

	if ( $self->{also_commits_files} ) {
		open( my $cfiles_fh, ">>:encoding(utf8)", $cfiles_csv_out_fpath )
			|| croak("Can't open '$cfiles_csv_out_fpath' for write/append: $!");
		$self->{cfiles_csv_fh} = $cfiles_fh;
	}

    my $csv = Text::CSV_XS->new();
    $csv->eol("\n");
	$self->{csv_obj} = $csv;
}

sub print_csv_headers {
	my ( $self ) = @_;

    my @head_row = qw/
        commit_sha1 project
        author_date committer_date
        commit_author commit_author_email commit_committer commit_committer_email
        merge parents
        files_a files_m files_d lines_add lines_rm
    /;
    $self->{csv_obj}->print( $self->{csv_fh}, \@head_row );

	if ( $self->{also_commits_files} ) {
		my @cfiles_head_row = qw/
			sha1 fpath dir_l1 dir_l2 fname ftype lang sub_project lines_add lines_rm
		/;
		$self->{csv_obj}->print( $self->{cfiles_csv_fh}, \@cfiles_head_row );
	}
}

sub gmtime_to_ymd {
    my ( $self, $gmtime ) = @_;
    my $dt = DateTime->from_epoch( epoch => $gmtime );
    return $dt->ymd;
}

sub get_file_details {
	my ( $self, $fpath ) = @_;

	my ( $dirs_str, $fname ) = $fpath =~ m{^ (.*?) ([^\/]+) $}x;
	my ( $dir_l1, $dir_l2 ) = $dirs_str =~ m{^ ([^\/]+) \/ ([^\/]*) \/?}x;
	$dir_l1 //= '';
	$dir_l2 //= '';

	return ( $dir_l1, $dir_l2, $fname );
}

sub get_file_fname_lang {
	my ( $self, $fpath, $file_sha1_hash, $git_file_mode ) = @_;
	return ('code','Perl')          if $fpath =~ m{\.(pl|pm)$}i;
	return ('doc', 'Perl')          if $fpath =~ m{\.(pod)$}i;
	return ('test','Perl')          if $fpath =~ m{\.(t)$}i;
	return ('code','Perl 6')        if $fpath =~ m{\.(p6)$}i;
	return ('code','NQP')           if $fpath =~ m{\.(nqp)$}i;
	return ('code','PIR')           if $fpath =~ m{\.(pir)$}i;
	return ('code','C')             if $fpath =~ m{\.(c|h)$}i;
	return ('code','JavaScript')    if $fpath =~ m{\.(js)$}i;
	return ('code','Python')        if $fpath =~ m{\.(py)$}i;
	return ('code','Java')          if $fpath =~ m{\.(java)$}i;
	return ('code','Bash')          if $fpath =~ m{\.(sh)$}i;
	return ('code','Haskell')       if $fpath =~ m{\.(hs)$}i;
	return ('view','HTML')          if $fpath =~ m{\.(html?)$}i;
	return ('view','CSS')           if $fpath =~ m{\.(css?)$}i;
	return ('unk','unk');
}

sub process_one {
    my ( $self, $project_alias, $project_name, $git_lograw_obj, %args ) = @_;
	$args{git_log_args} = {} unless defined $args{git_log_args};

    print "Runnnig update for project '$project_alias'.\n" if $self->{vl} >= 4;
	my ( $state_fpath, $state, $project_state_fpath, $project_state ) = $self->get_project_state( $project_alias );

    print "Loading log.\n" if $self->{vl} >= 4;
    my $log = $git_lograw_obj->get_log(
        $project_state->{done_sha},
        %{ $args{git_log_args} }
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
            $rcommit_sha, $project_name,
            $author_dt_str, $committer_dt_str,
            $commit->{author}{name}, $commit->{author}{email},
            $commit->{committer}{name}, $commit->{committer}{email},
            $is_merge ? '1' : '0', $num_of_parents,
            @files_sum_stat, @lines_sum_stat
        ] );

		if ( $self->{also_commits_files} ) {
			foreach my $item ( @{$commit->{items}} ) {
				# Not a regular file - see
				# https://github.com/gitster/git/blob/master/Documentation/technical/index-format.txt
				unless ( $item->{mode} =~ /^100/ ) {
					next;
				}

				my $fpath = $item->{name};
				my $lines_add = 0;
				my $lines_rm = 0;

				if ( exists $commit->{stat}{$fpath} ) {
					my $file_stat = $commit->{stat}{$fpath};
					$lines_add = $file_stat->{lines_added};
					$lines_rm = $file_stat->{lines_removed};
				}

				my ( $dir_l1, $dir_l2, $fname ) = $self->get_file_details( $fpath );
				my ( $ftype, $lang ) = $self->get_file_fname_lang(
					$fpath, $item->{hash}, $item->{mode}
				);
				my $sub_project = ( not defined $args{to_sub_project_tr_closure} )
					? '-'
					: $args{to_sub_project_tr_closure}->( $fpath, $dir_l1, $dir_l2, $fname )
				;

				# sha1 fpath dir_l1 dir_l2 fname ftype lang sub_project lines_add lines_rm
				$self->{csv_obj}->print( $self->{cfiles_csv_fh}, [
					$rcommit_sha, $fpath,
					$dir_l1, $dir_l2, $fname,
					$ftype, $lang, $sub_project,
					$lines_add, $lines_rm
				] );
			}
		}
    }

    $state->{max_id} = $max_id;

    $self->save_data( $state_fpath, $state );
    $self->save_data( $project_state_fpath, $project_state );
    return 1;
}

sub close_csv_files {
	my $self = shift;
	$self->{csv_fh}->close();
	if ( $self->{also_commits_files} ) {
		$self->{cfiles_csv_fh}->close();
	}
	$self->{csv_obj} = undef;
}

1;
