################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

Function Split-FileToStream {
    <#
        .SYNOPSIS
        Loads a file into memory and splits it into mulitple memory streams. Can be used with a delimiter.
        The default split size is the number of logical CPUs.

        .EXAMPLE
        Split-FileToStream 'C:\path\to\file.txt'
        
        .EXAMPLE
        Split-FileToStream -Path 'C:\path\to\file.idx' -Delimiter 'somechars'
    #>

    [CmdletBinding()]
    [OutputType([PsObject])]
    Param(
        # Path to file to split
        [Parameter(Mandatory=$true,
                   Position=1,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [Alias('FullName')]
        [string]$Path,

        # The delimiter on which to split the file. Default is [System.Environment]::NewLine.
        [Parameter(Mandatory=$false,
                   Position=2,
                   ValueFromPipelineByPropertyName=$true)]
        [string]$Delimiter = [System.Environment]::NewLine,

        # Buffer size for the stream reader and writers. Default is 4KB.
        [Parameter(Mandatory=$false)]
        $BufferSize = 4KB,

        # Maximum number of resulting memory streams. Default is number of Logical Processors.
        [Parameter(Mandatory=$false)]
        $SplitNumber,

        # Encoding of the input stream / file. Default is UTF8.
        [Parameter(Mandatory=$false)]
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )

    Begin {
        if (!$SplitNumber) {
            $SplitNumber = Get-WmiObject Win32_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors `
                | select -ExpandProperty Sum
        }
    }

    Process {

        $stream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read,
            $BufferSize,
            [System.IO.FileOptions]::SequentialScan
        )

        [long]$splitSize = $stream.Length / $SplitNumber

        ################################################################################
        # Get rid of the BOM if there is one

        if ($Encoding.GetPreamble()) {
            $bomLen = $Encoding.GetPreamble().Length
            $bom = New-Object byte[] $bomLen
            $stream.Read($bom, 0, $bomLen) | Out-Null
            if (Compare-Object $bom $Encoding.GetPreamble()) {
                $stream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
            } else {
                Write-Warning "BOM found ($($bomLen) bytes). It will be ignored."
            }
        }

        ################################################################################

        $buf = New-Object byte[] $BufferSize
        $mem = New-Object System.IO.MemoryStream

        $splitPointer = $splitSize
        $start = $stream.Position

        while (($lt = $stream.Read($buf, 0, $buf.Length)) -gt 0) {

            if ($stream.Position -ge $splitPointer -and
                ($stream.Position -eq $stream.Length -or
                ($lastDelim = $Encoding.GetString($buf[0..($lt-1)]).LastIndexOf($Delimiter)) -ne -1)) {

                if ($stream.Position -eq $stream.Length) {
                    $endPosition = $lt
                    $end = $stream.Position
                } else {
                    $endPosition = $Encoding.GetBytes(
                        $Encoding.GetString($buf).Substring(0, $lastDelim + $Delimiter.Length)
                    ).Length

                    # Grab the carriage return and/or new line if there is one
                    if ($Encoding.GetString($buf[$endPosition]) -eq "`r") {
                        $endPosition ++
                    }
                    if ($Encoding.GetString($buf[$endPosition]) -eq "`n") {
                        $endPosition ++
                    }

                    $end = $stream.Position - $BufferSize + $endPosition
                }

                $mem.Write($buf, 0, $endPosition)
                $mem.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null

                [pscustomobject]@{
                    Stream = $mem
                    Start  = $start
                    End    = $end
                } | Add-Member -MemberType ScriptProperty `
                               -Name Length `
                               -Value { $this.Stream.Length } `
                               -PassThru `
                    | Write-Output

                if ($stream.Position -ne $stream.Length) {
                    $mem = New-Object System.IO.MemoryStream
                    $mem.Write($buf, $endPosition, $lt - $endPosition)

                    $splitPointer += $splitSize
                    if ($splitPointer -gt $stream.Length) {
                        $splitPointer = $stream.Length
                    }

                    $start = $end
                }

            } else {
                $mem.Write($buf, 0, $lt)
            }

        }

    }

    End {
        if ($stream) {
            Write-Verbose "Closing stream."
            $stream.Close()
        }
    }

}

Export-ModuleMember -Function 'Split-FileToStream'
