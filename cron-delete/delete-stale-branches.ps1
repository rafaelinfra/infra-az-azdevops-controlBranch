$project = "<nome do projeto do devops>"

# Get a list of repositories in the project
$repos = az repos list --project $project --output json | ConvertFrom-Json

# Loop through each repository in the project
foreach ($repo in $repos) {
    $repositoryName = $repo.name

    # Skip the "terraform" repository
    #if ($repositoryName -eq "terraform") {
    #    Write-Host ("Skipping repository: $repositoryName")
    #    continue
    #}

    $excludeBranches = @("main", "master", "dev")
    $daysDeleteBefore = -90
    $dateTimeNow = [DateTime]::Now
    $dateTimeBeforeToDelete = $dateTimeNow.AddDays($daysDeleteBefore)

    if (-not (Test-Path env:IS_DRY_RUN)) { $env:IS_DRY_RUN = $true }

    Write-Host ("Repository: $repositoryName")
    Write-Host ("is dry run: {0}" -f $env:IS_DRY_RUN)
    Write-Host ("datetime now: {0}" -f $dateTimeNow)
    Write-Host ("delete branches before {0}" -f (Get-Date $dateTimeBeforeToDelete))

    $refs = az repos ref list --project $project --repository $repositoryName --filter heads | ConvertFrom-Json

    $toDeleteBranches = @()

    foreach ($ref in $refs) {
        if ($ref.name -replace "refs/heads/" -in $excludeBranches) {
            continue
        }

        $objectId = $ref.objectId

        # fetch individual commit details
        $commit = az devops invoke `
            --area git `
            --resource commits `
            --route-parameters `
            project=$project `
            repositoryId=$repositoryName `
            commitId=$objectId |
            ConvertFrom-Json

        $toDelete = [PSCustomObject]@{
            objectId     = $objectId
            name         = $ref.name
            creator      = $ref.creator.uniqueName
            lastAuthor   = $commit.committer.email
            lastModified = $commit.push.date
        }
        $toDeleteBranches += , $toDelete
    }

    $toDeleteBranches = $toDeleteBranches | Where-Object { (Get-Date $_.lastModified) -lt (Get-Date $dateTimeBeforeToDelete) }

    if ($toDeleteBranches.count -eq 0) {
        Write-Host "No stale branches to delete"
        continue
    }

    $toDeleteBranches | ForEach-Object {
        Write-Host ("deleting staled branch in repository $($repositoryName): name={0} - id={1} - lastModified={2}" -f $_.name, $_.objectId, $_.lastModified)
        if ([System.Convert]::ToBoolean($env:IS_DRY_RUN)) {
            $result = az repos ref delete `
                --name $_.name `
                --object-id $_.objectId `
                --project $project `
                --repository $repositoryName |
                ConvertFrom-Json
            Write-Host ("success message: {0}" -f $result.updateStatus)
        }
    }
}
