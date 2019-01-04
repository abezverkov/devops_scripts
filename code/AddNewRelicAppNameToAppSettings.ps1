#dir *.config | .\AddNewRelicAppNameToAppSettings.ps1
[CmdletBinding()]
param (
    [Parameter(ValueFromPipeline=$true,Mandatory=$true)]
    $FileName,

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf=$true
)

Begin {

    function Format-XML ([xml]$xml, $indent=2)
    {
        $StringWriter = New-Object System.IO.StringWriter
        $settings = New-Object System.XMl.XmlWriterSettings
        #$settings.Formatting = “indented”
        $settings.Indent = $true
        $XmlWriter = [System.XMl.XmlTextWriter]::Create($StringWriter,$settings)
        $xml.WriteContentTo($XmlWriter)
        $XmlWriter.Flush()
        $StringWriter.Flush()
        $output = $StringWriter.ToString()
        #Write-Host $output
        return $output
    }

    function Get-MyContent ()
    {
        param (
            [Parameter(Mandatory=$True,Position=1,ValueFromPipeline)]
            $filePath
        )

        return Get-Content $filePath -Raw -Encoding UTF8
    }

    function Set-MyContent ()
    {
        param (
            [Parameter(Mandatory=$True,Position=1)]
            $filePath,
            [Parameter(Mandatory=$True,Position=2,ValueFromPipeline)]
            $fileContent
        )
       [byte[]]$bom = @(0xEF,0xBB,0xBF)
       [byte[]]$bf = Get-Content $filePath -Encoding Byte -TotalCount 3
       if ((Compare-Object $bom $bf -SyncWindow 0).Count -eq 0)
       {
           $encoding = New-Object System.Text.UTF8Encoding $true
       }
       else
       {
           $encoding = New-Object System.Text.UTF8Encoding $false
       }

        #$fileContent | Set-Content $filePath -Encoding UTF8
        $filePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($filePath)
        [IO.File]::WriteAllText($filePath, $fileContent, $encoding)
    }

    function AppendNode([System.Xml.XmlElement]$parentnode, $name, $innertext){
        $xml = $parentnode.OwnerDocument;
        $c = $xml.CreateElement($name, $parentnode.NamespaceURI);
        if ($innertext -ne $null) {
            $c.InnerXml = $innertext;
        }
        $parentnode.AppendChild($c) | Out-Null
        return [System.Xml.XmlElement]$c
    }

}

Process {
    $appSetting = Get-Item $FileName
    $xml = New-Object xml
    $xml.PreserveWhitespace = $true
    $xml.LoadXml(($appSetting | Get-MyContent))
    
    if ($xml.appSettings.Count -eq  0) {
        Write-Host ('No appSettings section found in: {0}' -f $appSetting.FullName) -ForegroundColor Red
    }
    elseif (! ($xml.appSettings.add | where key -eq 'NewRelic.AppName')) {
        Write-Host "Updating $appSetting"
        $namespace = $xml.appSettings.NamespaceURI;
        $relicNode = $xml.CreateElement('add', $xml.Project.NamespaceURI);
        $relicNode.SetAttribute('key','NewRelic.AppName');
        $relicNode.SetAttribute('value','Set.By.Octopus');
        $xml.appSettings.AppendChild($xml.CreateWhitespace("  ")) | Out-Null
        $xml.appSettings.AppendChild($relicNode) | Out-Null
        $xml.appSettings.AppendChild($xml.CreateWhitespace("`r`n")) | Out-Null
    }
    if (-not($WhatIf)) {
        Set-MyContent $appSetting (Format-Xml $xml)
    }
    #break;
}

End {
}