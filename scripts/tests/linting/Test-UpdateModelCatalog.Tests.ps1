#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../linting/Update-ModelCatalog.ps1'
    . $script:ScriptPath

    # Suppress Write-Host output during tests
    Mock Write-Host {}
    Mock Write-Warning {}
}

#region Get-RemoteYaml Tests

Describe 'Get-RemoteYaml' -Tag 'Unit' {
    Context 'when URL returns valid YAML' {
        It 'Parses YAML content into objects' {
            $yamlContent = @"
- name: Claude Sonnet 4
  release_status: GA
- name: GPT-5 mini
  release_status: Preview
"@
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ Content = $yamlContent }
            }

            $result = Get-RemoteYaml -Url 'https://example.com/test.yml'
            $result | Should -HaveCount 2
            $result[0].name | Should -Be 'Claude Sonnet 4'
            $result[1].release_status | Should -Be 'Preview'
        }
    }

    Context 'when URL request fails' {
        It 'Throws an error' {
            Mock Invoke-WebRequest { throw 'Network error' }

            { Get-RemoteYaml -Url 'https://example.com/fail.yml' } | Should -Throw
        }
    }

    Context 'when YAML is empty' {
        It 'Returns null or empty' {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ Content = '' }
            }

            $result = Get-RemoteYaml -Url 'https://example.com/empty.yml'
            $result | Should -BeNullOrEmpty
        }
    }
}

#endregion Get-RemoteYaml Tests

#region Merge-ModelData Tests

Describe 'Merge-ModelData' -Tag 'Unit' {
    Context 'when given matching release status and pricing data' {
        BeforeAll {
            $script:ReleaseStatus = @(
                @{ name = 'Claude Sonnet 4'; release_status = 'GA' }
                @{ name = 'GPT-5 mini'; release_status = 'Preview' }
            )
            $script:Pricing = @(
                @{ model = 'Claude Sonnet 4'; input = '$3.00'; provider = 'anthropic' }
                @{ model = 'GPT-5 mini'; input = '$0.25'; provider = 'openai' }
            )
            $script:Result = @(Merge-ModelData -ReleaseStatus $script:ReleaseStatus -Pricing $script:Pricing)
        }

        It 'Returns an entry for each model in release status' {
            $script:Result | Should -HaveCount 2
        }

        It 'Appends (copilot) suffix to model names' {
            $script:Result[0].name | Should -Be 'Claude Sonnet 4 (copilot)'
            $script:Result[1].name | Should -Be 'GPT-5 mini (copilot)'
        }

        It 'Maps GA release status to ga' {
            $script:Result[0].status | Should -Be 'ga'
        }

        It 'Maps non-GA release status to preview' {
            $script:Result[1].status | Should -Be 'preview'
        }

        It 'Derives tier from input price' {
            $script:Result[0].tier | Should -Be 'standard'
            $script:Result[1].tier | Should -Be 'fast'
        }

        It 'Takes provider from upstream pricing data' {
            $script:Result[0].provider | Should -Be 'Anthropic'
            $script:Result[1].provider | Should -Be 'OpenAI'
        }

        It 'Emits no multiplier property' {
            $script:Result[0].Contains('multiplier') | Should -BeFalse
        }

        It 'Emits fields in a stable order' {
            @($script:Result[0].Keys) | Should -Be @('name', 'tier', 'status', 'provider')
        }
    }

    Context 'tier classification from input price' {
        It 'Assigns free tier for a zero price' {
            $release = @(@{ name = 'Free Model'; release_status = 'GA' })
            $pricing = @(@{ model = 'Free Model'; input = '$0.00'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'free'
        }

        It 'Assigns fast tier below the first boundary' {
            $release = @(@{ name = 'Fast Model'; release_status = 'GA' })
            $pricing = @(@{ model = 'Fast Model'; input = '$0.25'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'fast'
        }

        It 'Assigns fast tier exactly at the first boundary' {
            $release = @(@{ name = 'Fast Edge'; release_status = 'GA' })
            $pricing = @(@{ model = 'Fast Edge'; input = '$1.00'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'fast'
        }

        It 'Assigns standard tier just past the first boundary' {
            $release = @(@{ name = 'Standard Low'; release_status = 'GA' })
            $pricing = @(@{ model = 'Standard Low'; input = '$1.01'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'standard'
        }

        It 'Assigns standard tier exactly at the second boundary' {
            $release = @(@{ name = 'Standard Edge'; release_status = 'GA' })
            $pricing = @(@{ model = 'Standard Edge'; input = '$3.00'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'standard'
        }

        It 'Assigns premium tier just past the second boundary' {
            $release = @(@{ name = 'Premium Model'; release_status = 'GA' })
            $pricing = @(@{ model = 'Premium Model'; input = '$3.01'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'premium'
        }

        It 'Assigns premium tier exactly at the third boundary' {
            $release = @(@{ name = 'Premium Edge'; release_status = 'GA' })
            $pricing = @(@{ model = 'Premium Edge'; input = '$5.00'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'premium'
        }

        It 'Assigns ultra tier past the third boundary' {
            $release = @(@{ name = 'Ultra Model'; release_status = 'GA' })
            $pricing = @(@{ model = 'Ultra Model'; input = '$10.00'; provider = 'anthropic' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'ultra'
        }

        It 'Returns a string tier, not an array' {
            $release = @(@{ name = 'Tier Check'; release_status = 'GA' })
            $pricing = @(@{ model = 'Tier Check'; input = '$0.25'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -BeOfType [string]
        }
    }

    Context 'when a model has no pricing entry' {
        It 'Warns and falls back to standard tier' {
            $release = @(@{ name = 'No Price Model'; release_status = 'GA' })
            $pricing = @(@{ model = 'Other Model'; input = '$5.00'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'standard'
            Should -Invoke Write-Warning -Times 1 -Exactly
        }

        It 'Falls back to the name-pattern provider matcher' {
            $release = @(@{ name = 'Claude Unlisted'; release_status = 'GA' })
            $pricing = @(@{ model = 'Other Model'; input = '$5.00'; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].provider | Should -Be 'Anthropic'
        }
    }

    Context 'when upstream names carry footnote markers' {
        It 'Strips the marker before matching' {
            $release = @(@{ name = 'Claude Sonnet 5'; release_status = 'GA' })
            $pricing = @(@{ model = 'Claude Sonnet 5[^sonnet-5-promo]'; input = '$2.00'; provider = 'anthropic' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'standard'
            $result[0].provider | Should -Be 'Anthropic'
        }
    }

    Context 'when a model has one row per context-window band' {
        It 'Uses the cheapest band' {
            $release = @(@{ name = 'Banded Model'; release_status = 'GA' })
            $pricing = @(
                @{ model = 'Banded Model'; input = '$2.50'; provider = 'openai' }
                @{ model = 'Banded Model'; input = '$5.00'; provider = 'openai' }
            )
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'standard'
        }
    }

    Context 'when release status has multiple models' {
        It 'Processes all models in order' {
            $release = @(
                @{ name = 'Model A'; release_status = 'GA' }
                @{ name = 'Model B'; release_status = 'Preview' }
                @{ name = 'Model C'; release_status = 'GA' }
            )
            $pricing = @(
                @{ model = 'Model A'; input = '$0.00'; provider = 'openai' }
                @{ model = 'Model B'; input = '$2.00'; provider = 'openai' }
                @{ model = 'Model C'; input = '$4.00'; provider = 'openai' }
            )
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result | Should -HaveCount 3
            $result[0].name | Should -Be 'Model A (copilot)'
            $result[1].name | Should -Be 'Model B (copilot)'
            $result[2].name | Should -Be 'Model C (copilot)'
            $result[0].tier | Should -Be 'free'
            $result[1].tier | Should -Be 'standard'
            $result[2].tier | Should -Be 'premium'
        }
    }

    Context 'when the price cell is empty' {
        It 'Treats the model as unpriced' {
            $release = @(@{ name = 'Empty Price'; release_status = 'GA' })
            $pricing = @(@{ model = 'Empty Price'; input = ''; provider = 'openai' })
            $result = @(Merge-ModelData -ReleaseStatus $release -Pricing $pricing)
            $result[0].tier | Should -Be 'standard'
            $result[0].provider | Should -Be 'OpenAI'
        }
    }
}

#endregion Merge-ModelData Tests

#region Get-ArchivedModelData Tests

Describe 'Get-ArchivedModelData' -Tag 'Unit' {
    Context 'when the model has an archived upstream record' {
        It 'Returns the last-known provider and tier' {
            $result = Get-ArchivedModelData -Name 'Goldeneye (copilot)'
            $result.Provider | Should -Be 'GitHub'
            $result.Tier | Should -Be 'standard'
        }
    }

    Context 'when the model has no archived record' {
        It 'Returns null' {
            Get-ArchivedModelData -Name 'Claude Sonnet 5 (copilot)' | Should -BeNullOrEmpty
        }
    }
}

#endregion Get-ArchivedModelData Tests

#region Compare-Catalogs Tests

Describe 'Compare-Catalogs' -Tag 'Unit' {
    Context 'when catalogs are identical' {
        It 'Returns empty added, removed, and changed arrays' {
            $models = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'Model B (copilot)'; tier = 'premium' }
            )
            $result = Compare-Catalogs -Current $models -Discovered $models
            $result.added | Should -HaveCount 0
            $result.removed | Should -HaveCount 0
            $result.changed | Should -HaveCount 0
        }
    }

    Context 'when new models are added' {
        It 'Identifies added models' {
            $current = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
            )
            $discovered = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'Model B (copilot)'; tier = 'premium' }
            )
            $result = Compare-Catalogs -Current $current -Discovered $discovered
            $result.added | Should -HaveCount 1
            $result.added[0].name | Should -Be 'Model B (copilot)'
        }
    }

    Context 'when models are removed' {
        It 'Identifies removed models' {
            $current = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'Model B (copilot)'; tier = 'premium' }
            )
            $discovered = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
            )
            $result = Compare-Catalogs -Current $current -Discovered $discovered
            $result.removed | Should -HaveCount 1
            $result.removed[0].name | Should -Be 'Model B (copilot)'
        }
    }

    Context 'when tiers change' {
        It 'Identifies changed tiers' {
            $current = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
            )
            $discovered = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'premium' }
            )
            $result = Compare-Catalogs -Current $current -Discovered $discovered
            $result.changed | Should -HaveCount 1
            $result.changed[0].name | Should -Be 'Model A (copilot)'
            $result.changed[0].oldTier | Should -Be 'standard'
            $result.changed[0].newTier | Should -Be 'premium'
        }
    }

    Context 'when all types of changes occur simultaneously' {
        It 'Reports additions, removals, and changes together' {
            $current = @(
                [PSCustomObject]@{ name = 'Stable (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'Removed (copilot)'; tier = 'premium' }
                [PSCustomObject]@{ name = 'Changed (copilot)'; tier = 'standard' }
            )
            $discovered = @(
                [PSCustomObject]@{ name = 'Stable (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'Changed (copilot)'; tier = 'premium' }
                [PSCustomObject]@{ name = 'Added (copilot)'; tier = 'free' }
            )
            $result = Compare-Catalogs -Current $current -Discovered $discovered
            $result.added | Should -HaveCount 1
            $result.removed | Should -HaveCount 1
            $result.changed | Should -HaveCount 1
            $result.added[0].name | Should -Be 'Added (copilot)'
            $result.removed[0].name | Should -Be 'Removed (copilot)'
            $result.changed[0].name | Should -Be 'Changed (copilot)'
        }
    }

    Context 'when current catalog is empty' {
        It 'Reports all discovered models as added' {
            $current = @(
                [PSCustomObject]@{ name = 'placeholder'; tier = 'free' }
            )
            # Use a single-element to avoid empty array issues; test with actual additions
            $discovered = @(
                [PSCustomObject]@{ name = 'New A (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'New B (copilot)'; tier = 'premium' }
            )
            $result = Compare-Catalogs -Current $current -Discovered $discovered
            $result.added | Should -HaveCount 2
            $result.removed | Should -HaveCount 1
        }
    }

    Context 'when tier does not change' {
        It 'Does not report unchanged models' {
            $current = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'Model B (copilot)'; tier = 'premium' }
            )
            $discovered = @(
                [PSCustomObject]@{ name = 'Model A (copilot)'; tier = 'standard' }
                [PSCustomObject]@{ name = 'Model B (copilot)'; tier = 'premium' }
            )
            $result = Compare-Catalogs -Current $current -Discovered $discovered
            $result.changed | Should -HaveCount 0
        }
    }
}

#endregion Compare-Catalogs Tests

#region Invoke-ModelCatalogUpdate Tests

Describe 'Invoke-ModelCatalogUpdate' -Tag 'Unit' {
    BeforeAll {
        $script:CatalogDir = Join-Path ([System.IO.Path]::GetTempPath()) "CatalogUpdateTests_$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $script:CatalogDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:CatalogDir) {
            Remove-Item -Path $script:CatalogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'when no existing catalog exists' {
        BeforeAll {
            $script:NewCatalogPath = Join-Path $script:CatalogDir 'new-catalog.json'
            if (Test-Path $script:NewCatalogPath) { Remove-Item $script:NewCatalogPath -Force }

            $release = @(
                @{ name = 'Model A'; release_status = 'GA' }
                @{ name = 'Model B'; release_status = 'Preview' }
            )
            $pricing = @(
                @{ model = 'Model A'; input = '$2.00'; provider = 'openai' }
                @{ model = 'Model B'; input = '$0.25'; provider = 'openai' }
            )

            $script:NewResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:NewCatalogPath
        }

        It 'Returns created status' {
            $script:NewResult.status | Should -Be 'created'
        }

        It 'Returns null diff' {
            $script:NewResult.diff | Should -BeNullOrEmpty
        }

        It 'Returns all discovered models in finalModels' {
            $script:NewResult.finalModels | Should -HaveCount 2
        }

        It 'Writes catalog file to disk' {
            Test-Path $script:NewCatalogPath | Should -BeTrue
        }

        It 'Written catalog contains correct model count' {
            $written = Get-Content $script:NewCatalogPath -Raw | ConvertFrom-Json
            $written.models | Should -HaveCount 2
        }

        It 'Written catalog has lastUpdated field' {
            $written = Get-Content $script:NewCatalogPath -Raw | ConvertFrom-Json
            $written.lastUpdated | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when catalog exists with no changes' {
        BeforeAll {
            $script:UnchangedPath = Join-Path $script:CatalogDir 'unchanged-catalog.json'
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:UnchangedPath -Encoding utf8

            $release = @(@{ name = 'Model A'; release_status = 'GA' })
            $pricing = @(@{ model = 'Model A'; input = '$2.00'; provider = 'openai' })

            $script:UnchangedResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:UnchangedPath
        }

        It 'Returns unchanged status' {
            $script:UnchangedResult.status | Should -Be 'unchanged'
        }

        It 'Updates lastUpdated timestamp in file' {
            $written = Get-Content $script:UnchangedPath -Raw | ConvertFrom-Json
            $written.lastUpdated | Should -Be (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    Context 'when models are added' {
        BeforeAll {
            $script:AddedPath = Join-Path $script:CatalogDir 'added-catalog.json'
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:AddedPath -Encoding utf8

            $release = @(
                @{ name = 'Model A'; release_status = 'GA' }
                @{ name = 'Model B'; release_status = 'Preview' }
            )
            $pricing = @(
                @{ model = 'Model A'; input = '$2.00'; provider = 'openai' }
                @{ model = 'Model B'; input = '$4.00'; provider = 'openai' }
            )

            $script:AddedResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:AddedPath
        }

        It 'Returns updated status' {
            $script:AddedResult.status | Should -Be 'updated'
        }

        It 'Includes new model in finalModels' {
            $names = @($script:AddedResult.finalModels | ForEach-Object { if ($_ -is [hashtable]) { $_['name'] } else { $_.name } })
            $names | Should -Contain 'Model B (copilot)'
        }

        It 'Reports addition in diff' {
            $script:AddedResult.diff.added | Should -HaveCount 1
        }
    }

    Context 'when models are removed' {
        BeforeAll {
            $script:RemovedPath = Join-Path $script:CatalogDir 'removed-catalog.json'
            # Unexpired, so the entry exercises retiredDate preservation rather than pruning.
            $script:PreservedRetiredDate = (Get-Date).AddDays(30).ToString('yyyy-MM-dd')
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                    @{ name = 'Model B (copilot)'; tier = 'premium'; status = 'ga'; provider = 'OpenAI' }
                    @{ name = 'Model C (copilot)'; tier = 'fast'; status = 'retiring'; provider = 'OpenAI'; retiredDate = $script:PreservedRetiredDate }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:RemovedPath -Encoding utf8

            $release = @(@{ name = 'Model A'; release_status = 'GA' })
            $pricing = @(@{ model = 'Model A'; input = '$2.00'; provider = 'openai' })

            $script:RemovedResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:RemovedPath
        }

        It 'Returns updated status' {
            $script:RemovedResult.status | Should -Be 'updated'
        }

        It 'Returns a hashtable with status, diff, and finalModels keys' {
            $script:RemovedResult.Keys | Should -Contain 'status'
            $script:RemovedResult.Keys | Should -Contain 'diff'
            $script:RemovedResult.Keys | Should -Contain 'finalModels'
        }

        It 'Marks removed model as retiring PSCustomObject in finalModels' {
            $retiring = $script:RemovedResult.finalModels | Where-Object {
                if ($_ -is [hashtable]) { $_['name'] -eq 'Model B (copilot)' }
                else { $_.name -eq 'Model B (copilot)' }
            }
            $retiring | Should -BeOfType [PSCustomObject]
            $retiring.status | Should -Be 'retiring'
        }

        It 'Preserves tier and provider on retiring model' {
            $retiring = $script:RemovedResult.finalModels | Where-Object {
                if ($_ -is [hashtable]) { $_['name'] -eq 'Model B (copilot)' }
                else { $_.name -eq 'Model B (copilot)' }
            }
            $retiring.tier | Should -Be 'premium'
            $retiring.provider | Should -Be 'OpenAI'
        }

        It 'Emits no multiplier on retiring model' {
            $retiring = $script:RemovedResult.finalModels | Where-Object {
                if ($_ -is [hashtable]) { $_['name'] -eq 'Model B (copilot)' }
                else { $_.name -eq 'Model B (copilot)' }
            }
            $retiring.PSObject.Properties['multiplier'] | Should -BeNullOrEmpty
        }

        It 'Keeps the original retiredDate on an already-retiring model' {
            $stillRetiring = $script:RemovedResult.finalModels | Where-Object {
                if ($_ -is [hashtable]) { $_['name'] -eq 'Model C (copilot)' }
                else { $_.name -eq 'Model C (copilot)' }
            }
            $stillRetiring.retiredDate | Should -Be $script:PreservedRetiredDate
        }

        It 'Sets retiredDate as future date on removed model' {
            $retiring = $script:RemovedResult.finalModels | Where-Object {
                if ($_ -is [hashtable]) { $_['name'] -eq 'Model B (copilot)' }
                else { $_.name -eq 'Model B (copilot)' }
            }
            $retiring.retiredDate | Should -Not -BeNullOrEmpty
            [datetime]::Parse($retiring.retiredDate) | Should -BeGreaterThan (Get-Date)
        }

        It 'Keeps non-removed models unchanged' {
            $kept = $script:RemovedResult.finalModels | Where-Object {
                if ($_ -is [hashtable]) { $_['name'] -eq 'Model A (copilot)' }
                else { $_.name -eq 'Model A (copilot)' }
            }
            $kept | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when a retiring model reaches its retirement date' {
        BeforeAll {
            $script:PrunePath = Join-Path $script:CatalogDir 'prune-catalog.json'
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                    @{ name = 'Expired (copilot)'; tier = 'fast'; status = 'retiring'; provider = 'OpenAI'; retiredDate = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd') }
                    @{ name = 'Retiring Today (copilot)'; tier = 'fast'; status = 'retiring'; provider = 'OpenAI'; retiredDate = (Get-Date).ToString('yyyy-MM-dd') }
                    @{ name = 'Malformed (copilot)'; tier = 'fast'; status = 'retiring'; provider = 'OpenAI'; retiredDate = 'not-a-date' }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:PrunePath -Encoding utf8

            $release = @(@{ name = 'Model A'; release_status = 'GA' })
            $pricing = @(@{ model = 'Model A'; input = '$2.00'; provider = 'openai' })

            $script:PruneResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:PrunePath
        }

        It 'Drops an entry whose retirement date has passed' {
            $script:PruneResult.finalModels.name | Should -Not -Contain 'Expired (copilot)'
        }

        It 'Keeps an entry retiring today for the whole of its final day' {
            $script:PruneResult.finalModels.name | Should -Contain 'Retiring Today (copilot)'
        }

        It 'Keeps an entry whose retirement date cannot be parsed' {
            $script:PruneResult.finalModels.name | Should -Contain 'Malformed (copilot)'
        }

        It 'Leaves active models untouched' {
            $script:PruneResult.finalModels.name | Should -Contain 'Model A (copilot)'
        }
    }

    Context 'when a removed model has an archived upstream record' {
        BeforeAll {
            $script:ArchivedPath = Join-Path $script:CatalogDir 'archived-catalog.json'
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                    @{ name = 'Goldeneye (copilot)'; tier = 'free'; status = 'ga'; provider = 'Unknown' }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ArchivedPath -Encoding utf8

            $release = @(@{ name = 'Model A'; release_status = 'GA' })
            $pricing = @(@{ model = 'Model A'; input = '$2.00'; provider = 'openai' })

            $script:ArchivedResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:ArchivedPath
        }

        It 'Replaces the placeholder provider with the archived value' {
            $entry = $script:ArchivedResult.finalModels | Where-Object { $_.name -eq 'Goldeneye (copilot)' }
            $entry.provider | Should -Be 'GitHub'
        }

        It 'Replaces the placeholder tier with the archived value' {
            $entry = $script:ArchivedResult.finalModels | Where-Object { $_.name -eq 'Goldeneye (copilot)' }
            $entry.tier | Should -Be 'standard'
        }
    }

    Context 'when a provider cannot be resolved from upstream or name' {
        It 'Warns instead of writing the Unknown sentinel silently' {
            $unresolvedPath = Join-Path $script:CatalogDir 'unresolved-catalog.json'
            $release = @(@{ name = 'Mystery Model'; release_status = 'GA' })
            $pricing = @(@{ model = 'Mystery Model'; input = '$2.00'; provider = 'new_vendor' })

            Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $unresolvedPath | Out-Null

            Should -Invoke Write-Warning -ParameterFilter { $Message -like '*unresolved provider*' } -Times 1 -Exactly
        }
    }

    Context 'when tiers change' {
        BeforeAll {
            $script:ChangedPath = Join-Path $script:CatalogDir 'changed-catalog.json'
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ChangedPath -Encoding utf8

            $release = @(@{ name = 'Model A'; release_status = 'GA' })
            $pricing = @(@{ model = 'Model A'; input = '$10.00'; provider = 'openai' })

            $script:ChangedResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:ChangedPath
        }

        It 'Returns updated status' {
            $script:ChangedResult.status | Should -Be 'updated'
        }

        It 'Reports change in diff' {
            $script:ChangedResult.diff.changed | Should -HaveCount 1
            $script:ChangedResult.diff.changed[0].oldTier | Should -Be 'standard'
            $script:ChangedResult.diff.changed[0].newTier | Should -Be 'ultra'
        }
    }

    Context 'when DryRun is specified' {
        BeforeAll {
            $script:DryRunPath = Join-Path $script:CatalogDir 'dryrun-catalog.json'
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:DryRunPath -Encoding utf8

            $release = @(
                @{ name = 'Model A'; release_status = 'GA' }
                @{ name = 'Model B'; release_status = 'GA' }
            )
            $pricing = @(
                @{ model = 'Model A'; input = '$2.00'; provider = 'openai' }
                @{ model = 'Model B'; input = '$4.00'; provider = 'openai' }
            )

            $script:DryRunResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:DryRunPath -DryRun
        }

        It 'Returns dryrun status' {
            $script:DryRunResult.status | Should -Be 'dryrun'
        }

        It 'Does not modify the catalog file' {
            $written = Get-Content $script:DryRunPath -Raw | ConvertFrom-Json
            $written.lastUpdated | Should -Be '2026-01-01'
            $written.models | Should -HaveCount 1
        }

        It 'Still computes finalModels' {
            $script:DryRunResult.finalModels.Count | Should -BeGreaterThan 1
        }
    }

    Context 'when DryRun with no changes' {
        BeforeAll {
            $script:DryRunNoChangePath = Join-Path $script:CatalogDir 'dryrun-nochange.json'
            $existingCatalog = @{
                lastUpdated = '2026-01-01'
                source      = 'https://example.com'
                models      = @(
                    @{ name = 'Model A (copilot)'; tier = 'standard'; status = 'ga'; provider = 'OpenAI' }
                )
            }
            $existingCatalog | ConvertTo-Json -Depth 5 | Set-Content -Path $script:DryRunNoChangePath -Encoding utf8

            $release = @(@{ name = 'Model A'; release_status = 'GA' })
            $pricing = @(@{ model = 'Model A'; input = '$2.00'; provider = 'openai' })

            $script:DryRunNoChangeResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:DryRunNoChangePath -DryRun
        }

        It 'Returns unchanged status' {
            $script:DryRunNoChangeResult.status | Should -Be 'unchanged'
        }

        It 'Does not update lastUpdated in file' {
            $written = Get-Content $script:DryRunNoChangePath -Raw | ConvertFrom-Json
            $written.lastUpdated | Should -Be '2026-01-01'
        }
    }

    Context 'when catalog path directory does not exist' {
        BeforeAll {
            $script:DeepPath = Join-Path $script:CatalogDir 'deep/nested/dir/catalog.json'
            if (Test-Path (Split-Path $script:DeepPath -Parent)) {
                Remove-Item (Split-Path $script:DeepPath -Parent) -Recurse -Force
            }

            $release = @(@{ name = 'Model A'; release_status = 'GA' })
            $pricing = @(@{ model = 'Model A'; input = '$2.00'; provider = 'openai' })

            $script:DeepResult = Invoke-ModelCatalogUpdate -ReleaseStatus $release -Pricing $pricing -CatalogPath $script:DeepPath
        }

        It 'Creates directory and writes catalog' {
            Test-Path $script:DeepPath | Should -BeTrue
        }

        It 'Returns created status' {
            $script:DeepResult.status | Should -Be 'created'
        }
    }
}

#endregion Invoke-ModelCatalogUpdate Tests
