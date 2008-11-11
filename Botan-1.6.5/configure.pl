#!/usr/bin/perl -w

require 5.006;

use strict;
use Getopt::Long;
use File::Spec;
use File::Copy;

my $MAJOR_VERSION = 1;
my $MINOR_VERSION = 6;
my $PATCH_VERSION = 5;

my $VERSION_STRING = "$MAJOR_VERSION.$MINOR_VERSION.$PATCH_VERSION";

##################################################
# Data                                           #
##################################################
my (%CPU, %OPERATING_SYSTEM, %COMPILER, %MODULES);

my @DOCS = (
   'api.pdf', 'tutorial.pdf', 'fips140.pdf',
   'api.tex', 'tutorial.tex', 'fips140.tex',
   'credits.txt', 'info.txt', 'license.txt', 'log.txt',
   'thanks.txt', 'todo.txt', 'pgpkeys.asc');

my %MODULE_SETS =
    (
     'unix' => [ 'alloc_mmap', 'es_egd', 'es_ftw', 'es_unix', 'fd_unix',
                 'tm_unix' ],
     'beos' => [ 'es_beos', 'es_unix', 'fd_unix', 'tm_unix' ],
     'win32' => ['es_capi', 'es_win32', 'mux_win32', 'tm_win32' ],
     );

my $TRACING = 0;

##################################################
# Run main() and Quit                            #
##################################################
main();
exit;

##################################################
# Main Driver                                    #
##################################################
sub main {
    my $config = {};

    my $base_dir = where_am_i();

    $$config{'base-dir'} = $base_dir;
    $$config{'config-dir'} = File::Spec->catdir($base_dir, 'misc', 'config');
    $$config{'mods-dir'} = File::Spec->catdir($base_dir, 'modules');
    $$config{'src-dir'} = File::Spec->catdir($base_dir, 'src');
    $$config{'include-dir'} = File::Spec->catdir($base_dir, 'include');
    $$config{'checks-dir'} = File::Spec->catdir($base_dir, 'checks');
    $$config{'doc-dir'} = File::Spec->catdir($base_dir, 'doc');

    %CPU = read_info_files($config, 'arch', \&get_arch_info);
    %OPERATING_SYSTEM = read_info_files($config, 'os', \&get_os_info);
    %COMPILER = read_info_files($config, 'cc', \&get_cc_info);
    %MODULES = read_module_files($config);

    add_to($config, {
        'version_major' => $MAJOR_VERSION,
        'version_minor' => $MINOR_VERSION,
        'version_patch' => $PATCH_VERSION,
        'version'       => $VERSION_STRING,
        });

    my ($target, $module_list) = get_options($config);

    my $default_value_is = sub {
        my ($var, $val) = @_;
        $$config{$var} = $val if not defined($$config{$var});
    };

    &$default_value_is('gcc_bug', 0);
    &$default_value_is('autoconfig', 1);
    &$default_value_is('debug', 0);
    &$default_value_is('shared', 'yes');
    &$default_value_is('build-dir', 'build');
    &$default_value_is('local_config', '');

    choose_target($config, $target);

    my $os = $$config{'os'};
    my $cc = $$config{'compiler'};

    &$default_value_is('prefix', os_info_for($os, 'install_root'));
    &$default_value_is('libdir', os_info_for($os, 'lib_dir'));
    &$default_value_is('docdir', os_info_for($os, 'doc_dir'));
    &$default_value_is('make_style', $COMPILER{$cc}{'makefile_style'});

    my @modules = choose_modules($config, $module_list);

    add_to($config, {
        'includedir'    => os_info_for($os, 'header_dir'),

        'build_lib'     => File::Spec->catdir($$config{'build-dir'}, 'lib'),
        'build_check'   => File::Spec->catdir($$config{'build-dir'}, 'checks'),
        'build_include' =>
            File::Spec->catdir($$config{'build-dir'}, 'include'),
        'build_include_botan' =>
            File::Spec->catdir($$config{'build-dir'}, 'include', 'botan'),

        'modules'       => [ @modules ],
        'mp_bits'       => find_mp_bits(@modules),
        'mod_libs'      => [ using_libs($os, @modules) ],

        'sources'       => {
            map_to($$config{'src-dir'}, dir_list($$config{'src-dir'}))
            },

        'includes'      => {
            map_to($$config{'include-dir'}, dir_list($$config{'include-dir'}))
            },

        'check_src'     => {
            map_to($$config{'checks-dir'},
                   grep { $_ ne 'keys' and !m@\.(dat|h)$@ }
                      dir_list($$config{'checks-dir'}))
            }
        });

    load_modules($config);

    mkdirs($$config{'build-dir'},
           $$config{'build_include'}, $$config{'build_include_botan'},
           $$config{'build_lib'}, $$config{'build_check'});

    write_pkg_config($config);

    process_template(File::Spec->catfile($$config{'config-dir'}, 'buildh.in'),
                     File::Spec->catfile($$config{'build-dir'}, 'build.h'),
                     $config);
    $$config{'includes'}{'build.h'} = $$config{'build-dir'};

    copy_include_files($config);

    generate_makefile($config);
}

sub where_am_i {
    my ($volume,$dir,$file) = File::Spec->splitpath($0);
    my $src_dir = File::Spec->catpath($volume, $dir, '');
    return $src_dir if $src_dir;
    return File::Spec->curdir();
}

##################################################
# Diagnostics                                    #
##################################################
sub with_diagnostic {
    my ($type, @args) = @_;

    my $args = join('', @args);
    my $str = "($type): ";
    while(length($str) < 14) { $str = ' ' . $str; }

    $str .= $args . "\n";
    return $str;
}

sub croak {
    die with_diagnostic('error', @_);
}

sub warning {
    warn with_diagnostic('note', @_);
}

sub autoconfig {
    print with_diagnostic('autoconfig', @_);
}

sub emit_help {
    print join('', @_);
    exit;
}

sub trace {
    return unless $TRACING;

    my (undef, undef, $line1) = caller(0);
    my (undef, undef, $line2, $func1) = caller(1);
    my (undef, undef, undef, $func2) = caller(2);

    $func1 =~ s/main:://;
    $func2 =~ s/main:://;

    warn with_diagnostic('trace', "at $func1:$line1 - ", @_);
}

##################################################
# Display Help and Quit                          #
##################################################
sub display_help {
   my $sets = join('|', sort keys %MODULE_SETS);

   my $helptxt = <<ENDOFHELP;
Usage: $0 [options] CC-OS-CPU

See doc/building.pdf for more information about this program.

Options:
  --prefix=PATH:       set the base installation directory
  --libdir=PATH:       install library files in \${prefix}/\${libdir}
  --docdir=PATH:       install documentation in \${prefix}/\${docdir}
  --build-dir=DIR:     setup the build in DIR
  --local-config=FILE: include the contents of FILE into build.h

  --modules=MODS:      add module(s) MODS to the library.
  --module-set=SET:    add a pre-specified set of modules ($sets)
  --module-info:       display some information about known modules

  --debug:             set compiler flags for debugging
  --disable-shared:    disable building shared libararies
  --noauto:            disable autoconfiguration
  --make-style=STYLE:  override the guess as to what type of makefile to use

You may use 'generic' for OS or CPU (useful if your OS or CPU isn't listed).

CPU can be a generic family name or a specific model name. Common aliases are
supported but not listed. Choosing a specific submodel will usually result in
code that will not run on earlier versions of that architecture.

ENDOFHELP

   my $listing = sub {
       my ($header, @list) = @_;

       return '' if (@list == 0);

       my ($output, $len) = ('', 0);

       my $append = sub {
          my ($to_append) = @_;
          $output .= $to_append;
          $len += length $to_append;
       };

       &$append($header . ': ');

       foreach my $name (sort @list) {
           next if $name eq 'defaults';
           if($len > 71) {
               $output .= "\n   ";
               $len = 3;
           }
           &$append($name . ' ');
       }
       return $output . "\n";
   };

    emit_help($helptxt,
              &$listing('CC', keys %COMPILER),
              &$listing('OS', keys %OPERATING_SYSTEM),
              &$listing('CPU', keys %CPU),
              &$listing('Modules', keys %MODULES));
}

##################################################
# Display Further Information about Modules      #
##################################################
sub display_module_info {

    my $info = '';
    foreach my $mod (sort keys %MODULES) {
        my $modinfo = $MODULES{$mod};
        my $fullname = $$modinfo{'realname'};

        while(length($mod) < 10) { $mod .= ' '; }
        $info .= "$mod - $fullname\n";
    }
    emit_help($info);
}

##################################################
# 
##################################################
sub choose_target {
    my ($config, $target) = @_;

    if($target eq '' and $$config{'autoconfig'}) {
        $target = guess_triple();
        autoconfig("Guessing your system config is $target");
    }

    my ($cc,$os,$submodel) = split(/-/,$target,3);

    display_help()
        unless(defined($cc) and defined($os) and defined($submodel));

    croak("Compiler $cc isn't known (try --help)")
        unless defined($COMPILER{$cc});

    my %ccinfo = %{$COMPILER{$cc}};

    $os = os_alias($os);
    croak("OS $os isn't known (try --help)") unless
        ($os eq 'generic' or defined($OPERATING_SYSTEM{$os}));

    my $arch = undef;
    ($arch, $submodel) = figure_out_arch($submodel);

    croak(realname($os), " doesn't run on $arch ($submodel)")
        unless($arch eq 'generic' or $os eq 'generic' or
               in_array($arch, $OPERATING_SYSTEM{$os}{'arch'}));

    croak(realname($cc), " doesn't run on $arch ($submodel)")
        unless($arch eq 'generic' or
               (in_array($arch, $ccinfo{'arch'})));

    croak(realname($cc), " doesn't run on ", realname($os))
        unless($os eq 'generic' or (in_array($os, $ccinfo{'os'})));

    # hacks
    if($cc eq 'gcc') {
        $ccinfo{'binary_name'} = 'c++' if($os eq 'darwin');

        if($$config{'gcc_bug'} != 1) {
            my $binary = $ccinfo{'binary_name'};

            my $gcc_version = `$binary -v 2>&1`;

            $gcc_version = '' if not defined $gcc_version;

            # Some versions of GCC are a little buggy dealing with
            # long long in C++. The last check is because on Cygwin
            # (at least for me) gcc_version doesn't get the output,
            # maybe something to do with the stderr redirection? If
            # it's Cygwin and we didn't get output, assume it's a
            # buggy GCC. There is no reduction in code quality so even
            # if we're wrong it's OK.

            if(($gcc_version =~ /4\.[0123]/) || ($gcc_version =~ /3\.[34]/) ||
               ($gcc_version =~ /2\.95\.[0-4]/) ||
               ($gcc_version eq '' && $^O eq 'cygwin'))
            {
                warning('Enabling -fpermissive to work around ',
                        'possible GCC bug');

                $$config{'gcc_bug'} = 1;
            }
            if($gcc_version =~ /2\.95\.[0-4]/)
            {
                warning('GCC 2.95.x issues many spurious warnings');
            }
        }
    }

    add_to($config, {
        'compiler'      => $cc,
        'os'            => $os,
        'arch'          => $arch,
        'submodel'      => $submodel,
    });
}

sub choose_modules {
    my ($config, $mod_str) = @_;

    my @modules = grep { $_ ne '' } split(/,/, $mod_str);

    if($$config{'autoconfig'})
    {
        foreach my $mod (guess_mods($config)) {

            autoconfig("Enabling module $mod")
                unless in_array($mod, \@modules);

            push @modules, $mod;
        }
    }

    # Uniqify @modules
    my %uniqed_mods = map_to(undef, @modules);
    @modules = sort keys %uniqed_mods;

    foreach (@modules) {
        croak("Module '$_' isn't known (try --help)")
            unless defined $MODULES{$_};
    }
    return @modules;
}

sub get_options {
    my ($config) = @_;

    my $save_option = sub {
        my ($opt, $val) = @_;
        $opt =~ s/-/_/g;
        $$config{$opt} = $val;
    };

    my $module_set = '';
    my @modules;
    exit 1 unless GetOptions(
               'help' => sub { display_help(); },
               'module-info' => sub { display_module_info(); },
               'version' => sub { emit_help("Botan $VERSION_STRING\n") },

               'prefix=s' => sub { &$save_option(@_); },
               'docdir=s' => sub { &$save_option(@_); },
               'libdir=s' => sub { &$save_option(@_); },
               'build-dir=s' => sub { &$save_option('build', $_[0]); },
               'local-config=s' =>
                  sub { &$save_option('local_config', slurp_file($_[1])); },

               'make-style=s' => sub { &$save_option(@_); },

               'modules=s' => \@modules,
               'module-set=s' => \$module_set,

               'debug' => sub { &$save_option($_[0], 1); },
               'disable-shared' => sub { $$config{'shared'} = 'no'; },
               'noauto' => sub { $$config{'autoconfig'} = 0; },
               'dumb-gcc|gcc295x' => sub { $$config{'gcc_bug'} = 1; }
               );

    croak("Module set $module_set isn't known (try --help)")
        if($module_set && !defined($MODULE_SETS{$module_set}));

    if($module_set) {
        foreach (@{ $MODULE_SETS{$module_set} }) { push @modules,$_; }
    }

    my $mod_str = join(',', @modules);

    return ('', $mod_str) if($#ARGV == -1);
    return ($ARGV[0], $mod_str) if($#ARGV == 0);
    display_help();
}

##################################################
# Functions to search the info tables            #
##################################################
sub figure_out_arch {
    my ($name) = @_;

    return ('generic', 'generic') if($name eq 'generic');

    my $submodel_alias = sub {
        my ($name,$info) = @_;

        my %info = %{$info};

        foreach my $submodel (@{$info{'submodels'}}) {
            return $submodel if($name eq $submodel);
        }

        return '' unless defined $info{'submodel_aliases'};
        my %sm_aliases = %{$info{'submodel_aliases'}};

        foreach my $alias (keys %sm_aliases) {
            my $official = $sm_aliases{$alias};
            return $official if($alias eq $name);
        }
        return '';
    };

    my $find_arch = sub {
        my $name = $_[0];

        foreach my $arch (keys %CPU) {
            my %info = %{$CPU{$arch}};

            return $arch if($name eq $arch);

            foreach my $alias (@{$info{'aliases'}}) {
                return $arch if($name eq $alias);
            }

            foreach my $submodel (@{$info{'submodels'}}) {
                return $arch if($name eq $submodel);
            }

            foreach my $submodel (keys %{$info{'submodel_aliases'}}) {
                return $arch if($name eq $submodel);
            }
        }
        return undef;
    };

    my $arch = &$find_arch($name);
    croak("Arch type $name isn't known (try --help)") unless defined $arch;
    trace("mapped name '$name' to arch '$arch'");

    my %archinfo = %{ $CPU{$arch} };

    my $submodel = &$submodel_alias($name, \%archinfo);

    if($submodel eq '') {
        $submodel = $archinfo{'default_submodel'};

        warning("Using $submodel as default type for family ", realname($arch))
           if($submodel ne $arch);
    }

    trace("mapped name '$name' to submodel '$submodel'");

    croak("Couldn't figure out arch type of $name")
        unless defined($arch) and defined($submodel);

    return ($arch,$submodel);
}

sub os_alias {
    my $name = $_[0];

    foreach my $os (keys %OPERATING_SYSTEM) {
        foreach my $alias (@{$OPERATING_SYSTEM{$os}{'aliases'}}) {
            if($alias eq $name) {
                trace("os_alias($name) -> $os");
                return $os;
                }
        }
    }

    return $name;
}

sub os_info_for {
    my ($os,$what) = @_;

    croak('os_info_for called with an os of defaults (internal problem)')
        if($os eq 'defaults');

    my $result = '';

    if(defined($OPERATING_SYSTEM{$os})) {
        my %osinfo = %{$OPERATING_SYSTEM{$os}};
        $result = $osinfo{$what};
    }

    if(!defined($result) or $result eq '') {
        $result = $OPERATING_SYSTEM{'defaults'}{$what};
    }

    croak("os_info_for: No info for $what on $os") unless defined $result;

    return $result;
}

sub my_compiler {
    my ($config) = @_;
    my $cc = $$config{'compiler'};

    croak('my_compiler called, but no compiler set in config')
        unless defined $cc and $cc ne '';

    croak("unknown compiler $cc") unless defined $COMPILER{$cc};

    return %{$COMPILER{$cc}};
}

sub mach_opt {
    my ($config) = @_;

    my %ccinfo = my_compiler($config);

    # Nothing we can do in that case
    return '' unless $ccinfo{'mach_opt_flags'};

    my $submodel = $$config{'submodel'};
    my $arch = $$config{'arch'};
    if(defined($ccinfo{'mach_opt_flags'}{$submodel}))
    {
        return $ccinfo{'mach_opt_flags'}{$submodel};
    }
    elsif(defined($ccinfo{'mach_opt_flags'}{$arch})) {
        my $mach_opt_flags = $ccinfo{'mach_opt_flags'}{$arch};
        my $processed_modelname = $submodel;

        my $remove = '';
        if(defined($ccinfo{'mach_opt_re'}) and
           defined($ccinfo{'mach_opt_re'}{$arch})) {
            $remove = $ccinfo{'mach_opt_re'}{$arch};
        }

        $processed_modelname =~ s/$remove//;
        $mach_opt_flags =~ s/SUBMODEL/$processed_modelname/g;
        return $mach_opt_flags;
    }
    return '';
}

##################################################
#                                                #
##################################################
sub using_libs {
   my ($os,@using) = @_;
   my %libs;

   foreach my $mod (@using) {
      my %MOD_LIBS = %{ $MODULES{$mod}{'libs'} };
      foreach my $mod_os (keys %MOD_LIBS) {
          next if($mod_os =~ /^all!$os$/);
          next if($mod_os =~ /^all!$os,/);
          next if($mod_os =~ /^all!.*,${os}$/);
          next if($mod_os =~ /^all!.*,$os,.*/);
          next unless($mod_os eq $os or ($mod_os =~ /^all.*/));
          my @liblist = split(/,/, $MOD_LIBS{$mod_os});
          foreach my $lib (@liblist) { $libs{$lib} = 1; }
          }
      }

   return sort keys %libs;
   }

sub libs {
    my ($prefix,$suffix,@libs) = @_;
    my $output = '';
    foreach my $lib (@libs) {
        $output .= ' ' if($output ne '');
        $output .= $prefix . $lib . $suffix;
    }
    return $output;
}

##################################################
# Path and file manipulation utilities           #
##################################################
sub portable_symlink {
   my ($from, $to_dir, $to_fname) = @_;

   my $can_symlink = 0;
   my $can_link = 0;

   unless($^O eq 'MSWin32' or $^O eq 'dos' or $^O eq 'cygwin') {
       $can_symlink = eval { symlink("",""); 1 };
       $can_link = eval { link("",""); 1 };
   }

   chdir $to_dir or croak("Can't chdir to $to_dir ($!)");

   if($can_symlink) {
       symlink $from, $to_fname or
           croak("Can't symlink $from to $to_fname ($!)");
   }
   elsif($can_link) {
       link $from, $to_fname or
           croak("Can't link $from to $to_fname ($!)");
   }
   else {
       copy ($from, $to_fname) or
           croak("Can't copy $from to $to_fname ($!)");
   }

   my $go_up = File::Spec->splitdir($to_dir);
   for(my $j = 0; $j != $go_up; $j++) # return to where we were
   {
       chdir File::Spec->updir();
   }
}

sub copy_include_files {
    my ($config) = @_;

    my $include_dir = $$config{'build_include_botan'};

    trace('Copying to ', $include_dir);

    foreach my $file (dir_list($include_dir)) {
        my $path = File::Spec->catfile($include_dir, $file);
        unlink $path or croak("Could not unlink $path ($!)");
    }

   my $link_up = sub {
       my ($dir, $file) = @_;
       my $updir = File::Spec->updir();
       portable_symlink(File::Spec->catfile($updir, $updir, $updir,
                                            $dir, $file),
                        $include_dir, $file);
   };

    my $files = $$config{'includes'};

    foreach my $file (keys %$files) {
        &$link_up($$files{$file}, $file);
    }
}

sub dir_list {
    my ($dir) = @_;
    opendir(DIR, $dir) or croak("Couldn't read directory '$dir' ($!)");

    my @listing = grep { $_ ne File::Spec->curdir() and
                         $_ ne File::Spec->updir() } readdir DIR;

    closedir DIR;
    return @listing;
}

sub mkdirs {
    my (@dirs) = @_;
    foreach my $dir (@dirs) {
        next if( -e $dir and -d $dir ); # skip it if it's already there
        mkdir($dir, 0777) or
            croak("Could not create directory $dir ($!)");
    }
}

sub slurp_file {
    my $file = $_[0];

    return '' if(!defined($file) or $file eq '');

    croak("'$file': No such file") unless(-e $file);
    croak("'$file': Not a regular file") unless(-f $file);

    open FILE, "<$file" or croak("Couldn't read $file ($!)");

    my $output = '';
    while(<FILE>) { $output .= $_; }
    close FILE;

    return $output;
}

sub which
{
    my $file = $_[0];
    my @paths = split(/:/, $ENV{PATH});
    foreach my $path (@paths)
    {
        my $file_path = File::Spec->catfile($path, $file);
        return $file_path if(-e $file_path and -r $file_path);
    }
    return '';
}

# Return a hash mapping every var in a list to a constant value
sub map_to {
    my $var = shift;
    return map { $_ => $var } @_;
}

sub in_array {
    my($target, $array) = @_;
    return 0 unless defined($array);
    foreach (@$array) { return 1 if($_ eq $target); }
    return 0;
}

sub add_to {
    my ($to,$from) = @_;

    foreach my $key (keys %$from) {
        $$to{$key} = $$from{$key};
    }
}

##################################################
#                                                #
##################################################
sub find_mp_bits {
    my(@modules_list) = @_;
    my $mp_bits = 32; # default, good for most systems

    my $seen_mp_module = undef;

    foreach my $modname (@modules_list) {
        my %modinfo = %{ $MODULES{$modname} };
        if($modinfo{'mp_bits'}) {
            if(defined($seen_mp_module) and $modinfo{'mp_bits'} != $mp_bits) {
                croak('Inconsistent mp_bits requests from modules ',
                      $seen_mp_module, ' and ', $modname);
            }

            $seen_mp_module = $modname;
            $mp_bits = $modinfo{'mp_bits'};
        }
    }
    return $mp_bits;
}

##################################################
#                                                #
##################################################
sub realname {
    my $arg = $_[0];

    return $COMPILER{$arg}{'realname'}
       if defined $COMPILER{$arg};

    return $OPERATING_SYSTEM{$arg}{'realname'}
       if defined $OPERATING_SYSTEM{$arg};

    return $CPU{$arg}{'realname'}
       if defined $CPU{$arg};

    return $arg;
}

##################################################
#                                                #
##################################################
sub load_modules {
    my ($config) = @_;

    my @modules = @{$$config{'modules'}};

    foreach my $mod (@modules) {
        load_module($config, $mod);
    }

    my $gen_defines = sub {
        my $defines = '';

        my $arch = $$config{'arch'};
        if($arch ne 'generic') {
            $arch = uc $arch;
            $defines .= "#define BOTAN_TARGET_ARCH_IS_$arch\n";

            my $submodel = $$config{'submodel'};
            if($arch ne $submodel) {
                $submodel = uc $submodel;
                $submodel =~ s/-/_/g;
                $defines .= "#define BOTAN_TARGET_CPU_IS_$submodel\n";
            }
        }

        my @defarray;
        foreach my $mod (@modules) {
            my $defs = $MODULES{$mod}{'define'};
            next unless $defs;

            push @defarray, split(/,/, $defs);
        }
        foreach (sort @defarray) {
            die unless(defined $_ and $_ ne '');
            $defines .= "#define BOTAN_EXT_$_\n";
        }
        chomp($defines);
        return $defines;
    };

    $$config{'defines'} = &$gen_defines();
}

sub load_module {
    my ($config, $modname) = @_;

    my %module = %{$MODULES{$modname}};

    my $works_on = sub {
        my ($what, @lst) = @_;
        return 1 if not @lst; # empty list -> no restrictions
        return 1 if $what eq 'generic'; # trust the user
        return in_array($what, \@lst);
    };

    # Check to see if everything is OK WRT system requirements
    my $os = $$config{'os'};

    croak("Module '$modname' does not run on $os")
        unless(&$works_on($os, @{$module{'os'}}));

    my $arch = $$config{'arch'};
    my $sub = $$config{'submodel'};

    croak("Module '$modname' does not run on $arch/$sub")
        unless(&$works_on($arch, @{$module{'arch'}}) or
               &$works_on($sub, @{$module{'arch'}}));

    my $cc = $$config{'compiler'};

    croak("Module '$modname' does not work with $cc")
        unless(&$works_on($cc, @{$module{'cc'}}));

    my $handle_files = sub {
        my($lst, $func) = @_;
        return unless defined($lst);

        foreach (sort @$lst) {
            &$func($modname, $config, $_);
        }
    };

    &$handle_files($module{'ignore'},  \&ignore_file);
    &$handle_files($module{'add'},     \&add_file);
    &$handle_files($module{'replace'},
                   sub { ignore_file(@_); add_file(@_); });

    warning($modname, ': ', $module{'note'})
        if(defined($module{'note'}));
}

##################################################
#                                                #
##################################################
sub file_type {
    my ($config, $file) = @_;

    return ('sources', $$config{'src-dir'})
        if($file =~ /\.cpp$/ or $file =~ /\.S$/);
    return ('includes', $$config{'include-dir'})
        if($file =~ /\.h$/);

    croak('file_type() - don\'t know what sort of file ', $file, ' is');
}

sub add_file {
    my ($modname, $config, $file) = @_;

    check_for_file($config, $file, $modname, $modname);

    my $mod_dir = File::Spec->catdir($$config{'mods-dir'}, $modname);

    my $do_add_file = sub {
        my ($type) = @_;

        croak("File $file already added from ", $$config{$type}{$file})
            if(defined($$config{$type}{$file}));

        $$config{$type}{$file} = $mod_dir;
    };

    &$do_add_file(file_type($config, $file));
}

sub ignore_file {
    my ($modname, $config, $file) = @_;
    check_for_file($config, $file, undef, $modname);

    my $do_ignore_file = sub {
        my ($type, $ok_if_from) = @_;

        if(defined ($$config{$type}{$file})) {

            croak("$modname - File $file modified from ",
                  $$config{$type}{$file})
                if($$config{$type}{$file} ne $ok_if_from);

            delete $$config{$type}{$file};
        }
    };

    &$do_ignore_file(file_type($config, $file));
}

sub check_for_file {
   my ($config, $file, $added_from, $modname) = @_;

   my $full_path = sub {
       my ($file,$modname) = @_;

       return File::Spec->catfile($$config{'mods-dir'}, $modname, $file)
           if(defined($modname));

       my @typeinfo = file_type($config, $file);
       return File::Spec->catfile($typeinfo[1], $file);
   };

   $file = &$full_path($file, $added_from);

   croak("Module $modname requires that file $file exist. This error\n      ",
         'should never occur; please contact the maintainers with details.')
       unless(-e $file);
}

##################################################
#                                                #
##################################################
sub process_template {
    my ($in, $out, $config) = @_;

    trace("$in -> $out");

    my $contents = slurp_file($in);

    foreach my $name (keys %$config) {
        my $val = $$config{$name};

        croak("Undefined variable $name in $in") unless defined $val;

        $contents =~ s/@\{var:$name\}/$val/g;

        unless($val eq 'no' or $val eq 'false') {
            $contents =~ s/\@\{if:$name (.*)\}/$1/g;
            $contents =~ s/\@\{if:$name (.*) (.*)\}/$1/g;
        } else {
            $contents =~ s/\@\{if:$name (.*)\}//g;
            $contents =~ s/\@\{if:$name (.*) (.*)\}/$2/g;
        }
    }

    if($contents =~ /@\{var:([a-z_]*)\}/ or
       $contents =~ /@\{if:(.*) /) {
        croak("Unbound variable '$1' in $in");
    }

    open OUT, ">$out" or croak("Couldn't write $out ($!)");
    print OUT $contents;
    close OUT;
}

##################################################
#                                                #
##################################################
sub read_list {
    my ($line, $reader, $marker, $func) = @_;

    if($line =~ m@^<$marker>$@) {
        while(1) {
            $line = &$reader();
            last if($line =~ m@^</$marker>$@);
            &$func($line);
        }
    }
}

sub list_push {
    my ($listref) = @_;
    return sub { push @$listref, $_[0]; }
}

sub match_any_of {
    my ($line, $hash, $quoted, $any_of) = @_;

    $quoted = ($quoted eq 'quoted') ? 1 : 0;

    my @match_these = split(/:/, $any_of);

    foreach my $what (split(/:/, $any_of)) {
        $$hash{$what} = $1 if(not $quoted and $line =~ /^$what (.*)/);
        $$hash{$what} = $1 if($quoted and $line =~ /^$what \"(.*)\"/);
    }
}

##################################################
#                                                #
##################################################
sub make_reader {
    my $filename = $_[0];

    croak("make_reader(): Arg was undef") if not defined $filename;

    open FILE, "<$filename" or
        croak("Couldn't read $filename ($!)");

    return sub {
        my $line = '';
        while(1) {
            my $line = <FILE>;
            last unless defined($line);

            chomp($line);
            $line =~ s/#.*//;
            $line =~ s/^\s*//;
            $line =~ s/\s*$//;
            $line =~ s/\s\s*/ /;
            $line =~ s/\t/ /;
            return $line if $line ne '';
        }
        close FILE;
        return undef;
    }
}

##################################################
#                                                #
##################################################
sub read_info_files {
    my ($config, $dir, $func) = @_;

    $dir = File::Spec->catdir($$config{'config-dir'}, $dir);

    my %allinfo;
    foreach my $file (dir_list($dir)) {
        my $fullpath = File::Spec->catfile($dir, $file);

        trace("reading $fullpath");
        %{$allinfo{$file}} = &$func($file, $fullpath);
    }

    return %allinfo;
}

sub read_module_files {
    my ($config) = @_;

    my $mod_dir = $$config{'mods-dir'};

    my %allinfo;
    foreach my $dir (dir_list($mod_dir)) {
        my $modfile = File::Spec->catfile($mod_dir, $dir, 'modinfo.txt');

        trace("reading $modfile");
        %{$allinfo{$dir}} = get_module_info($dir, $modfile);
    }

    return %allinfo;
}

##################################################
#                                                #
##################################################
sub get_module_info {
   my ($name, $file) = @_;
   my $reader = make_reader($file);

   my %info;
   $info{'name'} = $name;
   $info{'external_libs'} = 0;
   $info{'libs'} = {};

   while($_ = &$reader()) {
       match_any_of($_, \%info, 'quoted', 'realname:note');
       match_any_of($_, \%info, 'unquoted', 'define:mp_bits');

       $info{'external_libs'} = 1 if(/^uses_external_libs/);

       read_list($_, $reader, 'arch', list_push(\@{$info{'arch'}}));
       read_list($_, $reader, 'cc', list_push(\@{$info{'cc'}}));
       read_list($_, $reader, 'os', list_push(\@{$info{'os'}}));
       read_list($_, $reader, 'add', list_push(\@{$info{'add'}}));
       read_list($_, $reader, 'replace', list_push(\@{$info{'replace'}}));
       read_list($_, $reader, 'ignore', list_push(\@{$info{'ignore'}}));

       read_list($_, $reader, 'libs',
                 sub {
                     my $line = $_[0];
                     $line =~ m/^([\w!,]*) -> ([\w,-]*)$/;
                     $info{'libs'}{$1} = $2;
                 });

       if(/^require_version /) {
           if(/^require_version (\d+)\.(\d+)\.(\d+)$/) {
               my $version = "$1.$2.$3";
               my $needed_version = 100*$1 + 10*$2 + $3;

               my $have_version =
                   100*$MAJOR_VERSION + 10*$MINOR_VERSION + $PATCH_VERSION;

               if($needed_version > $have_version) {
                   warning("Module $name needs v$version; disabling");
                   return ();
               }
           }
           else {
               croak("In module $name, bad version requirement '$_'");
           }
       }
   }

   return %info;
}

##################################################
#                                                #
##################################################
sub get_arch_info {
    my ($name,$file) = @_;
    my $reader = make_reader($file);

    my %info;
    $info{'name'} = $name;

    while($_ = &$reader()) {
        match_any_of($_, \%info, 'quoted', 'realname');
        match_any_of($_, \%info, 'unquoted', 'default_submodel');

        read_list($_, $reader, 'aliases', list_push(\@{$info{'aliases'}}));
        read_list($_, $reader, 'submodels', list_push(\@{$info{'submodels'}}));

        read_list($_, $reader, 'submodel_aliases',
                  sub {
                      my $line = $_[0];
                      $line =~ m/^(\S*) -> (\S*)$/;
                      $info{'submodel_aliases'}{$1} = $2;
                  });
    }
    return %info;
}

##################################################
#                                                #
##################################################
sub get_os_info {
    my ($name,$file) = @_;
    my $reader = make_reader($file);

    my %info;
    $info{'name'} = $name;

    while($_ = &$reader()) {
        match_any_of($_, \%info, 'quoted', 'realname:ar_command');

        match_any_of($_, \%info, 'unquoted',
                   'os_type:obj_suffix:so_suffix:static_suffix:' .
                   'install_root:header_dir:lib_dir:doc_dir:' .
                   'install_user:install_group:ar_needs_ranlib:' .
                   'install_cmd_data:install_cmd_exec');

        read_list($_, $reader, 'aliases', list_push(\@{$info{'aliases'}}));
        read_list($_, $reader, 'arch', list_push(\@{$info{'arch'}}));

        read_list($_, $reader, 'supports_shared',
                  list_push(\@{$info{'supports_shared'}}));
    }
    return %info;
}

##################################################
#                                                #
##################################################
sub get_cc_info {
    my ($name,$file) = @_;
    my $reader = make_reader($file);

    my %info;
    $info{'name'} = $name;

    while($_ = &$reader()) {
        match_any_of($_, \%info, 'quoted',
                   'realname:binary_name:' .
                   'compile_option:output_to_option:add_include_dir_option:' .
                   'add_lib_dir_option:add_lib_option:' .
                   'lib_opt_flags:check_opt_flags:' .
                   'lang_flags:warning_flags:so_obj_flags:ar_command:' .
                   'debug_flags:no_debug_flags');

        match_any_of($_, \%info, 'unquoted', 'makefile_style');

        read_list($_, $reader, 'os', list_push(\@{$info{'os'}}));
        read_list($_, $reader, 'arch', list_push(\@{$info{'arch'}}));

        sub quoted_mapping {
            my $hashref = $_[0];
            return sub {
                my $line = $_[0];
                $line =~ m/^(\S*) -> \"(.*)\"$/;
                $$hashref{$1} = $2;
            }
        }

        read_list($_, $reader, 'mach_abi_linking',
                  quoted_mapping(\%{$info{'mach_abi_linking'}}));
        read_list($_, $reader, 'so_link_flags',
                  quoted_mapping(\%{$info{'so_link_flags'}}));

        read_list($_, $reader, 'mach_opt',
                  sub {
                      my $line = $_[0];
                      $line =~ m/^(\S*) -> \"(.*)\" ?(.*)?$/;
                      $info{'mach_opt_flags'}{$1} = $2;
                      $info{'mach_opt_re'}{$1} = $3;
                  });

    }
    return %info;
}

sub guess_mods {
    my ($config) = @_;

    my $cc = $$config{'compiler'};
    my $os = $$config{'os'};
    my $arch = $$config{'arch'};
    my $submodel = $$config{'submodel'};

    my @usable_modules;

    foreach my $mod (sort keys %MODULES) {
        my %modinfo = %{ $MODULES{$mod} };

        # If it uses external libs, the user has to request it specifically
        next if($modinfo{'external_libs'});

        my @cc_list = @{ $modinfo{'cc'} };
        next if(scalar @cc_list > 0 && !in_array($cc, \@cc_list));

        my @os_list = @{ $modinfo{'os'} };
        next if(scalar @os_list > 0 && !in_array($os, \@os_list));

        my @arch_list = @{ $modinfo{'arch'} };
        next if(scalar @arch_list > 0 &&
                !in_array($arch, \@arch_list) &&
                !in_array($submodel, \@arch_list));

        push @usable_modules, $mod;
    }
    return @usable_modules;
}

##################################################
#                                                #
##################################################
sub write_pkg_config {
    my ($config) = @_;

    return if($$config{'os'} eq 'generic' or
              $$config{'os'} eq 'windows');

    $$config{'link_to'} = libs('-l', '', 'm', @{$$config{'mod_libs'}});

    process_template(
       File::Spec->catfile($$config{'config-dir'}, 'botan-config.in'),
       'botan-config', $config);
    chmod 0755, 'botan-config';

    delete $$config{'link_to'};
}

##################################################
#                                                #
##################################################
sub file_list {
    my ($put_in, $from, $to, %files) = @_;
    my $spaces = 16;

    my $list = '';

    my $len = $spaces;
    foreach (sort keys %files) {
        my $file = $_;

        if($len > 60) {
            $list .= "\\\n" . ' 'x$spaces;
            $len = $spaces;
        }

        $file =~ s/$from/$to/ if(defined($from) and defined($to));

        my $dir = $files{$_};
        $dir = $put_in if defined $put_in;

        if(defined($dir)) {
            $list .= File::Spec->catfile ($dir, $file) . ' ';
            $len += length($file) + length($dir);
        }
        else {
            $list .= $file . ' ';
            $len += length($file);
        }
    }

    return $list;
}

sub build_cmds {
    my ($config, $dir, $flags, $files) = @_;

    my $output = '';

    my $obj_suffix = $$config{'obj_suffix'};

    my %ccinfo = my_compiler($config);

    my $inc = $ccinfo{'add_include_dir_option'};
    my $from = $ccinfo{'compile_option'};
    my $to = $ccinfo{'output_to_option'};

    my $inc_dir = $$config{'build_include'};

    # Probably replace by defaults to -I -c -o
    croak('undef value found in build_cmds')
        unless defined($inc) and defined($from) and defined($to);

    my $bld_line = "\t\$(CXX) $inc$inc_dir $flags $from\$? $to\$@";

    foreach (sort keys %$files) {
        my $src_file = File::Spec->catfile($$files{$_}, $_);
        my $obj_file = File::Spec->catfile($dir, $_);

        $obj_file =~ s/\.cpp$/.$obj_suffix/;
        $obj_file =~ s/\.S$/.$obj_suffix/;

        $output .= "$obj_file: $src_file\n$bld_line\n\n";
    }
    chomp($output);
    chomp($output);
    return $output;
}

sub generate_makefile {
   my ($config) = @_;

   trace('entering');

   sub os_ar_command {
       return os_info_for(shift, 'ar_command');
   }

   sub append_if {
       my($var,$addme,$cond) = @_;

       croak('append_if: reference was undef') unless defined $var;

       if($cond and $addme ne '') {
           $$var .= ' ' unless($$var eq '' or $$var =~ / $/);
           $$var .= $addme;
       }
   }

   sub append_ifdef {
       my($var,$addme) = @_;
       append_if($var, $addme, defined($addme));
   }

   my $empty_if_nil = sub {
       my $val = $_[0];
       return $val if defined($val);
       return '';
   };

   my %ccinfo = my_compiler($config);

   my $lang_flags = '';
   append_ifdef(\$lang_flags, $ccinfo{'lang_flags'});
   append_if(\$lang_flags, "-fpermissive", $$config{'gcc_bug'});

   my $debug = $$config{'debug'};

   my $lib_opt_flags = '';
   append_ifdef(\$lib_opt_flags, $ccinfo{'lib_opt_flags'});
   append_ifdef(\$lib_opt_flags, $ccinfo{'debug_flags'}) if($debug);
   append_ifdef(\$lib_opt_flags, $ccinfo{'no_debug_flags'}) if(!$debug);

   # This is a default that works on most Unix and Unix-like systems
   my $ar_command = 'ar crs';
   my $ranlib_command = 'true'; # almost no systems need it anymore

   # See if there are any over-riding methods. We presume if CC is creating
   # the static libs, it knows how to create the index itself.

   my $os = $$config{'os'};

   if($ccinfo{'ar_command'}) {
       $ar_command = $ccinfo{'ar_command'};
   }
   elsif(os_ar_command($os))
   {
       $ar_command = os_ar_command($os);
       $ranlib_command = 'ranlib'
           if(os_info_for($os, 'ar_needs_ranlib') eq 'yes');
   }

   my $arch = $$config{'arch'};

   my $abi_opts = '';
   append_ifdef(\$abi_opts, $ccinfo{'mach_abi_linking'}{$arch});
   append_ifdef(\$abi_opts, $ccinfo{'mach_abi_linking'}{$os});
   append_ifdef(\$abi_opts, $ccinfo{'mach_abi_linking'}{'all'});
   $abi_opts = ' ' . $abi_opts if($abi_opts ne '');

   if($$config{'shared'} eq 'yes' and
      (in_array('all', $OPERATING_SYSTEM{$os}{'supports_shared'}) or
       in_array($arch, $OPERATING_SYSTEM{$os}{'supports_shared'}))) {

       $$config{'so_obj_flags'} = &$empty_if_nil($ccinfo{'so_obj_flags'});
       $$config{'so_link'} = &$empty_if_nil($ccinfo{'so_link_flags'}{$os});

       if($$config{'so_link'} eq '') {
           $$config{'so_link'} =
               &$empty_if_nil($ccinfo{'so_link_flags'}{'default'})
       }

       if($$config{'so_obj_flags'} eq '' and $$config{'so_link'} eq '') {
           $$config{'shared'} = 'no';

           warning($$config{'compiler'}, ' has no shared object flags set ',
                   "for $os; disabling shared");
       }
   }
   else {
       $$config{'shared'} = 'no';
       $$config{'so_obj_flags'} = '';
       $$config{'so_link'} = '';
   }

   add_to($config, {
       'cc'              => $ccinfo{'binary_name'} . $abi_opts,
       'lib_opt'         => $lib_opt_flags,
       'check_opt'       => &$empty_if_nil($ccinfo{'check_opt_flags'}),
       'mach_opt'        => mach_opt($config),
       'lang_flags'      => $lang_flags,
       'warn_flags'      => &$empty_if_nil($ccinfo{'warning_flags'}),

       'ar_command'      => $ar_command,
       'ranlib_command'  => $ranlib_command,
       'static_suffix'   => os_info_for($os, 'static_suffix'),
       'so_suffix'       => os_info_for($os, 'so_suffix'),
       'obj_suffix'      => os_info_for($os, 'obj_suffix'),

       'install_cmd_exec' => os_info_for($os, 'install_cmd_exec'),
       'install_cmd_data' => os_info_for($os, 'install_cmd_data'),
       'install_user' => os_info_for($os, 'install_user'),
       'install_group' => os_info_for($os, 'install_group'),
       });

   my $is_in_doc_dir =
       sub { -e File::Spec->catfile($$config{'doc-dir'}, $_[0]) };

   my $docs = file_list(undef, undef, undef,
                        map_to($$config{'doc-dir'},
                               grep { &$is_in_doc_dir($_); } @DOCS));

   $docs .= File::Spec->catfile($$config{'base-dir'}, 'readme.txt');

   my $includes = file_list(undef, undef, undef,
                            map_to($$config{'build_include_botan'},
                                   keys %{$$config{'includes'}}));

   my $lib_objs = file_list($$config{'build_lib'}, '(\.cpp$|\.S$)',
                            '.' . $$config{'obj_suffix'},
                            %{$$config{'sources'}});

   my $check_objs = file_list($$config{'build_check'}, '.cpp',
                              '.' . $$config{'obj_suffix'},
                              %{$$config{'check_src'}}),

   my $lib_build_cmds = build_cmds($config, $$config{'build_lib'},
                                   '$(LIB_FLAGS)', $$config{'sources'});

   my $check_build_cmds = build_cmds($config, $$config{'build_check'},
                                     '$(CHECK_FLAGS)', $$config{'check_src'});

   add_to($config, {
       'lib_objs' => $lib_objs,
       'check_objs' => $check_objs,
       'lib_build_cmds' => $lib_build_cmds,
       'check_build_cmds' => $check_build_cmds,

       'doc_files'       => $docs,
       'include_files'   => $includes
       });

   my $template_dir = File::Spec->catdir($$config{'config-dir'}, 'makefile');
   my $template = undef;

   my $make_style = $$config{'make_style'};

   if($make_style eq 'unix') {
       $template = File::Spec->catfile($template_dir, 'unix.in');

       $template = File::Spec->catfile($template_dir, 'unix_shr.in')
           if($$config{'shared'} eq 'yes');

       $$config{'install_cmd_exec'} =~ s/(OWNER|GROUP)/\$($1)/g;
       $$config{'install_cmd_data'} =~ s/(OWNER|GROUP)/\$($1)/g;

       add_to($config, {
           'link_to' => libs('-l', '', 'm', @{$$config{'mod_libs'}}),
       });
   }
   elsif($make_style eq 'nmake') {
       $template = File::Spec->catfile($template_dir, 'nmake.in');

       add_to($config, {
           'shared' => 'no',
           'link_to' => libs('', '.'.$$config{'static_suffix'},
                             @{$$config{'mod_libs'}}),
       });
   }

   croak("Don't know about makefile format '$make_style'")
       unless defined $template;

   trace("'$make_style' -> '$template'");

   process_template($template, 'Makefile', $config);
}

##################################################
# Configuration Guessing                         #
##################################################
sub guess_cpu_from_this
{
    my $cpuinfo = lc $_[0];
    my $cpu = '';

    $cpu = 'athlon' if($cpuinfo =~ /athlon/);
    $cpu = 'pentium4' if($cpuinfo =~ /pentium 4/);
    $cpu = 'pentium4' if($cpuinfo =~ /pentium\(r\) 4/);
    $cpu = 'pentium3' if($cpuinfo =~ /pentium iii/);
    $cpu = 'pentium2' if($cpuinfo =~ /pentium ii/);
    $cpu = 'pentium3' if($cpuinfo =~ /pentium 3/);
    $cpu = 'pentium2' if($cpuinfo =~ /pentium 2/);

    $cpu = 'core2duo' if($cpuinfo =~ /intel\(r\) core\(tm\)2/);

    $cpu = 'athlon64' if($cpuinfo =~ /athlon64/);
    $cpu = 'athlon64' if($cpuinfo =~ /athlon\(tm\) 64/);
    $cpu = 'opteron' if($cpuinfo =~ /opteron/);

    # The 32-bit SPARC stuff is impossible to match to arch type easily, and
    # anyway the uname stuff will pick up that it's a SPARC so it doesn't
    # matter. If it's an Ultra, assume a 32-bit userspace, no 64-bit code
    # possible; that's the most common setup right now anyway
    $cpu = 'sparc32-v9' if($cpuinfo =~ /ultrasparc/);

    # 64-bit PowerPC
    $cpu = 'rs64a' if($cpuinfo =~ /rs64-/);
    $cpu = 'power3' if($cpuinfo =~ /power3/);
    $cpu = 'power4' if($cpuinfo =~ /power4/);
    $cpu = 'power5' if($cpuinfo =~ /power5/);
    $cpu = 'ppc970' if($cpuinfo =~ /ppc970/);

    # Ooh, an Alpha. Try to figure out what kind
    if($cpuinfo =~ /alpha/)
    {
        $cpu = 'alpha-ev4' if($cpuinfo =~ /ev4/);
        $cpu = 'alpha-ev5' if($cpuinfo =~ /ev5/);
        $cpu = 'alpha-ev56' if($cpuinfo =~ /ev56/);
        $cpu = 'alpha-pca56' if($cpuinfo =~ /pca56/);
        $cpu = 'alpha-ev6' if($cpuinfo =~ /ev6/);
        $cpu = 'alpha-ev67' if($cpuinfo =~ /ev67/);
        $cpu = 'alpha-ev68' if($cpuinfo =~ /ev68/);
        $cpu = 'alpha-ev7' if($cpuinfo =~ /ev7/);
    }

    trace('guessing ', $cpu) if($cpu);
    return $cpu;
}

# Do some WAGing and see if we can figure out what system we are. Think about
# this as a really moronic config.guess
sub guess_triple
{
    # /bin/sh, good bet we're on something Unix-y (at least it'll have uname)
    if(-f '/bin/sh')
    {
        my $os = lc `uname -s 2>/dev/null`; chomp $os;

        # Let the crappy hacks commence!

        # Cygwin's uname -s is cygwin_<windows version>
        $os = 'cygwin' if($os =~ /^cygwin/);
        $os = os_alias($os);

        if(!defined $OPERATING_SYSTEM{$os})
        {
            warning("Unknown uname -s output: $os, falling back to 'generic'");
            $os = 'generic';
        }

        my $cpu = '';

        # If we have /proc/cpuinfo, try to get nice specific information about
        # what kind of CPU we're running on.
        my $cpuinfo = '/proc/cpuinfo';

        if(-e $cpuinfo and -r $cpuinfo)
        {
            $cpu = guess_cpu_from_this(slurp_file($cpuinfo));
        }

        # `umame -p` is sometimes something stupid like unknown, but in some
        # cases it can be more specific (useful) than `uname -m`
        if($cpu eq '') # no guess so far
        {
            my $uname_p = `uname -p 2>/dev/null`;
            chomp $uname_p;
            $cpu = guess_cpu_from_this($uname_p);

            # If guess_cpu_from_this didn't figure it out, try it plain
            if($cpu eq '') { $cpu = lc $uname_p; }

            sub known_arch {
                my ($name) = @_;

                foreach my $arch (keys %CPU) {
                    my %info = %{$CPU{$arch}};

                    return 1 if $name eq $info{'name'};
                    foreach my $submodel (@{$info{'submodels'}}) {
                        return 1 if $name eq $submodel;
                    }

                    foreach my $alias (@{$info{'aliases'}}) {
                        return 1 if $name eq $alias;
                    }

                    if(defined($info{'submodel_aliases'})) {
                        my %submodel_aliases = %{$info{'submodel_aliases'}};
                        foreach my $sm_alias (keys %submodel_aliases) {
                            return 1 if $name eq $sm_alias;
                        }
                    }
                }
                return 0;
            }

            if(!known_arch($cpu))
            {
                # Nope, couldn't figure out uname -p
                $cpu = lc `uname -m 2>/dev/null`;
                chomp $cpu;

                if(!known_arch($cpu))
                {
                    $cpu = 'generic';
                }
            }
        }

        my @CCS = ('gcc', 'icc', 'compaq', 'kai'); # Skips several, oh well...

        # First try the CC enviornmental variable, if it's set
        if(defined($ENV{CC}))
        {
            my @new_CCS = ($ENV{CC});
            foreach my $cc (@CCS) { push @new_CCS, $cc; }
            @CCS = @new_CCS;
        }

        my $cc = '';
        foreach (@CCS)
        {
            my $bin_name = $COMPILER{$_}{'binary_name'};
            $cc = $_ if(which($bin_name) ne '');
            last if($cc ne '');
        }

        if($cc eq '') {
            my $msg =
               "Can't find a usable C++ compiler, is your PATH right?\n" .
               "You might need to run with explicit compiler/system flags;\n" .
               "   run '$0 --help' for more information\n";
            croak($msg);
        }

        return "$cc-$os-$cpu";
    }
    elsif($^O eq 'MSWin32' or $^O eq 'dos')
    {
        my $os = 'windows'; # obviously

        # Suggestions on this? The Win32 'shell' env is not so hot. We could
        # try using cpuinfo, except that will crash hard on NT/Alpha (like what
        # we're doing now won't!). In my defense of choosing i686:
        #   a) There are maybe a few hundred Alpha/MIPS boxes running NT4 today
        #   b) Anyone running Windows on < Pentium Pro deserves to lose.
        my $cpu = 'i686';

        # No /bin/sh, so not cygwin. Assume VC++; again, this could be much
        # smarter
        my $cc = 'msvc';
        return "$cc-$os-$cpu";
    }
    else
    {
        croak('Autoconfiguration failed (try --help)');
    }
}
