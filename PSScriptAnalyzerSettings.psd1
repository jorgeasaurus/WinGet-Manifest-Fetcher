@{
    # Use Severity when you want to limit the generated diagnostic records to a
    # subset of: Error, Warning and Information.
    # Uncomment the following line if you only want Errors and Warnings but
    # not Information diagnostic records.
    Severity = @('Error','Warning')

    # Use IncludeRules when you want to run only a subset of the default rule set.
    #IncludeRules = @('PSAvoidDefaultValueSwitchParameter',
    #                 'PSMissingModuleManifestField',
    #                 'PSReservedCmdletChar',
    #                 'PSReservedParams',
    #                 'PSShouldProcess',
    #                 'PSUseApprovedVerbs',
    #                 'PSUseDeclaredVarsMoreThanAssignments')

    # Use ExcludeRules when you want to run most of the default set of rules except
    # for a few rules you wish to "exclude".  Note: if a rule is in both IncludeRules
    # and ExcludeRules, the rule will be excluded.
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingConvertToSecureStringWithPlainText'  # Required for GitHub token authentication
    )

    # You can use the following entry to supply parameters to rules that take parameters.
    # For instance, the PSAvoidUsingCmdletAliases rule takes a whitelist for aliases you
    # want to allow.
    Rules = @{
        # Do not flag 'cd' alias.
        PSAvoidUsingCmdletAliases = @{
            Whitelist = @('cd')
        }

        # Check if your script uses cmdlets that are compatible with PowerShell Core,
        # version 6.0.0-alpha, on Linux.
        PSUseCompatibleCmdlets = @{
            Compatibility = @(
                'desktop-5.1.14393.206-windows',
                'core-7.0.0-windows',
                'core-7.0.0-linux',
                'core-7.0.0-macos'
            )
        }
    }
}