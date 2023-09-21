#region function definitions
function New-MemberObject {
    param (
        [Parameter(Mandatory = $true)]
        [string]$MemberID,

        [Parameter(Mandatory = $true)]
        [string]$ParentStructure,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    $PropertiesHT = @{
        MemberID = $MemberID
        ParentStructure = $ParentStructure
        Type = $Type
    }

    $CustomObject = New-Object -TypeName PSObject -Property $PropertiesHT
    # Write-Log -LogLevel DEBUG -Message "Created object: | $MemberID | $ParentStructure | $Type |"
    return $CustomObject
}

function Get-MyGroupMembers{
    <#
    .SYNOPSIS
        Get-MyGroupMembers retrieves members from a specified RoleGroup or SecurityGroup.
        Get-MyGroupMembers [-SkipGroups <string[]>] -GroupName <string> -GroupType <string>

    .DESCRIPTION
        This function retrieves members from a specified group, allowing you to filter by group type.
        
    .PARAMETER SkipGroups
            Specifies an optional array of group names to skip during member retrieval.
            This parameter is required to avoid double-processing of nested groups that might contain top-level groups.
            Let's take example the following structure:
            - TopLevelGroup
            --- GroupA
            --- GroupB
            ------ GroupX
            ------ GroupY
            --------- Group1   
            --------- Group2
            --------- GroupB <<< When we get here, GroupB is already processed so the 2nd processing should be skipped

        .PARAMETER GroupName
            Specifies the name of the target group from which members will be retrieved. This parameter is mandatory.

    .EXAMPLE
        Example 1:
        Get-MyGroupMembers -GroupName "MyGroup" -SkipGroups "MyGroup"
        
        This command retrieves members from the "MyGroup" RoleGroup. Also, it will skip MyGroup if MyGroup is found in any sub-groups.
    #>

    
    param (
       [Parameter(Mandatory = $false)]
       [string[]] $SkipGroups = @(),

       [Parameter(Mandatory = $true)]
       [string] $GroupName
   )
   
   $Members = @()
   Write-Log -LogLevel DEBUG -Message "Get-MyGroupMembers -GroupName $GroupName"

   $GroupMembers = Get-AdGroup -Filter "Name -eq '$($GroupName)'" -Server $GC -Properties Members | Select-Object -ExpandProperty Members
   if($GroupMembers){
       foreach($GroupMember in $GroupMembers){
           $ADObject = Get-ADObject $GroupMember -Server $GC
           $Members += New-MemberObject -memberID $ADObject.Name -parentStructure $GroupName -type $ADObject.ObjectClass

           if(($ADObject.ObjectClass -eq 'group') -and (!$SkipGroups.contains($ADObject.Name))){
               $SkipGroups += $ADObject.Name 
               $Members += Get-myGroupMembers -GroupName $ADObject.Name -SkipGroups $SkipGroups
           }elseif($SkipGroups.contains($ADObject.Name)){
               Write-Debug "Calling function for $($ADObject.Name) of type $($ADObject.ObjectClass) --- skipping (already processed)"
           }
       }
   }
   return $Members
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Output", "Warning", "Debug", "Error")]
        [string] $LogLevel,

        [Parameter(Mandatory = $true)]
        [string] $Message,

        [string] $LogFile = $null,

        [switch] $SkipScreenOutput
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $processId = $PID
    $logEntry = "$timestamp [$processId] [$LogLevel] $Message"

    if ($LogFile -and -not $SkipScreenOutput) {
        $logEntry | Out-File -Append -FilePath $LogFile
    }

    if(!$SkipScreenOutput){
        switch ($LogLevel) {
            "Output" {
                Write-Output $logEntry
            }
            "Warning" {
                Write-Warning $logEntry
            }
            "Debug" {
                Write-Debug $logEntry
            }
            "Error" {
                Write-Error $logEntry
            }
        }
    }
}
#endregion


#region global variables
$ManagementRoleAssignmentsFilePath = ".\ManagementRoleAssignments.csv"
$RoleGroupsMembersFilePath = ".\RoleGroupsMembers.csv"
$ManagementRoleEntriesFilePath = ".\ManagementRoleEntries.csv"
$ManagementScopesFilePath = ".\ManagementScopes.csv"
# DomainController with GC Port, to run the AD Cmdlets against
$GC = (Get-ADDomainController -Discover).Name + ":3268"
#endregion


########################################
# Export Management Role Assignments #
########################################
#region Get all Management Role Assignments:
$ManagementRoleAssignments = Get-ManagementRoleAssignment | `
    Where-Object -FilterScript {@("SecurityGroup", "RoleGroup") -contains $_.RoleAssigneeType} | `
    Sort-Object -Property User 

# Arrange Data: 
$ExportObject = @()
$index = 0
Foreach($MRA in $ManagementRoleAssignments){
    $ExportHT = [ordered]@{
        GroupName = $MRA.User.Name
        GroupDN = $MRA.User.DistinguishedName
        Role = $MRA.Role.Name
        RecipientReadScope = $MRA.RecipientReadScope
        RecipientWriteScope = $MRA.RecipientWriteScope
        ConfigReadScope = $MRA.ConfigReadScope
        ConfigWriteScope = $MRA.ConfigWriteScope
        CustomRecipientWriteScope = $MRA.CustomRecipientWriteScope
        CustomConfigWriteScope = $MRA.CustomConfigWriteScope
    }

    $ExportObject += New-Object -TypeName PSCustomObject -Property $ExportHT
    
    # Progress bar:
    $pc = $index * 100 / ($ManagementRoleAssignments.count)
    Write-Progress -Activity "Working on it..." -Status "$index out of $($ManagementRoleAssignments.count)" -PercentComplete $pc
    $index++
}

# Export Data
$ExportObject | Export-CSV -Path $ManagementRoleAssignmentsFilePath -NoTypeInformation
#endregion


##################################################
# Export Management Role Groups Members          #
##################################################
#region Role Group Members
$counter = 0 
$itemsExported = 0
foreach($MRA in $ManagementRoleAssignments){
    $AssignmentsMembers = @()
    $AssignmentsMembers += Get-myGroupMembers -GroupName $MRA.RoleAssigneeName -SkipGroups @($MRA.RoleAssigneeName)

    $AssignmentsMembers | Select-Object @{Name='TopLevelGroup';Expression={$MRA.RoleAssigneeName}}, * | Export-CSV -Path $RoleGroupsMembersFilePath -NoTypeInformation -Append
    $itemsExported += $AssignmentsMembers.count

    $pc = $counter * 100 / $($ManagementRoleAssignments.count)
    Write-Progress -Activity "Working on iteration $counter / $($ManagementRoleAssignments.count)..." -Status "... $itemsExported lines exported" -PercentComplete $pc
    Write-Log -LogLevel OUTPUT -Message "[$($counter)/$($ManagementRoleAssignments.count)]Processed $($MRA.Name) with $($AssignmentsMembers.count) total assignments"
    $counter++
}
#endregion


###################################
# Export Management Role Entries #
###################################
$ManagementRoles = Get-ManagementRole

$ExportObject = @()
$index = 0
Foreach($MR in $ManagementRoles){
    Foreach($RoleEntry in $MR.RoleEntries){
        $ExportHT = [ordered]@{
            ManagementRoleName = $MR.Name
            Description = $MR.Description
            RoleEntry = $RoleEntry.Name
            Parameters = $RoleEntry.Parameters -join "; -"
        }
        $ExportObject += New-Object -TypeName PSCustomObject -Property $ExportHT
    
        $pc = $index * 100 / ($ManagementRoles.count)
        Write-Progress -Activity "Working on it..." -Status "Item $index out of $($ManagementRoles.count)" -PercentComplete $pc
    }
    $index++
}

# Export Data
$ExportObject | Export-CSV -Path $ManagementRoleEntriesFilePath -NoTypeInformation


###################################
# Export Management Scopes       #
###################################
#region Management Scopes
$ManagementScopes = Get-ManagementScope

# Arrange Data: 
$ExportObject = @()
$index = 0
Foreach($Scope in $ManagementScopes){
    $ExportHT = [ordered]@{
        ScopeName = $Scope.Name
        ScopeRestrictionType = $Scope.ScopeRestrictionType
        RecipientRoot = $Scope.RecipientRoot
        RecipientFilter = $Scope.RecipientFilter
    }

    $ExportObject += New-Object -TypeName PSCustomObject -Property $ExportHT
    
    # Progress bar:
    $pc = $index * 100 / ($ManagementScopes.count)
    Write-Progress -Activity "Working on it..." -Status "Item $index out of $($ManagementScopes.count)" -PercentComplete $pc
    $index++
}

# Export Data
$ExportObject | Export-CSV -Path $ManagementScopesFilePath -NoTypeInformation
#endregion
