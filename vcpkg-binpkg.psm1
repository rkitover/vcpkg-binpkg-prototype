add-type -assembly 'System.IO.Compression.FileSystem'
        
function check_env {
    if (-not $env:VCPKG_ROOT) {
        write-error -ea stop 'The VCPKG_ROOT environment variable must be set.'
    }

    $global:vcpkg = join-path $env:VCPKG_ROOT $(
        if ($iswindows) { 'vcpkg.exe' } else { 'vcpkg' }
    )
}

function add_zip_entry([io.compression.ziparchive]$zip, [io.fileinfo]$file, $entry) {
    [io.compression.zipfileextensions]::createentryfromfile(
        $zip, $file, $entry,
        [io.compression.compressionlevel]::optimal
    ) > $null
}

function read_files([io.fileinfo]$file_list) {

    return get-content $file_list `
       | %{ "./installed/$_" } `
       | ?{ test-path -pathtype leaf $_ -ea ignore }
}

function read_db {
    param(
        [array]$db_lines
    )

    $entry = [ordered]@{}

    foreach ($line in $db_lines) {
        if ($line -match '^$') {
            if ($entry.count) { $entry }
            $entry = [ordered]@{}
        }
        elseif ($line -match '^([^:]+): +(.+) *$') {
            $entry[$matches[1]] = $matches[2];
        }
    }

    # There may not be a blank line at the end of the file.
    if ($entry.count) { $entry }
}

function read_status_file {
    [array]$entries = read_db(get-content (join-path $env:VCPKG_ROOT installed/vcpkg/status) -ea ignore)

    foreach ($entry in $entries) {
        if (-not $entry.contains('Feature')) {
            $entry['Feature'] = 'core'
        }
    }

    return $entries
}

function write_status_file {
    param(
        [array]$entries
    )

    $entries | %{
        foreach ($key in $_.keys) {
            if (-not ($key -eq 'Feature' -and $_[$key] -eq 'core')) {
                "${key}: " + $_[$key]
            }
        }
        ''
    } | set-content (join-path $env:VCPKG_ROOT installed/vcpkg/status)
}

function read_port_control_file([string]$package) {
    $entry = [ordered]@{}

    [array]$entries = read_db(get-content (join-path $env:VCPKG_ROOT ports/$package/CONTROL))

    [array]$control = foreach ($entry in $entries) {
        [ordered]@{
            'Feature'     = if ($entry.Feature)  { $entry.Feature } else { 'core' };
            'Description' = $entry.Description;
            'Depends'     = $entry['Build-Depends'];
        }
    }

    $control
}

function WriteVcpkgPkgZip {
    param(
        [validatescript({
            if ($_ -notmatch ':') { throw 'Package must be of the form <pkg>:<triplet>' }
            return $true
        })]
        [string]$qualified_package
    )

    check_env

    ($pkg, $triplet) = $qualified_package -split ':'

    $cwd = $PWD

    pushd $env:VCPKG_ROOT

    if (-not ($file_list = file_list $pkg $triplet)) {
        write-error -ea stop "${pkg}:$triplet is not installed"
    }

    $files = read_files $file_list

    # Make CONTROL file.
    $control_file = new-temporaryfile

    $status_entries = read_status_file | where-object {
        $_.Package -eq $pkg -and $_.Architecture -eq $triplet
    }

    &{foreach ($entry in $status_entries) {
        "Feature: " + $(if ($entry.Feature) { $entry.Feature } else { 'core' })

        foreach ($key in 'Version', 'Depends', 'Abi', 'Description') {
            "${key}: " + $entry[$key]
        }
        
        if ($entry.contains('Port-Version')) {
            "Port-Version: " + $entry['Port-Version']
        }

        ''
    }} > $control_file
    
    $zip_file = (split-path -leaf $file_list) -replace '\.list$',''
    
    if ($revision = ($status_entries | ?{ $_.feature -eq 'core' })['Port-Version']) {
        $zip_file = $zip_file -replace '^([^_]+)_([^_]+)_',('${1}_$2' + "-r${revision}_")
    }
    
    $zip_file  = join-path $cwd ($zip_file + '.zip')

    "Creating $zip_file..."

    add-type -assembly 'System.IO.Compression.FileSystem'

    [System.IO.Directory]::SetCurrentDirectory($env:VCPKG_ROOT)

    if (test-path $zip_file) { remove-item $zip_file }

    $zip = [System.IO.Compression.ZipFile]::Open(
        $zip_file,
        [System.IO.Compression.ZipArchiveMode]::Create
    )

    add_zip_entry $zip $control_file 'CONTROL'

    add_zip_entry $zip $file_list $file_list

    foreach ($file in $files) {
        add_zip_entry $zip $file $file
    }

    $zip.dispose()

    popd

    remove-item $control_file

    'done.'
}

function file_list([string]$package, [string]$triplet) {
    (resolve-path -relative `
        installed/vcpkg/info/${pkg}_*${triplet}.list -ea ignore `
    ) -replace '\\', '/'
}

function RemoveVcpkgPkg {
    param(
        [validatescript({
            if ($_ -notmatch ':') { throw 'Package must be of the form <pkg>:<triplet>' }
            return $true
        })]
        [string]$qualified_package
    )

    check_env

    ($pkg, $triplet) = $qualified_package -split ':'

    pushd $env:VCPKG_ROOT

    if (-not ($file_list = file_list $pkg $triplet)) {
        write-error -ea stop "${pkg}:$triplet is not installed"
    }

    "Removing ${pkg}:$triplet..."

    foreach ($file in (read_files $file_list)) {
        ri $file
    }

    ri $file_list

## TODO: Currently missing dependencies cause vcpkg to consider the database
## corrupt.
#
#    $entries = read_status_file | where-object {
#    -not ($_['Package'] -eq $pkg -and $_['Architecture'] -eq $triplet)
#    }
#
#    write_status_file $entries

    popd

    'done.'
}

function read_control($zip) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zip);
    $zip.entries | ?{ $_.fullname -eq 'CONTROL' } | %{
        $control_text = (new-object System.IO.StreamReader($_.Open())).ReadToEnd()
    }
    $zip.dispose()
    read_db($control_text -split '\r?\n')
}

function order_zips_by_depends {
    $zips = [ordered]@{}

    foreach ($pkg in $input) {
        $control = read_control $pkg | ?{ $_.feature -eq 'core' }
        (split-path -leaf $pkg) -match '^[^_]+_[^_]+_(.+)\.zip$' > $null
        $triplet = $matches[1]
        $zips[$pkg] = ($control.depends -split ', ') | ? length | %{ if (-not ($_ -match ':')) { "${_}:$triplet" } else { $_ } }
    }
    
    $ordered = [ordered]@{}

    while ($zips.count) {
        $pkg = $zips.getenumerator() | select -first 1 | % key
        
        $resolve = {
            param($pkg)
            
            (split-path -leaf $pkg) -match '^([^_]+)' > $null
            $pkg_name = $matches[1]
            
            $zips[$pkg] | ?{ $_ -notmatch "^${pkg_name}(:|`$)" } | %{
                $_ -match '^([^:]+):(.*)' > $null
                $dep_name,$triplet = $matches[1,2]
            
                @($zips.keys) | ?{
                    (split-path -leaf $_) -match "^${dep_name}_[^_]+_${triplet}\.zip" `
                    -and -not $ordered.contains($_)
                }
            } | %{ &$resolve $_ }
            
            $ordered[$pkg] = $true
            $zips.remove($pkg)
        }
        
        &$resolve $pkg
    }
    
    $ordered.keys
}

function InstallVcpkgPkgZip($zips) {
    check_env
    
# Relaunch as an elevated process for default VS vcpkg.
    if ((convert-path $env:VCPKG_ROOT) -match 'C:\\Program Files\\Microsoft Visual Studio\\') {
        if (-not ([security.principal.windowsprincipal] [security.principal.windowsidentity]::getcurrent() `
            ).isinrole([security.principal.windowsbuiltInrole]::administrator) `
        ) {
            'Elevation is required for writing to the default VS vcpkg, please confirm the following UAC prompt...'
            $pwsh = [system.diagnostics.process]::getcurrentprocess().mainmodule.filename
            start-process -wait -verb runas `
                $pwsh '-noprofile', '-executionpolicy', 'bypass', '-command', `
                    "sl '$pwd'; import-module '$pscommandpath'; `$env:VCPKG_ROOT = '$env:VCPKG_ROOT'; vcpkg-instpkg $zips"
            exit
        }
    }

    $zips = if (test-path -pathtype leaf $zips) { (resolve-path $zips).path } `
            else { gci $zips -filter '*.zip' | % fullname | order_zips_by_depends }
    
    if (-not $zips) {
        write-error -ea stop 'No packages to install'
    }
    
    foreach ($zip_file in $zips) {
        ($pkg, $version, $triplet) = ((split-path -leaf $zip_file) -replace '\.zip$','') -split '_'

        # Parse revision (Port-Version)
        $revision = $null
        if ($version -match '(.*)-r(\d+)$') {
            $version,$revision = $matches[1,2]
        }

        $status_entries  = read_status_file
        $control_entries = read_control $zip_file

        # Install build deps

        $deps = $control_entries | ?{ $_.feature -eq 'core' } | %{ $_.depends -split ', ' } | ?{ $_ -match '^vcpkg-' }

        $host_triplet = if ($iswindows) { 'x64-windows' }
                        elseif ($islinux) { 'x64-linux' }
                        elseif ($ismacos) { 'x64-osx' }
                        else { $triplet -replace '(-static|-dynamic|-release|-md)','' }

        
        foreach ($build_dep in $deps) {
            $build_dep -match '^([^:]+):?(.*)' > $null
            $build_dep,$build_dep_triplet = $matches[1,2]

            if (-not $build_dep_triplet) { $build_dep_triplet = $host_triplet }

            if (-not ($status_entries | ?{ $_.package -eq $build_dep -and $_.architecture -eq $build_dep_triplet })) {
                "Installing build dependency ${build_dep}:$build_dep_triplet for $zip_file..."
                &$vcpkg install "${build_dep}:$build_dep_triplet"
                # status db is only fully written on next operation, so do a dummy operation
                &$vcpkg install nonexistent *> $null
                # update status db after install
                $status_entries  = read_status_file
            }
        }

        pushd $env:VCPKG_ROOT

        if (file_list $pkg $triplet) {
            RemoveVcpkgPkg "${pkg}:$triplet"
        }

        "Installing $zip_file..."

        [System.IO.Directory]::SetCurrentDirectory($env:VCPKG_ROOT)

        $zip = [System.IO.Compression.ZipFile]::OpenRead($zip_file);

        foreach ($entry in $zip.entries) {
            if ($entry.fullname -ne 'CONTROL') {
                $dirname = split-path -parent $entry.fullname

                if (-not (test-path $dirname)) {
                    ni -it dir $dirname > $null
                }

                [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
                    $entry,
                    $entry.FullName,
                    $true
                )
            }
        }

        $zip.dispose()

        # Update status database.

        foreach ($control in $control_entries) {
            $exists = $false

            $status_entry = [ordered]@{}

            $status_entry.Package = $pkg

            if ($control.Feature -eq 'core') {
                $status_entry.Version = $version

                if ($revision) {
                    $status_entry['Port-Version'] = $revision
                }
            }
            else {
                $status_entry.Feature = $control.Feature
            }

            $status_entry.Depends         = $control.Depends
            $status_entry.Architecture    = $triplet
            $status_entry['Multi-Arch']   = 'same'
            $status_entry.Description     = $control.Description
            $status_entry.Type            = 'Port'
            $status_entry.Status          = 'install ok installed'

            $status_entries = &{
                foreach ($status in $status_entries) {
                    if ($status.Package -eq $pkg -and $status.Architecture -eq $triplet -and $status.Feature -eq $control.Feature) {
                        $exists = $true

                        @($status.keys) | %{
                            if ($status_entry.contains($_)) {
                                $status[$_] = $status_entry[$_]
                            }
                        }
                    }

                    $status
                }

                if (-not $exists) {
                    $status_entry
                }
            }

            write_status_file $status_entries
        }

        popd

        'done.'
    }
}

set-alias -name vcpkg-rmpkg   -val RemoveVcpkgPkg

set-alias -name vcpkg-mkpkg   -val WriteVcpkgPkgZip

set-alias -name vcpkg-instpkg -val InstallVcpkgPkgZip

export-modulemember -alias    vcpkg-mkpkg,      vcpkg-instpkg,      vcpkg-rmpkg `
                    -function WriteVcpkgPkgZip, InstallVcpkgPkgZip, RemoveVcpkgPkg

