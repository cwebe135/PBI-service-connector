# PBI-service-connector
Custom Power BI Connector that wraps the Power BI Service REST API

## Decription
This custom connector accesses the Power BI Service REST API through
a registered Microsoft Entra application. For your organization, it
would be preferable to create your own registered application to
remove the dependency on the original hosted by BJU Press. If the
application is private, you will need to add a client secret.

## Exposed Endpoints
Only a few endpoints have been exposed so far; others may be added as
needed.
 * Workspaces
   - `PBIServiceMetadata.Workspaces`: Returns all workspaces the
      logged in user is a member of. Does not include My Workspace
 * Reports
   - `PBIServiceMetadata.Reports`: Navigator for reports by workspace.
   - `PBIServiceMetadata.ReportsByWorkspaceId`: Lists reports in a
      single workspace, identified by workspace ID.

## Building .mez File
Running `build_project.py` with no arguments will build the .mez file
in the debug folder, where the Power Query SDK will identify it.
Running the script with the additional argument `distribute` will
additionally copy the .mez file to the appropriate location in the
Windows file directory for Power BI Desktop to access the custom
connector. At this time, Power BI Desktop is not available for other
platforms, so this step is skipped if not run in a Windows
environment.