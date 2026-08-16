# סקריפט בדיקה - להריץ במחשב שבו מחוברת המדפסת הפיזית (במשרד).
# מטרה: לגלות אם הדרייבר תומך ב-Print Schema המלא (חוברת/הידוק/כריכה)
# או רק ב-DEVMODE הבסיסי (מה שה-HTA הישן היה מוגבל אליו).
#
# הרצה: לחיצה כפולה על probe-printer.bat (או ידנית:
#   powershell -ExecutionPolicy Bypass -File probe-printer.ps1)
#
# הפלט: קובץ ZIP אחד על שולחן העבודה (PrinterProbe_<תאריך-שעה>.zip) עם
# לוג הריצה המלא + קובץ XML לכל מדפסת - קובץ יחיד, נוח לשלוח (וואטסאפ
# וכו', לא מייל). אין תלות ב-git/GitHub/שום הרשאה.

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $PSScriptRoot "probe-log_$stamp.txt"
Start-Transcript -Path $logFile -NoClobber | Out-Null

Add-Type -AssemblyName System.Printing
Import-Module PrintManagement -ErrorAction SilentlyContinue

$printers = Get-Printer | Select-Object Name, DriverName, PortName

Write-Host "=== מדפסות מותקנות ===" -ForegroundColor Cyan
$printers | Format-Table -AutoSize

$server = New-Object System.Printing.PrintServer

foreach ($p in $printers) {
    $safeName = ($p.Name -replace '[\\/:*?"<>|]', '_')
    $outFile = Join-Path $PSScriptRoot "capabilities_$safeName.xml"
    try {
        $queue = $server.GetPrintQueue($p.Name)
        $stream = $queue.GetPrintCapabilitiesAsXml()
        $reader = New-Object System.IO.StreamReader($stream)
        $xmlText = $reader.ReadToEnd()
        $reader.Close()
        $xmlText | Out-File -FilePath $outFile -Encoding utf8
        Write-Host "נשמר: $outFile" -ForegroundColor Green

        $xml = [xml]$xmlText
        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("psf", "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework")
        $ns.AddNamespace("psk", "http://schemas.microsoft.com/windows/2003/08/printing/printschemakeywords")

        $bookletSupport = $xml.SelectNodes("//psf:Feature[contains(@name,'Booklet')]", $ns)
        $stapleSupport  = $xml.SelectNodes("//psf:Feature[contains(@name,'Staple') or contains(@name,'Finishing')]", $ns)

        Write-Host ("  תמיכה בחוברת (Booklet): {0}" -f ($(if ($bookletSupport.Count -gt 0) {"כן"} else {"לא נמצא"})))
        Write-Host ("  תמיכה בהידוק (Staple): {0}" -f ($(if ($stapleSupport.Count -gt 0) {"כן"} else {"לא נמצא"})))
    } catch {
        Write-Host "שגיאה עבור $($p.Name): $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  (כנראה דרייבר v3 ישן שלא תומך ב-Print Schema המלא - נצטרך גישה אחרת)"
    }
}

Stop-Transcript | Out-Null

# אריזה לקובץ יחיד נוח לשליחה (וואטסאפ/דיסק-און-קי וכו' - לא מייל) -
# הלוג המלא + כל קבצי ה-XML, בלי תלות ב-git/GitHub/שום הרשאה.
try {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $zipPath = Join-Path $desktop "PrinterProbe_$stamp.zip"
    $filesToZip = @($logFile) + (Get-ChildItem -Path $PSScriptRoot -Filter "capabilities_*.xml" | Select-Object -ExpandProperty FullName)
    Compress-Archive -Path $filesToZip -DestinationPath $zipPath -Force
    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Yellow
    Write-Host "הכל ארוז לקובץ אחד, על שולחן העבודה:" -ForegroundColor Yellow
    Write-Host "  $zipPath" -ForegroundColor Yellow
    Write-Host "שלחו את הקובץ הזה בחזרה (וואטסאפ למשל - לא מייל) - זהו." -ForegroundColor Yellow
    Write-Host "=====================================================" -ForegroundColor Yellow
} catch {
    Write-Host ("שגיאה באריזת התוצאות ל-ZIP: " + $_.Exception.Message) -ForegroundColor Red
}
