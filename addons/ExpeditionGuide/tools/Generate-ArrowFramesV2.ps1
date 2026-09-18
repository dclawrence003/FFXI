param(
    [string]$Source = (Join-Path $PSScriptRoot '..\assets\arrow\arrow_base_v2.png'),
    [string]$Destination = (Join-Path $PSScriptRoot '..\assets\arrow'),
    [int]$FrameCount = 32
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sourcePath = [IO.Path]::GetFullPath($Source)
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (-not [IO.File]::Exists($sourcePath)) { throw "Missing source: $sourcePath" }
if ($FrameCount -lt 8 -or $FrameCount -gt 128) { throw 'FrameCount must be 8-128.' }
[IO.Directory]::CreateDirectory($destinationPath) | Out-Null

$sourceImage = [Drawing.Bitmap]::new($sourcePath)
try {
    for ($index = 0; $index -lt $FrameCount; $index++) {
        $frame = [Drawing.Bitmap]::new(
            $sourceImage.Width, $sourceImage.Height,
            [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($frame)
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceOver
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.TranslateTransform($frame.Width / 2, $frame.Height / 2)
                $graphics.RotateTransform([single](360 * $index / $FrameCount))
                $graphics.TranslateTransform(-$frame.Width / 2, -$frame.Height / 2)
                $graphics.DrawImage($sourceImage, 0, 0)
            } finally {
                $graphics.Dispose()
            }
            $output = Join-Path $destinationPath ('arrow_v2_{0:D2}.png' -f $index)
            $frame.Save($output, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $frame.Dispose()
        }
    }
} finally {
    $sourceImage.Dispose()
}

Write-Host "Generated $FrameCount arrow_v2 frames in $destinationPath"
