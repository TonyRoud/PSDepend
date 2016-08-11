<#
    .SYNOPSIS
        EXPERIMENTAL: Installs a module from a PowerShell repository like the PowerShell Gallery using nuget.exe

    .DESCRIPTION
        EXPERIMENTAL: Installs a module from a PowerShell repository like the PowerShell Gallery using nuget.exe

        Note: If we find an existing module that doesn't meet the specified criteria in the Target, we remove it.

        Relevant Dependency metadata:
            Name: The name for this module
            Version: Used to identify existing installs meeting this criteria, and as RequiredVersion for installation.  Defaults to 'latest'
            Source: Source Uri for Nuget.  Defaults to https://www.powershellgallery.com/api/v2/
            Target: Required path to save this module.  No Default
                Example: To install PSDeploy to C:\temp\PSDeploy, I would specify C:\temp
            AddToPath: Add the Target to ENV:PSModulePath

    .PARAMETER Force
        If specified and Target is specified, create folders to Target if needed

    .PARAMETER Import
        If specified, import the module in the global scope

    .EXAMPLE

        @{
            PSDeploy = @{
                DependencyType = 'PSGalleryNuget'
                Target = 'C:\Temp'
                Version = '0.1.19'
            }
        }

        # Install PSDeploy via nuget PSGallery feed, to C:\temp, at version 0.1.19

    .EXAMPLE

        @{
            PSDeploy = @{
                DependencyType = 'PSGalleryNuget'
                Source = 'https://nuget.int.feed/'
                Target = 'C:\Temp'
            }
        }

        # Install the latest version of PSDeploy on an internal nuget feed, to C:\temp, 

#>
[cmdletbinding()]
param(
    [PSTypeName('PSDepend.Dependency')]
    [psobject[]]$Dependency,

    [switch]$Force,

    [switch]$Import
)

# Extract data from Dependency
    $DependencyName = $Dependency.DependencyName
    $Name = $Dependency.Name
    if(-not $Name)
    {
        $Name = $DependencyName
    }

    $Version = $Dependency.Version
    if(-not $Version)
    {
        $Version = 'latest'
    }

    $Source = $Dependency.Source
    if(-not $Dependency.Source)
    {
        $Source = 'https://www.powershellgallery.com/api/v2/'
    }

    # We use target as a proxy for Scope
    if(-not $Dependency.Target)
    {
        Write-Error "PSGalleryNuget requires a Dependency Target. Skipping [$DependencyName]"
        return
    }

if(-not (Get-Command Nuget.exe -ErrorAction SilentlyContinue))
{
    Write-Error "PSGalleryNuget requires Nuget.exe.  Ensure this is in your path, or explicitly specified in $ModuleRoot\PSDepend.NugetPath.  Skipping [$DependencyName]"
}

Write-Verbose -Message "Getting dependency [$name] from Nuget source [$Source]"

# This code works for both install and save scenarios.
$ModulePath =  Join-Path $Target $Name

if(Test-Path $ModulePath)
{
    $Manifest = Join-Path $ModulePath "$Name.psd1"
    if(-not (Test-Path $Manifest))
    {
        # For now, skip if we don't find a psd1
        Write-Error "Could not find manifest [$Manifest] for dependency [$Name]"
        return
    }

    Write-Verbose "Found existing module [$Name]"

    # Thanks to Brandon Padgett!
    $ManifestData = Import-LocalizedData -BaseDirectory $ModulePath -FileName "$Name.psd1"
    $ExistingVersion = $ManifestData.ModuleVersion
    $GalleryVersion = ( Find-NugetPackage -Name $Name -PackageSourceUrl $Source -IsLatest ).Version
    
    # Version string, and equal to current
    if( $Version -and $Version -ne 'latest' -and $Version -eq $ExistingVersion)
    {
        Write-Verbose "You have the requested version [$Version] of [$Name]"
        return $null
    }
    
    # latest, and we have latest
    if( $Version -and
        ($Version -eq 'latest' -or $Version -like '') -and
        $GalleryVersion -le $ExistingVersion
    )
    {
        Write-Verbose "You have the latest version of [$Name], with installed version [$ExistingVersion] and PSGallery version [$GalleryVersion]"
        return $null
    }

    Write-Verbose "Removing existing [$ModulePath]`nContinuing to install [$Name]: Requested version [$version], existing version [$ExistingVersion], PSGallery version [$GalleryVersion]"
    Remove-Item $ModulePath -Force -Recurse 
}

if(($TargetExists = Test-Path $Target -PathType Container) -or $Force)
{
    Write-Verbose "Saving [$Name] with path [$Target]"
    $NugetParams = '-Source', $Source, '-ExcludeVersion', '-NonInteractive', '-OutputDirectory', $Target
    if($Force)
    {
        Write-Verbose "Force creating directory path to [$Target]"
        $Null = New-Item -ItemType Directory -Path $Target -Force -ErrorAction SilentlyContinue
    }
    if($Version -and $Version -notlike 'latest')
    {
        $NugetParams += '-version', $Version
    }
    nuget.exe install $Name @NugetParams

    if($Dependency.AddToPath)
    {
        Write-Verbose "Setting PSModulePath to`n$($env:PSModulePath, $Scope -join ';' | Out-String)"
        $env:PSModulePath = $env:PSModulePath, $Target -join ';'
    }
}
else
{
    Write-Error "Target [$Target] exists must be true, and is [$TargetExists]. Alternatively, specify -Force to create the Target"
}

if($Import)
{
    Write-Verbose "Importing [$ModulePath]"
    Import-Module $ModulePath -Scope Global -Force 
}