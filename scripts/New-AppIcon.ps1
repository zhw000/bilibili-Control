$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$iconTarget = Join-Path $PSScriptRoot '..\ios\BiliRemote\Assets.xcassets\AppIcon.appiconset\AppIcon.png'
$bitmap = New-Object System.Drawing.Bitmap 1024,1024
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(235,87,125))
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$pink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235,87,125))
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(180,245,110,110,180,90)
$path.AddArc(734,245,110,110,270,90)
$path.AddArc(734,655,110,110,0,90)
$path.AddArc(180,655,110,110,90,90)
$path.CloseFigure()
$graphics.FillPath($white,$path)
$graphics.FillRectangle($pink,224,290,575,432)
$triangle = [System.Drawing.PointF[]]@([System.Drawing.PointF]::new(438,381),[System.Drawing.PointF]::new(438,631),[System.Drawing.PointF]::new(641,506))
$graphics.FillPolygon($white,$triangle)
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White),37
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$graphics.DrawLine($pen,383,155,449,238)
$graphics.DrawLine($pen,641,155,575,238)
$graphics.FillEllipse($white,452,826,120,38)
$bitmap.Save($iconTarget,[System.Drawing.Imaging.ImageFormat]::Png)
# Package the same artwork at common Windows taskbar, tray and Explorer sizes.
$windowsTarget = Join-Path $PSScriptRoot '..\desktop\BiliRemote.Host\Assets\AppIcon.ico'
New-Item -ItemType Directory -Force (Split-Path $windowsTarget) | Out-Null
$sizes = @(16,20,24,32,40,48,64,128,256)
$images = foreach ($size in $sizes) {
    $small = New-Object System.Drawing.Bitmap $size,$size
    $canvas = [System.Drawing.Graphics]::FromImage($small)
    $canvas.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $canvas.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $canvas.DrawImage($bitmap,0,0,$size,$size)
    $memory = New-Object System.IO.MemoryStream
    $small.Save($memory,[System.Drawing.Imaging.ImageFormat]::Png)
    ,$memory.ToArray()
    $memory.Dispose(); $canvas.Dispose(); $small.Dispose()
}
$file = [System.IO.File]::Create($windowsTarget)
$writer = New-Object System.IO.BinaryWriter $file
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
} finally { $writer.Dispose() }
$pen.Dispose(); $path.Dispose(); $white.Dispose(); $pink.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
Write-Output "Created app icon: $iconTarget"
Write-Output "Created Windows icon: $windowsTarget"
