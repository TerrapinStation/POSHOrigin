function Invoke-POSHOriginNEW {
    <#
        .SYNOPSIS
            Invokes a POSHOrigin configuration directly by calling Invoke-DscResource.
            
            ** THIS IS AN EXPERIMENTAL CMDLET AND MAY BE SIGNIFICANTLY MODIFIED IN FUTURE VERSIONS **
        .DESCRIPTION
            Invokes a POSHOrigin configuration directly by calling Invoke-DscResource. The custom object(s) passed into this function will be
            translated into a hashtable suitable for Invoke-DscResource.
            
            ** THIS IS AN EXPERIMENTAL CMDLET AND MAY BE SIGNIFICANTLY MODIFIED IN FUTURE VERSIONS **
        .PARAMETER InputObject
            One or more custom objects containing the required options for the DSC resource to be provisioned.
        .PARAMETER WhatIf
            Only execute the TEST functionality of DSC.
            
            NO RESOURCES WILL BE MODIFIED.
        .PARAMETER Confirm
            Prompts you for confirmation before running the cmdlet.
        .PARAMETER PassThru
            Return the result of the DSC run.
        .EXAMPLE
            Compiles and invokes a POSHOrigin configuration. Infrastructure resources defined in $myConfig will be tested for compliance and as
            necessary created, deleted, or modified.
            
            Invoke-POSHOriginNEW -Resource $myConfig -Verbose
        .EXAMPLE
            Compiles and tests a POSHOrigin configuration. This will only test the DSC resources for compliance.
            NO RESOURCES WILL BE CREATED, DELETED, OR MODIFIED
            
            Invoke-POSHOrigin -Resource $myConfig -Verbose -WhatIf
        .EXAMPLE
            Pass the options from the POSHOrigin resource directly to Invoke-DscResource.
            
            $myConfig | Invoke-POSHOriginNEW -NoTranslate -Verbose
    #>
    [cmdletbinding()]
    param(
        [parameter(Mandatory,ValueFromPipeline)]
        [ValidateScript({ $_.PSObject.TypeNames[0] -eq 'POSHOrigin.Resource' })]
        [Alias('Resource')]
        [psobject[]]$InputObject,

        #[switch]$NoTranslate,
        
        [switch]$PrettyPrint,

        [switch]$WhatIf,

        [switch]$PassThru
    )

    begin {

        # Start stopwatch
        $sw = [diagnostics.stopwatch]::StartNew()

        $results = @()

        # Used to track DSC resources that have been executed.
        # We'll use this so any dependent resources will only execute
        # if all of their dependencies have.
        # NOTE
        # This doesn't validate that the dependent service is in the desired state. Only that the "Set" function was executed
        $executedResources = @()

        if ($PSBoundParameters.ContainsKey('NoTranslate')) {
            Write-Verbose -Message "NoTranslate specified. No property translation will be attempted"
        }

        function Write-ResourceStatus {
            param (
                [string]$Resource,
                [string]$Name,
                [ValidateSet('Test', 'Get', 'Set')]
                [string]$State,
                [switch]$Inner,
                [switch]$Complete,
                [string]$Message
            )
            $cmd = {
                if (-Not $PSBoundParameters.ContainsKey('Inner')) {
                    switch ($State) {
                        'Test' {
                            Write-Host -Object "Testing resource "  -ForegroundColor Cyan -NoNewLine
                        }
                        'Get' {
                            Write-Host -Object "Getting resource "  -ForegroundColor Cyan -NoNewLine
                        }
                        'Set' {
                            Write-Host -Object "Setting resource "  -ForegroundColor Cyan -NoNewLine
                        }
                    }
                    Write-Host -Object "[$Resource]" -ForegroundColor Magenta -NoNewLine
                    #Write-Host -Object "$Resource" -ForegroundColor Magenta -NoNewLine
                    #Write-Host -Object '-' -ForegroundColor Gray -NoNewLine
                    Write-Host -Object $Name -ForegroundColor Green
                } else {
                    if (-Not $PSBoundParameters.ContainsKey('Complete')) {
                        Write-Host -Object "  - $Message" -ForegroundColor Green
                    } else {

                        # Get the true/false and time result
                        $r = ($Message -split ' ')[0].Trim()
                        $time = ($message -split 'in')[1].Trim()
                        Write-Host -Object "Tested: " -ForegroundColor Cyan -NoNewline
                        if ($r -eq 'True') {
                            Write-Host -Object "[$r]" -ForegroundColor Green -NoNewline
                        } else {
                            Write-Host -Object "[$r]" -ForegroundColor Red -NoNewline
                        }
                        Write-Host -Object " in " -ForegroundColor Cyan -NoNewline
                        Write-Host -Object "$time" -ForegroundColor Green
                    }
                }
            }

            Invoke-Command -ScriptBlock $cmd
        }

        function Convert-DSCVerboseOutput([string]$line) {
            # Write line to log file
            Out-File -Encoding utf8 -Append -FilePath $outputFile -Inputobject $_

            # Try and extract the information we want from the line
            $line = $line | select-string -Pattern '^.*?:'
            $msg = $null
            if ($line) {
                $action = $type = $resName = $null
                #Write-Verbose $line

                $machine = ($line -split ']: ')[0].TrimStart(1,'[')
                $type = $resName = $null
                $message = [string]::Empty
                if ($line -match 'LCM:\s\s\[\s') {
                    $action = ($line -split '(LCM:\s\s\[)(\s)(.*?\s)(\s*.*?\s)')[3].Trim()
                    $type = ($line -split '(LCM:\s\s\[)(\s)(.*?\s)(\s*.*?\s)')[4].Trim()

                    #$action = ($line -split 'LCM:\s\s\[\s')[1].Split(' ')[0]
                    #$type = (($line -split 'LCM:\s\s\[\s')[1] -Split ']')[0].Split(' ')[2]
                    #$type = ((($line -split 'LCM:\s\s\[\s')[1] -Split ']')[0] -split '\s.*')[1]
                    if ($line -match '\[\[') {
                        $resName = ($line -split '\[\[')[1].Split(']')[0]
                    }
                }
                if ($line -match 'DirectResourceAccess\]') {
                    $message = ($line -split 'DirectResourceAccess\]')[1].Trim()
                } else {
                    $message = ($line -split 'LCM:\s\s\[\sEnd\s\s\s\sSet\s\s\s\s\s\s]')[1].Trim()
                }

                $msg = [pscustomobject]@{
                    machine = $machine
                    action = $action
                    type = $type
                    resource = $resName
                    message = $message
                }
                return $msg
                #Write-Host ($msg | ft -AutoSize | out-string)
            }
        }
        
        function Invoke-DscResourcePrettyPrint {
            [cmdletbinding()]
            param(
                [string]$ResourceName,
                
                [string]$Method,
                
                [hashtable]$params    
            )
            
            $result = $null            
            Invoke-DscResource -Method $Method @params -OutVariable result -Verbose:$VerbosePreference 4>&1 | foreach {
                $msg = Convert-DSCVerboseOutput -line $_
                if ($msg) {
                    if (($msg.message -ne [string]::Empty) -and ($msg.action -ne 'end')) {
                        Write-ResourceStatus -Resource $msg.resource -Name $ResourceName -Inner -Message $msg.message
                    }
                    if ($msg.action -eq 'end' -and $msg.type -eq 'test') {
                        Write-ResourceStatus -Resource $msg.resource -Name $ResourceName -Inner -Message $msg.message -Complete
                    }
                }
            }    
        }
    }

    process {
        # Temporarily disable the PowerShell progress bar
        $oldProgPref = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'

        foreach ($item in $InputObject) {

            $result = "" | Select Resource, InDesiredState

            # Derive the resource type and module from the resource properties
            # and try to find the DSC resource
            $module = $item.Resource.Split(':')[0]
            $resource = $item.Resource.Split(':')[1]
            $dscResource = _GetDscResource -module $module -Resource $resource

            if ($dscResource) {

                # Construct resource parameters
                if ($null -eq $item.Options.Ensure) {
                    $item.Options | Add-Member -Type NoteProperty -Name 'Ensure' -Value 'Present'
                }

                # Our params and hash to be splatted to Invoke-DscResource
                $params = @{}
                #$hash = _GetDscResourcePropertyHash -DSCResource $dscResource -Resource $item -NoTranslate ($PSBoundParameters.ContainsKey('NoTranslate'))
                $hash = $item | _ConvertToDscResourceHash

                $params = @{
                    Name = $dscResource.Name
                    ModuleName = $dscResource.ModuleName
                    Property = $hash
                }

                Write-Debug ($params.Property | Format-List -Property * | Out-String)
                
                $outputFile = 'C:\temp\runlog.log'
                if (-not (Test-Path -Path $outputFile)) {
                    New-Item -Path $outputFile -Type File -Force
                }

                if ($PSBoundParameters.ContainsKey('WhatIf')) {
                    # Just test the resource
                    Write-ResourceStatus -Resource $dscResource.Name -Name $item.Name -State Test
                    $testResult = $null                    
                    if ($PSBoundParameters.ContainsKey('PrettyPrint')) {
                        Invoke-DscResourcePrettyPrint -Method Test -params $params -OutVariable testResult
                    } else {
                        $testResult = Invoke-DscResource -Method Test @params -Verbose:$VerbosePreference -InformationAction $InformationPreference    
                    }
                    
                    if ($PSBoundParameters.ContainsKey('PassThru')) {
                        $result = "" | Select Resource, InDesiredState
                        Write-ResourceStatus -Resource $dscResource.Name -Name $item.Name -State Get

                        $getResult = $null                        
                        if ($PSBoundParameters.ContainsKey('PrettyPrint')) {
                            Invoke-DscResourcePrettyPrint -Method Get -params $params -OutVariable getResult    
                        } else {
                            $getResult = Invoke-DscResource -Method Get @params -Verbose:$VerbosePreference    
                        }
                        
                        $result.Resource = $getResult
                        $result.InDesiredState = $testResult.InDesiredState
                        $results += $result
                    }
                } else {
                    # Test if this resource has any dependencies and only execute if those have been met.
                    $continue = $true
                    $dependenciesExist = @(($item.DependsOn).Count -gt 0)
                    if ($dependenciesExist) {
                        if ($dependency -inotin $executedResources.Keys) {                            
                            $continue = $false
                        }
                    } else {
                        $continue = $true
                    }

                    # All dependencies met?
                    if ($continue) {
                        # Test and invoke the resource
                        $testResult = $null
                        Write-ResourceStatus -Resource $dscResource.Name -Name $item.Name -State Test
                        
                        If ($PSBoundParameters.ContainsKey('PrettyPrint')) {
                            Invoke-DscResourcePrettyPrint -Method Test -params $params -OutVariable testResult
                        } else {
                            $testResult = Invoke-DscResource -Method Test @params -Verbose:$VerbosePreference -InformationAction $InformationPreference    
                        }
                        
                        if (-Not $testResult.InDesiredState) {
                            Write-ResourceStatus -Resource $dscResource.Name -Name $item.Name -State Set
                            try {
                                if ($PSBoundParameters.ContainsKey('PrettyPrint')) {
                                    Invoke-DscResourcePrettyPrint -Method Set -params $params
                                } else {
                                    Invoke-DscResource -Method Set @params -Verbose:$VerbosePreference -InformationAction $InformationPreference    
                                }
                            } catch {
                                Write-Error -Message 'There was a problem setting the resource'
                                Write-Error -Message "$($_.InvocationInfo.ScriptName)($($_.InvocationInfo.ScriptLineNumber)): $($_.InvocationInfo.Line)"
                                write-Error $_
                            }
                        }
                        # Track the resource as 'executed' for dependent resources
                        $executedResources += $item.FullName
                    } else {
                        Write-Error -Message "Dependencies have not been met for resource $($item.FullName). This resource will not be invoked."
                    }

                    if ($PSBoundParameters.ContainsKey('PassThru')) {
                        Write-ResourceStatus -Resource $dscResource.Name -Name $item.Name -State Test
                        $testResult = $null
                        $testResult = Invoke-DscResource -Method Test @params -Verbose:$VerbosePreference -InformationAction $InformationPreference
                        
                        Write-ResourceStatus -Resource $dscResource.Name -Name $item.Name -State Get
                        $getResult = $null
                        $getResult = Invoke-DscResource -Method Get @params -Verbose:$VerbosePreference -InformationAction $InformationPreference

                        $result.Resource = $getResult
                        $result.InDesiredState = $testResult.InDesiredState
                        $results += $result
                    }
                }
            } else {
                Write-Error -Message "Unable to find DSC resource: $($item.Resource)"
            }
            Write-Host -Object "`n"
        }
    }

    end {
        # Reset the progress bar preference
        $global:ProgressPreference = $oldProgPref

        if ($PSBoundParameters.ContainsKey('PassThru')) {
            $results
        }

        # Stop stopwatch
        Write-Verbose -Message "Command finished in $($sw.Elapsed.TotalSeconds) seconds"
        $sw.stop()
    }
}
