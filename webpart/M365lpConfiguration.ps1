﻿param([PSCredential]$Credentials,
  [string]$TenantName,
  [string]$SiteCollectionName,
  [switch]$AppCatalogAdminOnly,
  [switch]$SiteAdminOnly)
 
if ($AppCatalogAdminOnly -and $SiteAdminOnly) {
  Write-Host "Select either -AppCatalogAdminOnly or -SiteAdminOnly"
  Write-Host "If you want to run both tenant and site admin parts, don't pass either parameter"
  break
}
$AppCatalogAdmin = $AppCatalogAdminOnly
$SiteAdmin = $SiteAdminOnly

if (!($AppCatalogAdminOnly) -and !($SiteAdminOnly)) {
  $AppCatalogAdmin = $true
  $SiteAdmin = $true
}
#region Legal stuff for Telemetry

Write-Host "Microsoft collects active usage data from your organization’s use of Microsoft 365 learning pathways. Microsoft will use this data to help improve the future Microsoft 365 learning pathways solutions. To learn more about Microsoft privacy policies see https://go.microsoft.com/fwlink/?LinkId=521839. If you would like to opt out of this data collection, please type Ctrl-C to stop this script and see Readme file (`"Disabling Telemetry Collection section`") for instructions on how to opt out.`n"
Read-Host "Press Enter to Continue"

$optInTelemetry = $true
#endregion

# verify the PnP cmdlets we need are installed
if (!(Get-Command Connect-PnPOnline -ErrorAction SilentlyContinue  )) {
  Write-Host "Could not find PnP PowerShell cmdlets"
  Write-Host "Please install them and run this script again"
  Write-Host "You can install them with the following line:"
  Write-Host "`nInstall-Module SharePointPnPPowerShellOnline`n"
  break
} 

# Now let's check if $Credentials is empty 
while ([string]::IsNullOrWhitespace($Credentials)) {
  # Prompt the user
  $Credentials = Get-Credential -Message "Please enter SharePoint Online admin account"
}

# Check if tenant name was passed in
while ([string]::IsNullOrWhitespace($TenantName)) {
  # No TenantName was passed, prompt the user
  $TenantName = Read-Host "Please enter your tenant name: (contoso) " 
  $TenantName = $TenantName.Trim()
  $TestAdminURL = "https://$TenantName-admin.sharepoint.com"
  # Test that it's a mostly valid URL
  # This doesn't catch everything
  if (!([system.uri]::IsWellFormedUriString($TestAdminURL, [System.UriKind]::Absolute))) {
    Write-Host "$TestAdminURL is not a valid URL."  -BackgroundColor Black -ForegroundColor Red
    Clear-Variable TenantName
  }
} 

$AdminURL = "https://$TenantName-admin.sharepoint.com"

# Check if $SiteCollectionName was passed in
if ([string]::IsNullOrWhitespace($SiteCollectionName) ) {
  # No TenantName was passed, prompt the user
  $SiteCollectionName = Read-Host "Please enter your site collection name: (Press Enter for `'MicrosoftTraining`') "
  if ([string]::IsNullOrWhitespace($SiteCollectionName)) {
    $SiteCollectionName = "MicrosoftTraining"
  }
}
$clSite = "https://$TenantName.sharepoint.com/sites/$SiteCollectionName"

#region Connect to Admin site.
if ($AppCatalogAdmin) { 
  try {
    Connect-PnPOnline -Url $AdminURL -Credentials $Credentials
  }
  catch {
    Write-Host "Failed to authenticate to $AdminURL"
    Write-Host $_
    break
  }
  # Need an App Catalog site collection defined for Set-PnPStorageEntity to work
  if (!(Get-PnPTenantAppCatalogUrl)) {
    Write-Host "Tenant $TenantName must have an App Catalog site defined" -BackgroundColor Black -ForegroundColor Red
    Write-Host "Please visit https://social.technet.microsoft.com/wiki/contents/articles/36933.create-app-catalog-in-sharepoint-online.aspx to learn how, then run this setup script again"
    Write-Host "`n"
    Disconnect-PnPOnline
    break

  }
  $appcatalog = Get-PnPTenantAppCatalogUrl
    
  try {
    # Test that user can write values to the App Catalog
    Set-PnPStorageEntity -Key MicrosoftCustomLearningCdn -Value "https://pnp.github.io/custom-learning-office-365/" -Description "CDN source for Microsoft Content" -ErrorAction Stop 
  }
  catch {
    Write-Host "User $($Credentials.UserName) cannot write to App Catalog site" -BackgroundColor Black -ForegroundColor Red
    Write-Host "Please make sure they are a Site Collection Admin for $appcatalog"
    Write-Host $_
    Disconnect-PnPOnline
    break
  }
  Get-PnPStorageEntity -Key MicrosoftCustomLearningCdn
  Set-PnPStorageEntity -Key MicrosoftCustomLearningSite -Value $clSite -Description "Microsoft 365 learning pathways Site Collection"
  Get-PnPStorageEntity -Key MicrosoftCustomLearningSite
  Set-PnPStorageEntity -Key MicrosoftCustomLearningTelemetryOn -Value $optInTelemetry -Description "Microsoft 365 learning pathways Telemetry Setting"
  Get-PnPStorageEntity -Key MicrosoftCustomLearningTelemetryOn
    
  Disconnect-PnPOnline # Disconnect from SharePoint Admin
  if ($AppCatalogAdminOnly) {
    Write-Host "`nTenant is configured. Run this script with the -SiteAdminOnly parameter to configure the site collection"
  }
}
#endregion

#region Content stuff
if ($SiteAdmin) { 
  try {
    Connect-PnPOnline -Url $clSite -Credentials $Credentials -ErrorAction Stop
  }
  catch {
    Write-Host "Failed to find to $clSite or user $($Credentials.UserName) does not have permission" -BackgroundColor Black -ForegroundColor Red
    Write-Host "Please create a Modern Communications site at $clsite and rerun this setup script"
    break
  } # end catch

  # Get the app
  # Check for it at the tenant level first
  $id = (Get-PnPApp | Where-Object -Property title -Like -Value "Microsoft 365 learning pathways").id 

  if ($id -ne $null) { 
    # Found the app in the tenant app catalog
    # Install it to the site collection if it's not already there
    Install-PnPApp -Identity $id -ErrorAction SilentlyContinue 
  }
  else { 
    Write-Host "Could not find `"Microsoft 365 learning pathways`" app. Please install in it your app catalog and run this script again."
    break
  }
  # Delete pages if they exist. Alert user.
  $clv = Get-PnPListItem -List "Site Pages" -Query "<View><Query><Where><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>CustomLearningViewer.aspx</Value></Eq></Where></Query></View>"
  if ($clv -ne $null) {
    Write-Host "Found an existing CustomLearningViewer.aspx page. Deleting it."
    # Renaming and moving to Recycle Bin to prevent potential naming overlap
    Set-PnPListItem -List "Site Pages" -Identity $clv.Id -Values @{"FileLeafRef" = "CustomLearningViewer$((Get-Date).Minute)$((Get-date).second).aspx" }
    Move-PnPListItemToRecycleBin -List "Site Pages" -Identity $clv.Id -Force
  }
  # Now create the page whether it was there before or not
  $clvPage = Add-PnPClientSidePage "CustomLearningViewer" # Will fail if user can't write to site collection
  $clvSection = Add-PnPClientSidePageSection -Page $clvPage -SectionTemplate OneColumn -Order 1
  # Before I try to add the Microsoft 365 learning pathways web parts verify they have been deployed to the site collection
  $timeout = New-TimeSpan -Minutes 1 # wait for a minute then time out
  $stopwatch = [diagnostics.stopwatch]::StartNew()
  Write-Host "." -NoNewline
  $WebPartsFound = $false
  while ($stopwatch.elapsed -lt $timeout) {
    if (Get-PnPAvailableClientSideComponents -page CustomLearningViewer.aspx -Component "Microsoft 365 learning pathways administration") {
      Write-Host "Microsoft 365 learning pathways web parts found"
      $WebPartsFound = $true
      break
    }
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 10
  }

  # loop either timed out or web parts were found. Let's see which it was
  if ($WebPartsFound -eq $false) {
    Write-Host "Could not find Microsoft 365 learning pathways Web Parts."
    Write-Host "Please verify the Microsoft 365 learning pathways Package is installed and run this installation script again."
    break 
  }
    
  Add-PnPClientSideWebPart -Page $clvPage -Component "Microsoft 365 learning pathways"
  Set-PnPClientSidePage -Identity $clvPage -Publish
  $clv = Get-PnPListItem -List "Site Pages" -Query "<View><Query><Where><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>CustomLearningViewer.aspx</Value></Eq></Where></Query></View>"
  $clv["PageLayoutType"] = "SingleWebPartAppPage"
  $clv.Update()
  Invoke-PnPQuery # Done with the viewer page

  $cla = Get-PnPListItem -List "Site Pages" -Query "<View><Query><Where><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>CustomLearningAdmin.aspx</Value></Eq></Where></Query></View>"
  if ($cla -ne $null) {
    Write-Host "Found an existing CustomLearningAdmin.aspx page. Deleting it."
    # Renaming and moving to Recycle Bin to prevent potential naming overlap
    Set-PnPListItem -List "Site Pages" -Identity $cla.Id -Values @{"FileLeafRef" = "CustomLearningAdmin$((Get-Date).Minute)$((Get-date).second).aspx" }
    Move-PnPListItemToRecycleBin -List "Site Pages" -Identity $cla.Id -Force    
  }

  $claPage = Add-PnPClientSidePage "CustomLearningAdmin" -Publish
  $claSection = Add-PnPClientSidePageSection -Page $claPage -SectionTemplate OneColumn -Order 1
  Add-PnPClientSideWebPart -Page $claPage -Component "Microsoft 365 learning pathways administration"
  Set-PnPClientSidePage -Identity $claPage -Publish
  $cla = Get-PnPListItem -List "Site Pages" -Query "<View><Query><Where><Eq><FieldRef Name='FileLeafRef'/><Value Type='Text'>CustomLearningAdmin.aspx</Value></Eq></Where></Query></View>"
  $cla["PageLayoutType"] = "SingleWebPartAppPage"
  $cla.Update()
  Invoke-PnPQuery # Done with the Admin page
}

Write-Host "Microsoft 365 learning pathways Pages created at $clSite"
#endregion
