Add-PSSnapin Microsoft.SharePoint.PowerShell -erroraction SilentlyContinue
$logFileName="Log $(get-date -f _yyyy-MM-dd_HH_mmss).txt"
Start-Transcript -path $logFileName -append

######################################Config Section#########################################################
# Import CSV file name
$UserListCSV = "Members.csv"
# Digital.ai IDP URL
$Uri = 'https://XXXXXXXX/identity/v1/users'
# Account ID - User need to be added
$account_ID = "XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
# Token ID
$Token= "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
#############################################################################################################
 
# Import the CSV file
$UserList = Import-CSV $UserListCSV #-header("GroupName","UserAccount") - If CSV doesn't has headers

function Create-User {
    param(
        $email,
        $family_name,
        $given_name,
        $username
    )
    
    $body = @"
{ 
    "account_id": "$account_ID",
    "email": "$email",
    "given_name": "$given_name",
    "family_name": "$family_name",
    "groups": [],
    "is_password_temporary": true,
    "roles": [],
    "send_password_reset": true,
    "username": "$username"
} 
"@ 

    $headers = @{
        "Content"       = "application/json"
        "Authorization" = "Bearer " +$token
    }

    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "========================================================================================="
        Write-Host "User added successfully :" $email -ForegroundColor Green
        Write-Host "========================================================================================="
    }
    catch {
        #Dig into the exception to get the Response details.
        #Note that value__ is not a typo.
        Write-Host "========================================================================================"
        Write-Host " User Creation failed ! : User name :" $email -ForegroundColor red
        Write-Host "========================================================================================"
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ -ForegroundColor red
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor red
        Write-Host "Error:" $_.Exception.Message
        Write-Host "----------------------------------------------------------------------------------------"
        Write-Host "Detailed Error:" $_
        Write-Host "request Body: "$body
        Write-Host "========================================================================================"
    }
}
 
#Iterate through each user from CSV file
foreach ($user in $UserList) {
    Create-User -email $User.Email -username $user.Username -family_name $User."Short Name" -given_name $User.Name
}

Stop-Transcript