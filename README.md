<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Experimental Binary Package Support for vcpkg](#experimental-binary-package-support-for-vcpkg)
  - [Installation (PowerShell)](#installation-powershell)
  - [Installation (cmd.exe)](#installation-cmdexe)
  - [Installation (Linux or MacOS)](#installation-linux-or-macos)
  - [USAGE](#usage)
    - [`vcpkg-mkpkg <pkg>:<triplet>`](#vcpkg-mkpkg-pkgtriplet)
    - [`vcpkg-instpkg [<package.zip>|<directory>]`](#vcpkg-instpkg-packagezipdirectory)
    - [`vcpkg-listmissing <directory>`](#vcpkg-listmissing-directory)
    - [`vcpkg-pruneincomplete [<directory>]`](#vcpkg-pruneincomplete-directory)
    - [`vcpkg-listdeps <pkg>:<triplet> [<pkg>:<triplet> ...]`](#vcpkg-listdeps-pkgtriplet-pkgtriplet-)
    - [`vcpkg-listhostdeps <pkg>:<triplet> [<pkg>:<triplet> ...]`](#vcpkg-listhostdeps-pkgtriplet-pkgtriplet-)
    - [`vcpkg-rmpkg <pkg>:<triplet>`](#vcpkg-rmpkg-pkgtriplet)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Experimental Binary Package Support for vcpkg

### Installation (PowerShell)

```powershell
mkdir ~/source/repos
cd ~/source/repos
git clone git@github.com:rkitover/vcpkg-binpkg-prototype
cd
echo "`r`nImport-Module ~/source/repos/vcpkg-binpkg-prototype/vcpkg-binpkg.psm1" >> $profile
```

then launch a new shell. You will have the commands as aliases (see
[USAGE](#usage).)

### Installation (cmd.exe)

```batchfile
mkdir ~/source/repos
cd ~/source/repos
git clone git@github.com:rkitover/vcpkg-binpkg-prototype
```

Add the directory `~/source/repos/vcpkg-binpkg-prototype/bin` to your user
`PATH` for the `.bat` command wrappers.

### Installation (Linux or MacOS)

[Install](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7)
`powershell-preview` or `powershell`.

```bash
mkdir ~/source/repos
cd ~/source/repos
git clone git@github.com:rkitover/vcpkg-binpkg-prototype
```

add `~/source/repos/vcpkg-binpkg-prototype/bin` to your `PATH` in your
`~/.bashrc` for the shell script wrappers.

### USAGE

You must set the environment variable `VCPKG_ROOT` to the path to your vcpkg
installation.

#### `vcpkg-mkpkg <pkg>:<triplet>`

Given an installed package qualified with its triplet, this command will create
a `.zip` binary package in the current directory that can be installed in any
vcpkg installation.

#### `vcpkg-instpkg [<package.zip>|<directory>]`

Installs a package made with `vcpkg-mkpkg` into the vcpkg installation pointed
to by the environment variable `VCPKG_ROOT`. If the package or another version
is already installed for the package triplet, it is removed first.

Build dependencies are automatically installed in new vcpkg clones.

You can also pass a directory path containing packages and they will be
installed in dependency order.

#### `vcpkg-listmissing <directory>`

Lists missing dependencies in the package set in the given directory. This is
normal for e.g. host build dependencies such as `vcpkg-cmake` for a non-host
triplet such as `-static`.

#### `vcpkg-pruneincomplete [<directory>]`

Prints packages in the given directory (default: current directory) whose
dependencies cannot be fully satisfied. A dependency is satisfied if it is
either present as a `.zip` in the directory or already installed in vcpkg.

Cascades: if removing a package from the list causes another package's
dependencies to become incomplete, that package is listed as well.

This is useful to ensure that only complete dependency sets are installed, since
vcpkg considers the package database corrupt if any dependency in the graph is
missing.

#### `vcpkg-listdeps <pkg>:<triplet> [<pkg>:<triplet> ...]`

Lists target (non-host) core and feature dependencies of one or more installed
packages, one per line, each qualified as `<pkg>:<triplet>`. Multiple packages
may be passed as separate arguments or as a single comma- and/or space-separated
string; the combined dependency set is deduplicated. Bare dependencies inherit
the parent package's triplet, feature qualifiers (e.g. `[ssl]`) are stripped,
self-references between features of the same port are omitted, and host build
tools (`vcpkg-*`) are excluded — use `vcpkg-listhostdeps` for those.

#### `vcpkg-listhostdeps <pkg>:<triplet> [<pkg>:<triplet> ...]`

Like `vcpkg-listdeps`, but lists only the host build-tool dependencies (the
`vcpkg-*` packages that run on the host triplet, e.g. `x64-windows` when
cross-compiling to `arm64-windows-static`). Output is unqualified by triplet,
since all entries belong to the host tool architecture.

#### `vcpkg-rmpkg <pkg>:<triplet>`

Removes the files for an installed vcpkg package, but **NOT** the status
database entries. You will most likely not need this command.
