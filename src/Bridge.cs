using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Diagnostics;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Drawing;
using System.Linq;

class Bridge : ApplicationContext {
    const int Port=18100;
    readonly string root=AppDomain.CurrentDomain.BaseDirectory;
    readonly string data=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Lbp810Bridge");
    readonly string jobs;
    readonly bool dry;
    readonly NotifyIcon icon;
    volatile bool stop;
    volatile bool busy;
    TcpListener listener;
    static readonly object logLock=new object();
    public Bridge(bool dryRun) {
        dry=dryRun; jobs=Path.Combine(data,"jobs"); Directory.CreateDirectory(jobs);
        var menu=new ContextMenuStrip();
        menu.Items.Add("Open job logs",null,delegate { Process.Start("explorer.exe",jobs); });
        menu.Items.Add("USB diagnostic",null,delegate { Process.Start(new ProcessStartInfo(Path.Combine(root,"Diagnose.cmd")){UseShellExecute=true}); });
        menu.Items.Add("Exit (pauses document printing)",null,delegate { ExitThread(); });
        icon=new NotifyIcon { Icon=SystemIcons.Application,Text=dry?"Canon LBP-810: TEST MODE":"Canon LBP-810 USB bridge",ContextMenuStrip=menu,Visible=true };
        icon.DoubleClick+=delegate { Process.Start("explorer.exe",jobs); };
        listener=new TcpListener(IPAddress.Loopback,Port); listener.Start();
        Log("Bridge 0.3 started on 127.0.0.1:"+Port+" DryRun="+dry);
        foreach(var dir in Directory.GetDirectories(jobs)) {
            string state=Path.Combine(dir,"state.txt");
            if(File.Exists(state) && File.ReadAllText(state)=="printing") File.WriteAllText(state,"interrupted - may have printed some pages; no automatic retry");
        }
        new Thread(AcceptLoop){IsBackground=true}.Start();
        new Thread(Worker){IsBackground=true}.Start();
    }
    void Log(string value) {
        lock(logLock) File.AppendAllText(Path.Combine(data,"bridge.log"),DateTime.Now.ToString("s")+" "+value+Environment.NewLine);
    }
    void AcceptLoop() {
        while(!stop) try {
            using(var client=listener.AcceptTcpClient()) {
                client.ReceiveTimeout=60000;
                string dir=Path.Combine(jobs,DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff")+"-"+Guid.NewGuid().ToString("N").Substring(0,8));
                Directory.CreateDirectory(dir);
                string receiving=Path.Combine(dir,"receiving.tmp"); long total=0;
                try {
                    using(var output=new FileStream(receiving,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                        var stream=client.GetStream(); byte[] buffer=new byte[65536]; int n;
                        while((n=stream.Read(buffer,0,buffer.Length))>0) {
                            total+=n; if(total>100L*1024*1024) throw new IOException("Job exceeds 100 MB");
                            output.Write(buffer,0,n);
                        }
                    }
                    if(total==0) { File.Delete(receiving); Directory.Delete(dir); continue; }
                    ValidatePdf(receiving);
                    File.Move(receiving,Path.Combine(dir,"document.pdf"));
                    File.WriteAllText(Path.Combine(dir,"state.txt"),"ready");
                    Log("Received "+total+" bytes: "+Path.GetFileName(dir));
                } catch(Exception e) {
                    File.WriteAllText(Path.Combine(dir,"state.txt"),"receive failed: "+e.Message); Log("Receive failed: "+e.Message);
                }
            }
        } catch(Exception e) { if(!stop) { Log("Listener: "+e.Message); Thread.Sleep(1000); } }
    }
    static void ValidatePdf(string path) {
        using(var f=File.OpenRead(path)) {
            byte[] head=new byte[5]; if(f.Read(head,0,5)!=5 || Encoding.ASCII.GetString(head)!="%PDF-") throw new IOException("Expected a PDF job; check the queue uses Microsoft Print To PDF");
            f.Position=Math.Max(0,f.Length-4096); byte[] tail=new byte[(int)(f.Length-f.Position)]; f.Read(tail,0,tail.Length);
            if(!Encoding.ASCII.GetString(tail).Contains("%%EOF")) throw new IOException("Incomplete PDF: missing EOF");
        }
    }
    void Worker() {
        while(!stop) {
            try {
                foreach(var dir in Directory.GetDirectories(jobs).OrderBy(x=>x)) {
                    if(stop) break;
                    string state=Path.Combine(dir,"state.txt");
                    if(!File.Exists(state) || File.ReadAllText(state)!="ready") continue;
                    File.WriteAllText(state,"printing");
                    busy=true;
                    try {
                        string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"System32\WindowsPowerShell\v1.0\powershell.exe");
                        string args="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+Path.Combine(root,"Render-Job.ps1")+"\" -Pdf \""+Path.Combine(dir,"document.pdf")+"\" -JobDir \""+dir+"\""+(dry?" -DryRun":"");
                        var info=new ProcessStartInfo(ps,args){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
                        using(var proc=new Process {StartInfo=info}) using(var log=new StreamWriter(Path.Combine(dir,"print.log"),true)) {
                            object gate=new object();
                            proc.OutputDataReceived+=delegate(object s,DataReceivedEventArgs e) { if(e.Data!=null) lock(gate) { log.WriteLine(e.Data); log.Flush(); } };
                            proc.ErrorDataReceived+=delegate(object s,DataReceivedEventArgs e) { if(e.Data!=null) lock(gate) { log.WriteLine(e.Data); log.Flush(); } };
                            proc.Start(); proc.BeginOutputReadLine(); proc.BeginErrorReadLine();
                            // A long document may take time. Each USB page and PDF operation has its own timeout.
                            proc.WaitForExit();
                            if(proc.ExitCode!=0) throw new IOException("Rendering/printing failed; see print.log. Do not retry blindly: some pages may have printed.");
                        }
                        File.WriteAllText(state,dry?"dry-run completed (no USB output)":"completed");
                        if(!dry) File.Delete(Path.Combine(dir,"document.pdf"));
                        Log("Completed: "+Path.GetFileName(dir));
                    } catch(Exception e) { File.WriteAllText(state,"failed: "+e.Message); Log("Job failed: "+e.Message); }
                    finally { busy=false; }
                }
            } catch(Exception e) { Log("Worker: "+e.Message); }
            Thread.Sleep(1000);
        }
    }
    protected override void ExitThreadCore() {
        if(busy) { MessageBox.Show("A job is being processed. Wait until it finishes before exiting.","Canon LBP-810"); return; }
        stop=true; listener.Stop(); icon.Visible=false; icon.Dispose(); base.ExitThreadCore();
    }
    [STAThread] static void Main(string[] args) {
        bool created;
        using(var single=new Mutex(true,@"Local\Lbp810Bridge-18100",out created)) {
            if(!created) { MessageBox.Show("Canon LBP-810 bridge is already running."); return; }
            try { Application.EnableVisualStyles(); Application.Run(new Bridge(Array.IndexOf(args,"--dry-run")>=0)); }
            catch(Exception e) { MessageBox.Show(e.ToString(),"Canon LBP-810 bridge"); }
        }
    }
}
