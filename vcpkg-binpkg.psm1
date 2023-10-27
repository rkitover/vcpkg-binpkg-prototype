function check_env {
    if (-not $env:VCPKG_ROOT) {
	write-error -erroraction stop 'The VCPKG_ROOT environment variable must be set.'
    }
}

function add_zip_entry {
    param(
		[System.IO.Compression.ZipArchive]$zip,
		[System.IO.FileInfo]$file,
		[string]$entry
    )

    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
		$zip, $file, $entry,
		[System.IO.Compression.CompressionLevel]::Optimal
    ) > $null
}

function read_files {
    param([System.IO.FileInfo]$file_list)

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
	    if ($entry.count) {
		$entry
	    }
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
		write-output ($key + ': ' + $_[$key])
	    }
	}
	write-output ""
    } | set-content (join-path $env:VCPKG_ROOT installed/vcpkg/status)
}

function read_port_control_file {
    param(
	[string]$package
    )

    $entry = [ordered]@{}

    [array]$entries = read_db(get-content (join-path $env:VCPKG_ROOT ports/$package/CONTROL))

    [array]$control = foreach ($entry in $entries) {
	[ordered]@{
	    'Feature'     = if ($entry.Feature)  { $entry.Feature } else { 'core' };
	    'Description' = $entry.Description;
	    'Depends'     = $entry['Build-Depends'];
	}
    }

    return $control
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

    push-location $env:VCPKG_ROOT

    if (-not ($file_list = file_list $pkg $triplet)) {
	write-error -erroraction stop "${pkg}:$triplet is not installed"
    }

    $files = read_files $file_list

    # Make CONTROL file.

    $control_file = new-temporaryfile

    $status_entries = read_status_file | where-object {
		$_.Package -eq $pkg -and $_.Architecture -eq $triplet
    }

    &{foreach ($entry in $status_entries) {
		write-output ("Feature: " + $(if ($entry.Feature) { $entry.Feature } else { 'core' }))

		foreach ($key in 'Version', 'Port-Version', 'Depends', 'Abi', 'Description') {
			write-output ("${key}: " + $entry[$key])
		}

		write-output ''
    }} > $control_file

    $revision = ($status_entries | ?{ $_.feature -eq 'core' })[0]['Port-Version']

    $zip_file  = join-path $cwd ((split-path -leafbase $file_list) + '.zip')

    write-host -nonewline "Creating $zip_file..."

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

    $zip.Dispose()

    pop-location

    remove-item $control_file

    write-host 'done.'
}

function file_list {
    param(
	[string]$package,
	[string]$triplet
    )

    (resolve-path -relative installed/vcpkg/info/${pkg}_*${triplet}.list) -replace '\\', '/'
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

    push-location $env:VCPKG_ROOT

    if (-not ($file_list = file_list $pkg $triplet)) {
	write-error -erroraction stop "${pkg}:$triplet is not installed"
    }

    write-host -nonewline "Removing ${pkg}:$triplet..."

    foreach ($file in (read_files $file_list)) {
	remove-item $file
    }

    remove-item $file_list

## TODO: Currently missing dependencies cause vcpkg to consider the database
## corrupt.
#
#    $entries = read_status_file | where-object {
#	-not ($_['Package'] -eq $pkg -and $_['Architecture'] -eq $triplet)
#    }
#
#    write_status_file $entries

    pop-location

    write-host 'done.'
}

function InstallVcpkgPkgZip {
    param(
        [validatescript({
            if (-not ((test-path -pathtype leaf $_) -and ($_ -match '\.zip$'))) {
		throw "$_ is not a zip file"
	    }
	    return $true
        })]
        [System.IO.FileInfo]$zip_file
    )

    check_env

    [string]$zip_file = resolve-path $zip_file

    ($pkg, $version, $triplet) = ((split-path -leaf $zip_file) -replace '\.zip$','') -split '_'

    push-location $env:VCPKG_ROOT

    if (file_list $pkg $triplet) {
	RemoveVcpkgPkg "${pkg}:$triplet"
    }

    write-host -nonewline "Installing $zip_file..."

    add-type -assembly 'System.IO.Compression.FileSystem'

    [System.IO.Directory]::SetCurrentDirectory($env:VCPKG_ROOT)

    $zip = [System.IO.Compression.ZipFile]::OpenRead($zip_file);

    foreach ($entry in $zip.Entries) {
	if ($entry.FullName -eq 'CONTROL') {
	    $control_text = (new-object System.IO.StreamReader($entry.Open())).ReadToEnd()
	}
	else {
	    $dirname = split-path -parent $entry.FullName

	    if (-not (test-path $dirname)) {
			new-item -itemtype "directory" -path $dirname > $null
	    }

	    [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
		$entry,
		$entry.FullName,
		$true
	    )
	}
    }

    $zip.Dispose()

    # Update status database.

    $control_entries = read_db($control_text -split '\r?\n')
    $status_entries  = read_status_file

    foreach ($control in $control_entries) {
		$exists = $false

		$status_entry = [ordered]@{}

		$status_entry.Package = $pkg

		if ($control.Feature -eq 'core') {
			$status_entry.Version = $version
		}
		else {
			$status_entry.Feature = $control.Feature
		}

		$status_entry.Depends       = $control.Depends
		$status_entry.Architecture  = $triplet
		$status_entry['Multi-Arch'] = 'same'
		$status_entry.Description   = $control.Description
		$status_entry.Type          = 'Port'
		$status_entry.Status        = 'install ok installed'

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

    pop-location

    write-host 'done.'
}

set-alias -name vcpkg-rmpkg   -val RemoveVcpkgPkg

set-alias -name vcpkg-mkpkg   -val WriteVcpkgPkgZip

set-alias -name vcpkg-instpkg -val InstallVcpkgPkgZip

export-modulemember -alias    vcpkg-mkpkg,      vcpkg-instpkg,      vcpkg-rmpkg `
		    -function WriteVcpkgPkgZip, InstallVcpkgPkgZip, RemoveVcpkgPkg

