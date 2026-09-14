param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Escape-XmlText {
    param([string]$Text)

    return [System.Security.SecurityElement]::Escape($Text)
}

function New-ParagraphXml {
    param(
        [string]$Text,
        [string]$Style = 'Normal'
    )

    $escaped = Escape-XmlText $Text
    $preserve = if ($Text.StartsWith(' ') -or $Text.EndsWith(' ')) { ' xml:space="preserve"' } else { '' }
    return "<w:p><w:pPr><w:pStyle w:val=`"$Style`"/></w:pPr><w:r><w:t$preserve>$escaped</w:t></w:r></w:p>"
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutput)

if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("pc-pos-docx-" + [guid]::NewGuid())
$wordDirectory = Join-Path $tempDirectory 'word'
$wordRelsDirectory = Join-Path $wordDirectory '_rels'
$relsDirectory = Join-Path $tempDirectory '_rels'

New-Item -ItemType Directory -Path $wordDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $wordRelsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $relsDirectory -Force | Out-Null

try {
    $paragraphs = [System.Collections.Generic.List[string]]::new()
    $insideCodeBlock = $false

    foreach ($line in [System.IO.File]::ReadAllLines($resolvedInput, [System.Text.Encoding]::UTF8)) {
        if ($line -match '^```') {
            $insideCodeBlock = -not $insideCodeBlock
            continue
        }

        if ($insideCodeBlock) {
            $paragraphs.Add((New-ParagraphXml -Text $line -Style 'Code'))
            continue
        }

        if ($line -match '^(#{1,3})\s+(.+)$') {
            $level = $matches[1].Length
            $paragraphs.Add((New-ParagraphXml -Text $matches[2] -Style "Heading$level"))
            continue
        }

        if ($line -match '^[-*]\s+(.+)$') {
            $paragraphs.Add((New-ParagraphXml -Text ("• " + $matches[1]) -Style 'Normal'))
            continue
        }

        if ($line -match '^\d+\.\s+(.+)$') {
            $paragraphs.Add((New-ParagraphXml -Text $line -Style 'Normal'))
            continue
        }

        if ($line -match '^\|') {
            $paragraphs.Add((New-ParagraphXml -Text $line -Style 'TableText'))
            continue
        }

        $paragraphs.Add((New-ParagraphXml -Text $line -Style 'Normal'))
    }

    $documentXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $($paragraphs -join "`n    ")
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
"@

    $stylesXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr>
    <w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
    <w:pPr><w:keepNext/><w:spacing w:before="300" w:after="160"/></w:pPr>
    <w:rPr><w:b/><w:color w:val="1F4E78"/><w:sz w:val="34"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>
    <w:pPr><w:keepNext/><w:spacing w:before="260" w:after="120"/></w:pPr>
    <w:rPr><w:b/><w:color w:val="2F5597"/><w:sz w:val="28"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>
    <w:pPr><w:keepNext/><w:spacing w:before="220" w:after="100"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Code">
    <w:name w:val="Code"/><w:basedOn w:val="Normal"/>
    <w:pPr><w:ind w:left="360"/><w:shd w:fill="F2F2F2"/><w:spacing w:after="0"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="19"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="TableText">
    <w:name w:val="Table Text"/><w:basedOn w:val="Normal"/>
    <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr>
  </w:style>
</w:styles>
"@

    $contentTypesXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>
"@

    $relationshipsXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"@

    $documentRelationshipsXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"@

    [System.IO.File]::WriteAllText((Join-Path $wordDirectory 'document.xml'), $documentXml, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $wordDirectory 'styles.xml'), $stylesXml, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $tempDirectory '[Content_Types].xml'), $contentTypesXml, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $relsDirectory '.rels'), $relationshipsXml, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $wordRelsDirectory 'document.xml.rels'), $documentRelationshipsXml, [System.Text.UTF8Encoding]::new($false))

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $resolvedOutput) {
        Remove-Item -LiteralPath $resolvedOutput -Force
    }
    $archive = [System.IO.Compression.ZipFile]::Open(
        $resolvedOutput,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        $entries = @{
            '[Content_Types].xml'          = (Join-Path $tempDirectory '[Content_Types].xml')
            '_rels/.rels'                  = (Join-Path $relsDirectory '.rels')
            'word/document.xml'            = (Join-Path $wordDirectory 'document.xml')
            'word/styles.xml'              = (Join-Path $wordDirectory 'styles.xml')
            'word/_rels/document.xml.rels' = (Join-Path $wordRelsDirectory 'document.xml.rels')
        }

        foreach ($entryName in $entries.Keys) {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $entries[$entryName],
                $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
    }
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

Write-Output "Created: $resolvedOutput"
