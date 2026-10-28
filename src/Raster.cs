using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
public static class Raster {
    public static void Convert(string png,string pbm) {
        const int W=4960,H=7014;
        using(var source=new Bitmap(png)) using(var bitmap=new Bitmap(W,H,PixelFormat.Format24bppRgb)) {
            using(var g=Graphics.FromImage(bitmap)) {
                g.Clear(Color.White);
                double scale=Math.Min((double)W/source.Width,(double)H/source.Height);
                int w=(int)Math.Round(source.Width*scale),h=(int)Math.Round(source.Height*scale);
                g.DrawImage(source,new Rectangle((W-w)/2,(H-h)/2,w,h));
            }
            var bits=bitmap.LockBits(new Rectangle(0,0,W,H),ImageLockMode.ReadOnly,PixelFormat.Format24bppRgb);
            try {
                byte[] row=new byte[Math.Abs(bits.Stride)], packed=new byte[W/8];
                double[] current=new double[W+2],next=new double[W+2];
                using(var f=new FileStream(pbm,FileMode.Create,FileAccess.Write)) {
                    byte[] header=System.Text.Encoding.ASCII.GetBytes("P4\n4960 7014\n"); f.Write(header,0,header.Length);
                    for(int y=0;y<H;y++) {
                        Marshal.Copy(IntPtr.Add(bits.Scan0,y*bits.Stride),row,0,row.Length);
                        Array.Clear(packed,0,packed.Length); Array.Clear(next,0,next.Length);
                        for(int x=0;x<W;x++) {
                            double value=(row[x*3]*29+row[x*3+1]*150+row[x*3+2]*77)/256.0+current[x+1];
                            bool black=value<128;
                            if(black) packed[x/8]|=(byte)(128>>(x%8));
                            double error=value-(black?0:255);
                            current[x+2]+=error*7/16; next[x]+=error*3/16; next[x+1]+=error*5/16; next[x+2]+=error/16;
                        }
                        f.Write(packed,0,packed.Length); var swap=current;current=next;next=swap;
                    }
                }
            } finally { bitmap.UnlockBits(bits); }
        }
    }
}
