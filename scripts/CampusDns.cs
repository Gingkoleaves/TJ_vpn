using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;

public static class CampusDns {
    static int U16(byte[] b, int p) { if (p < 0 || p + 2 > b.Length) throw new IOException("Truncated DNS response"); return (b[p] << 8) | b[p+1]; }
    static string Name(byte[] b, ref int position) {
        int cursor=position, jumps=0; bool jumped=false; var parts=new List<string>();
        while (true) {
            if (cursor >= b.Length || jumps++ > 128) throw new IOException("Invalid DNS name compression");
            int count=b[cursor++];
            if (count == 0) { if (!jumped) position=cursor; return String.Join(".",parts).ToLowerInvariant(); }
            if ((count & 0xc0) == 0xc0) {
                if (cursor >= b.Length) throw new IOException("Invalid DNS pointer");
                int target=((count & 0x3f) << 8) | b[cursor++];
                if (!jumped) position=cursor;
                jumped=true; cursor=target; continue;
            }
            if (count > 63 || cursor+count > b.Length) throw new IOException("Invalid DNS label");
            parts.Add(Encoding.ASCII.GetString(b,cursor,count)); cursor += count;
        }
    }
    public static string[] Parse(byte[] response, int id, string host) {
        if (response.Length < 12 || U16(response,0) != id || (response[2] & 0x80) == 0 || (response[2] & 2) != 0 || (response[3] & 15) != 0 || U16(response,4) != 1)
            throw new IOException("Invalid, truncated or unsuccessful campus DNS response");
        int cursor=12;
        string question=Name(response,ref cursor);
        if (question != host.ToLowerInvariant() || U16(response,cursor) != 1 || U16(response,cursor+2) != 1) throw new IOException("DNS question mismatch");
        cursor += 4;
        var aliases=new Dictionary<string,string>(); var records=new Dictionary<string,List<string>>();
        int answers=U16(response,6);
        for (int i=0;i<answers;i++) {
            string owner=Name(response,ref cursor);
            int type=U16(response,cursor), kind=U16(response,cursor+2), length=U16(response,cursor+8); cursor += 10;
            if (cursor+length > response.Length) throw new IOException("Truncated DNS record");
            if (kind == 1 && type == 1 && length == 4) {
                var address=new byte[4]; Array.Copy(response,cursor,address,0,4);
                if (!records.ContainsKey(owner)) records[owner]=new List<string>();
                records[owner].Add(new IPAddress(address).ToString());
            } else if (kind == 1 && type == 5) { int nameOffset=cursor; aliases[owner]=Name(response,ref nameOffset); }
            cursor += length;
        }
        string current=host.ToLowerInvariant(); var visited=new HashSet<string>();
        while (visited.Add(current)) {
            if (records.ContainsKey(current)) return new HashSet<string>(records[current]).ToArrayCompat();
            if (!aliases.ContainsKey(current)) break;
            current=aliases[current];
        }
        throw new IOException("Campus DNS returned no IPv4 address for " + host);
    }
    static string[] ToArrayCompat(this HashSet<string> values) { var result=new string[values.Count]; values.CopyTo(result); return result; }
    static byte[] Query(int id,string host) {
        using (var stream=new MemoryStream()) {
            stream.Write(new byte[]{(byte)(id>>8),(byte)id,1,0,0,1,0,0,0,0,0,0},0,12);
            foreach (string label in host.Split('.')) {
                byte[] text=Encoding.ASCII.GetBytes(label);
                if (text.Length < 1 || text.Length > 63) throw new ArgumentException("Invalid DNS label");
                stream.WriteByte((byte)text.Length); stream.Write(text,0,text.Length);
            }
            stream.Write(new byte[]{0,0,1,0,1},0,5); return stream.ToArray();
        }
    }
    static void ReadAll(Stream stream,byte[] bytes) {
        int read=0;
        while (read < bytes.Length) { int count=stream.Read(bytes,read,bytes.Length-read); if (count == 0) throw new IOException("Campus DNS closed connection"); read += count; }
    }
    public static string[] Resolve(string host,string server,string source) {
        int id=(Guid.NewGuid().GetHashCode() & 0xffff); byte[] query=Query(id,host);
        var local=new IPEndPoint(IPAddress.Parse(source),0);
        try {
            using (var client=new TcpClient(local)) {
                var connect=client.ConnectAsync(IPAddress.Parse(server),53);
                if (!connect.Wait(2500)) throw new TimeoutException("Campus DNS TCP connect timed out");
                using (var stream=client.GetStream()) {
                    stream.ReadTimeout=3000; stream.WriteTimeout=3000;
                    stream.WriteByte((byte)(query.Length>>8)); stream.WriteByte((byte)query.Length); stream.Write(query,0,query.Length);
                    var size=new byte[2]; ReadAll(stream,size);
                    var response=new byte[U16(size,0)]; ReadAll(stream,response);
                    return Parse(response,id,host);
                }
            }
        } catch (Exception error) {
            if (!(error is SocketException || error is IOException || error is TimeoutException || error is AggregateException)) throw;
            using (var client=new UdpClient(local)) {
                client.Client.ReceiveTimeout=3000; client.Connect(server,53); client.Send(query,query.Length);
                IPEndPoint remote=null; byte[] response=client.Receive(ref remote);
                return Parse(response,id,host);
            }
        }
    }
}
