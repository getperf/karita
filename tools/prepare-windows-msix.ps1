# msix 3.18 generates a LockScreen declaration using a colored logo as a badge.
# karita has no lock-screen/badge feature; do not declare that unused integration.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $repoRoot 'apps/karita/build/windows/x64/runner/Release/AppxManifest.xml'
$document = [xml]::new()
$document.PreserveWhitespace = $true
$document.Load($manifestPath)
$namespace = [Xml.XmlNamespaceManager]::new($document.NameTable)
$namespace.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')
foreach ($node in @($document.SelectNodes('//uap:VisualElements/uap:LockScreen', $namespace))) {
    $node.ParentNode.RemoveChild($node) | Out-Null
}
$document.Save($manifestPath)
Write-Output 'Removed unused LockScreen declaration from generated manifest.'
