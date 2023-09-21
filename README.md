# ExchangeRbacOverviewExport
A small tool to help with an overview export of the Exchange RBAC implementation.

## Description
Having to do an export of the RBAC permissions in a large Exchange environment has always proven to be a time consuming task for me. 
After doing this from scratch for a few times, because I never believed it would be important to save the scripts somewhere safe, I have decided to store the script in Git.
Maybe someone else finds it useful too.

## The goal
The main goal was to export the following information:
- Who has permissions in the environment.
- What permissions are assigned.
- What is the scope of those assigned permissions.

## The challenge of 'Get-ADGroupMember -Recursive'
With cmdlets like 'Get-ManagementRoleAssignment' and 'Get-ManagementScope' it is quite easy to see what kind of permissions are being assigned, with which scope and also to see the first level of assignment. 
The challenge was to navigate top-down from the top level assignment, which usually is a RoleGroup or a SecurityGroup, and export the full list of users. 
This is challenging especially in large environments, in multi-domain forests where the intuitive use of 'Get-ADGroupMember' cmdlet together with the -Recursive switch usually throws some errors, like the one specified [here](https://learn.microsoft.com/en-us/troubleshoot/windows-server/identity/get-adgroupmember-error-remote-forest-members).
At a frist glance, local admin rights on the machine are required, together with some not-so-common-for-an-exchange-admin rights ('Remove-ADObject'). 
Being lazy, I stopped the research and developed my own solution, which gets the members by running the 'Get-ADGroup' cmdlet against the Global Catalog port, and fetching the 'Members' property. 
Of course, additional iterations are required to fetch each Member from the above output (which is a DN), but hey... that's why the computers are for. To do the work.

## The output
The output is going to be 4 CSV files with the following structure: 
- .\ManagementRoleAssignments.csv with the following columns:

   GroupName 

   GroupDN 

   Role 

   RecipientReadScope 

   RecipientWriteScope 

   ConfigReadScope

   ConfigWriteScope

   CustomRecipientWriteScope 

   CustomConfigWriteScope

- .\RoleGroupsMembers.csv witht he following columns:

   MemberID
        
   ParentStructure
   
   Type

- .\ManagementRoleEntries.csv with the following columns

   ManagementRoleName

   Description 

   RoleEntry 

   Parameters 

- .\ManagementScopes.csv

   ScopeName 

   ScopeRestrictionType 

   RecipientRoot 

   RecipientFilter 

The CSV files can be merged into Excel, or can be further processed with PowerShell, or Python, etc. for further insights. 
The columns are exported to cover for my report needs, but can be extended / restricted, if needed. 

## How to run it
The runbook can be run by sections while connected to Exchange Management Shell / Exchange Online Powershell and AD. 