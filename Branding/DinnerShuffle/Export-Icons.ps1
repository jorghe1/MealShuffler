param([string]$Source = (Join-Path $PSScriptRoot 'Logo-Master.png'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($Source)
try {
    foreach ($size in @(1024, 180, 60, 32)) {
        $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($image, 0, 0, $size, $size)
            $bitmap.Save((Join-Path $PSScriptRoot "Icon-$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
} finally { $image.Dispose() }
