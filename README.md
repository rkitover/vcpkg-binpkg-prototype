<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Experimental Binary Package Support for vcpkg](#experimental-binary-package-support-for-vcpkg)
  - [Installation (PowerShell)](#installation-powershell)
  - [Installation (cmd.exe)](#installation-cmdexe)
  - [Installation (Linux or MacOS)](#installation-linux-or-macos)
  - [USAGE](#usage)
    - [`vcpkg-mkpkg <pkg>:<triplet>`](#vcpkg-mkpkg-pkgtriplet)
    - [`vcpkg-instpkg <package.zip>`](#vcpkg-instpkg-packagezip)
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

#### `vcpkg-rmpkg <pkg>:<triplet>`

Removes the files for an installed vcpkg package, but **NOT** the status
database entries. You will most likely not need this command.
