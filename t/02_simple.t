#!/usr/bin/perl

# perl -Ilib -I../Git-Repository-LogRaw/lib -I../Git-ClonesManager/lib t/02_simple.t

# Base flow tests.

use strict;
use Test::Spec;
use base qw(Test::Spec);
use Test::MockObject;

use FindBin ();
use File::Temp ();
use File::Slurp ();

use Git::ClonesManager;
use Git::Repository::LogRaw;

use Git::Analytics;


sub get_clonesmanager_obj {
	my ( $project_alias ) = @_;

	my $repos_clones_base_dir = File::Spec->catdir( $FindBin::RealBin, '..', 'temp' );
	mkdir($repos_clones_base_dir) unless -d $repos_clones_base_dir;

	my $repos_clones_dir = File::Spec->catdir( $repos_clones_base_dir, 't-repos-gcm' );
	mkdir($repos_clones_dir) unless -d $repos_clones_dir;

	my $cm_obj = Git::ClonesManager->new( data_path => $repos_clones_dir, vl => 1 );
	return $cm_obj;
}

my $project_alias = 'tt-tr1';
my $cm_obj = get_clonesmanager_obj($project_alias);
my $base_repo_obj = $cm_obj->get_repo_obj(
	$project_alias,
	repo_url => 'git@github.com:mj41/tt-tr1.git',
	skip_fetch => 1,
);

my $tmp_dir = File::Temp::tempdir( CLEANUP => 1 );
ok( (-d $tmp_dir), 'tmp dir created' );

sub commits_csv {
	return <<'COMMIT_CSV';
commit_sha1,project,author_date,committer_date,commit_author,commit_author_email,commit_committer,commit_committer_email,merge,parents,files_a,files_m,files_d,lines_add,lines_rm
5ac7c3d75e2af0fde3e07ce9e1698339c4241150,"GA test pr",2011-02-04,2011-02-04,"Michal Jurosz",mj@mj41.cz,"Michal Jurosz",mj@mj41.cz,0,1,0,1,0,1,1
88b266ba0c3021c3951b778c69ba16a1fc011270,"GA test pr",2011-02-07,2011-02-07,"Michal Jurosz",mj@mj41.cz,"Michal Jurosz",mj@mj41.cz,0,1,0,1,0,3,0
da1b48a750aefd30aaaf9aac4df8e7606f05a855,"GA test pr",2012-02-08,2012-02-08,"Michal Jurosz",mj@mj41.cz,"Michal Jurosz",mj@mj41.cz,0,1,6,0,0,67,0
fac2f14fc69dcb680bc83fbb827e12ff391e839b,"GA test pr",2012-04-01,2012-04-01,"Michal Jurosz",mj@mj41.cz,"Michal Jurosz",mj@mj41.cz,0,1,0,4,0,4,2
e1cd1429359c6e8cc10f7c1c20c0969390546f11,"GA test pr",2012-04-01,2012-04-01,"Michal Jurosz",mj@mj41.cz,"Michal Jurosz",mj@mj41.cz,0,1,0,2,0,1,1
COMMIT_CSV
}

sub commits_files_csv {
	return <<'COMMIT_FILES_CSV';
sha1,fpath,dir_l1,dir_l2,ftype,lang,sub_project
5ac7c3d75e2af0fde3e07ce9e1698339c4241150,Configure.pl,,,Configure.pl,,,,0,0
88b266ba0c3021c3951b778c69ba16a1fc011270,Makefile,,,Makefile,,,,0,0
da1b48a750aefd30aaaf9aac4df8e7606f05a855,.gitignore,,,.gitignore,,,,0,0
da1b48a750aefd30aaaf9aac4df8e7606f05a855,t/1_base.t,t,,1_base.t,,,,0,0
da1b48a750aefd30aaaf9aac4df8e7606f05a855,t/2_err.t,t,,2_err.t,,,,0,0
da1b48a750aefd30aaaf9aac4df8e7606f05a855,t/3_more.t,t,,3_more.t,,,,0,0
da1b48a750aefd30aaaf9aac4df8e7606f05a855,t/harness,t,,harness,,,,0,0
fac2f14fc69dcb680bc83fbb827e12ff391e839b,t/1_base.t,t,,1_base.t,,,,0,0
fac2f14fc69dcb680bc83fbb827e12ff391e839b,t/2_err.t,t,,2_err.t,,,,0,0
fac2f14fc69dcb680bc83fbb827e12ff391e839b,t/3_more.t,t,,3_more.t,,,,0,0
e1cd1429359c6e8cc10f7c1c20c0969390546f11,t/3_more.t,t,,3_more.t,,,,0,0
COMMIT_FILES_CSV
}


my $verbose_level = $ARGV[0] // 1;

describe "method" => sub {

	my $git_lograw_obj;
	my $ga_obj;

	my $commits_fpath = File::Spec->catfile( $tmp_dir, 'commits.csv' );
	my $commits_files_fpath = File::Spec->catfile( $tmp_dir, 'commits_details.csv' );

	it "Git::Repository::LogRaw->new" => sub {
		$git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, $verbose_level );
	};

	it "new" => sub {
		$ga_obj = Git::Analytics->new(
			verbose_level => $verbose_level,
			also_commits_files => 1,
			data_cache_dir => $tmp_dir,
		);
	};

	it "open_out_csv_files" => sub {
		$ga_obj->open_out_csv_files( $commits_fpath, $commits_files_fpath );
	};

	it "print_csv_headers" => sub {
		$ga_obj->print_csv_headers();
	};

	it "print_csv_headers" => sub {
		$ga_obj->process_one(
			$project_alias,
			'GA test pr',
			$git_lograw_obj,
			git_log_args => {
				rev_range => 'b5a35dc398e30bcec04c3dcb14f53a077750466c..e1cd1429359c6e8cc10f7c1c20c0969390546f11',
			}
		);
	};

	it "close_csv_file" => sub {
		$ga_obj->close_csv_files();
		ok(1);
	};


	it "commits csv content" => sub {
		ok( -f $commits_fpath ) && is(
			File::Slurp::read_file( $commits_fpath ),
			commits_csv(),
		);
	};

	it "commits_files csv content" => sub {
		ok( -f $commits_files_fpath ) && is(
			File::Slurp::read_file( $commits_files_fpath ),
			commits_files_csv(),
		);
	};
};

runtests unless caller;
