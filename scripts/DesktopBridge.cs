using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;

public sealed class CampusCredentialServer : IDisposable {
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint pid);
    readonly NamedPipeServerStream pipe;
    readonly Task waiting;
    public CampusCredentialServer(string name) {
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
        pipe = new NamedPipeServerStream(name, PipeDirection.Out, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 4096, 4096, security);
        waiting = pipe.WaitForConnectionAsync();
    }
    public bool Connected { get { return waiting.IsCompleted && !waiting.IsFaulted && !waiting.IsCanceled; } }
    public void Send(int expectedPid, string username, string password) {
        uint actual;
        if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out actual) || actual != expectedPid)
            throw new InvalidOperationException("Credential pipe client identity mismatch.");
        Validate(username, password);
        using (var writer = new BinaryWriter(pipe, new UTF8Encoding(false), true)) {
            writer.Write(username); writer.Write(password); writer.Flush();
        }
    }
    public static void Validate(string username, string password) {
        if (String.IsNullOrWhiteSpace(username) || username.Length > 128 || username.IndexOfAny(new char[]{'\r','\n','\0'}) >= 0)
            throw new ArgumentException("Enter a valid campus username.");
        if (String.IsNullOrEmpty(password) || password.Length > 4096 || password.IndexOfAny(new char[]{'\r','\n','\0'}) >= 0)
            throw new ArgumentException("Enter a valid campus password.");
    }
    public void Dispose() { pipe.Dispose(); }
}

public static class CampusCredentialClient {
    public static Task<string[]> ReceiveAsync(string name, int expectedServerPid) {
        return Task.Run(() => Receive(name, expectedServerPid));
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetNamedPipeServerProcessId(IntPtr pipe, out uint pid);
    public static string[] Receive(string name, int expectedServerPid) {
        using (var pipe = new NamedPipeClientStream(".", name, PipeDirection.In, PipeOptions.Asynchronous)) {
            pipe.Connect(45000);
            uint actual;
            if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out actual) || actual != expectedServerPid)
                throw new InvalidOperationException("Credential pipe server identity mismatch.");
            var read = Task.Run(() => {
                using (var reader = new BinaryReader(pipe, new UTF8Encoding(false), true)) {
                    string username = reader.ReadString();
                    string password = reader.ReadString();
                    CampusCredentialServer.Validate(username, password);
                    return new string[]{username, password};
                }
            });
            if (!read.Wait(45000)) throw new TimeoutException("Credential handoff timed out.");
            return read.Result;
        }
    }
}

public sealed class CampusBackgroundProcess : IDisposable {
    static readonly object startLock = new object();
    public readonly Process Process;
    readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
    string secret;
    public CampusBackgroundProcess(string binary, string arguments, string password) {
        secret=password;
        Process = new Process();
        Process.StartInfo = new ProcessStartInfo(binary, arguments) {
            WorkingDirectory=Path.GetDirectoryName(binary), UseShellExecute=false, CreateNoWindow=true,
            RedirectStandardInput=true, RedirectStandardOutput=true, RedirectStandardError=true,
            StandardOutputEncoding=new UTF8Encoding(false), StandardErrorEncoding=new UTF8Encoding(false)
        };
        Process.OutputDataReceived += OnLine; Process.ErrorDataReceived += OnLine;
        try {
            StartWithoutInputPreamble(); Process.BeginOutputReadLine(); Process.BeginErrorReadLine();
            byte[] input = new UTF8Encoding(false).GetBytes(password + "\n");
            try { Process.StandardInput.BaseStream.Write(input, 0, input.Length); Process.StandardInput.BaseStream.Flush(); }
            finally { Array.Clear(input, 0, input.Length); Process.StandardInput.Close(); }
        } catch {
            try { if (!Process.HasExited) Process.Kill(); } catch { }
            Process.Dispose(); secret=null; throw;
        }
    }
    void StartWithoutInputPreamble() {
        lock (startLock) {
            // Modern .NET supports an explicit stdin encoding. Windows PowerShell's
            // .NET Framework instead creates an auto-flushing writer using Console.InputEncoding,
            // which can write a BOM before we write our UTF-8 password bytes.
            var inputEncodingProperty = typeof(ProcessStartInfo).GetProperty("StandardInputEncoding");
            if (inputEncodingProperty != null) {
                inputEncodingProperty.SetValue(Process.StartInfo, new UTF8Encoding(false), null);
                Process.Start();
                return;
            }
            var previousEncoding = Console.InputEncoding;
            if (previousEncoding.GetPreamble().Length == 0) {
                Process.Start();
                return;
            }
            try {
                Console.InputEncoding = new UTF8Encoding(false);
                Process.Start();
            } finally {
                Console.InputEncoding = previousEncoding;
            }
        }
    }
    void OnLine(object sender, DataReceivedEventArgs e) {
        if (e.Data == null) return;
        lines.Enqueue(Redact(e.Data, secret));
    }
    public static string Redact(string line, string password) {
        string lower=line.ToLowerInvariant();
        if (lower.Contains("set-cookie") || lower.Contains("authorization:") || lower.Contains("cookie=") || lower.Contains("cookie:") || lower.Contains("ansession") || lower.Contains("password:")) return "[authentication detail hidden]";
        return String.IsNullOrEmpty(password) ? line : line.Replace(password, "[hidden]");
    }
    public string[] Drain() {
        var result=new System.Collections.Generic.List<string>(); string line;
        while (lines.TryDequeue(out line)) result.Add(line);
        return result.ToArray();
    }
    public void Dispose() { secret=null; Process.Dispose(); }
}
