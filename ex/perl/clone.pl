#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use feature 'say';
use feature 'state';

use Data::Dumper;
use Carp;
use Git::Repository;

###############################################################################
# Logging
###############################################################################
sub _log {
  my $type = shift;
  my $format = @_> 1 ? shift : '%s';
  state $prev_log_ts;
  my $now = time;
  my $diff = defined $prev_log_ts ? $now - $prev_log_ts : 0;
  my $now_str = scalar localtime($now);
  $prev_log_ts = $now;
  warn sprintf(join(' ', '[%.6f][%s][+%.6f][%s]', $format)."\n", $now, $now_str, $diff, $type, @_);
}

sub WARN { _log('WRN', @_)}
sub ERROR { _log('ERR', @_)}
sub INFO { _log('INF', @_)}
sub DIE { ERROR(@_); exit 1}

###############################################################################
# Git
###############################################################################
sub git_common_opts {
  return {
    fatal => [ 1..255 ],
    env => {
      LC_ALL => 'C',
      TERM => '',
      #GIT_CONFIG_NOSYSTEM => 1,
      #XDG_CONFIG_HOME     => undef,
      #HOME                => undef,
    },
  };
}

sub create_git_object {
  my $opt = shift;
  my $git = Git::Repository->new(
    work_tree => $opt->{WorkDir},
    git_common_opts(),
  );
  return $git;
}

sub git_clone {
  my $ctx = shift;
  my $ret = {error => 0, fatal => 0, stdout => [], stderr => []};
  my ($git_cmd, $git_args) = (clone => ['--recurse-submodules', @{$ctx->{opt}}{qw(RepoUrl WorkDir)}]);
  my $desc = join(' ', 'git', $git_cmd, map{ "$_" } @$git_args);
  WARN('run %s', $desc);
  eval {
    my $cmd = Git::Repository->command($git_cmd => @$git_args);
    @{$ret->{stderr}} = $cmd->stderr->getlines();
    @{$ret->{stdout}} = $cmd->stdout->getlines(); # FIXME: may block forever in case of interactive command
    $cmd->close;
    chomp, ERROR("$desc: $_") for @{$ret->{stderr}};
    chomp, WARN("$desc: $_") for @{$ret->{stdout}};
    WARN('success %s', $desc);
  }; if ($@) {
    DIE('%s: %s', $desc, $@);
  }
  $ctx->{git} = create_git_object($ctx->{opt});
}

sub git_fetch {
  my $ctx = shift;
  $ctx->{git} //= create_git_object($ctx->{opt});
  git_exec($ctx, fetch => [$ctx->{opt}{Remote}]);
}


sub git_exec {
  my $ctx = shift or croak 'want context';
  my ($git_cmd, $git_args) = (shift, shift//{});
  croak 'want array' unless ref $git_args eq 'ARRAY';
  my $ret = {error => 0, fatal => 0, stdout => [], stderr => []};
  my $desc = join(' ', 'git', $git_cmd, map{ "$_" } @$git_args);
  WARN('run %s', $desc);
  eval {
    my $cmd = $ctx->{git}->command($git_cmd => @$git_args);
    @{$ret->{stderr}} = $cmd->stderr->getlines();
    @{$ret->{stdout}} = $cmd->stdout->getlines(); # FIXME: may block forever in case of interactive command
    $cmd->close;
    chomp, ERROR("$desc: $_") for @{$ret->{stderr}};
    chomp, WARN("$desc: $_") for @{$ret->{stdout}};
    WARN('success %s', $desc);
  }; if ($@) {
    DIE('%s: %s', $desc, $@);
  }
  return $ret;
}

###############################################################################
# Main
###############################################################################
my $opt = {
  RepoUrl => 'git@github.com:mxpaul/git-repository-example.git',
  Remote => 'origin',
  WorkDir => '/home/user/tmp/test/git-repository-example',
  Branch => 'master',
};

my $ctx = {
  opt => $opt,
};

if (-d $opt->{WorkDir} && -d join('/', $opt->{WorkDir}, '.git')) {
  git_fetch($ctx);
} else {
  git_clone($ctx);
}
DIE('git undef') unless ref $ctx->{git};


git_exec($ctx, checkout => [@{$opt}{qw(Branch)}]);
git_exec($ctx, log => ["-10"]);
