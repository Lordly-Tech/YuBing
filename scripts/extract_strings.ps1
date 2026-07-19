$sourceDir = "F:\Test-YuBing\apple"
$outputFile = "F:\Test-YuBing\scripts\strings.json"

$chinese = [regex]'[\u4e00-\u9fff]'
$strings = New-Object 'System.Collections.Generic.HashSet[string]'

Get-ChildItem -LiteralPath $sourceDir -Filter "*.swift" -Recurse -File | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return }

    # Text("...")
    [regex]::Matches($content, '(?<=Text\(")[^"]+(?="\))') | ForEach-Object { $null = $strings.Add($_.Value) }

    # Button("...")
    [regex]::Matches($content, '(?<=Button\(")[^"]+(?="\))') | ForEach-Object { $null = $strings.Add($_.Value) }

    # Label("...", ...)
    [regex]::Matches($content, '(?<=Label\(")[^"]+(?=",)') | ForEach-Object { $null = $strings.Add($_.Value) }

    # ContentUnavailableView("...", ...)
    [regex]::Matches($content, '(?<=ContentUnavailableView\(")[^"]+(?=",)') | ForEach-Object { $null = $strings.Add($_.Value) }

    # .navigationTitle("...")
    [regex]::Matches($content, '(?<=navigationTitle\(")[^"]+(?="\))') | ForEach-Object { $null = $strings.Add($_.Value) }

    # .searchable(..., prompt: "...")
    [regex]::Matches($content, 'prompt:\s*"([^"]+)"') | ForEach-Object { $null = $strings.Add($_.Groups[1].Value) }

    # Alert / .alert title: Text("..."), message: Text("...")
    [regex]::Matches($content, '(?<=title:\s*Text\(")[^"]+(?="\))') | ForEach-Object { $null = $strings.Add($_.Value) }
    [regex]::Matches($content, '(?<=message:\s*Text\(")[^"]+(?="\))') | ForEach-Object { $null = $strings.Add($_.Value) }

    # description: Text("...")
    [regex]::Matches($content, '(?<=description:\s*Text\(")[^"]+(?="\))') | ForEach-Object { $null = $strings.Add($_.Value) }
}

$result = $strings | Where-Object { $_ -match $chinese } | Sort-Object

Set-Content -LiteralPath $outputFile -Value ($result | ConvertTo-Json) -Encoding UTF8
