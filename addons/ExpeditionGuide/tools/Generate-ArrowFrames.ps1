param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\assets\arrow'),
    [int]$FrameCount = 32,
    [int]$Size = 192
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $resolvedOutput)) {
    [System.IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null
}

function New-ArrowPath {
    param([float]$OffsetX, [float]$OffsetY)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $points = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(96 + $OffsetX, 10 + $OffsetY),
        [System.Drawing.PointF]::new(178 + $OffsetX, 105 + $OffsetY),
        [System.Drawing.PointF]::new(126 + $OffsetX, 92 + $OffsetY),
        [System.Drawing.PointF]::new(126 + $OffsetX, 159 + $OffsetY),
        [System.Drawing.PointF]::new(66 + $OffsetX, 159 + $OffsetY),
        [System.Drawing.PointF]::new(66 + $OffsetX, 92 + $OffsetY),
        [System.Drawing.PointF]::new(14 + $OffsetX, 105 + $OffsetY)
    )
    $path.AddPolygon($points)
    return $path
}

for ($frame = 0; $frame -lt $FrameCount; $frame++) {
    $bitmap = [System.Drawing.Bitmap]::new(
        $Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode =
        [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.TranslateTransform($Size / 2, $Size / 2)
    $graphics.RotateTransform(360.0 * $frame / $FrameCount)
    $graphics.TranslateTransform(-96, -96)

    $shadowPath = New-ArrowPath 4 10
    $shadowBrush = [System.Drawing.SolidBrush]::new(
        [System.Drawing.Color]::FromArgb(110, 0, 0, 0))
    $graphics.FillPath($shadowBrush, $shadowPath)

    $depthPath = New-ArrowPath 0 7
    $depthBrush = [System.Drawing.SolidBrush]::new(
        [System.Drawing.Color]::FromArgb(255, 93, 45, 0))
    $depthPen = [System.Drawing.Pen]::new(
        [System.Drawing.Color]::FromArgb(255, 36, 18, 0), 4)
    $graphics.FillPath($depthBrush, $depthPath)
    $graphics.DrawPath($depthPen, $depthPath)

    $facePath = New-ArrowPath 0 0
    $faceBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.RectangleF]::new(10, 8, 170, 154),
        [System.Drawing.Color]::FromArgb(255, 255, 252, 170),
        [System.Drawing.Color]::FromArgb(255, 245, 143, 16),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $outlinePen = [System.Drawing.Pen]::new(
        [System.Drawing.Color]::FromArgb(255, 255, 228, 92), 4)
    $graphics.FillPath($faceBrush, $facePath)
    $graphics.DrawPath($outlinePen, $facePath)

    $highlightPen = [System.Drawing.Pen]::new(
        [System.Drawing.Color]::FromArgb(210, 255, 255, 236), 3)
    $graphics.DrawLine($highlightPen, 96, 18, 27, 98)
    $graphics.DrawLine($highlightPen, 96, 18, 165, 98)

    $path = Join-Path $resolvedOutput ('arrow_{0:D2}.png' -f $frame)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

    $highlightPen.Dispose()
    $outlinePen.Dispose()
    $faceBrush.Dispose()
    $depthPen.Dispose()
    $depthBrush.Dispose()
    $shadowBrush.Dispose()
    $facePath.Dispose()
    $depthPath.Dispose()
    $shadowPath.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

Write-Output ("Generated {0} arrow frames in {1}" -f $FrameCount, $resolvedOutput)
