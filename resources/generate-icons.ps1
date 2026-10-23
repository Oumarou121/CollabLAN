# generate-icons.ps1 - regenere les icones de LocaLink depuis le trace
# vectoriel de la marque (le meme que ui/Components/BrandMark.qml).
#
# Tuile papier (#F3EFE6) a filet discret ; trois postes, cercle interrompu
# et rayons a l'encre du texte (#17161B), serveur central a l'Encre de la
# marque (#2F3FCF). Les
# traits s'epaississent aux petites tailles pour rester lisibles.
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

    static Pen Flat(Color c, float w) {
        var p = new Pen(c, w);
        p.StartCap = LineCap.Flat; p.EndCap = LineCap.Flat; p.LineJoin = LineJoin.Round;
        return p;
    }

    // Trace de la marque sur la grille 64 (cf. BrandMark.qml), w = epaississement.
    // Cercle commun : centre (32.05, 35.62), rayon 22.31 ; angles en degres, sens horaire.
    static void DrawMark(Graphics g, float w) {
        var circle = new RectangleF(32.05f - 22.31f, 35.62f - 22.31f, 44.62f, 44.62f);
        using (var p = Flat(Ink, 2.8f * w)) {
            g.DrawArc(p, circle, 236.5f, -63.8f);
            g.DrawArc(p, circle, 303.5f, 63.8f);
            g.DrawArc(p, circle, 123.8f, -67.6f);
        }
        using (var p = Stroke(Ink, 2.64f * w)) {
            using (var r = RoundRect(23.95f, 5.79f, 16.19f, 11.48f, 1.04f)) g.DrawPath(p, r);
            using (var r = RoundRect(3.06f, 42.02f, 14.4f, 10.83f, 1.04f)) g.DrawPath(p, r);
            using (var r = RoundRect(46.64f, 42.02f, 14.3f, 10.83f, 1.04f)) g.DrawPath(p, r);
        }
        using (var b = new SolidBrush(Ink)) {
            g.FillRectangle(b, 30.64f, 18.2f, 3.38f, 2.4f);
            g.FillRectangle(b, 8.52f, 53.9f, 2.63f, 1.9f);
            g.FillRectangle(b, 52.94f, 53.9f, 2.64f, 1.9f);
        }
        using (var p = Stroke(Ink, 2.35f * w)) {
            g.DrawLine(p, 29.32f, 20.75f, 34.68f, 20.75f);
            g.DrawLine(p, 7.67f, 56.42f, 12.94f, 56.42f);
            g.DrawLine(p, 51.15f, 56.42f, 56.42f, 56.42f);
        }
        using (var p = Flat(Ink, 2.4f * w)) {
            g.DrawLine(p, 32.05f, 23.29f, 32.05f, 28f);
            g.DrawLine(p, 23.11f, 37.98f, 20.09f, 42.02f);
            g.DrawLine(p, 40.99f, 37.98f, 44f, 42.02f);
        }
        using (var b = new SolidBrush(Brand))
        using (var r = RoundRect(24.61f, 29.41f, 14.87f, 14.97f, 2.35f)) g.FillPath(b, r);
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
                g.TranslateTransform(6.4f, 6.4f);
                g.ScaleTransform(0.8f, 0.8f);
                DrawMark(g, size <= 16 ? 1.9f : size <= 24 ? 1.6f : size <= 32 ? 1.35f : size <= 48 ? 1.15f : 1f);
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
