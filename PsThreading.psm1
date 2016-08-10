################################################################################
# Author     : Antony Onipko
# Copyright  : (c) 2016 Antony Onipko. All rights reserved.
################################################################################
# This work is licensed under the
# Creative Commons Attribution-ShareAlike 4.0 International License.
# To view a copy of this license, visit
# https://creativecommons.org/licenses/by-sa/4.0/
################################################################################

Get-ChildItem -Path $psScriptRoot `
    | ? { $_ -match '^Func_.+$' } `
    | % {
        . (Join-Path -Path $psScriptRoot -ChildPath $_)
    }
