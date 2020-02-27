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
	   | where-object { test-path -pathtype leaf $_ }
}

function read_status_file {
    $entry = [ordered]@{}

    [array]$entries = foreach ($line in get-content (join-path $env:VCPKG_ROOT installed/vcpkg/status)) {
	if ($line -match '^$') {
	    if ($entry.count) {
		$entry
	    }
	    $entry = [ordered]@{}
	}
	elseif ($line -match '^([^:]+): +(.*) *$') {
	    $entry[$matches[1]] = $matches[2];
	}
    }

    foreach ($entry in $entries) {
	if (-not $entry['Feature']) {
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

    [array]$entries = foreach ($line in get-content (join-path $env:VCPKG_ROOT ports/$package/CONTROL)) {
	if ($line -match '^$') {
	    if ($entry.count) {
		$entry
	    }
	    $entry = [ordered]@{}
	}
	elseif ($line -match '^([^:]+): +(.*) *$') {
	    $entry[$matches[1]] = $matches[2];
	}
    }

    # No blank line at the end of the file.
    $entries += $entry

    [array]$control = foreach ($entry in $entries) {
	[ordered]@{
	    'Feature'     = if ($entry.Feature)  { $entry.Feature } else { 'core' };
	    'Description' = $entry.Description;
	    'Depends'     = $entry['Build-Depends'];
	}
    }

    return $control
}

function read_control {
    param(
	[string]$control_text
    )

    $entry = [ordered]@{}

    foreach ($line in ($control_text -split '\r?\n')) {
	if ($line -match '^$') {
	    if ($entry.count) {
		$entry
	    }
	    $entry = [ordered]@{}
	}
	elseif ($line -match '^([^:]+): +(.*) *$') {
	    $entry[$matches[1]] = $matches[2];
	}
    }
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

    $zip_file  = join-path $cwd ((split-path -leafbase $file_list) + '.zip')

    $files = read_files $file_list

    # Make CONTROL file.

    $control_file = new-temporaryfile

    $status_entries = read_status_file | where-object {
	$_.Package -eq $pkg -and $_.Architecture -eq $triplet
    }

    foreach ($entry in $status_entries) {
	write-output ("Feature: " + $(if ($entry.Feature) { $entry.Feature } else { 'core' })) >> $control_file

	foreach ($key in 'Description', 'Depends') {
	    write-output ("${key}: " + $entry[$key]) >> $control_file
	}

	write-output '' >> $control_file
    }

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

    (resolve-path -relative installed/vcpkg/info/${pkg}*${triplet}.list) -replace '\\', '/'
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

    ($pkg, $version, $triplet) = (split-path -leafbase $zip_file) -split '_'

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

    $control_entries = read_control $control_text
    $status_entries  = read_status_file

    foreach ($control in $control_entries) {
	$exists = $false

	foreach ($status in $status_entries) {
	    if ($status.Package -eq $pkg -and $status.Architecture -eq $triplet -and $status.Feature -eq $control.Feature) {
		$exists = $true

		$status.Package = $pkg

		if ($control.Feature -eq 'core') {
		    $status.Version = $version
		}
		else {
		    $status.Feature = $control.Feature
		}

		$status.Depends       = $control.Depends
		$status.Architecture  = $triplet
		$status['Multi-Arch'] = 'same'
		$status.Description   = $control.Description
		$status.Type          = 'Port'
		$status.Status        = 'install ok installed'
	    }
	}

	if (-not $exists) {
	    $new_status_entry = [ordered]@{}


	    $new_status_entry.Package = $pkg

	    if ($control.Feature -eq 'core') {
		$new_status_entry.Version = $version
	    }
	    else {
		$new_status_entry.Feature = $control.Feature
	    }

	    $new_status_entry.Depends       = $control.Depends
	    $new_status_entry.Architecture  = $triplet
	    $new_status_entry['Multi-Arch'] = 'same'
	    $new_status_entry.Description   = $control.Description
	    $new_status_entry.Type          = 'Port'
	    $new_status_entry.Status        = 'install ok installed'

	    $status_entries += $new_status_entry
	}
    }

    write_status_file $status_entries

    pop-location

    write-host 'done.'
}

set-alias -name vcpkg-rmpkg   -val RemoveVcpkgPkg

set-alias -name vcpkg-mkpkg   -val WriteVcpkgPkgZip

set-alias -name vcpkg-instpkg -val InstallVcpkgPkgZip

export-modulemember -alias    vcpkg-mkpkg,      vcpkg-instpkg,      vcpkg-rmpkg `
		    -function WriteVcpkgPkgZip, InstallVcpkgPkgZip, RemoveVcpkgPkg

