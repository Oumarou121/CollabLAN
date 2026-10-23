# generate-icons.ps1 - regenere les icones de LocaLink depuis le trace
# vectoriel de la marque (le meme que ui/Components/BrandMark.qml).
#
# Tuile papier (#F3EFE6) a filet discret, personne de gauche a l'encre du
# texte (#17161B), personne de droite a l'Encre de la marque (#2F3FCF).
# Produit :
#   resources/win/app.ico                      16 a 256 px (BMP, PNG pour 256 comme avant)
#   resources/mac/app.icns                     16 a 1024 px (PNG)
#   resources/linux/icons/NxN/localink.png     16 a 512 px
#   ui/Assets/logo.png                         256 px (icone de la zone de notification)
#
# Usage (Windows PowerShell 5.1) : powershell -NoProfile -File resources/generate-icons.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;

public static class LocaLinkIcon {
    static readonly Color Paper = Color.FromArgb(0xF3, 0xEF, 0xE6);
    static readonly Color Ink = Color.FromArgb(0x17, 0x16, 0x1B);
    static readonly Color Brand = Color.FromArgb(0x2F, 0x3F, 0xCF);

    static Pen Stroke(Color c, float w) {
        var p = new Pen(c, w);
        p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
        return p;
    }

    // Trace de la marque sur la grille 64 (cf. BrandMark.qml).
    static void DrawMark(Graphics g, Color paper) {
        var circle = new RectangleF(32f - 22.5f, 33.5f - 22.5f, 45f, 45f);
        using (var b = new SolidBrush(Ink)) g.FillEllipse(b, 13.4f - 6.2f, 7.2f - 6.2f, 12.4f, 12.4f);
        using (var b = new SolidBrush(Brand)) g.FillEllipse(b, 50.6f - 6.2f, 7.2f - 6.2f, 12.4f, 12.4f);
        using (var p = Stroke(Ink, 11f)) g.DrawArc(p, circle, 215f, -143f);
        using (var p = Stroke(Ink, 10f)) g.DrawLine(p, 14f, 20.68f, 32f, 39f);
        using (var p = Stroke(paper, 14.4f)) g.DrawArc(p, circle, 325f, 143f);
        using (var p = Stroke(paper, 13.4f)) g.DrawLine(p, 50f, 20.68f, 31.4f, 39.6f);
        using (var p = Stroke(Brand, 11f)) g.DrawArc(p, circle, 325f, 143f);
        using (var p = Stroke(Brand, 10f)) g.DrawLine(p, 50f, 20.68f, 31.4f, 39.6f);
    }

    static GraphicsPath RoundRect(float x, float y, float w, float h, float r) {
        var gp = new GraphicsPath();
        float d = r * 2;
        gp.AddArc(x, y, d, d, 180, 90);
        gp.AddArc(x + w - d, y, d, d, 270, 90);
        gp.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        gp.AddArc(x, y + h - d, d, d, 90, 90);
        gp.CloseFigure();
        return gp;
    }

    // Rendu sur-echantillonne puis reduit, pour des bords nets aux petites tailles.
    public static Bitmap Render(int size) {
        int big = Math.Max(size * 8, 512);
        using (var hi = new Bitmap(big, big, PixelFormat.Format32bppArgb)) {
            using (var g = Graphics.FromImage(hi)) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.Clear(Color.Transparent);
                g.ScaleTransform(big / 64f, big / 64f);
                using (var tile = RoundRect(0.5f, 0.5f, 63f, 63f, 14f)) {
                    using (var b = new SolidBrush(Paper)) g.FillPath(b, tile);
                    using (var p = new Pen(Color.FromArgb(46, Ink), 1f)) g.DrawPath(p, tile);
                }
                g.TranslateTransform(9.6f, 9.6f);
                g.ScaleTransform(0.7f, 0.7f);
                DrawMark(g, Paper);
            }
            var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp)) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;
                g.Clear(Color.Transparent);
                g.DrawImage(hi, new Rectangle(0, 0, size, size));
            }
            return bmp;
        }
    }

    static byte[] Png(Bitmap b) {
        using (var ms = new MemoryStream()) { b.Save(ms, ImageFormat.Png); return ms.ToArray(); }
    }

    // DIB 32 bits (BGRA, de bas en haut) + masque AND vide : entree .ico classique.
    static byte[] Dib(Bitmap b) {
        int w = b.Width, h = b.Height;
        int maskStride = ((w + 31) / 32) * 4;
        using (var ms = new MemoryStream())
        using (var bw = new BinaryWriter(ms)) {
            bw.Write(40); bw.Write(w); bw.Write(h * 2); bw.Write((short)1); bw.Write((short)32);
            bw.Write(0); bw.Write(w * h * 4 + maskStride * h); bw.Write(0); bw.Write(0); bw.Write(0); bw.Write(0);
            for (int y = h - 1; y >= 0; y--)
                for (int x = 0; x < w; x++) {
                    var c = b.GetPixel(x, y);
                    bw.Write(c.B); bw.Write(c.G); bw.Write(c.R); bw.Write(c.A);
                }
            bw.Write(new byte[maskStride * h]);
            return ms.ToArray();
        }
    }

    public static void WriteIco(string path, int[] sizes) {
        var images = new List<byte[]>();
        foreach (var s in sizes) using (var b = Render(s)) images.Add(s < 256 ? Dib(b) : Png(b));
        using (var fs = File.Create(path))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write((short)0); bw.Write((short)1); bw.Write((short)sizes.Length);
            int offset = 6 + 16 * sizes.Length;
            for (int i = 0; i < sizes.Length; i++) {
                int s = sizes[i];
                bw.Write((byte)(s >= 256 ? 0 : s)); bw.Write((byte)(s >= 256 ? 0 : s));
                bw.Write((byte)0); bw.Write((byte)0); bw.Write((short)1); bw.Write((short)32);
                bw.Write(images[i].Length); bw.Write(offset);
                offset += images[i].Length;
            }
            foreach (var img in images) bw.Write(img);
        }
    }

    static void BE(BinaryWriter bw, int v) { bw.Write((byte)(v >> 24)); bw.Write((byte)(v >> 16)); bw.Write((byte)(v >> 8)); bw.Write((byte)v); }

    public static void WriteIcns(string path) {
        var types = new string[] { "icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10", "ic11", "ic12", "ic13", "ic14" };
        var sizes = new int[] { 16, 32, 64, 128, 256, 512, 1024, 32, 64, 256, 512 };
        var entries = new List<byte[]>();
        foreach (var s in sizes) using (var b = Render(s)) entries.Add(Png(b));
        int total = 8;
        foreach (var e in entries) total += 8 + e.Length;
        using (var fs = File.Create(path))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write(System.Text.Encoding.ASCII.GetBytes("icns")); BE(bw, total);
            for (int i = 0; i < types.Length; i++) {
                bw.Write(System.Text.Encoding.ASCII.GetBytes(types[i])); BE(bw, 8 + entries[i].Length); bw.Write(entries[i]);
            }
        }
    }

    public static void WritePng(string path, int size) {
        using (var b = Render(size)) b.Save(path, ImageFormat.Png);
    }
}
'@

[LocaLinkIcon]::WriteIco((Join-Path $root 'resources/win/app.ico'), [int[]](16, 20, 24, 32, 40, 48, 64, 128, 256))
[LocaLinkIcon]::WriteIcns((Join-Path $root 'resources/mac/app.icns'))
foreach ($s in 16, 24, 32, 48, 64, 128, 256, 512) {
    [LocaLinkIcon]::WritePng((Join-Path $root "resources/linux/icons/${s}x${s}/localink.png"), $s)
}
[LocaLinkIcon]::WritePng((Join-Path $root 'ui/Assets/logo.png'), 256)
Write-Output 'Icones regenerees.'
