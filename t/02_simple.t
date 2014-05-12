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

my $project_alias = 'git-trepo';
my $cm_obj = get_clonesmanager_obj($project_alias);
my $base_repo_obj = $cm_obj->get_repo_obj(
	$project_alias,
	repo_url => 'git@github.com:mj41/git-trepo.git',
	skip_fetch => 1,
);

my $tmp_dir = File::Temp::tempdir( CLEANUP => 1 );
ok( (-d $tmp_dir), 'tmp dir created' );

sub commits_csv {
	return <<'COMMIT_CSV';
commit_sha1,project,author_date,committer_date,commit_author,commit_author_email,commit_committer,commit_committer_email,merge,parents,files_a,files_m,files_d,lines_add,lines_rm
c1845d7580a091c1718e083cc5e90751cf3853f3,"GA test pr",2006-07-21,2006-07-21,"Karel Lysohlavka",kal@houby.eu,"Karel Lysohlavka",kal@houby.eu,0,0,1,0,0,2,0
ac03197f450c74342f76f6eab41569a26fa3baaa,"GA test pr",2006-07-22,2006-07-22,"Karel Lysohlavka",kal@houby.eu,"Josef Pepa Muchomurka",josef.p.muchomurka@mushrooms.com,0,1,0,1,0,3,0
5f210bbb24cd5aefebe2af941161fc932977b3c3,"GA test pr",2006-07-23,2006-07-23,"Karel Lysohlavka",kal@houby.eu,"Josef Pepa Muchomurka",josef.p.muchomurka@mushrooms.com,0,1,0,1,0,1,3
4fab7f5354212394c2d351de2c62618a5df69357,"GA test pr",2006-07-24,2006-07-24,"Josef Pepa Muchomurka",josef.p.muchomurka@mushrooms.com,"Josef Pepa Muchomurka",josef.p.muchomurka@mushrooms.com,0,1,0,0,1,0,3
51a4b7bfd29422c94d9508c64432918b45edcf1b,"GA test pr",2006-07-25,2006-07-25,"Karel Lysohlavka",kal@houby.eu,"Josef Pepa Muchomurka",josef.p.muchomurka@mushrooms.com,0,1,7,0,0,13,0
50f8430f51ab6dd09f7b70ba04f50c7e6f8a013c,"GA test pr",2006-07-26,2006-07-26,"Josef Pepa Muchomurka",josef.p.muchomurka@mushrooms.com,"Josef Pepa Muchomurka",josef.p.muchomurka@mushrooms.com,0,1,0,7,0,8,6
5cc99b1f762d5693b9c6ab37d7ae876d799b84bc,"GA test pr",2006-07-27,2006-07-27,"Karel Lysohlavka",kal@houby.eu,"Karel Lysohlavka",kal@houby.eu,0,1,0,1,4,0,13
940397865d3b109ce7933d188bd37240897545bf,"GA test pr",2006-07-28,2006-07-28,"Eva Bedlova Zajickova",eva-zajickova@v-hribovem-lesiku.cz,"Eva Bedlova Zajickova",eva-zajickova@v-hribovem-lesiku.cz,0,1,2,0,3,2,2
COMMIT_CSV
}

sub commits_files_csv {
	return <<'COMMIT_FILES_CSV';
sha1,fpath,dir_l1,dir_l2,fname,ftype,lang,sub_project,cf_status_short,cf_status_descr,lines_add,lines_rm
c1845d7580a091c1718e083cc5e90751cf3853f3,fileR1.txt,,,fileR1.txt,unk,unk,-,A,added,2,0
ac03197f450c74342f76f6eab41569a26fa3baaa,fileR1.txt,,,fileR1.txt,unk,unk,-,M,modified,3,0
5f210bbb24cd5aefebe2af941161fc932977b3c3,fileR1.txt,,,fileR1.txt,unk,unk,-,M,modified,1,3
4fab7f5354212394c2d351de2c62618a5df69357,fileR1.txt,,,fileR1.txt,unk,unk,-,R,removed,0,3
51a4b7bfd29422c94d9508c64432918b45edcf1b,dirA/fileA01.txt,dirA,,fileA01.txt,unk,unk,-,A,added,3,0
51a4b7bfd29422c94d9508c64432918b45edcf1b,dirB/s-dirX/fileBsX02.txt,dirB,s-dirX,fileBsX02.txt,unk,unk,-,A,added,5,0
51a4b7bfd29422c94d9508c64432918b45edcf1b,dirB/s-dirY/fileBsY03.txt,dirB,s-dirY,fileBsY03.txt,unk,unk,-,A,added,5,0
50f8430f51ab6dd09f7b70ba04f50c7e6f8a013c,dirA/fileA01.txt,dirA,,fileA01.txt,unk,unk,-,M,modified,2,2
50f8430f51ab6dd09f7b70ba04f50c7e6f8a013c,dirB/s-dirX/fileBsX02.txt,dirB,s-dirX,fileBsX02.txt,unk,unk,-,M,modified,5,0
50f8430f51ab6dd09f7b70ba04f50c7e6f8a013c,dirB/s-dirY/fileBsY03.txt,dirB,s-dirY,fileBsY03.txt,unk,unk,-,M,modified,1,4
5cc99b1f762d5693b9c6ab37d7ae876d799b84bc,dirA/fileA01.txt,dirA,,fileA01.txt,unk,unk,-,R,removed,0,3
5cc99b1f762d5693b9c6ab37d7ae876d799b84bc,dirB/s-dirX/fileBsX02.txt,dirB,s-dirX,fileBsX02.txt,unk,unk,-,R,removed,0,10
940397865d3b109ce7933d188bd37240897545bf,dirA/fileA04-BsY03.txt,dirA,,fileA04-BsY03.txt,unk,unk,-,A,added,2,0
940397865d3b109ce7933d188bd37240897545bf,dirB/s-dirY/fileBsY03.txt,dirB,s-dirY,fileBsY03.txt,unk,unk,-,R,removed,0,2
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
				rev_range => '940397865d3b109ce7933d188bd37240897545bf',
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
