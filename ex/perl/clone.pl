#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use feature 'say';
use feature 'state';

use Data::Dumper;
use Carp;
use AnyEvent;
use AnyEvent::Handle;
use System::Command -quiet;
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

sub fd_reader {
  my $cv = pop or croak 'want cv';
  my $arg = shift; croak 'want hash' unless ref $arg eq 'HASH';

  my %s;
  $cv->begin;
  $s{handle} = AnyEvent::Handle->new(
    fh => $arg->{fd},
    on_error => sub {
      my ($h, $fatal, $err) = (shift, shift, shift);
      ERROR('%s stderr: %s on_error: %s', $arg->{desc}, ($fatal? '[FATAL]' : ''), $err//'<undef>' );
      $h->destroy;
      $cv->end;
      undef %s;
    },
    on_read => sub {
      #WARN('%s stderr: ENTER on_read', $desc);
      %s or return;
      my $h = shift or return;
      while (length($h->{rbuf}) && $h->{rbuf} =~ /\G([^\n]+)?$/sm) {
        my $line = substr($h->{rbuf}, 0, length($1//'') + 1, '');
        return unless defined $line;
        chomp $line;
        push @{$arg->{dst}}, $line if ref $arg->{dst} eq 'ARRAY';
        $arg->{logger}->($line) if ref $arg->{logger} eq 'CODE';
      }
    },
    on_eof => sub {
      $cv->end;
      delete $s{err_handle};
    },
  );
}

sub git_exec {
  my $ctx = shift or croak 'want context';
  my ($git_cmd, $git_args) = (shift, shift//{});
  croak 'want array' unless ref $git_args eq 'ARRAY';
  my $ret = {error => 0, fatal => 0, stdout => [], stderr => []};
  my $desc = join(' ', 'git', $git_cmd, map{ "$_" } @$git_args);
  WARN('====================================');
  WARN('run %s', $desc);
  my $cv = AE::cv;
  eval {
    my $cmd = $ctx->{git}->command($git_cmd => @$git_args);
    fd_reader({fd => $cmd->stderr, desc => $desc, logger => \&ERROR, dst => $ret->{stderr}}, $cv);
    fd_reader({fd => $cmd->stdout, desc => $desc, logger => \&WARN, dst => $ret->{stdout}}, $cv);
    $cv->recv;
    #$cmd->close if $cmd->is_terminated;
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
